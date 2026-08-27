/**
 * Step 05 §6 - invalidation after a change no trigger can see.
 *
 * The behaviour that matters is not "it sets a field". It is that a partial
 * run never reads as a full one, that re-running is safe, and that one bad
 * quote cannot leave the rest silently Ready on stale content.
 */
@IsTest
private class QuoteDocumentInvalidationJobTest {

    @TestSetup
    static void setup() {
        QuoteDocumentTestData.setup();
    }

    private static Id readyQuote() {
        Id quoteId = QuoteDocumentTestData.quoteId();
        QuoteDocumentStaleness.suppress();
        try {
            update new SBQQ__Quote__c(Id = quoteId, Document_Data_Status__c = 'Ready');
        } finally {
            QuoteDocumentStaleness.resume();
        }
        return quoteId;
    }

    private static String statusOf(Id quoteId) {
        return [SELECT Document_Data_Status__c FROM SBQQ__Quote__c WHERE Id = :quoteId]
            .Document_Data_Status__c;
    }

    @IsTest
    static void aReadyQuoteIsMarkedStale() {
        Id quoteId = readyQuote();

        Test.startTest();
        QuoteDocumentInvalidationJob.Outcome outcome = QuoteDocumentInvalidationJob.runNow(200);
        Test.stopTest();

        Assert.areEqual('Stale', statusOf(quoteId), 'Deploying metadata does not invalidate. This does.');
        Assert.areEqual(1, outcome.processed, 'The count must reflect real work.');
        Assert.areEqual(0, outcome.failed);
    }

    /**
     * Idempotence comes from the query, not from a checkpoint: the job selects
     * Ready quotes and its own work makes them Stale, so a second run has
     * nothing left to do. A checkpoint that can be lost is a checkpoint that
     * will be.
     */
    @IsTest
    static void reprocessingIsIdempotent() {
        readyQuote();

        Test.startTest();
        QuoteDocumentInvalidationJob.Outcome first = QuoteDocumentInvalidationJob.runNow(200);
        QuoteDocumentInvalidationJob.Outcome second = QuoteDocumentInvalidationJob.runNow(200);
        Test.stopTest();

        Assert.areEqual(1, first.processed, 'The first run does the work.');
        Assert.areEqual(0, second.processed, 'The second finds nothing left, rather than redoing it.');
        Assert.areEqual(0, second.failed);
    }

    /** Resuming after a partial run picks up only what is left, for the same reason. */
    @IsTest
    static void resumeAfterPartialRunSkipsCompletedWork() {
        readyQuote();

        Test.startTest();
        QuoteDocumentInvalidationJob.Outcome partial = QuoteDocumentInvalidationJob.runNow(0);
        Assert.areEqual(0, partial.processed, 'A zero-cap run processes nothing.');
        Assert.areEqual('Ready', statusOf(QuoteDocumentTestData.quoteId()), 'And changes nothing.');

        QuoteDocumentInvalidationJob.Outcome resumed = QuoteDocumentInvalidationJob.runNow(200);
        Test.stopTest();

        Assert.areEqual(1, resumed.processed, 'Resuming finds the work the capped run left.');
    }

    @IsTest
    static void countsReportProcessedAndFailed() {
        readyQuote();

        Test.startTest();
        QuoteDocumentInvalidationJob.Outcome outcome = QuoteDocumentInvalidationJob.runNow(200);
        Test.stopTest();

        String described = outcome.describe();
        Assert.isTrue(described.contains('1 quote(s) marked Stale'), 'Counts must be reportable: ' + described);
        Assert.isTrue(described.contains('0 failed'), 'Including the failure count: ' + described);
    }

    /**
     * A partial run must never read as a full invalidation. Nothing in the
     * outcome may claim completeness - only counts, which an operator compares
     * against what they expected.
     */
    @IsTest
    static void aPartialRunNeverReportsFullInvalidation() {
        readyQuote();

        Test.startTest();
        QuoteDocumentInvalidationJob.Outcome outcome = QuoteDocumentInvalidationJob.runNow(0);
        Test.stopTest();

        String described = outcome.describe();
        Assert.isTrue(described.contains('0 quote(s)'), 'A run that did nothing must say so: ' + described);
        Assert.isFalse(
            described.containsIgnoreCase('all quotes'),
            'No wording may imply completeness the run cannot know: ' + described
        );
    }

    @IsTest
    static void theBatchEntryPointRuns() {
        readyQuote();

        Test.startTest();
        Database.executeBatch(new QuoteDocumentInvalidationJob(), 200);
        Test.stopTest();

        Assert.areEqual(
            'Stale',
            statusOf(QuoteDocumentTestData.quoteId()),
            'The batch path must do the same work as the synchronous one.'
        );
    }

    /** A quote that is not Ready is not touched - invalidation is not a status reset. */
    @IsTest
    static void quotesThatAreNotReadyAreLeftAlone() {
        Id quoteId = QuoteDocumentTestData.quoteId();
        QuoteDocumentStaleness.suppress();
        try {
            update new SBQQ__Quote__c(Id = quoteId, Document_Data_Status__c = 'Failed');
        } finally {
            QuoteDocumentStaleness.resume();
        }

        Test.startTest();
        QuoteDocumentInvalidationJob.Outcome outcome = QuoteDocumentInvalidationJob.runNow(200);
        Test.stopTest();

        Assert.areEqual('Failed', statusOf(quoteId), 'A failed quote must not be quietly relabelled Stale.');
        Assert.areEqual(0, outcome.processed);
    }
}
