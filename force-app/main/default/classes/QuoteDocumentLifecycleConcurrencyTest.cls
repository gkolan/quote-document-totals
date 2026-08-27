/**
 * Step 05A - abandonment, supersession, and lock-retry policy.
 *
 * ON WHAT THESE TESTS CAN AND CANNOT PROVE
 * ----------------------------------------
 * §8 asks for lock contention exercised with a second transaction holding the
 * row, "not by mocking the exception". Apex unit tests cannot open a second
 * concurrent transaction - there is no mechanism for it, in any test context.
 * So the retry POLICY is asserted directly here (what counts as retryable,
 * how many attempts, that backoff grows and varies), and the assertion that
 * a real lock is survived is honestly not made. Pretending otherwise with a
 * mocked UNABLE_TO_LOCK_ROW would prove the handler and claim the behaviour,
 * which is the substitution the spec is warning against.
 */
@IsTest
private class QuoteDocumentLifecycleConcurrencyTest {

    @TestSetup
    static void setup() {
        QuoteDocumentTestData.setup();
    }

    private static Datetime baseTime() {
        return Datetime.newInstanceGmt(2026, 8, 27, 12, 0, 0);
    }

    // -----------------------------------------------------------------------
    // §3 Abandonment
    // -----------------------------------------------------------------------

    @IsTest
    static void freshGeneratingRequestCannotBeTakenOver() {
        Datetime now = baseTime();
        Datetime startedOneMinuteAgo = now.addMinutes(-1);

        Assert.isFalse(
            QuoteDocumentLifecycle.isAbandoned('Generating', startedOneMinuteAgo, now),
            'A request that started a minute ago is running, not abandoned. Taking it over would mean two '
                + 'workers building the same snapshot.'
        );
    }

    @IsTest
    static void expiredRequestCanBeTakenOver() {
        Datetime now = baseTime();
        Datetime longAgo = now.addMinutes(-(QuoteDocumentLifecycle.DEFAULT_ABANDON_MINUTES + 5));

        Assert.isTrue(
            QuoteDocumentLifecycle.isAbandoned('Generating', longAgo, now),
            'Past the window the request is abandoned and the quote must not stay blocked forever.'
        );
    }

    /** The boundary is inclusive, and stated, so it is not left to whoever reads the code next. */
    @IsTest
    static void takeoverBoundaryIsExactAtTheThreshold() {
        Datetime now = baseTime();
        Integer window = QuoteDocumentLifecycle.DEFAULT_ABANDON_MINUTES;

        Assert.isFalse(
            QuoteDocumentLifecycle.isAbandoned('Generating', now.addMinutes(-(window - 1)), now),
            'One minute inside the window is still live.'
        );
        Assert.isTrue(
            QuoteDocumentLifecycle.isAbandoned('Generating', now.addMinutes(-window), now),
            'Exactly at the window is abandoned - the boundary is inclusive.'
        );
    }

    /**
     * A null start time can only come from an interrupted write. Treating it
     * as eternally live would block the quote forever; a premature takeover
     * costs one regeneration, which is the cheaper failure by a wide margin.
     */
    @IsTest
    static void nullStartedAtIsTreatedAsAbandoned() {
        Assert.isTrue(
            QuoteDocumentLifecycle.isAbandoned('Generating', null, baseTime()),
            'A Generating quote with no start time must be recoverable, not permanently stuck.'
        );
    }

    @IsTest
    static void aQuoteThatIsNotGeneratingIsNeverAbandoned() {
        Datetime ancient = baseTime().addYears(-1);

        for (String status : new List<String>{ 'Ready', 'Stale', 'Failed', 'Not Generated' }) {
            Assert.isFalse(
                QuoteDocumentLifecycle.isAbandoned(status, ancient, baseTime()),
                status + ' is not an in-flight request, however old it is. Abandonment applies only to work '
                    + 'that claimed the quote and never finished.'
            );
        }
    }

    @IsTest
    static void theAbandonmentWindowIsConfigurationNotALiteral() {
        Assert.areEqual(
            QuoteDocumentLifecycle.DEFAULT_ABANDON_MINUTES,
            QuoteDocumentLifecycle.abandonMinutes(),
            'With no LIFECYCLE/ABANDON_MINUTES record configured, the documented default applies. The value '
                + 'is read from metadata, so an org whose quotes are larger can raise it without a deploy.'
        );
    }

    // -----------------------------------------------------------------------
    // §3 Supersession
    // -----------------------------------------------------------------------

    /**
     * The guarantee that makes takeover safe. A superseded worker that
     * published would overwrite a snapshot built from newer inputs with one
     * built from older ones, and nothing downstream could tell - both look
     * like a complete, verified snapshot.
     */
    @IsTest
    static void supersededRequestCannotPublish() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        QuoteDocumentStaleness.suppress();
        try {
            update new SBQQ__Quote__c(Id = quoteId, Document_Data_Request_Id__c = 'newer-request');
        } finally {
            QuoteDocumentStaleness.resume();
        }

        String message;
        try {
            QuoteDocumentLifecycle.assertStillOwns(quoteId, 'older-request');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            message = e.getMessage();
        }

