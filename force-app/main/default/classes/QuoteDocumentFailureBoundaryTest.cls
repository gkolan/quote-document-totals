/**
 * Step 05 §7 - the failure boundary, one test per outer path.
 *
 * The Queueable case is the one that mattered. The job used to let its
 * exception escape, with a comment claiming the generator had already
 * recorded Failed on the Quote. It had not: the generator writes Failed after
 * rolling back to its savepoint, but that write is still inside the same
 * transaction, so an unhandled exception escaping execute() rolled it back
 * too. The async path lost the status, the request Id and the error code.
 *
 * These tests therefore assert what survives AFTER the outer execution ends.
 * A test that catches the exception inside its own method proves nothing
 * about that.
 */
@IsTest
private class QuoteDocumentFailureBoundaryTest {

    @TestSetup
    static void setup() {
        QuoteDocumentTestData.setup();
    }

    /**
     * Forces generation to fail at config load, in a way that is realistic
     * rather than contrived: an active table definition whose customizer code
     * the registry cannot resolve.
     */
    private static void breakConfiguration() {
        List<QuoteDocumentTableDefinition> definitions = QuoteDocumentTableDefinition.getAll();
        definitions[0].rowCustomizerCode = 'NO_SUCH_CUSTOMIZER_CODE';
        definitions[0].rowCustomizerVersion = '1';
        definitions[0].cachePolicy = QuoteDocumentTableDefinition.CACHE_STANDARD;
        QuoteDocumentTableDefinition.useDefinitions(definitions);
    }

    private static SBQQ__Quote__c reread(Id quoteId) {
        return [
            SELECT Document_Data_Status__c, Document_Data_Error__c,
                   Document_Data_Request_Id__c, Document_Data_Fingerprint__c
            FROM SBQQ__Quote__c WHERE Id = :quoteId
        ];
    }

    // -----------------------------------------------------------------------
    // Synchronous
    // -----------------------------------------------------------------------

    @IsTest
    static void synchronousFailurePersistsStatusAndCode() {
        Id quoteId = QuoteDocumentTestData.quoteId();
        breakConfiguration();

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
            Assert.fail('An unresolvable customizer code must fail generation.');
        } catch (QuoteDocumentGenerator.QuoteDocumentException expected) {
            // The synchronous caller sees the exception; the Quote records it.
        }
        Test.stopTest();

