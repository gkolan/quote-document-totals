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

    /**
     * Stays on this class despite the split - QuoteDocumentQuery,
     * QuoteDocumentVerification, QuoteDocumentTableDefinition,
     * QuoteDocumentLine, QuoteDocumentRowBuilder and the customizer registry
     * all throw it by this name, and so do the tests that catch it. Moving it
     * would be a rename across the whole framework for no gain.
     */
    public class QuoteDocumentException extends Exception {}

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

        // The launch contract, exposed declaratively so a Flow-driven launch
        // can pass these to the renderer - step 01A section 6b. A renderer
        // must bind by request Id AND fingerprint, so both have to leave the
        // action, not just be written to the Quote.
        @InvocableVariable(label='Request Id')
        public String requestId;
        @InvocableVariable(label='Fingerprint')
        public String fingerprint;
        @InvocableVariable(label='Reused Existing Snapshot')
        public Boolean reused;
    }

    /**
     * What one quote's generate-or-reuse actually did.
     *
     * generate() used to return void, which made the launch contract in step
     * 01A section 6b unimplementable: a caller had no way to learn the request
     * Id and fingerprint it must hand the renderer, so it would have had to
     * re-read the Quote - a second read that can already disagree with what
     * this transaction wrote.
     *
     * `reused` is not cosmetic. It is what an ALWAYS_REBUILD test asserts on,
     * and what tells an operator whether a launch actually recomputed.
     */
    public class GenerationOutcome {
        public Id quoteId;
        public String requestId;
        public String fingerprint;
        public String status;
        public Boolean reused;

        /** Integrity of the persisted OUTPUT, as opposed to the fingerprint's identity of the INPUTS. */
        public String payloadHash;
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
                List<GenerationOutcome> outcomes = generate(new Set<Id>{ request.quoteId });

                // Every launch must hand the renderer the request Id and the
                // fingerprint it just computed, so a declarative launch has to
                // be able to read them back off this action - step 01A 6b.
                if (!outcomes.isEmpty()) {
                    result.requestId = outcomes[0].requestId;
                    result.fingerprint = outcomes[0].fingerprint;
                    result.reused = outcomes[0].reused;
                }

                result.tableCount = [
                    SELECT COUNT() FROM Quote_Document_Table__c WHERE Quote__c = :request.quoteId
                ];
                result.rowCount = [
                    SELECT COUNT() FROM Quote_Document_Row__c
                    WHERE Quote_Document_Table__r.Quote__c = :request.quoteId
                ];
                result.success = true;
                result.message = (result.reused == true ? 'Reused the existing snapshot: ' : 'Generated ')
                    + result.tableCount + ' tables and ' + result.rowCount
                    + ' rows. This quote is ready for document generation.';
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
    public static List<GenerationOutcome> generate(Set<Id> quoteIds) {
        List<SBQQ__Quote__c> quotes = QuoteDocumentQuery.quotesWithLines(quoteIds);

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

        List<GenerationOutcome> outcomes = new List<GenerationOutcome>();
        for (SBQQ__Quote__c quote : quotes) {
            outcomes.add(generateOne(quote));
        }
        return outcomes;
    }

    /**
     * Refuses to start when another attempt is genuinely still running.
     *
     * This is where the abandonment window earns its keep. A quote sitting in
     * Generating is either a live attempt - in which case starting a second
     * one means two workers building the same snapshot - or a dead one, in
     * which case refusing forever would block the quote permanently.
     * QuoteDocumentLifecycle.isAbandoned draws that line, from configuration
     * rather than a literal, and a null start time counts as abandoned because
     * that state can only come from an interrupted write.
     *
     * Taking over is safe because publication re-reads the request Id: a
     * superseded worker that finishes later cannot publish.
     */
    private static void assertNotAlreadyRunning(SBQQ__Quote__c quote) {
        Datetime startedAt = (Datetime) quote.getPopulatedFieldsAsMap()
            .get('Document_Data_Started_At__c');

        if (!'Generating'.equals(quote.Document_Data_Status__c)) {
            return;
        }
        if (QuoteDocumentLifecycle.isAbandoned(quote.Document_Data_Status__c, startedAt, System.now())) {
            // Abandoned: take it over. The previous attempt cannot publish.
            return;
        }

        throw QuoteDocumentContributorError.build(
            'GENERATION_ALREADY_RUNNING',
            'Quote ' + quote.Id + ' is already being generated (request '
                + quote.Document_Data_Request_Id__c + ', started ' + startedAt + '). Starting a second '
                + 'attempt would mean two workers building the same snapshot. It becomes available for '
                + 'takeover once the abandonment window has passed.'
        );
    }

    /**
     * Records that this attempt is in flight.
     *
     * Written in its own DML before the savepoint work so Document_Data_
     * Started_At__c means what its help text says - when THIS attempt began,
     * which is what abandonment detection compares against.
     */
    private static void claim(Id quoteId, String requestId) {
        QuoteDocumentStaleness.suppress();
        try {
            update new SBQQ__Quote__c(
                Id = quoteId,
                Document_Data_Status__c = 'Generating',
                Document_Data_Started_At__c = System.now(),
                Document_Data_Request_Id__c = requestId
            );
        } finally {
            QuoteDocumentStaleness.resume();
        }
    }

    /**
     * Correlates one generation attempt for support, which is exactly what
     * SBQQ__Quote__c.Document_Data_Request_Id__c's help text already describes
     * - the field exists and nothing has ever written it. Wired up here rather
     * than adding a second field with the same meaning.
     *
     * Not a UUID type: the value only has to be unique enough to tell one
     * attempt from another in a log, and time-plus-random reads better in a
     * support ticket than an opaque hex string.
     */
    private static String newRequestId() {
        return System.now().getTime() + '-' + Math.abs(Crypto.getRandomInteger());
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

    private static GenerationOutcome generateOne(SBQQ__Quote__c quote) {
        List<QuoteDocumentLine> allLines = normalize(quote);

        // Assigned before any work begins, so the failure path writes the Id
        // of the attempt that actually failed. Assigning it inside the try
        // would leave a rolled-back attempt with no identity at all.
        String requestId = newRequestId();

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

            GenerationOutcome outcome = new GenerationOutcome();
            outcome.quoteId = quote.Id;
            outcome.fingerprint = fingerprint;

            if (canReuse(quote, fingerprint, definitions)) {
                // The request Id of the attempt that PUBLISHED this snapshot,
                // never a fresh one. A renderer binds by request Id, so
                // inventing one here would hand it an identifier matching no
                // generation that ever ran - step 01A section 9.
                outcome.requestId = quote.Document_Data_Request_Id__c;
                outcome.status = quote.Document_Data_Status__c;
                outcome.payloadHash = quote.Document_Payload_Hash__c;
                outcome.reused = true;
                return outcome;
            }

            // One locale per snapshot, decided once, before any string is
            // resolved. Held for the whole quote so two tables can never come
            // out in different languages - the locale is part of the
            // fingerprint, so "this snapshot, in this language" is a single
            // identity.
            // Claim the quote for this attempt before any work begins. The
            // row is already held under FOR UPDATE by the query above, so no
            // other transaction can interleave between the claim and the
            // publish - which is what makes the supersede check below a
            // guarantee rather than a narrowing of the window.
            assertNotAlreadyRunning(quote);
            claim(quote.Id, requestId);

            String locale = QuoteDocumentLocale.resolve(quote);
            QuoteDocumentLabels labels = QuoteDocumentLabels.forLocale(locale);

            outcome.requestId = requestId;
            outcome.status = 'Ready';
            outcome.reused = false;

            delete [SELECT Id FROM Quote_Document_Table__c WHERE Quote__c = :quote.Id];
            delete [SELECT Id FROM Quote_Document_Block__c WHERE Quote__c = :quote.Id];

            for (QuoteDocumentTableDefinition definition : definitions) {
                List<QuoteDocumentLine> lines = applyFilter(allLines, definition.lineFilter);

                Quote_Document_Table__c table = newTable(quote, definition, !lines.isEmpty(), locale);
                tables.add(table);
                List<Quote_Document_Row__c> rows =
                    new QuoteDocumentRowBuilder(definition, labels).build(lines);
                rows = applyRowCustomizer(quote, definition, lines, rows, labels);
                rowsByCode.put(definition.tableCode, rows);
            }
            insert tables;

            Map<String, Quote_Document_Table__c> tableByCode = new Map<String, Quote_Document_Table__c>();
            for (Quote_Document_Table__c t : tables) {
                tableByCode.put(t.Table_Code__c, t);
            }

            // Columns, once the tables have Ids. Built from the same
            // definitions the rows came from, so a table can never state a
            // column layout that its rows were not generated against.
            List<Quote_Document_Column__c> allColumns = new List<Quote_Document_Column__c>();
            for (QuoteDocumentTableDefinition definition : definitions) {
                Id tableId = tableByCode.get(definition.tableCode).Id;
                for (QuoteDocumentColumnDefinition column : QuoteDocumentColumnDefinition.forTable(definition)) {
                    allColumns.add(newColumn(tableId, column, labels));
                }
            }
            insert allColumns;

            // Standalone narrative, ordered in the SAME sequence as the
            // tables so a renderer walks one list. Core decides what is
            // included; the renderer never does.
            List<Quote_Document_Block__c> blocks = QuoteDocumentBlockBuilder.build(quote, locale);
            QuoteDocumentBlockBuilder.assertOrderingIsUnambiguous(blocks, tables);
            insert blocks;

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

                // Title and locale are carried onto the stamped record so
                // verification can actually see them. They were set at insert
                // and are unchanged here - re-sending two fields is a smaller
                // price than a presentation assertion that has to re-query the
                // row it is verifying.
                Quote_Document_Table__c table = new Quote_Document_Table__c(
                    Id = inserted.Id,
                    Table_Code__c = inserted.Table_Code__c,
                    Display_Title__c = inserted.Display_Title__c,
                    Locale__c = inserted.Locale__c
                );
                stampTable(table, definition, rows);
                QuoteDocumentVerification.verify(quote, table, definition, rows);
                stamped.add(table);
            }
            update stamped;

            // Only now is the quote safe to print from. Written last and in the
            // same transaction as the rows, so Ready always means every table
            // came from this one generation. The fingerprint stamped here is
            // the one computed at the top of this method, before generation -
            // nothing that feeds it changes mid-transaction.
            // Last thing before publication: confirm this attempt still owns
            // the quote. A request that was taken over as abandoned may still
            // be running; if it published here it would overwrite a snapshot
            // built from newer inputs with one built from older ones, and
            // nothing downstream could tell.
            QuoteDocumentLifecycle.assertStillOwns(quote.Id, requestId);

            // Computed AFTER insert and after verification, by reading the
            // snapshot back out of the database. Reading it back rather than
            // hashing the in-memory lists is the point: the hash must describe
            // what was actually saved, including anything a trigger, a
            // validation rule or a field default changed on the way in.
            // Hashing the intent would certify a document that was never
            // stored.
            String payloadHash = QuoteDocumentPayloadHash.compute(quote.Id);
            outcome.payloadHash = payloadHash;

            markQuote(quote.Id, 'Ready', System.now(), null, fingerprint, requestId, payloadHash);

            return outcome;

        } catch (DmlException de) {
            Database.rollback(sp);
            // The bare platform message names neither the row nor the field,
            // which makes a permissions problem needlessly hard to diagnose.
            String detail = de.getMessage();
            if (de.getNumDml() > 0) {
                detail += ' | fields: ' + de.getDmlFieldNames(0) + ' | ' + de.getDmlMessage(0);
            }
            throw fail(quote, detail, de, requestId);
        } catch (Exception e) {
            Database.rollback(sp);

            // A LOCK failure is not a document failure. Nothing about the
            // existing snapshot is wrong - the generation simply did not run -
            // so the status is left exactly as it was, and the error is
            // rethrown for the caller to retry. Writing Failed here would mark
            // a perfectly good Ready snapshot as broken because a neighbouring
            // transaction happened to hold a row.
            if (QuoteDocumentLifecycle.isRetryable(e)) {
                throw e;
            }
            throw fail(quote, e.getMessage(), e, requestId);
        }
    }

    /**
     * Records the failure on the Quote and returns the exception to throw.
     *
     * The status write happens after the rollback and in its own DML, so it
     * survives. A quote left silently on its previous Ready status after a
     * failed regeneration is exactly how a stale document gets signed.
     */
    private static QuoteDocumentException fail(
        SBQQ__Quote__c quote, String detail, Exception cause, String requestId
    ) {
        // The thrown message keeps the full detail: it goes to the caller and
        // the debug log, both of which are access-controlled.
        String message = 'Document generation failed for quote ' + quote.Name + ': ' + detail;

        try {
            // What gets PERSISTED is assembled from a stable code plus
            // allowlisted context - never copied from the exception.
            // Document_Data_Error__c is readable by anyone who can read the
            // Quote, and raw exception text echoes customer data: a DML error
            // repeats the field values it rejected, a contributor's message
            // can quote a product description. Abbreviating to 3000 characters
            // bounded the length and sanitized nothing.
            markQuote(
                quote.Id,
                'Failed',
                null,
                QuoteDocumentError.persistable(cause, requestId),
                requestId
            );
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
    private static void markQuote(
        Id quoteId, String status, Datetime generatedOn, String error, String requestId
    ) {
        QuoteDocumentStaleness.suppress();
        try {
            update new SBQQ__Quote__c(
                Id = quoteId,
                Document_Data_Status__c = status,
                Document_Data_Generated_On__c = generatedOn,
                Document_Data_Error__c = error,
                Document_Data_Request_Id__c = requestId
            );
        } finally {
            QuoteDocumentStaleness.resume();
        }
    }

    /**
     * Success path only - stamps the fingerprint and the request Id that made
     * this generation's output.
     *
     * The request Id is written here, with Ready and the fingerprint, so all
     * three describe the same attempt. Writing it earlier would leave a
     * request Id on the Quote for an attempt that then rolled back, pointing
     * support at a generation whose records never existed.
     */
    private static void markQuote(
        Id quoteId, String status, Datetime generatedOn, String error, String fingerprint,
        String requestId, String payloadHash
    ) {
        QuoteDocumentStaleness.suppress();
        try {
            update new SBQQ__Quote__c(
                Id = quoteId,
                Document_Data_Status__c = status,
                Document_Data_Generated_On__c = generatedOn,
                Document_Data_Error__c = error,
                Document_Data_Fingerprint__c = fingerprint,
                Document_Data_Request_Id__c = requestId,
                Document_Payload_Hash__c = payloadHash
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

        // One ALWAYS_REBUILD contributor on ANY applicable table skips reuse
        // for the WHOLE QUOTE, not just that table. That is not a design
        // preference - canReuse is evaluated per quote and generate() returns
        // from the entire quote on a match, so "defeat reuse for that table"
        // is not expressible here. Said plainly because the coarser behaviour
        // is the one an admin will be surprised by.
        for (QuoteDocumentTableDefinition definition : definitions) {
            if (definition.alwaysRebuilds()) {
                return false;
            }
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
    // Normalize
    //
    // The query itself, and the schema validation that makes its dynamic SOQL
    // safe, live in QuoteDocumentQuery.
    // -----------------------------------------------------------------------

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
        List<Quote_Document_Row__c> rows,
        QuoteDocumentLabels labels
    ) {
        if (!definition.hasContributor()) {
            return rows;
        }

        QuoteDocumentRowCustomizerContext context = new QuoteDocumentRowCustomizerContext();
        context.quote = quote;
        context.definition = definition;
        context.lines = lines;
        context.rows = rows;
        context.currencyIsoCode = currencyOf(quote);
        context.locale = labels.getLocale();
        context.labels = labels;

        // Apex first, then Flow. This order is public contract, not incidental
        // - step 01A section 7. The Flow sees the Apex customizer's rows and
        // can overwrite them; the Apex customizer never sees the Flow's. Last
        // writer wins on the same field of the same row, deliberately, so a
        // Flow can undo an Apex customizer without touching its code.
        if (String.isNotBlank(definition.rowCustomizerCode)) {
            context.rows = runContributor(
                QuoteDocumentRowCustomizerRegistry.resolve(definition.rowCustomizerCode), context
            );
        }
        if (String.isNotBlank(definition.rowCustomizerFlow)) {
            context.rows = runContributor(new QuoteDocumentFlowRowCustomizer(), context);
        }

        QuoteDocumentContributorOutput.validate(context.rows, definition);
        return context.rows;
    }

    /** Null means "unchanged" - the documented Apex contract. The Flow bridge rejects null before it reaches here. */
    private static List<Quote_Document_Row__c> runContributor(
        QuoteDocumentRowCustomizer instance, QuoteDocumentRowCustomizerContext context
    ) {
        List<Quote_Document_Row__c> returned = instance.customize(context);
        return returned == null ? context.rows : returned;
    }

    /**
     * CurrencyIsoCode does not exist in a single-currency org, so a static
     * reference will not compile there - the same reason QuoteDocumentQuery
     * builds its field list dynamically.
     */
    private static String currencyOf(SBQQ__Quote__c quote) {
        Map<String, Object> populated = quote.getPopulatedFieldsAsMap();
        return populated.containsKey('CurrencyIsoCode')
            ? String.valueOf(populated.get('CurrencyIsoCode'))
            : null;
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

    /**
     * One generated column record.
     *
     * Display_Label__c is the field's own schema label for now. Step 03
     * replaces this with a dictionary lookup keyed on Column_Code__c - which
     * is why the code, not the label, is what a renderer keys off. Reading the
     * schema label rather than constructing an English phrase here keeps the
     * "no English literal outside the dictionary" rule intact in the meantime.
     */
    private static Quote_Document_Column__c newColumn(
        Id tableId, QuoteDocumentColumnDefinition column, QuoteDocumentLabels labels
    ) {
        return new Quote_Document_Column__c(
            Quote_Document_Table__c = tableId,
            Column_Code__c = column.columnCode,
            Display_Label__c = columnLabel(column, labels),
            Display_Order__c = column.displayOrder,
            Value_Field__c = column.valueField,
            Data_Type__c = column.dataType,
            Is_Displayed__c = true
        );
    }

    /**
     * The dictionary first, the schema label only as a documented fallback.
     *
     * A column code that has a dictionary entry is translatable; one that does
     * not falls back to the field's own label, which at least follows the
     * org's own translations of that field rather than a string invented here.
     * The fallback is deliberate and visible - it is never a blank.
     */
    private static String columnLabel(QuoteDocumentColumnDefinition column, QuoteDocumentLabels labels) {
        if (column.isLabelColumn()) {
            // The one heading with no field behind it, so the dictionary is
            // the only possible source and a missing key must fail.
            return labels.resolve(QuoteDocumentLabels.KEY_COLUMN_LABEL);
        }
        if (labels.has(column.columnCode)) {
            return labels.resolve(column.columnCode);
        }

        SObjectField field = Quote_Document_Row__c.SObjectType.getDescribe()
            .fields.getMap().get(column.valueField.toLowerCase());
        return field == null
            ? column.columnCode
            : field.getDescribe().getLabel().abbreviate(255);
    }

    /**
     * hasQualifyingLines drives Is_Displayed__c, and it is deliberately about
     * LINES rather than rows.
     *
     * "No Detail rows" would be the obvious test and is wrong: a summary table
     * (Show_Details__c = false) never emits a Detail row even when it has
     * plenty of data, so that rule would hide CHARGE_TYPE_SUMMARY and every
     * table like it. Row_Count__c is wrong for the opposite reason - the
     * builder always emits a Grand Total, so an empty table still has a row.
     * Whether any source line survived the filter is the question the renderer
     * conditional was really asking.
     */
    private static Quote_Document_Table__c newTable(
        SBQQ__Quote__c quote,
        QuoteDocumentTableDefinition definition,
        Boolean hasQualifyingLines,
        String locale
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
            Status__c = 'Generating',

            // Printable presentation, snapshotted so a renderer never reads
            // configuration - the whole point of the contract. Title is
            // guaranteed non-blank by config load; the rest are legitimately
            // optional and blank is a valid value, not a missing one.
            Display_Title__c = definition.displayTitle,
            Display_Subtitle__c = definition.displaySubtitle,
            Intro_Text__c = definition.introText,
            Footer_Text__c = definition.footerText,
            Is_Displayed__c = hasQualifyingLines,
            Locale__c = locale
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
        Quote_Document_Row__c grandTotal = QuoteDocumentVerification.findGrandTotal(rows);

        for (String field : QuoteDocumentTableDefinition.measureFields(definition.measureSet)) {
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

}