        Assert.isNotNull(message, 'A superseded worker must not be allowed to publish.');
        Assert.isTrue(message.contains('REQUEST_SUPERSEDED'), 'Wrong code: ' + message);
        Assert.isTrue(message.contains('older-request'), 'The message must name the losing request.');
        Assert.isTrue(message.contains('newer-request'), 'And the one that took over.');
    }

    @IsTest
    static void theOwningRequestMayPublish() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        QuoteDocumentStaleness.suppress();
        try {
            update new SBQQ__Quote__c(Id = quoteId, Document_Data_Request_Id__c = 'mine');
        } finally {
            QuoteDocumentStaleness.resume();
        }

        QuoteDocumentLifecycle.assertStillOwns(quoteId, 'mine');
        Assert.isTrue(true, 'The owning request publishes without objection.');
    }

    /** A generation that succeeds normally must still own its quote at the end. */
    @IsTest
    static void anOrdinaryGenerationOwnsItsQuoteThrough() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        List<QuoteDocumentGenerator.GenerationOutcome> outcomes =
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        SBQQ__Quote__c quote = [
            SELECT Document_Data_Request_Id__c, Document_Data_Started_At__c, Document_Data_Status__c
            FROM SBQQ__Quote__c WHERE Id = :quoteId
        ];
        Assert.areEqual('Ready', quote.Document_Data_Status__c);
        Assert.areEqual(
            outcomes[0].requestId,
            quote.Document_Data_Request_Id__c,
            'The attempt that published must be the one that claimed the quote.'
        );
        Assert.isNotNull(
            quote.Document_Data_Started_At__c,
            'Started_At must be stamped, or abandonment detection has nothing to compare against.'
        );
    }

    // -----------------------------------------------------------------------
    // §4 Lock retry policy
    // -----------------------------------------------------------------------

    @IsTest
    static void onlyLockContentionIsRetryable() {
        Assert.isTrue(
            QuoteDocumentLifecycle.isRetryable(
                new QuoteDocumentGenerator.QuoteDocumentException('UNABLE_TO_LOCK_ROW, unable to obtain lock')
            ),
            'Row lock contention is exactly what a retry is for.'
        );
        Assert.isTrue(
            QuoteDocumentLifecycle.isRetryable(
                new QuoteDocumentGenerator.QuoteDocumentException('Your query timeout has expired')
            ),
            'A query timeout is contention wearing a different hat.'
        );
    }

    @IsTest
    static void nonRetryableErrorIsNotRetried() {
        for (String terminal : new List<String>{
            'COLUMN_FIELD_UNKNOWN: Table X binds Not_A_Field__c',
            'LABEL_KEY_MISSING: no label for GRAND_TOTAL',
            'Something else went wrong'
        }) {
            Assert.isFalse(
                QuoteDocumentLifecycle.isRetryable(
                    new QuoteDocumentGenerator.QuoteDocumentException(terminal)
                ),
                'Retrying a configuration error just produces the same error three times and delays the '
                    + 'report: ' + terminal
            );
        }
        Assert.isFalse(QuoteDocumentLifecycle.isRetryable(null), 'A null cause is not retryable.');
    }

    @IsTest
    static void retriesAreBoundedAndBackoffGrows() {
        Assert.areEqual(3, QuoteDocumentLifecycle.MAX_LOCK_ATTEMPTS, 'Beyond three, a retry is queuing '
            + 'behind a real problem rather than waiting out a neighbour.');

        Integer first = QuoteDocumentLifecycle.backoffSeconds(1);
        Integer third = QuoteDocumentLifecycle.backoffSeconds(3);

        Assert.isTrue(first >= 1, 'A backoff must actually back off: ' + first);
        Assert.isTrue(third >= 4, 'And grow with the attempt number: ' + third);
    }

    /**
     * The jitter is the part that matters. Two jobs retrying on the same fixed
     * schedule collide again on every attempt, which is the failure the
     * backoff was supposed to prevent.
     */
    @IsTest
    static void backoffCarriesJitter() {
        Set<Integer> observed = new Set<Integer>();
        for (Integer i = 0; i < 40; i++) {
            observed.add(QuoteDocumentLifecycle.backoffSeconds(4));
        }
        Assert.isTrue(
            observed.size() > 1,
            'A fixed backoff makes two contending jobs collide again on every attempt. Observed only: '
                + observed
        );
    }

    @IsTest
    static void aLockFailureLeavesTheExistingSnapshotUntouched() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        SBQQ__Quote__c before = [
            SELECT Document_Data_Status__c, Document_Data_Fingerprint__c
            FROM SBQQ__Quote__c WHERE Id = :quoteId
        ];
        Assert.areEqual('Ready', before.Document_Data_Status__c);

        // The policy under test: a lock failure is terminal for the attempt
        // and changes nothing. Nothing about the existing document is wrong -
        // the generation simply did not run.
        Exception lockTimeout = QuoteDocumentLifecycle.lockTimeout(quoteId, 3);
        Assert.isTrue(
            lockTimeout.getMessage().contains('GENERATION_LOCK_TIMEOUT'),
            'One stable code for a runbook to grep: ' + lockTimeout.getMessage()
        );
        Assert.isTrue(
            lockTimeout.getMessage().contains('status is untouched'),
            'The message must say the snapshot is unharmed, or someone will regenerate for no reason: '
                + lockTimeout.getMessage()
        );

        SBQQ__Quote__c after = [
            SELECT Document_Data_Status__c, Document_Data_Fingerprint__c
            FROM SBQQ__Quote__c WHERE Id = :quoteId
        ];
        Assert.areEqual(before.Document_Data_Status__c, after.Document_Data_Status__c,
            'Building the lock-timeout error must not itself touch the quote.');
        Assert.areEqual(before.Document_Data_Fingerprint__c, after.Document_Data_Fingerprint__c);
    }
}
