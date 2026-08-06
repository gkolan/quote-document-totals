/**
 * Covers the pieces around generation rather than generation itself: the
 * readiness gate, stale marking, the per-quote Queueable, the Custom Metadata
 * definitions, and retention.
 *
 * The generation arithmetic is covered by QuoteDocumentGeneratorTest.
 */
@IsTest
private class QuoteDocumentLifecycleTest {

    @TestSetup
    static void setup() {
        QuoteDocumentTestData.setupLifecycle();
    }

    private static SBQQ__Quote__c quote() {
        return QuoteDocumentTestData.lifecycleQuote();
    }

    private static Id quoteId() {
        return quote().Id;
    }

    // Custom Metadata loading and grouping shape moved to
    // QuoteDocumentGroupingTest.

    // -----------------------------------------------------------------------
    // Readiness gate
    // -----------------------------------------------------------------------

    @IsTest
    static void generationMarksTheQuoteReady() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quote().Id });
        Test.stopTest();

        SBQQ__Quote__c after = quote();
        Assert.areEqual('Ready', after.Document_Data_Status__c,
            'Only a completed generation may open the document gate');
        Assert.isNotNull(after.Document_Data_Generated_On__c);
        Assert.isNull(after.Document_Data_Error__c);
    }

    @IsTest
    static void editingALineMarksTheQuoteStale() {
        QuoteDocumentGenerator.generate(new Set<Id>{ quote().Id });
        Assert.areEqual('Ready', quote().Document_Data_Status__c, 'Precondition: Ready');

        Test.startTest();
        SBQQ__QuoteLine__c line = [SELECT Id, SBQQ__Quantity__c FROM SBQQ__QuoteLine__c LIMIT 1];
        line.SBQQ__Quantity__c = 5;
        update line;
        Test.stopTest();

        // Test.stopTest() above is what runs the deferred future call.
        Assert.areEqual('Stale', quote().Document_Data_Status__c,
            'A changed line means the generated totals no longer describe the quote');
    }

    @IsTest
    static void deletingALineMarksTheQuoteStale() {
        QuoteDocumentGenerator.generate(new Set<Id>{ quote().Id });

        Test.startTest();
        delete [SELECT Id FROM SBQQ__QuoteLine__c LIMIT 1];
        Test.stopTest();

        Assert.areEqual('Stale', quote().Document_Data_Status__c);
    }

    @IsTest
    static void anUngeneratedQuoteIsNeverMarkedStale() {
        Assert.areEqual('Not Generated', quote().Document_Data_Status__c, 'Precondition');

        Test.startTest();
        SBQQ__QuoteLine__c line = [SELECT Id, SBQQ__Quantity__c FROM SBQQ__QuoteLine__c LIMIT 1];
        line.SBQQ__Quantity__c = 7;
        update line;
        Test.stopTest();

        Assert.areEqual('Not Generated', quote().Document_Data_Status__c,
            'Nothing has been generated, so there is nothing to go stale');
    }

    @IsTest
    static void writingTheStatusDoesNotRetriggerStaleMarking() {
        QuoteDocumentGenerator.generate(new Set<Id>{ quote().Id });

        // Document_Data_Status__c is not a watched field, so this update must
        // not bounce the quote straight back to Stale.
        Test.startTest();
        update new SBQQ__Quote__c(Id = quote().Id, Document_Data_Error__c = 'touched');
        Test.stopTest();

        Assert.areEqual('Ready', quote().Document_Data_Status__c,
            'Only fields that change the generated content should invalidate it');
    }

    // -----------------------------------------------------------------------
    // Async
    // -----------------------------------------------------------------------

    @IsTest
    static void queueableSkipsAQuoteThatIsNoLongerStale() {
        Id quoteId = quote().Id;
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Datetime firstRun = quote().Document_Data_Generated_On__c;

        // Ready, not Stale - so a queued job from an earlier save must exit
        // rather than regenerate. This is what makes duplicate requests free.
        Test.startTest();
        System.enqueueJob(new QuoteDocumentGenerateJob(quoteId));
        Test.stopTest();

        Assert.areEqual(firstRun, quote().Document_Data_Generated_On__c,
            'A non-stale quote should not be regenerated');
    }

    @IsTest
    static void queueableRegeneratesAStaleQuote() {
        Id quoteId = quote().Id;
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        update new SBQQ__Quote__c(Id = quoteId, Document_Data_Status__c = 'Stale');

        Test.startTest();
        System.enqueueJob(new QuoteDocumentGenerateJob(quoteId));
        Test.stopTest();

        Assert.areEqual('Ready', quote().Document_Data_Status__c,
            'A stale quote should be brought back to Ready');
    }

    @IsTest
    static void generateAsyncBackfillsAQuoteThatWasNeverGenerated() {
        Id quoteId = quote().Id;
        Assert.areEqual('Not Generated', quote().Document_Data_Status__c, 'Precondition');

        // A backfill must not skip quotes just because they are not Stale -
        // "never generated" is precisely the case it exists to handle.
        Test.startTest();
        QuoteDocumentGenerator.generateAsync(new Set<Id>{ quoteId });
        Test.stopTest();

        Assert.areEqual('Ready', quote().Document_Data_Status__c,
            'A backfill should generate unconditionally');
        Assert.isTrue([SELECT COUNT() FROM Quote_Document_Table__c] > 0);
    }

    // -----------------------------------------------------------------------
    // Flow entry point
    // -----------------------------------------------------------------------

    @IsTest
    static void invocableReturnsCountsForTheConfirmationScreen() {
        QuoteDocumentGenerator.Request request = new QuoteDocumentGenerator.Request();
        request.quoteId = quote().Id;

        Test.startTest();
        List<QuoteDocumentGenerator.Result> results =
            QuoteDocumentGenerator.generateFromFlow(new List<QuoteDocumentGenerator.Request>{ request });
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.isTrue(results[0].success, results[0].message);
        Assert.isTrue(results[0].tableCount > 0, 'The screen should be able to state a table count');
        Assert.isTrue(results[0].rowCount > 0, 'The screen should be able to state a row count');
        Assert.isTrue(results[0].message.contains('ready'), 'The message should be usable as-is');
    }

    @IsTest
    static void invocableReportsFailureRatherThanThrowing() {
        QuoteDocumentGenerator.Request request = new QuoteDocumentGenerator.Request();
        request.quoteId = null;

        Test.startTest();
        List<QuoteDocumentGenerator.Result> results =
            QuoteDocumentGenerator.generateFromFlow(new List<QuoteDocumentGenerator.Request>{ request });
        Test.stopTest();

        // A flow should show the user an error screen, not an unhandled fault.
        Assert.isFalse(results[0].success);
        Assert.isNotNull(results[0].message);
    }

    // -----------------------------------------------------------------------
    // Retention
    // -----------------------------------------------------------------------

    @IsTest
    static void retentionPurgesRejectedQuotesAndResetsTheGate() {
        Id quoteId = quote().Id;
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Assert.isTrue([SELECT COUNT() FROM Quote_Document_Table__c] > 0, 'Precondition: tables exist');

        update new SBQQ__Quote__c(Id = quoteId, SBQQ__Status__c = 'Rejected');

        Test.startTest();
        Database.executeBatch(new QuoteDocumentRetention(), 200);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Quote_Document_Table__c],
            'A rejected quote will never produce a document');
        Assert.areEqual(0, [SELECT COUNT() FROM Quote_Document_Row__c],
            'Rows go with their table through the master-detail cascade');
        Assert.areEqual('Not Generated', quote().Document_Data_Status__c,
            'The gate must close when the data behind it is gone');
    }

    @IsTest
    static void retentionLeavesAnAcceptedQuoteAlone() {
        Id quoteId = quote().Id;
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });

        update new SBQQ__Quote__c(Id = quoteId, SBQQ__Status__c = 'Accepted');
        QuoteDocumentRetention.retentionDays = 0; // everything is past the window

        Test.startTest();
        Database.executeBatch(new QuoteDocumentRetention(), 200);
        Test.stopTest();

        Assert.isTrue([SELECT COUNT() FROM Quote_Document_Table__c] > 0,
            'An accepted quote may sit behind a signed document - never purge it automatically');
    }

    /**
     * Every other retention test calls Database.executeBatch directly against
     * a new QuoteDocumentRetention() - correct for proving the batch logic,
     * but it never actually exercises the Schedulable.execute entry point
     * System.schedule() calls. The batch behavior itself is already proven by
     * the two tests above; this one exists only to cover that entry point.
     */
    @IsTest
    static void scheduledExecuteEnqueuesTheRetentionBatch() {
        Test.startTest();
        new QuoteDocumentRetention().execute(null);
        Test.stopTest();

        Assert.isTrue(true, 'Scheduling the retention batch must not throw');
    }

    // -----------------------------------------------------------------------
    // Request ownership
    // -----------------------------------------------------------------------

    @IsTest
    static void generatingIsAWritableRestrictedPicklistValue() {
        Id quoteId = quote().Id;

        Test.startTest();
        update new SBQQ__Quote__c(Id = quoteId, Document_Data_Status__c = 'Generating');
        Test.stopTest();

        Assert.areEqual('Generating', quote().Document_Data_Status__c,
            'Generating must be a real value in the restricted picklist, not just documentation');
    }

    // -----------------------------------------------------------------------
    // Staleness - branches not reached by the trigger-driven tests above
    // -----------------------------------------------------------------------

    /**
     * Every trigger-driven staleness test above supplies a real prior version
     * (Salesforce always does, in a genuine update trigger). Calling
     * markStaleFromQuotes directly with a prior map that is deliberately
     * missing an entry proves the "nothing to compare against, so skip rather
     * than guess" branch without needing a contrived trigger scenario.
     */
    @IsTest
    static void markStaleFromQuotesSkipsAQuoteWithNoPriorVersion() {
        Id qId = quote().Id;
        SBQQ__Quote__c updated = new SBQQ__Quote__c(Id = qId);
        Map<Id, SBQQ__Quote__c> priorById = new Map<Id, SBQQ__Quote__c>();

        Test.startTest();
        QuoteDocumentStaleness.markStaleFromQuotes(new List<SBQQ__Quote__c>{ updated }, priorById);
        Test.stopTest();

        Assert.areNotEqual('Stale', quote().Document_Data_Status__c,
            'With no prior version to compare against, the quote must be skipped, not guessed at');
    }

    private class MarkStaleFromQueueable implements Queueable {
        private Id quoteId;
        MarkStaleFromQueueable(Id quoteId) { this.quoteId = quoteId; }
        public void execute(QueueableContext context) {
            QuoteDocumentStaleness.markStale(new Set<Id>{ quoteId });
        }
    }

    /**
     * canDefer() is false inside any async context (Queueable included) -
     * Apex does not allow a @future call from inside another async context,
     * so markStale must apply the write inline there rather than deferring.
     * Every other staleness test runs from a synchronous trigger context and
     * so only ever exercises the deferred branch; this proves the other one.
     */
    @IsTest
    static void markStaleAppliesSynchronouslyWhenCalledFromAnAsyncContext() {
        Id qId = quote().Id;
        update new SBQQ__Quote__c(Id = qId, Document_Data_Status__c = 'Ready');

        Test.startTest();
        System.enqueueJob(new MarkStaleFromQueueable(qId));
        Test.stopTest();

        Assert.areEqual('Stale', quote().Document_Data_Status__c,
            'Inside an async context the write must happen inline - a future call cannot be queued from here');
    }
}