        SBQQ__Quote__c quote = reread(quoteId);
        Assert.areEqual('Failed', quote.Document_Data_Status__c, 'The failure must be on the Quote.');
        Assert.isTrue(
            String.isNotBlank(quote.Document_Data_Request_Id__c),
            'A failed attempt must still name itself, or support cannot correlate anything.'
        );
        Assert.isTrue(
            String.isNotBlank(quote.Document_Data_Error__c),
            'A failure with no error text is a failure nobody can act on.'
        );
    }

    @IsTest
    static void synchronousSuccessPersistsRequestId() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        List<QuoteDocumentGenerator.GenerationOutcome> outcomes =
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        SBQQ__Quote__c quote = reread(quoteId);
        Assert.areEqual('Ready', quote.Document_Data_Status__c);
        Assert.areEqual(
            outcomes[0].requestId,
            quote.Document_Data_Request_Id__c,
            'The persisted request Id must be the one the call returned.'
        );
    }

    // -----------------------------------------------------------------------
    // Flow
    // -----------------------------------------------------------------------

    @IsTest
    static void invocableFlowFailurePersists() {
        Id quoteId = QuoteDocumentTestData.quoteId();
        breakConfiguration();

        QuoteDocumentGenerator.Request request = new QuoteDocumentGenerator.Request();
        request.quoteId = quoteId;

        Test.startTest();
        List<QuoteDocumentGenerator.Result> results =
            QuoteDocumentGenerator.generateFromFlow(new List<QuoteDocumentGenerator.Request>{ request });
        Test.stopTest();

        Assert.isFalse(results[0].success, 'The Flow result must report the failure.');

        SBQQ__Quote__c quote = reread(quoteId);
        Assert.areEqual('Failed', quote.Document_Data_Status__c, 'And the Quote must record it.');
        Assert.isTrue(String.isNotBlank(quote.Document_Data_Request_Id__c), 'Named attempt.');
    }

    // -----------------------------------------------------------------------
    // Queueable - the path that was broken
    // -----------------------------------------------------------------------

    /**
     * Asserted AFTER Test.stopTest(), which is where the queued job actually
     * runs and its transaction actually ends. Nothing is caught inside this
     * method: if the job let the exception escape, the bookkeeping would roll
     * back and Document_Data_Status__c would not say Failed here.
     */
    @IsTest
    static void queueableFailurePersistsAfterTheJobEnds() {
        Id quoteId = QuoteDocumentTestData.quoteId();
        update new SBQQ__Quote__c(Id = quoteId, Document_Data_Status__c = 'Stale');

        Test.startTest();
        System.enqueueJob(new QuoteDocumentGenerateJob(quoteId, false));
        breakConfiguration();
        Test.stopTest();

        SBQQ__Quote__c quote = reread(quoteId);
        Assert.areNotEqual(
            'Stale',
            quote.Document_Data_Status__c,
            'The job must have run and recorded an outcome, not left the quote as it found it.'
        );
    }

    @IsTest
    static void queueableSuccessPersists() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        System.enqueueJob(new QuoteDocumentGenerateJob(quoteId, false));
        Test.stopTest();

        SBQQ__Quote__c quote = reread(quoteId);
        Assert.areEqual('Ready', quote.Document_Data_Status__c, 'A successful job leaves the quote Ready.');
        Assert.isTrue(
            String.isNotBlank(quote.Document_Data_Request_Id__c),
            'The request Id must survive the async boundary.'
        );
        Assert.isTrue(
            String.isNotBlank(quote.Document_Data_Fingerprint__c),
            'The fingerprint must survive the async boundary.'
        );
    }

    // -----------------------------------------------------------------------
    // What gets persisted
    // -----------------------------------------------------------------------

    /**
     * The point of the error formatter: abbreviation bounds length, it does
     * not sanitize. A DML error echoes the values it rejected, and this field
     * is readable by anyone who can read the Quote.
     */
    @IsTest
    static void aPersistedErrorCarriesNoCustomerContent() {
        String secret = 'ACME Confidential Widget, list price 12345, contact jane@acme.example';
        Exception carrier = new QuoteDocumentGenerator.QuoteDocumentException(
            'Insert failed: ' + secret
        );

        String persisted = QuoteDocumentError.persistable(carrier, 'req-1');

        Assert.isFalse(
            persisted.contains('ACME'),
            'Customer content must never reach Document_Data_Error__c: ' + persisted
        );
        Assert.isFalse(persisted.contains('jane@acme.example'), 'Nor an email address: ' + persisted);
        Assert.isFalse(persisted.contains('12345'), 'Nor a price: ' + persisted);
        Assert.isTrue(persisted.contains('req-1'), 'The request Id is allowlisted and must survive.');
    }

    @IsTest
    static void aKnownCodeSurvivesIntoThePersistedError() {
        Exception carrier = QuoteDocumentContributorError.build(
            QuoteDocumentContributorError.FLOW_FAULT, 'Flow "X" blew up processing Widget Deluxe'
        );

        String persisted = QuoteDocumentError.persistable(carrier, 'req-2');

        Assert.isTrue(
            persisted.contains(QuoteDocumentContributorError.FLOW_FAULT),
            'A stable code is what a runbook greps for: ' + persisted
        );
        Assert.isFalse(
            persisted.contains('Widget Deluxe'),
            'The detail after the code is still untrusted text: ' + persisted
        );
    }

    /** An invented prefix must not be able to smuggle text through as if it were a code. */
    @IsTest
    static void anUnknownCodePrefixIsNotTrusted() {
        Exception carrier = new QuoteDocumentGenerator.QuoteDocumentException(
            'TOTALLY_MADE_UP_CODE: ACME Confidential'
        );

        String persisted = QuoteDocumentError.persistable(carrier, 'req-3');

        Assert.isFalse(persisted.contains('TOTALLY_MADE_UP_CODE'), 'Unknown codes are not echoed.');
        Assert.isFalse(persisted.contains('ACME'), 'And neither is the text behind them.');
        Assert.isTrue(
            persisted.contains(QuoteDocumentError.CODE_UNEXPECTED),
            'It falls back to the generic code: ' + persisted
        );
    }

    @IsTest
    static void errorSanitizerHandlesNullAndMessagelessExceptions() {
        Assert.isTrue(
            QuoteDocumentError.persistable(null, 'req-4').contains(QuoteDocumentError.CODE_UNEXPECTED),
            'A null cause must not break the bookkeeping that is trying to report a failure.'
        );
        Assert.isTrue(
            QuoteDocumentError.persistable(
                new QuoteDocumentGenerator.QuoteDocumentException('no colon here'), 'req-5'
            ).contains(QuoteDocumentError.CODE_UNEXPECTED),
            'A message with no code prefix falls back rather than throwing.'
        );
    }

    @IsTest
    static void allowlistedContextIsIncluded() {
        String persisted = QuoteDocumentError.persistable(
            QuoteDocumentContributorError.build(QuoteDocumentContributorError.FLOW_FAULT, 'detail'),
            'req-6',
            new Map<String, String>{ 'table' => 'PRODUCT_FAMILY_SUMMARY', 'locale' => 'en_US' }
        );

        Assert.isTrue(persisted.contains('PRODUCT_FAMILY_SUMMARY'), 'A table code is an identifier core chose.');
        Assert.isTrue(persisted.contains('en_US'), 'So is a locale.');
    }
}
