/**
 * The one way to read a published document.
 *
 * Adapters querying the objects directly would each re-derive ordering,
 * visibility filtering, and the table-column-row join, and would drift apart.
 * One projection shared by every adapter is what makes "swap the renderer" a
 * small job rather than a rewrite.
 *
 * WHY THERE IS NO CONVENIENT OVERLOAD
 * -----------------------------------
 * Every entry point requires an expected request Id AND fingerprint, from the
 * generate-or-reuse call that preceded the render. There is deliberately no
 * quote-Id-only form - not for tests, not for admin inspection, not for bulk.
 *
 * This service cannot tell a "production" call from an "ad hoc" one. An
 * overload that skipped the expectations would therefore just BE the bypass
 * the rest of the contract prohibits, and would make step 06's condition 1b
 * unenforceable. Tests obtain the values the way every caller does.
 *
 * Administrators who need to look at a snapshot get describeSnapshot(), which
 * cannot return a payload and so can never be quietly promoted into a render
 * path.
 */
public with sharing class QuoteDocumentRenderService {

    /** Base fields every row carries, before any configured column binding is added. */
    private static final List<String> BASE_ROW_FIELDS = new List<String>{
        'Id', 'Quote_Document_Table__c', 'Row_Key__c', 'Row_Type__c', 'Display_Label__c',
        'Label_Key__c', 'Display_Order__c', 'Group_Level__c', 'Is_Displayed__c'
    };

    // -----------------------------------------------------------------------
    // Entry points
    // -----------------------------------------------------------------------

    public static QuoteDocumentPayload getPayload(
        Id quoteId, String expectedRequestId, String expectedFingerprint
    ) {
        List<QuoteDocumentPayload.PayloadResult> results = getPayloads(
            new List<QuoteDocumentPayload.PayloadRequest>{
                new QuoteDocumentPayload.PayloadRequest(quoteId, expectedRequestId, expectedFingerprint)
            }
        );

        QuoteDocumentPayload.PayloadResult result = results[0];
        if (result.success != true) {
            throw QuoteDocumentContributorError.build(result.errorCode, result.errorMessage);
        }
        return result.payload;
    }

    /**
     * Bulk retrieval. One query per object regardless of how many quotes or
     * tables are involved, so query count stays flat as volume grows - the
     * property that makes this usable from a batch at all.
     *
     * Each request carries its own expectations and its own outcome. One
     * mismatch fails THAT request; it never degrades the rest, and it never
     * lets a partial batch look like a whole one.
     */
    public static List<QuoteDocumentPayload.PayloadResult> getPayloads(
        List<QuoteDocumentPayload.PayloadRequest> requests
    ) {
        List<QuoteDocumentPayload.PayloadResult> results =
            new List<QuoteDocumentPayload.PayloadResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Set<Id> quoteIds = new Set<Id>();
        for (QuoteDocumentPayload.PayloadRequest request : requests) {
            if (request != null && request.quoteId != null) {
                quoteIds.add(request.quoteId);
            }
        }

        Map<Id, SBQQ__Quote__c> quotes = quoteIds.isEmpty()
            ? new Map<Id, SBQQ__Quote__c>()
            : new Map<Id, SBQQ__Quote__c>(
                (List<SBQQ__Quote__c>) Database.query(quoteSoql())
            );

        // Everything below is fetched ONCE for the whole batch. Moving any of
        // these inside the per-request loop would make query count scale with
        // batch size, which is the failure this shape exists to avoid.
        Map<Id, List<Quote_Document_Table__c>> tablesByQuote = tablesFor(quoteIds);
        Map<Id, List<Quote_Document_Column__c>> columnsByTable = columnsFor(tablesByQuote);
        Map<Id, List<SObject>> rowsByTable = rowsFor(tablesByQuote, columnsByTable);
        Map<Id, List<Quote_Document_Block__c>> blocksByQuote = blocksFor(quoteIds);

        // Integrity is verified for the WHOLE BATCH in one bulk load, not
        // once per request and not once per quote. The earlier per-quote cache
        // stopped a repeated quote being re-hashed but left the cost scaling
        // with the number of DISTINCT quotes - and the test that should have
        // caught that passed the same quote three times, so it measured the
        // cache rather than the work.
        Map<Id, String> actualHashByQuote = QuoteDocumentPayloadHash.computeAll(quoteIds);
        Map<Id, String> integrityFailureByQuote = new Map<Id, String>();

        for (QuoteDocumentPayload.PayloadRequest request : requests) {
            results.add(build(
                request, quotes, tablesByQuote, columnsByTable, rowsByTable, blocksByQuote,
                integrityFailureByQuote, actualHashByQuote
            ));
        }
        return results;
    }

    /**
     * CurrencyIsoCode only exists as a field when multi-currency is on, so a
     * static reference will not compile in a single-currency org - the same
     * guard QuoteDocumentQuery applies to its own SELECT list.
     *
     * This was a real defect, found in review: the projection read the
     * currency from getPopulatedFieldsAsMap() but the query never selected
     * it, so it came back null in EVERY org including a multi-currency one.
     * Both adapters format money from it, so every amount printed with no
     * currency - and nothing failed, because null is a legal value for a
     * field that legitimately does not exist in a single-currency org. That
     * is what made it invisible.
     *
     * Bind variable `quoteIds` is resolved by the caller's scope.
     */
    @TestVisible
    private static String quoteSoql() {
        String currencyField = UserInfo.isMultiCurrencyOrganization() ? ', CurrencyIsoCode' : '';

        return 'SELECT Id, Name, Document_Data_Status__c, Document_Data_Request_Id__c, '
            + 'Document_Data_Fingerprint__c, Document_Payload_Hash__c, '
            + 'Document_Data_Generated_On__c' + currencyField
            + ' FROM SBQQ__Quote__c WHERE Id IN :quoteIds';
    }

    /**
     * Whether the quote query actually selects the currency.
     *
     * Inspects the real SELECT list rather than returning a constant - a
     * helper that cannot fail is worse than no helper, because it reads like
     * coverage.
     */
    @TestVisible
    private static Boolean selectsCurrency() {
        return !UserInfo.isMultiCurrencyOrganization()
            || quoteSoql().contains('CurrencyIsoCode');
    }

    /**
     * Diagnostics for a human. Cannot return a payload, by design - see the
     * class comment.
     */
    public static QuoteDocumentPayload.SnapshotDescription describeSnapshot(Id quoteId) {
        List<SBQQ__Quote__c> quotes = [
            SELECT Id, Document_Data_Status__c, Document_Data_Request_Id__c,
                   Document_Data_Fingerprint__c, Document_Payload_Hash__c, Document_Data_Generated_On__c
            FROM SBQQ__Quote__c WHERE Id = :quoteId
        ];
        if (quotes.isEmpty()) {
            throw QuoteDocumentContributorError.build(
                'QUOTE_NOT_FOUND', 'No Quote found for ' + quoteId + '.'
            );
        }

        QuoteDocumentPayload.SnapshotDescription description =
            new QuoteDocumentPayload.SnapshotDescription();
        description.quoteId = quoteId;
        description.status = quotes[0].Document_Data_Status__c;
        description.requestId = quotes[0].Document_Data_Request_Id__c;
        description.fingerprint = quotes[0].Document_Data_Fingerprint__c;
        description.payloadHash = quotes[0].Document_Payload_Hash__c;
        description.generatedOn = quotes[0].Document_Data_Generated_On__c;

        List<Quote_Document_Table__c> tables = [
            SELECT Id, Locale__c FROM Quote_Document_Table__c WHERE Quote__c = :quoteId
        ];
        description.tableCount = tables.size();
        description.locale = tables.isEmpty() ? null : tables[0].Locale__c;
        description.rowCount = [
            SELECT COUNT() FROM Quote_Document_Row__c WHERE Quote_Document_Table__r.Quote__c = :quoteId
        ];
        description.columnCount = [
            SELECT COUNT() FROM Quote_Document_Column__c WHERE Quote_Document_Table__r.Quote__c = :quoteId
        ];
        description.blockCount = [
            SELECT COUNT() FROM Quote_Document_Block__c WHERE Quote__c = :quoteId
        ];
        return description;
    }

    // -----------------------------------------------------------------------
    // Retrieval
    // -----------------------------------------------------------------------

    private static Map<Id, List<Quote_Document_Table__c>> tablesFor(Set<Id> quoteIds) {
        Map<Id, List<Quote_Document_Table__c>> byQuote = new Map<Id, List<Quote_Document_Table__c>>();
        if (quoteIds.isEmpty()) {
            return byQuote;
        }
        for (Quote_Document_Table__c table : [
            SELECT Id, Quote__c, Table_Code__c, Display_Title__c, Display_Subtitle__c, Intro_Text__c,
                   Footer_Text__c, Is_Displayed__c, Display_Order__c, Locale__c, Status__c, Row_Count__c
            FROM Quote_Document_Table__c
            WHERE Quote__c IN :quoteIds
            ORDER BY Display_Order__c, Table_Code__c
        ]) {
            if (!byQuote.containsKey(table.Quote__c)) {
                byQuote.put(table.Quote__c, new List<Quote_Document_Table__c>());
            }
            byQuote.get(table.Quote__c).add(table);
        }
        return byQuote;
    }

    private static Map<Id, List<Quote_Document_Column__c>> columnsFor(
        Map<Id, List<Quote_Document_Table__c>> tablesByQuote
    ) {
        Set<Id> tableIds = new Set<Id>();
        for (List<Quote_Document_Table__c> tables : tablesByQuote.values()) {
            for (Quote_Document_Table__c table : tables) {
                tableIds.add(table.Id);
            }
        }

        Map<Id, List<Quote_Document_Column__c>> byTable = new Map<Id, List<Quote_Document_Column__c>>();
        if (tableIds.isEmpty()) {
            return byTable;
        }
        for (Quote_Document_Column__c column : [
            SELECT Id, Quote_Document_Table__c, Column_Code__c, Display_Label__c, Display_Order__c,
                   Value_Field__c, Data_Type__c, Is_Displayed__c
            FROM Quote_Document_Column__c
            WHERE Quote_Document_Table__c IN :tableIds
            ORDER BY Display_Order__c, Column_Code__c
        ]) {
            if (!byTable.containsKey(column.Quote_Document_Table__c)) {
                byTable.put(column.Quote_Document_Table__c, new List<Quote_Document_Column__c>());
            }
            byTable.get(column.Quote_Document_Table__c).add(column);
        }
        return byTable;
    }

    /**
     * The SELECT list is the union of the base fields and every Value_Field__c
     * configured on the columns being retrieved.
     *
     * Dynamic, and defensibly so. A static field list would make step 02's
     * subscriber-field binding valid metadata that never produces a value -
     * the column would exist, validate, and print blank forever. Every
     * interpolated name is checked against the row schema first, the same
     * discipline QuoteDocumentQuery.validateFieldPath applies to grouping
     * paths, so nothing unvalidated reaches the query string.
     */
    private static Map<Id, List<SObject>> rowsFor(
        Map<Id, List<Quote_Document_Table__c>> tablesByQuote,
        Map<Id, List<Quote_Document_Column__c>> columnsByTable
    ) {
        Set<Id> tableIds = new Set<Id>();
        for (List<Quote_Document_Table__c> tables : tablesByQuote.values()) {
            for (Quote_Document_Table__c table : tables) {
                tableIds.add(table.Id);
            }
        }

        Map<Id, List<SObject>> byTable = new Map<Id, List<SObject>>();
        if (tableIds.isEmpty()) {
            return byTable;
        }

        Set<String> fields = new Set<String>(BASE_ROW_FIELDS);
        Map<String, SObjectField> rowFields =
            Quote_Document_Row__c.SObjectType.getDescribe().fields.getMap();

        for (List<Quote_Document_Column__c> columns : columnsByTable.values()) {
            for (Quote_Document_Column__c column : columns) {
                if (String.isBlank(column.Value_Field__c)) {
                    continue;
                }
                if (!rowFields.containsKey(column.Value_Field__c.toLowerCase())) {
                    throw QuoteDocumentContributorError.build(
                        'COLUMN_VALUE_NOT_QUERIED',
                        'Column ' + column.Column_Code__c + ' binds ' + column.Value_Field__c
                            + ', which is not a field on Quote_Document_Row__c. It cannot be queried, and a '
                            + 'column that cannot be queried must fail rather than print an empty cell - a '
                            + 'null must always mean "no value", never "nobody selected it".'
                    );
                }
                fields.add(column.Value_Field__c);
            }
        }

        // Safe interpolation: every name above is either a literal from
        // BASE_ROW_FIELDS or one the describe map just proved exists.
        String soql =
            'SELECT ' + String.join(new List<String>(fields), ', ')
            + ' FROM Quote_Document_Row__c WHERE Quote_Document_Table__c IN :tableIds'
            + ' ORDER BY Display_Order__c, Row_Key__c';

        for (SObject row : Database.query(soql)) {
            Id tableId = (Id) row.get('Quote_Document_Table__c');
            if (!byTable.containsKey(tableId)) {
                byTable.put(tableId, new List<SObject>());
            }
            byTable.get(tableId).add(row);
        }
        return byTable;
    }

    private static Map<Id, List<Quote_Document_Block__c>> blocksFor(Set<Id> quoteIds) {
        Map<Id, List<Quote_Document_Block__c>> byQuote = new Map<Id, List<Quote_Document_Block__c>>();
        if (quoteIds.isEmpty()) {
            return byQuote;
        }
        for (Quote_Document_Block__c block : [
            SELECT Id, Quote__c, Block_Code__c, Block_Type__c, Display_Order__c, Is_Displayed__c,
                   Locale__c, Heading__c, Body__c, Source_Version__c
            FROM Quote_Document_Block__c
            WHERE Quote__c IN :quoteIds
            ORDER BY Display_Order__c, Block_Code__c
        ]) {
            if (!byQuote.containsKey(block.Quote__c)) {
                byQuote.put(block.Quote__c, new List<Quote_Document_Block__c>());
            }
            byQuote.get(block.Quote__c).add(block);
        }
        return byQuote;
    }

    // -----------------------------------------------------------------------
    // Projection
    // -----------------------------------------------------------------------

    private static QuoteDocumentPayload.PayloadResult build(
        QuoteDocumentPayload.PayloadRequest request,
        Map<Id, SBQQ__Quote__c> quotes,
        Map<Id, List<Quote_Document_Table__c>> tablesByQuote,
        Map<Id, List<Quote_Document_Column__c>> columnsByTable,
        Map<Id, List<SObject>> rowsByTable,
        Map<Id, List<Quote_Document_Block__c>> blocksByQuote,
        Map<Id, String> integrityFailureByQuote,
        Map<Id, String> actualHashByQuote
    ) {
        QuoteDocumentPayload.PayloadResult result = new QuoteDocumentPayload.PayloadResult();
        result.quoteId = request == null ? null : request.quoteId;
        result.success = false;

        try {
            if (request == null || request.quoteId == null) {
                fail('PAYLOAD_REQUEST_INVALID', 'A payload request must name a quote.');
            }
            SBQQ__Quote__c quote = quotes.get(request.quoteId);
            if (quote == null) {
                fail('QUOTE_NOT_FOUND', 'No Quote found for ' + request.quoteId + '.');
            }

            assertReady(quote);
            assertExpectationsMatch(request, quote);
            assertIntactOnce(quote, integrityFailureByQuote, actualHashByQuote);

            result.payload = project(
                quote,
                tablesByQuote.get(quote.Id),
                columnsByTable,
                rowsByTable,
                blocksByQuote.get(quote.Id),
                request.expectedRequestId
            );
            result.success = true;
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            // Per-request isolation: one failure must never remove a
            // successful result from the batch, and a partial batch must never
            // read as a whole one.
            result.success = false;
            result.errorMessage = e.getMessage();
            result.errorCode = e.getMessage().substringBefore(':').trim();
        }
        return result;
    }

    /**
     * Verifies the payload hash once per quote per batch, remembering the
     * outcome - including a FAILURE, so a tampered quote named by three
     * requests fails all three without being re-hashed three times.
     */
    private static void assertIntactOnce(
        SBQQ__Quote__c quote, Map<Id, String> failureByQuote, Map<Id, String> actualHashByQuote
    ) {
        if (failureByQuote.containsKey(quote.Id)) {
            String remembered = failureByQuote.get(quote.Id);
            if (remembered != null) {
                throw new QuoteDocumentGenerator.QuoteDocumentException(remembered);
            }
            return;
        }

        try {
            QuoteDocumentPayloadHash.assertIntact(
                quote.Id, quote.Document_Payload_Hash__c, actualHashByQuote.get(quote.Id)
            );
            failureByQuote.put(quote.Id, null);
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            failureByQuote.put(quote.Id, e.getMessage());
            throw e;
        }
    }

    private static void fail(String code, String detail) {
        throw QuoteDocumentContributorError.build(code, detail);
    }

    /** Step 06 condition 1: the status is named, so nobody has to go and look it up. */
    private static void assertReady(SBQQ__Quote__c quote) {
        if (!'Ready'.equals(quote.Document_Data_Status__c)) {
            fail(
                'SNAPSHOT_NOT_READY',
                'Quote ' + quote.Id + ' is "' + quote.Document_Data_Status__c + '", not Ready. Only a Ready '
                    + 'snapshot is complete and mutually consistent; anything else is either mid-generation, '
                    + 'known stale, or known failed.'
            );
        }
    }

    /**
     * Step 06 conditions 1a and 1b, together.
     *
     * A missing expectation is not a lenient case to wave through - it is the
     * launch contract being bypassed, which is condition 1b, and it fails with
     * its own message rather than being folded into a generic mismatch.
     */
    private static void assertExpectationsMatch(
        QuoteDocumentPayload.PayloadRequest request, SBQQ__Quote__c quote
    ) {
        if (String.isBlank(request.expectedRequestId) || String.isBlank(request.expectedFingerprint)) {
            fail(
                'LAUNCH_CONTRACT_BYPASSED',
                'Retrieval for quote ' + quote.Id + ' supplied no expected request Id and fingerprint. '
                    + 'Every launch must call generate-or-reuse first and bind to what it returns; reading a '
                    + 'Ready snapshot directly is how a document gets rendered from a snapshot that moved '
                    + 'underneath it.'
            );
        }

        if (!request.expectedRequestId.equals(quote.Document_Data_Request_Id__c)
            || !request.expectedFingerprint.equals(quote.Document_Data_Fingerprint__c)) {
            fail(
                'SNAPSHOT_MOVED',
                'Quote ' + quote.Id + ' was regenerated between launch and retrieval. Expected request '
                    + request.expectedRequestId + ' / fingerprint ' + request.expectedFingerprint
                    + ', found request ' + quote.Document_Data_Request_Id__c + ' / fingerprint '
                    + quote.Document_Data_Fingerprint__c + '. Re-run generate-or-reuse and retrieve with '
                    + 'what it returns - never with the older expectations, and never by accepting the '
                    + 'newer snapshot silently.'
            );
        }
    }

    private static QuoteDocumentPayload project(
        SBQQ__Quote__c quote,
        List<Quote_Document_Table__c> tables,
        Map<Id, List<Quote_Document_Column__c>> columnsByTable,
        Map<Id, List<SObject>> rowsByTable,
        List<Quote_Document_Block__c> blocks,
        String requestId
    ) {
        QuoteDocumentPayload payload = new QuoteDocumentPayload();
        payload.requestId = requestId;
        payload.quoteId = quote.Id;
        payload.quoteNumber = quote.Name;
        payload.fingerprint = quote.Document_Data_Fingerprint__c;
        payload.generatedOn = quote.Document_Data_Generated_On__c;
        payload.status = quote.Document_Data_Status__c;
        payload.contentVersion = QuoteDocumentFingerprint.contentVersion();

        Map<String, Object> populated = quote.getPopulatedFieldsAsMap();
        payload.currencyIsoCode = populated.containsKey('CurrencyIsoCode')
            ? String.valueOf(populated.get('CurrencyIsoCode'))
            : null;

        List<QuoteDocumentPayload.Section> sections = new List<QuoteDocumentPayload.Section>();

        for (Quote_Document_Table__c table : (tables == null ? new List<Quote_Document_Table__c>() : tables)) {
            if (table.Is_Displayed__c != true) {
                // Hidden means absent from the payload, not styled away. A
                // renderer that receives it would have to decide, and deciding
                // is precisely what this contract removes from renderers.
                continue;
            }
            assertTableComplete(table, rowsByTable.get(table.Id));
            payload.locale = table.Locale__c;
            sections.add(tableSection(table, columnsByTable.get(table.Id), rowsByTable.get(table.Id)));
        }

        for (Quote_Document_Block__c block : (blocks == null ? new List<Quote_Document_Block__c>() : blocks)) {
            if (block.Is_Displayed__c != true) {
                continue;
            }
            if (payload.locale == null) {
                payload.locale = block.Locale__c;
            }
            sections.add(blockSection(block));
        }

        payload.sections = sortedByOrder(sections);
        return payload;
    }

    /** Step 06 condition 8 - rows that refer to an incomplete generation. */
    private static void assertTableComplete(Quote_Document_Table__c table, List<SObject> rows) {
        if (!'Complete'.equals(table.Status__c)) {
            fail(
                'TABLE_NOT_COMPLETE',
                'Table ' + table.Table_Code__c + ' has Status__c "' + table.Status__c + '", not Complete, so '
                    + 'its rows belong to a generation that never finished.'
            );
        }

        Integer actual = rows == null ? 0 : rows.size();
        Integer recorded = table.Row_Count__c == null ? -1 : Integer.valueOf(table.Row_Count__c);
        if (recorded != actual) {
            fail(
                'TABLE_ROW_COUNT_MISMATCH',
                'Table ' + table.Table_Code__c + ' records Row_Count__c ' + recorded + ' but has ' + actual
                    + ' rows. Rows were added or removed after publication.'
            );
        }
    }

    private static QuoteDocumentPayload.Section tableSection(
        Quote_Document_Table__c table, List<Quote_Document_Column__c> columns, List<SObject> rows
    ) {
        QuoteDocumentPayload.Section section = new QuoteDocumentPayload.Section();
        section.sectionType = 'Table';
        section.code = table.Table_Code__c;
        section.displayOrder = table.Display_Order__c;
        section.title = table.Display_Title__c;
        section.subtitle = table.Display_Subtitle__c;
        section.introText = table.Intro_Text__c;
        section.footerText = table.Footer_Text__c;
        section.columns = new List<QuoteDocumentPayload.Column>();
        section.rows = new List<QuoteDocumentPayload.Row>();

        Map<String, String> fieldByCode = new Map<String, String>();
        for (Quote_Document_Column__c column : (columns == null
                ? new List<Quote_Document_Column__c>() : columns)) {
            if (column.Is_Displayed__c != true) {
                continue;
            }
            QuoteDocumentPayload.Column projected = new QuoteDocumentPayload.Column();
            projected.code = column.Column_Code__c;
            projected.label = column.Display_Label__c;
            projected.displayOrder = column.Display_Order__c;
            projected.dataType = column.Data_Type__c;
            section.columns.add(projected);

            if (String.isNotBlank(column.Value_Field__c)) {
                fieldByCode.put(column.Column_Code__c, column.Value_Field__c);
            }
        }

        for (SObject row : (rows == null ? new List<SObject>() : rows)) {
            if (row.get('Is_Displayed__c') != true) {
                continue;
            }
            QuoteDocumentPayload.Row projected = new QuoteDocumentPayload.Row();
            projected.key = (String) row.get('Row_Key__c');
            projected.rowType = (String) row.get('Row_Type__c');
            projected.label = (String) row.get('Display_Label__c');
            projected.labelKey = (String) row.get('Label_Key__c');
            projected.displayOrder = (Decimal) row.get('Display_Order__c');
            projected.groupLevel = (Decimal) row.get('Group_Level__c');

            for (QuoteDocumentPayload.Column column : section.columns) {
                String field = fieldByCode.get(column.code);
                if (field == null) {
                    // The label column: its value is the row's own label, so
                    // an adapter never special-cases it.
                    projected.values.put(column.code, projected.label);
                    continue;
                }
                // Raw and typed. Formatting belongs to the renderer, which has
                // locale and currency to do it with.
                projected.values.put(column.code, row.get(field));
            }
            section.rows.add(projected);
        }
        return section;
    }

    private static QuoteDocumentPayload.Section blockSection(Quote_Document_Block__c block) {
        QuoteDocumentPayload.Section section = new QuoteDocumentPayload.Section();
        section.sectionType = 'Block';
        section.code = block.Block_Code__c;
        section.displayOrder = block.Display_Order__c;
        section.heading = block.Heading__c;
        section.body = block.Body__c;
        section.blockType = block.Block_Type__c;
        return section;
    }

    /**
     * Tables and blocks come from two queries and must interleave into one
     * sequence. Insertion sort on a small list - a document has tens of
     * sections, not thousands, and Apex cannot sort a List of a
     * non-Comparable type without boilerplate. Same choice, for the same
     * reason, as QuoteDocumentRowBuilder's own ordering.
     */
    private static List<QuoteDocumentPayload.Section> sortedByOrder(
        List<QuoteDocumentPayload.Section> sections
    ) {
        List<QuoteDocumentPayload.Section> sorted = new List<QuoteDocumentPayload.Section>();
        for (QuoteDocumentPayload.Section section : sections) {
            Integer at = 0;
            while (at < sorted.size() && compare(sorted[at], section) <= 0) {
                at++;
            }
            // Apex's add(index, element) rejects index == size, so appending
            // past the end is a separate call rather than a special index.
            if (at == sorted.size()) {
                sorted.add(section);
            } else {
                sorted.add(at, section);
            }
        }
        return sorted;
    }

    /** Code breaks a tie, so ordering is stable rather than dependent on query order. */
    private static Integer compare(QuoteDocumentPayload.Section a, QuoteDocumentPayload.Section b) {
        Decimal left = a.displayOrder == null ? 0 : a.displayOrder;
        Decimal right = b.displayOrder == null ? 0 : b.displayOrder;
        if (left != right) {
            return left < right ? -1 : 1;
        }
        return (a.code == null ? '' : a.code).compareTo(b.code == null ? '' : b.code);
    }
}
