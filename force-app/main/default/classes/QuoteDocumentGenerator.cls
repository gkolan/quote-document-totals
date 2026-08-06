/**
 * Generates the document tables and rows for one or more Quotes.
 *
 *   query quote and lines -> normalize -> filter -> group -> total -> persist
 *
 * Everything for a Quote is replaced in a single transaction against a
 * savepoint, so a document consumer never sees a half-replaced set: either all
 * tables are Complete and mutually consistent, or none of them changed. The
 * Quote's Document_Data_Status__c is the readiness gate a document action
 * should check - per-table status cannot prove that every table belongs to the
 * same generation.
 *
 * SCALE: generate(Set<Id>) does every quote in ONE transaction, which is right
 * for a button and wrong for a batch. Anything bulk should call generateAsync,
 * which gives each quote its own transaction and therefore its own limits.
 */
public with sharing class QuoteDocumentGenerator {

    public class QuoteDocumentException extends Exception {}

    /** Amounts are compared to the cent, not exactly - these are Currency(16,2). */
    private static final Decimal TOLERANCE = 0.01;

    /**
     * Row types that are themselves the OUTPUT of aggregation - a Group
     * Header, Subtotal, Section Total or Grand Total never represents money
     * that exists independently of the rows beneath it. Everything else
     * (Detail, and any customizer-added type such as Discount or Rounding)
     * is a LEAF contribution: real money that has to be accounted for in
     * verify()'s two independent reconciliation paths. This is what lets a
     * customizer introduce a new counted row type without touching verify()
     * itself.
     */
    private static final Set<String> AGGREGATE_ROW_TYPES = new Set<String>{
        'Group Header', 'Subtotal', 'Section Total', 'Grand Total'
    };

    // -----------------------------------------------------------------------
    // Entry points
    // -----------------------------------------------------------------------

    public class Request {
        @InvocableVariable(label='Quote Id' required=true)
        public Id quoteId;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Tables Generated')
        public Integer tableCount;
        @InvocableVariable(label='Rows Generated')
        public Integer rowCount;
        @InvocableVariable(label='Message')
        public String message;
    }

    /**
     * Returns a Result so a screen flow can show a real confirmation rather
     * than a blank screen, and so a failure surfaces to the user instead of
     * only to the debug log.
     */
    @InvocableMethod(
        label='Generate Quote Document Tables'
        description='Rebuilds the document tables and rows for a Quote so a document template can print pre-computed totals.'
        category='CPQ'
    )
    public static List<Result> generateFromFlow(List<Request> requests) {
        List<Result> results = new List<Result>();

        for (Request request : requests) {
            Result result = new Result();
            try {
                generate(new Set<Id>{ request.quoteId });

                result.tableCount = [
                    SELECT COUNT() FROM Quote_Document_Table__c WHERE Quote__c = :request.quoteId
                ];
                result.rowCount = [
                    SELECT COUNT() FROM Quote_Document_Row__c
                    WHERE Quote_Document_Table__r.Quote__c = :request.quoteId
                ];
                result.success = true;
                result.message = 'Generated ' + result.tableCount + ' tables and '
                    + result.rowCount + ' rows. This quote is ready for document generation.';
            } catch (Exception e) {
                result.success = false;
                result.tableCount = 0;
                result.rowCount = 0;
                result.message = e.getMessage();
            }
            results.add(result);
        }

        return results;
    }

    /**
     * One transaction for every quote passed in. Correct for a single quote
     * from a button or flow; use generateAsync for anything larger.
     */
    public static void generate(Set<Id> quoteIds) {
        List<SBQQ__Quote__c> quotes = queryQuotes(quoteIds);

        // Silently doing nothing for an id that does not resolve is how a flow
        // ends up reporting success over an empty document.
        if (quotes.size() != quoteIds.size()) {
            Set<Id> found = new Set<Id>();
            for (SBQQ__Quote__c quote : quotes) {
                found.add(quote.Id);
            }
            Set<Id> missing = new Set<Id>(quoteIds);
            missing.removeAll(found);
            throw new QuoteDocumentException('No Quote found for: ' + missing);
        }

        for (SBQQ__Quote__c quote : quotes) {
            generateOne(quote);
        }
    }

    /**
     * One Queueable, and therefore one transaction, per quote. This is what
     * makes a bulk run safe: row volume scales with the size of a single quote
     * rather than with the size of the batch.
     *
     * Generates unconditionally. Asking for it is the intent - a backfill would
     * do nothing if it skipped quotes that are merely Not Generated. The
     * skip-unless-stale behaviour belongs to a refresh triggered by a save, and
     * lives in QuoteDocumentGenerateJob's one-argument constructor.
     *
     * A synchronous context can queue only 50 jobs, so cap the caller's batch.
     */
    public static void generateAsync(Set<Id> quoteIds) {
        for (Id quoteId : quoteIds) {
            System.enqueueJob(new QuoteDocumentGenerateJob(quoteId, false));
        }
    }

    // -----------------------------------------------------------------------
    // One quote, all tables, one transaction
    // -----------------------------------------------------------------------

    private static void generateOne(SBQQ__Quote__c quote) {
        List<QuoteDocumentLine> allLines = normalize(quote);

        Savepoint sp = Database.setSavepoint();
        List<Quote_Document_Table__c> tables = new List<Quote_Document_Table__c>();
        Map<String, List<Quote_Document_Row__c>> rowsByCode =
            new Map<String, List<Quote_Document_Row__c>>();

        try {
            List<QuoteDocumentTableDefinition> definitions = QuoteDocumentTableDefinition.getAll();

            // Fingerprint reuse (spec quote-docusign-launch Increment 2).
            // Everything up to here still ran - definition loading, path
            // validation, the line query, canonicalization - it only saves
            // the expensive half: delete, both inserts, and the stamp/
            // markQuote write. Sits inside the try block, same as the delete
            // below, so a broken definition still rolls back cleanly and
            // records Failed rather than throwing raw.
            String fingerprint = QuoteDocumentFingerprint.compute(quote, allLines, definitions);
            if (canReuse(quote, fingerprint, definitions)) {
                return;
            }

            delete [SELECT Id FROM Quote_Document_Table__c WHERE Quote__c = :quote.Id];

            for (QuoteDocumentTableDefinition definition : definitions) {
                List<QuoteDocumentLine> lines = applyFilter(allLines, definition.lineFilter);

                Quote_Document_Table__c table = newTable(quote, definition);
                tables.add(table);
                List<Quote_Document_Row__c> rows = new QuoteDocumentRowBuilder(definition).build(lines);
                rows = applyRowCustomizer(quote, definition, lines, rows);
                rowsByCode.put(definition.tableCode, rows);
            }
            insert tables;

            Map<String, Quote_Document_Table__c> tableByCode = new Map<String, Quote_Document_Table__c>();
            for (Quote_Document_Table__c t : tables) {
                tableByCode.put(t.Table_Code__c, t);
            }

            List<Quote_Document_Row__c> allRows = new List<Quote_Document_Row__c>();
            for (String code : rowsByCode.keySet()) {
                Id tableId = tableByCode.get(code).Id;
                for (Quote_Document_Row__c row : rowsByCode.get(code)) {
                    row.Quote_Document_Table__c = tableId;
                    copyCurrency(quote, row);
                    allRows.add(row);
                }
            }
            insert allRows;

            // Stamped onto fresh records rather than onto the inserted ones,
            // so the update carries only the fields that actually changed.
            // (This started as a workaround for Quote__c being a non-updateable
            // master-detail. Quote__c is a lookup now and could be re-sent
            // harmlessly, but sending only what changed is still the better
            // habit and keeps the update independent of the relationship type.)
            List<Quote_Document_Table__c> stamped = new List<Quote_Document_Table__c>();
            for (QuoteDocumentTableDefinition definition : definitions) {
                Quote_Document_Table__c inserted = tableByCode.get(definition.tableCode);
                List<Quote_Document_Row__c> rows = rowsByCode.get(definition.tableCode);

                Quote_Document_Table__c table = new Quote_Document_Table__c(
                    Id = inserted.Id,
                    Table_Code__c = inserted.Table_Code__c
                );
                stampTable(table, definition, rows);
                verify(quote, table, definition, rows);
                stamped.add(table);
            }
            update stamped;

            // Only now is the quote safe to print from. Written last and in the
            // same transaction as the rows, so Ready always means every table
            // came from this one generation. The fingerprint stamped here is
            // the one computed at the top of this method, before generation -
            // nothing that feeds it changes mid-transaction.
            markQuote(quote.Id, 'Ready', System.now(), null, fingerprint);

        } catch (DmlException de) {
            Database.rollback(sp);
            // The bare platform message names neither the row nor the field,
            // which makes a permissions problem needlessly hard to diagnose.
            String detail = de.getMessage();
            if (de.getNumDml() > 0) {
                detail += ' | fields: ' + de.getDmlFieldNames(0) + ' | ' + de.getDmlMessage(0);
            }
            throw fail(quote, detail, de);
        } catch (Exception e) {
            Database.rollback(sp);
            throw fail(quote, e.getMessage(), e);
        }
    }

    /**
     * Records the failure on the Quote and returns the exception to throw.
     *
     * The status write happens after the rollback and in its own DML, so it
     * survives. A quote left silently on its previous Ready status after a
     * failed regeneration is exactly how a stale document gets signed.
     */
    private static QuoteDocumentException fail(SBQQ__Quote__c quote, String detail, Exception cause) {
        String message = 'Document generation failed for quote ' + quote.Name + ': ' + detail;
        try {
            // Document_Data_Error__c is a Long Text Area (4000 chars) precisely
            // so this bound rarely bites - a Text(255) field used to sit here
            // and silently cut off the actionable part of longer, named error
            // messages (e.g. a misconfiguration explaining exactly which field
            // to fix), which defeated the point of writing a clear message in
            // the first place. Still capped, not unbounded - a raw DmlException
            // detail (assertUniqueRowKeys, a DML error listing many field
            // names) has no natural upper length.
            markQuote(quote.Id, 'Failed', null, message.abbreviate(3000));
        } catch (Exception ignored) {
            // Never let the bookkeeping hide the real error.
        }
        return new QuoteDocumentException(message, cause);
    }

    /**
     * Staleness is suppressed around this write. The generator is the one
     * changing the quote here, and it already knows the tables are current -
     * letting the trigger react would mark the quote stale from inside this
     * very DML.
     *
     * Deliberately does not touch Document_Data_Fingerprint__c - this
     * overload is also used by fail(), and a rolled-back generation must
     * leave whatever fingerprint was already stored untouched rather than
     * null it out, since the previously-committed tables (if any) are still
     * exactly what that fingerprint describes.
     */
    private static void markQuote(Id quoteId, String status, Datetime generatedOn, String error) {
        QuoteDocumentStaleness.suppress();
        try {
            update new SBQQ__Quote__c(
                Id = quoteId,
                Document_Data_Status__c = status,
                Document_Data_Generated_On__c = generatedOn,
                Document_Data_Error__c = error
            );
        } finally {
            QuoteDocumentStaleness.resume();
        }
    }

    /** Success path only - stamps the fingerprint that made this generation's output. */
    private static void markQuote(Id quoteId, String status, Datetime generatedOn, String error, String fingerprint) {
        QuoteDocumentStaleness.suppress();
        try {
            update new SBQQ__Quote__c(
                Id = quoteId,
                Document_Data_Status__c = status,
                Document_Data_Generated_On__c = generatedOn,
                Document_Data_Error__c = error,
                Document_Data_Fingerprint__c = fingerprint
            );
        } finally {
            QuoteDocumentStaleness.resume();
        }
    }

    /**
     * Reuse is only safe when all four hold - see spec quote-docusign-launch
     * §5.3. The last two are not belt-and-braces: Quote_Document_Table__c's
     * OWD is Public Read/Write, so anyone holding CPQ_Document_Totals can
     * delete rows out from under a Ready quote. A matching fingerprint alone
     * cannot see that the snapshot is now incomplete.
     */
    @TestVisible
    private static Boolean canReuse(
        SBQQ__Quote__c quote, String freshFingerprint, List<QuoteDocumentTableDefinition> definitions
    ) {
        if (!'Ready'.equals(quote.Document_Data_Status__c)) {
            return false;
        }
        if (quote.Document_Data_Fingerprint__c == null
            || !quote.Document_Data_Fingerprint__c.equals(freshFingerprint)) {
            return false;
        }

        Set<String> expectedCodes = new Set<String>();
        for (QuoteDocumentTableDefinition definition : definitions) {
            expectedCodes.add(definition.tableCode);
        }

        Map<Id, String> codeByTableId = new Map<Id, String>();
        for (Quote_Document_Table__c table : [
            SELECT Id, Table_Code__c FROM Quote_Document_Table__c WHERE Quote__c = :quote.Id
        ]) {
            codeByTableId.put(table.Id, table.Table_Code__c);
        }
        if (!new Set<String>(codeByTableId.values()).containsAll(expectedCodes)) {
            return false;
        }

        Set<Id> tablesWithGrandTotal = new Set<Id>();
        for (Quote_Document_Row__c row : [
            SELECT Quote_Document_Table__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__c IN :codeByTableId.keySet() AND Row_Type__c = 'Grand Total'
        ]) {
            tablesWithGrandTotal.add(row.Quote_Document_Table__c);
        }
        return tablesWithGrandTotal.size() == codeByTableId.size();
    }

    // -----------------------------------------------------------------------
    // Query and normalize
    // -----------------------------------------------------------------------

    /**
     * Fields QuoteDocumentLine always reads, whatever the configuration says.
     */
    private static final List<String> BASE_LINE_FIELDS = new List<String>{
        'Id', 'SBQQ__Number__c', 'SBQQ__Product__c', 'SBQQ__ProductName__c',
        'SBQQ__ProductCode__c', 'SBQQ__Product__r.Family', 'SBQQ__ChargeType__c',
        'SBQQ__Bundle__c', 'SBQQ__Bundled__c', 'SBQQ__Optional__c', 'SBQQ__OptionLevel__c',
        'SBQQ__RequiredBy__c', 'SBQQ__RequiredBy__r.SBQQ__ProductName__c',
        'SBQQ__Group__c', 'SBQQ__Group__r.Name', 'SBQQ__Quantity__c',
        'SBQQ__ListTotal__c', 'SBQQ__RegularTotal__c', 'SBQQ__TotalDiscountAmount__c',
        'SBQQ__NetTotal__c', 'SBQQ__CustomerTotal__c', 'SBQQ__NetPrice__c',
        'SBQQ__Existing__c', 'SBQQ__PriorQuantity__c',
        'SBQQ__UpgradedSubscription__c', 'SBQQ__RenewedSubscription__c'
    };

    /**
     * Built dynamically so a grouping configured as a field path is fetched
     * without an Apex change. Every configured path is validated against the
     * schema first, so a typo fails here with a readable message instead of an
     * opaque QueryException, and USER_MODE means a configured path cannot be
     * used to read a field the running user has no access to.
     *
     * FOR UPDATE locks the Quote row for the rest of this transaction. Without
     * it, two near-simultaneous generation requests for the same Quote (a
     * doubled button click, or two platform-event-driven refreshes once
     * automatic generation ships) can interleave: both read the same starting
     * state, both delete, both insert, and the second writer's commit is the
     * only one anyone can trust - but nothing stops the first writer's
     * in-flight DML from also landing. The lock serializes them: the second
     * transaction blocks until the first commits or rolls back, then proceeds
     * against post-commit state. SOQL rejects an explicit ORDER BY combined
     * with FOR UPDATE - lock acquisition order is Id order automatically -
     * which is exactly the property that avoids a deadlock between two
     * transactions each locking a different subset of the same two Quotes in
     * opposite order.
     */
    private static List<SBQQ__Quote__c> queryQuotes(Set<Id> quoteIds) {
        Set<String> lineFields = new Set<String>(BASE_LINE_FIELDS);

        for (String path : QuoteDocumentTableDefinition.allFieldPaths()) {
            validateFieldPath(path);
            lineFields.add(path);
        }

        // CurrencyIsoCode only exists as a field when multi-currency is on, and
        // a static reference to it will not compile in a single-currency org -
        // same guard as copyCurrency, applied to the SELECT list instead.
        String currencyField = UserInfo.isMultiCurrencyOrganization() ? ', CurrencyIsoCode' : '';

        String soql =
            'SELECT Id, Name, SBQQ__NetAmount__c, AccountIndustry__c, Document_Data_Status__c, '
            + 'Document_Data_Fingerprint__c' + currencyField + ', '
            + '(SELECT ' + String.join(new List<String>(lineFields), ', ')
            + ' FROM SBQQ__LineItems__r ORDER BY SBQQ__Number__c) '
            + 'FROM SBQQ__Quote__c WHERE Id IN :quoteIds WITH USER_MODE FOR UPDATE';

        return Database.query(soql);
    }

    /**
     * Walks a dot path through the describe layer so a bad configuration is
     * caught at generation time, naming the segment that does not exist.
     */
    private static void validateFieldPath(String path) {
        SObjectType current = SBQQ__QuoteLine__c.SObjectType;
        List<String> segments = path.split('\\.');

        for (Integer i = 0; i < segments.size(); i++) {
            String segment = segments[i];
            Boolean isLast = (i == segments.size() - 1);
            String fieldName = isLast ? segment : segment.replace('__r', '__c');

            Map<String, SObjectField> fields = current.getDescribe().fields.getMap();
            SObjectField field = fields.get(fieldName.toLowerCase());

            // Standard relationships such as Account or Owner end in Id rather
            // than __c, so fall back before giving up.
            if (field == null && !isLast) {
                field = fields.get((segment + 'Id').toLowerCase());
            }

            if (field == null) {
                throw new QuoteDocumentException(
                    'Grouping field path "' + path + '" is not valid: no field "' + segment
                    + '" on ' + current.getDescribe().getName()
                    + '. Fix the Field Path on the Quote Document Grouping record.'
                );
            }

            if (!isLast) {
                List<SObjectType> references = field.getDescribe().getReferenceTo();
                if (references.isEmpty()) {
                    throw new QuoteDocumentException(
                        'Grouping field path "' + path + '": "' + segment
                        + '" is not a relationship, so nothing can follow it.'
                    );
                }
                current = references[0];
            }
        }
    }

    private static List<QuoteDocumentLine> normalize(SBQQ__Quote__c quote) {
        List<QuoteDocumentLine> lines = new List<QuoteDocumentLine>();
        for (SBQQ__QuoteLine__c line : quote.SBQQ__LineItems__r) {
            lines.add(new QuoteDocumentLine(line, quote));
        }
        return lines;
    }

    /**
     * Runs the table definition's row customizer, if one is set, resolved
     * through the closed registry (spec quote-docusign-launch Increment 4).
     */
    private static List<Quote_Document_Row__c> applyRowCustomizer(
        SBQQ__Quote__c quote,
        QuoteDocumentTableDefinition definition,
        List<QuoteDocumentLine> lines,
        List<Quote_Document_Row__c> rows
    ) {
        if (String.isBlank(definition.rowCustomizerCode)) {
            return rows;
        }
        QuoteDocumentRowCustomizer instance =
            QuoteDocumentRowCustomizerRegistry.resolve(definition.rowCustomizerCode);

        QuoteDocumentRowCustomizerContext context = new QuoteDocumentRowCustomizerContext();
        context.quote = quote;
        context.definition = definition;
        context.lines = lines;
        context.rows = rows;

        List<Quote_Document_Row__c> customized = instance.customize(context);
        return customized == null ? context.rows : customized;
    }

    private static List<QuoteDocumentLine> applyFilter(List<QuoteDocumentLine> lines, String filter) {
        List<QuoteDocumentLine> kept = new List<QuoteDocumentLine>();
        for (QuoteDocumentLine line : lines) {
            if (line.matchesFilter(filter)) {
                kept.add(line);
            }
        }
        return kept;
    }

    // -----------------------------------------------------------------------
    // Persist
    // -----------------------------------------------------------------------

    private static Quote_Document_Table__c newTable(
        SBQQ__Quote__c quote,
        QuoteDocumentTableDefinition definition
    ) {
        // The name carries the quote number so a table is identifiable in a
        // list view or search result. Quote_Number__c is the field to trust
        // though - it is a formula and cannot drift.
        Quote_Document_Table__c table = new Quote_Document_Table__c(
            Name = (quote.Name + ' - ' + definition.tableName).abbreviate(80),
            Quote__c = quote.Id,
            Table_Code__c = definition.tableCode,
            Table_Key__c = quote.Id + ':' + definition.tableCode,
            Display_Order__c = definition.displayOrder,
            Amount_Basis__c = definition.amountBasis,
            Group_Dimensions__c = definition.groupDimensionsLabel(),
            Line_Filter__c = definition.lineFilter,
            Measure_Set__c = definition.measureSet,
            Status__c = 'Generating'
        );
        copyCurrency(quote, table);
        return table;
    }

    /**
     * The table carries the same measures as its grand total row, so a document
     * can print a total outside a repeating block. Written from the row rather
     * than recalculated, so the two can never disagree.
     */
    private static void stampTable(
        Quote_Document_Table__c table,
        QuoteDocumentTableDefinition definition,
        List<Quote_Document_Row__c> rows
    ) {
        Quote_Document_Row__c grandTotal = findGrandTotal(rows);

        for (String field : measureFields(definition.measureSet)) {
            table.put(field, grandTotal.get(field));
        }

        table.Row_Count__c = rows.size();
        table.Generated_On__c = System.now();
        table.Status__c = 'Complete';
    }

    /**
     * CurrencyIsoCode is added by the platform only when multi-currency is on,
     * and Apex that names it statically will not compile in a single-currency
     * org. Setting it dynamically keeps one codebase deployable to both.
     */
    private static void copyCurrency(SBQQ__Quote__c quote, SObject target) {
        if (UserInfo.isMultiCurrencyOrganization()) {
            target.put('CurrencyIsoCode', quote.get('CurrencyIsoCode'));
        }
    }

    // -----------------------------------------------------------------------
    // Verification
    //
    // No validation rule can see sibling records, so the checks that actually
    // stop a signed document carrying a wrong number have to live here.
    // -----------------------------------------------------------------------

    @TestVisible
    private static void verify(
        SBQQ__Quote__c quote,
        Quote_Document_Table__c table,
        QuoteDocumentTableDefinition definition,
        List<Quote_Document_Row__c> rows
    ) {
        Quote_Document_Row__c grandTotal = findGrandTotal(rows);
        List<String> fields = measureFields(definition.measureSet);

        // 0. Row_Key__c is only meaningful if it is actually unique within this
        //    table. The field itself cannot enforce that declaratively - the
        //    same key text (e.g. GRAND_TOTAL) is legitimately reused across
        //    different Quotes' tables, so the field is externalId but not
        //    unique - which means nothing stops two different group values
        //    from sanitizing to the same key (buildGroupKey uppercases and
        //    strips to [A-Z0-9_], so "R&D" and "R D" both become "R_D") and
        //    silently inserting as two rows sharing one key. Caught here,
        //    before Complete, rather than discovered later as a row a
        //    consuming template can no longer address unambiguously.
        assertUniqueRowKeys(rows, table);

        // 1. The grand total equals the sum of the included detail rows.
        // 2. It also equals the sum of the outermost subtotals. Two independent
        //    paths to the same number; if they disagree, the grouping dropped
        //    or duplicated a line.
        for (String field : fields) {
            Decimal fromDetails = 0;
            Decimal fromSubtotals = 0;

            for (Quote_Document_Row__c row : rows) {
                Decimal value = (Decimal) row.get(field);
                if (value == null) { continue; }

                // A leaf contribution always feeds the detail-rows path. A
                // Detail row also always sits inside a group, so it reaches
                // the subtotal path through that group's own Subtotal row -
                // counting it again here would double it. A leaf with no
                // group of its own (Group_Level__c 0 - a table-wide
                // adjustment such as a Rounding row) has no Subtotal to be
                // captured by, so it has to feed both paths directly or the
                // two paths would never agree.
                Boolean isLeaf = !AGGREGATE_ROW_TYPES.contains(row.Row_Type__c) && row.Include_In_Grand_Total__c;

                if (isLeaf) {
                    fromDetails += value;
                }
                if ((row.Row_Type__c == 'Subtotal' && row.Group_Level__c == 1)
                    || (isLeaf && row.Group_Level__c == 0)) {
                    fromSubtotals += value;
                }
            }

            Decimal stated = (Decimal) grandTotal.get(field);
            stated = stated == null ? 0 : stated;

            if (definition.showDetails) {
                assertClose(stated, fromDetails, table, field + ' grand total vs detail rows');
            }
            assertClose(stated, fromSubtotals, table, field + ' grand total vs level-1 subtotals');
        }

        // 3. The table's own measures match its grand total row.
        for (String field : fields) {
            assertClose((Decimal) table.get(field), (Decimal) grandTotal.get(field),
                        table, field + ' table measure vs grand total row');
        }

        // 4. The check that matters commercially: a price-waterfall table built
        //    from everything except optional products has to land on the same
        //    Net Amount that CPQ itself rolled up onto the Quote.
        Boolean reconcilesToQuote =
            QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL.equals(definition.measureSet)
            && QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL.equals(definition.lineFilter);

        if (reconcilesToQuote) {
            // CPQ's own SBQQ__NetAmount__c has no idea a Discount, Rounding,
            // or any other synthetic row exists - it only knows about real
            // quote lines. A counted row that is not a real line's own
            // Detail row can only ever pull this table's total away from
            // CPQ's, on the one table where the two are required to match
            // to the cent. Caught here rather than left to surface as a
            // baffling one-cent-off failure in the assertion below.
            assertNoSyntheticCountedRows(rows, table);

            if (quote.SBQQ__NetAmount__c != null) {
                assertClose(quote.SBQQ__NetAmount__c, (Decimal) grandTotal.get('Amount_Net__c'),
                            table, 'grand total vs Quote Net Amount');
            }
        }
    }

    private static void assertNoSyntheticCountedRows(List<Quote_Document_Row__c> rows, Quote_Document_Table__c table) {
        for (Quote_Document_Row__c row : rows) {
            Boolean isSyntheticCountedLeaf = !AGGREGATE_ROW_TYPES.contains(row.Row_Type__c)
                && row.Row_Type__c != 'Detail'
                && row.Include_In_Grand_Total__c;
            if (isSyntheticCountedLeaf) {
                table.Status__c = 'Failed';
                throw new QuoteDocumentException(
                    table.Table_Code__c + ': a ' + row.Row_Type__c + ' row ("' + row.Display_Label__c
                    + '") counts toward the grand total, but this table is checked against the Quote '
                    + 'Net Amount - CPQ has no knowledge of that row, so the two can never agree. Keep '
                    + 'Discount, Rounding or other synthetic counted rows off the PRICE_WATERFALL + '
                    + 'EXCLUDE_OPTIONAL table, or set Include_In_Grand_Total__c to false on them.'
                );
            }
        }
    }

    private static void assertUniqueRowKeys(List<Quote_Document_Row__c> rows, Quote_Document_Table__c table) {
        Set<String> seen = new Set<String>();
        for (Quote_Document_Row__c row : rows) {
            if (!seen.add(row.Row_Key__c)) {
                table.Status__c = 'Failed';
                throw new QuoteDocumentException(
                    table.Table_Code__c + ': duplicate Row_Key__c "' + row.Row_Key__c + '" - '
                    + 'two different rows produced the same key, most likely two grouping values '
                    + 'that sanitize to the same text (e.g. "R&D" and "R D" both become "R_D"). '
                    + 'Adjust the grouping value or the table\'s field path so the two are distinguishable.'
                );
            }
        }
    }

    private static void assertClose(Decimal expected, Decimal actual, Quote_Document_Table__c table, String what) {
        Decimal a = expected == null ? 0 : expected;
        Decimal b = actual == null ? 0 : actual;
        if (Math.abs(a - b) > TOLERANCE) {
            table.Status__c = 'Failed';
            throw new QuoteDocumentException(
                table.Table_Code__c + ': ' + what + ' - expected ' + a + ', got ' + b
            );
        }
    }

    private static Quote_Document_Row__c findGrandTotal(List<Quote_Document_Row__c> rows) {
        for (Quote_Document_Row__c row : rows) {
            if (row.Row_Type__c == 'Grand Total') {
                return row;
            }
        }
        throw new QuoteDocumentException('Table was built without a Grand Total row.');
    }

    private static List<String> measureFields(String measureSet) {
        if (QuoteDocumentTableDefinition.MEASURES_CHANGE.equals(measureSet)) {
            return new List<String>{
                'Amount_Net_New__c', 'Amount_Cancellation__c', 'Amount_Replacement_Removed__c',
                'Amount_Replacement_Added__c', 'Amount_Termination__c', 'Amount_Net_Change__c',
                'Amount_Final__c'
            };
        }
        return new List<String>{
            'Amount_List__c', 'Amount_Regular__c', 'Amount_Discount__c',
            'Amount_Net__c', 'Amount_Customer__c', 'Quantity__c'
        };
    }
}
