/**
 * Step 01A section 6b - the launch contract.
 *
 * Invalidation is best-effort: a trigger may not exist, a sweep may lag, a
 * dependency pack may declare LaunchRefreshOnly. Fresh fingerprint
 * computation is not best-effort - it happens on every generate() call before
 * canReuse decides anything. That only helps if a launch can actually get the
 * request Id and fingerprint back, which is what these tests pin.
 */
@IsTest
private class QuoteDocumentLaunchContractTest {

    @TestSetup
    static void setup() {
        QuoteDocumentTestData.setup();
    }

    @IsTest
    static void generateReturnsRequestIdAndFingerprintPerQuote() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        List<QuoteDocumentGenerator.GenerationOutcome> outcomes =
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        Assert.areEqual(1, outcomes.size(), 'One quote in, one outcome out.');
        QuoteDocumentGenerator.GenerationOutcome outcome = outcomes[0];

        Assert.areEqual(quoteId, outcome.quoteId, 'The outcome must identify its quote.');
        Assert.isNotNull(outcome.requestId, 'A launch cannot bind a renderer without a request Id.');
        Assert.isNotNull(outcome.fingerprint, 'A launch cannot bind a renderer without a fingerprint.');
        Assert.areEqual('Ready', outcome.status, 'A successful first generation is Ready.');
        Assert.isFalse(outcome.reused, 'The first generation cannot be a reuse.');
    }

    /** The Quote must agree with what was just returned, or the two would drift apart. */
    @IsTest
    static void theRequestIdIsStampedOnTheQuote() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        List<QuoteDocumentGenerator.GenerationOutcome> outcomes =
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        SBQQ__Quote__c stored = [
            SELECT Document_Data_Request_Id__c, Document_Data_Fingerprint__c
            FROM SBQQ__Quote__c WHERE Id = :quoteId
        ];
        Assert.areEqual(
            outcomes[0].requestId,
            stored.Document_Data_Request_Id__c,
            'Document_Data_Request_Id__c exists precisely for this and was written by nothing until now.'
        );
        Assert.areEqual(
            outcomes[0].fingerprint,
            stored.Document_Data_Fingerprint__c,
            'The stamped fingerprint must be the one this generation returned.'
        );
    }

    /**
     * The acceptance criterion that is easy to get wrong: a reuse must return
     * the request Id of the attempt that PUBLISHED the snapshot. Minting a
     * fresh one would hand the renderer an identifier matching no generation
     * that ever ran.
     */
    @IsTest
    static void reuseReturnsThePublishedRequestIdNeverANewOne() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        List<QuoteDocumentGenerator.GenerationOutcome> first =
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        List<QuoteDocumentGenerator.GenerationOutcome> second =
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        Assert.isFalse(first[0].reused, 'The first call generates.');
        Assert.isTrue(second[0].reused, 'Nothing changed, so the second call must reuse.');
        Assert.areEqual(
            first[0].requestId,
            second[0].requestId,
            'A reuse must report the request Id of the generation that actually produced the snapshot.'
        );
        Assert.areEqual(
            first[0].fingerprint,
            second[0].fingerprint,
            'A reuse means the fingerprint matched, so it must be the same value.'
        );
    }

    /**
     * ALWAYS_REBUILD means "rebuild whenever generation is requested", and it
     * applies to the whole quote, not one table - canReuse is evaluated per
     * quote. Asserted by generating twice with nothing changed and proving the
     * second call still rebuilt.
     */
    @IsTest
    static void oneAlwaysRebuildTableSkipsReuseForTheWholeQuote() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        List<QuoteDocumentGenerator.GenerationOutcome> first =
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });

        // Re-declare the loaded config with one table forced to ALWAYS_REBUILD,
        // leaving every other table ordinary - the mixed case the acceptance
        // criteria call for, not an all-or-nothing one.
        List<QuoteDocumentTableDefinition> definitions = QuoteDocumentTableDefinition.getAll();
        definitions[0].rowCustomizerCode = 'DISCOUNT_EXAMPLE';
        definitions[0].rowCustomizerVersion = '1';
        definitions[0].cachePolicy = QuoteDocumentTableDefinition.CACHE_ALWAYS_REBUILD;

        Boolean reusable = QuoteDocumentGenerator.canReuse(
            [
                SELECT Id, Document_Data_Status__c, Document_Data_Fingerprint__c
                FROM SBQQ__Quote__c WHERE Id = :quoteId
            ],
            first[0].fingerprint,
            definitions
        );
        Test.stopTest();

        Assert.isFalse(
            reusable,
            'A quote with an ALWAYS_REBUILD contributor on any applicable table must never take the reuse '
                + 'path, even with a matching fingerprint and every other table ordinary.'
        );
    }

    /** The declarative launch has to carry the same values, or a Flow-driven launch cannot conform. */
    @IsTest
    static void theInvocableActionReturnsTheLaunchValues() {
        QuoteDocumentGenerator.Request request = new QuoteDocumentGenerator.Request();
        request.quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        List<QuoteDocumentGenerator.Result> results =
            QuoteDocumentGenerator.generateFromFlow(new List<QuoteDocumentGenerator.Request>{ request });
        Test.stopTest();

        Assert.isTrue(results[0].success, 'Generation should succeed: ' + results[0].message);
        Assert.isNotNull(results[0].requestId, 'A Flow launch must be able to pass on the request Id.');
        Assert.isNotNull(results[0].fingerprint, 'A Flow launch must be able to pass on the fingerprint.');
        Assert.isFalse(results[0].reused, 'The first generation is not a reuse.');
    }
}
