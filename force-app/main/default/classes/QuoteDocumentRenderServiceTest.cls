/**
 * Step 07 - the one projection every adapter shares.
 *
 * Note how every test obtains its expectations: from generate-or-reuse, the
 * same way a real caller does. There is no test-only shortcut, because a
 * test-only shortcut would have to exist on the service, and a shortcut that
 * exists on the service IS the bypass the contract prohibits.
 */
@IsTest
private class QuoteDocumentRenderServiceTest {

    @TestSetup
    static void setup() {
        QuoteDocumentTestData.setup();
    }

    /** Generate, and hand back exactly what a launch would bind to. */
    private static QuoteDocumentGenerator.GenerationOutcome launch() {
        return QuoteDocumentGenerator.generate(
            new Set<Id>{ QuoteDocumentTestData.quoteId() }
        )[0];
    }

    private static QuoteDocumentPayload payloadFor(QuoteDocumentGenerator.GenerationOutcome outcome) {
        return QuoteDocumentRenderService.getPayload(
            outcome.quoteId, outcome.requestId, outcome.fingerprint
        );
    }

    private static String failureFrom(Id quoteId, String requestId, String fingerprint) {
        try {
            QuoteDocumentRenderService.getPayload(quoteId, requestId, fingerprint);
            return null;
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            return e.getMessage();
        }
    }

    // -----------------------------------------------------------------------
    // The happy path
    // -----------------------------------------------------------------------

    @IsTest
    static void payloadOrdersSectionsAndRowsCorrectly() {
        Test.startTest();
        QuoteDocumentPayload payload = payloadFor(launch());
        Test.stopTest();

        Assert.isFalse(payload.sections.isEmpty(), 'A Ready quote must produce sections.');

        Decimal previous = -1;
        Boolean sawTable = false;
        Boolean sawBlock = false;

        for (QuoteDocumentPayload.Section section : payload.sections) {
            Assert.isTrue(
                section.displayOrder >= previous,
                'Sections must arrive in one ascending sequence - tables and blocks interleaved, so a '
                    + 'renderer walks a single list.'
            );
            previous = section.displayOrder;

            if ('Table'.equals(section.sectionType)) {
                sawTable = true;
                Decimal previousRow = -1;
                for (QuoteDocumentPayload.Row row : section.rows) {
                    Assert.isTrue(row.displayOrder >= previousRow, 'Rows must arrive in order too.');
                    previousRow = row.displayOrder;
                }
            } else if ('Block'.equals(section.sectionType)) {
                sawBlock = true;
            }
        }

        Assert.isTrue(sawTable, 'The fixture generates tables.');
        Assert.isTrue(sawBlock, 'And the shipped content records generate blocks, in the same sequence.');
    }

    @IsTest
    static void thePayloadCarriesItsOwnIdentity() {
        Test.startTest();
        QuoteDocumentGenerator.GenerationOutcome outcome = launch();
        QuoteDocumentPayload payload = payloadFor(outcome);
        Test.stopTest();

        Assert.areEqual(QuoteDocumentPayload.CONTRACT_VERSION, payload.contractVersion);
        Assert.areEqual(outcome.quoteId, payload.quoteId);
        Assert.areEqual(outcome.requestId, payload.requestId, 'Bound to the attempt that was launched.');
        Assert.areEqual(outcome.fingerprint, payload.fingerprint);
        Assert.areEqual('Ready', payload.status);
        Assert.isTrue(String.isNotBlank(payload.locale), 'A renderer needs the locale to format.');
        Assert.isNotNull(payload.contentVersion);
    }

    @IsTest
    static void valuesAreKeyedByColumnCode() {
        Test.startTest();
        QuoteDocumentPayload payload = payloadFor(launch());
        Test.stopTest();

        for (QuoteDocumentPayload.Section section : payload.sections) {
            if (!'Table'.equals(section.sectionType)) {
                continue;
            }

            Set<String> columnCodes = new Set<String>();
            for (QuoteDocumentPayload.Column column : section.columns) {
                columnCodes.add(column.code);
            }

            for (QuoteDocumentPayload.Row row : section.rows) {
                Assert.areEqual(
                    columnCodes,
                    row.values.keySet(),
                    section.code + ': every value key must match a column code on its own section - no key '
                        + 'without a column, no column without a key. An adapter must never need to know '
                        + 'that COL_NET means Amount_Net__c.'
                );
                for (String key : row.values.keySet()) {
                    Assert.isFalse(
                        key.endsWith('__c'),
                        'A field API name leaked into the payload as a key: ' + key
                    );
                }
            }
        }
    }

    @IsTest
    static void amountsAreTypedNotFormatted() {
        Test.startTest();
        QuoteDocumentPayload payload = payloadFor(launch());
        Test.stopTest();

        Boolean sawCurrency = false;
        for (QuoteDocumentPayload.Section section : payload.sections) {
            if (!'Table'.equals(section.sectionType)) {
                continue;
            }
            for (QuoteDocumentPayload.Column column : section.columns) {
                if (!'Currency'.equals(column.dataType)) {
                    continue;
                }
                for (QuoteDocumentPayload.Row row : section.rows) {
                    Object value = row.values.get(column.code);
                    if (value == null) {
                        continue;
                    }
                    sawCurrency = true;
                    Assert.isTrue(
                        value instanceof Decimal,
                        'Money must arrive as Decimal, not as "$1,234.00". Formatting is the renderer\'s '
                            + 'job, and locale plus currencyIsoCode give it what it needs. Found: ' + value
                    );
                }
            }
        }
        Assert.isTrue(sawCurrency, 'The fixture must produce at least one currency value to check.');
    }

    // -----------------------------------------------------------------------
    // Visibility
    // -----------------------------------------------------------------------

    @IsTest
    static void hiddenRecordsAreExcluded() {
        Test.startTest();
        QuoteDocumentPayload payload = payloadFor(launch());
        Test.stopTest();

        Set<String> visibleCodes = new Set<String>();
        for (QuoteDocumentPayload.Section section : payload.sections) {
            visibleCodes.add(section.code);
        }

        for (Quote_Document_Table__c table : [
            SELECT Table_Code__c, Is_Displayed__c FROM Quote_Document_Table__c
            WHERE Quote__c = :QuoteDocumentTestData.quoteId() AND Is_Displayed__c = false
        ]) {
            Assert.isFalse(
                visibleCodes.contains(table.Table_Code__c),
                'A hidden table must be ABSENT from the payload, not present and flagged. A renderer that '
                    + 'receives it would have to decide, and deciding is what this contract removes.'
            );
        }
    }

    // -----------------------------------------------------------------------
    // The launch contract
    // -----------------------------------------------------------------------

    @IsTest
    static void retrievalWithoutExpectationsFailsAsABypass() {
        Test.startTest();
        QuoteDocumentGenerator.GenerationOutcome outcome = launch();
        String message = failureFrom(outcome.quoteId, null, null);
        Test.stopTest();

        Assert.isNotNull(message, 'Reading a Ready snapshot without expectations must fail.');
        Assert.isTrue(message.contains('LAUNCH_CONTRACT_BYPASSED'), 'Wrong code: ' + message);
        Assert.isTrue(
            message.contains('generate-or-reuse'),
            'The message must say what was skipped: ' + message
        );
    }

    @IsTest
    static void movedSnapshotFailsNamingBothValues() {
        Test.startTest();
        QuoteDocumentGenerator.GenerationOutcome outcome = launch();
        String message = failureFrom(outcome.quoteId, 'stale-request', 'stale-fingerprint');
        Test.stopTest();

        Assert.isNotNull(message, 'Expectations that do not match must fail.');
        Assert.isTrue(message.contains('SNAPSHOT_MOVED'), 'Wrong code: ' + message);
        Assert.isTrue(
            message.contains('stale-request') && message.contains(outcome.requestId),
            'The message must name BOTH the expected and the actual values: ' + message
        );
        Assert.isTrue(
            message.contains('never by accepting the newer snapshot silently'),
            'And must forbid the silent substitution: ' + message
        );
    }

    @IsTest
    static void nonReadyQuoteThrowsWithTheStatusNamed() {
        Test.startTest();
        QuoteDocumentGenerator.GenerationOutcome outcome = launch();
        QuoteDocumentStaleness.suppress();
        try {
            update new SBQQ__Quote__c(Id = outcome.quoteId, Document_Data_Status__c = 'Stale');
        } finally {
            QuoteDocumentStaleness.resume();
        }
        String message = failureFrom(outcome.quoteId, outcome.requestId, outcome.fingerprint);
        Test.stopTest();

        Assert.isNotNull(message, 'Only a Ready snapshot may be rendered.');
        Assert.isTrue(message.contains('SNAPSHOT_NOT_READY'), 'Wrong code: ' + message);
        Assert.isTrue(message.contains('Stale'), 'The message must name the status: ' + message);
    }

    @IsTest
    static void tamperedSnapshotFailsIntegrityBeforeAnyPayloadIsReturned() {
        Test.startTest();
        QuoteDocumentGenerator.GenerationOutcome outcome = launch();

        Quote_Document_Row__c row = [
            SELECT Id, Display_Label__c FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Quote__c = :outcome.quoteId LIMIT 1
        ];
        row.Display_Label__c = 'Edited after publication';
        Database.update(row, true, AccessLevel.SYSTEM_MODE);

        String message = failureFrom(outcome.quoteId, outcome.requestId, outcome.fingerprint);
        Test.stopTest();

        Assert.isNotNull(message, 'A tampered snapshot must never render.');
        Assert.isTrue(message.contains('PAYLOAD_INTEGRITY_MISMATCH'), 'Wrong code: ' + message);
    }

    // -----------------------------------------------------------------------
    // No bypass may exist at all
    // -----------------------------------------------------------------------

    /**
     * Asserted against the class's own source, because a convenience overload
     * is exactly the kind of thing that gets added later "just for a test" and
     * then used in production. If one appears, this fails.
     */
    @IsTest
    static void noOverloadOmitsExpectations() {
        ApexClass service = [
            SELECT Body FROM ApexClass WHERE Name = 'QuoteDocumentRenderService' LIMIT 1
        ];

        Assert.isFalse(
            service.Body.contains('getPayload(Id quoteId)'),
            'A quote-Id-only getPayload would be the bypass the contract prohibits, wearing a convenient '
                + 'signature. The service cannot tell a production call from an ad hoc one.'
        );
        Assert.isFalse(
            service.Body.contains('getPayloads(Set<Id>'),
            'A Set<Id> bulk entry point is the same bypass in a different shape - expectations are per '
                + 'quote, so a signature that cannot carry them cannot honour the contract.'
        );
    }

    /** Diagnostics must not be promotable into a render path. */
    @IsTest
    static void describeSnapshotCannotReturnAPayload() {
        Test.startTest();
        QuoteDocumentGenerator.GenerationOutcome outcome = launch();
        QuoteDocumentPayload.SnapshotDescription description =
            QuoteDocumentRenderService.describeSnapshot(outcome.quoteId);
        Test.stopTest();

        Assert.areEqual('Ready', description.status);
        Assert.areEqual(outcome.requestId, description.requestId);
        Assert.isTrue(description.tableCount > 0, 'Diagnostics report counts.');
        // The stronger assertion is one the COMPILER already makes. Writing
        // `description instanceof QuoteDocumentPayload` does not compile at
        // all - "always false since an instance of SnapshotDescription is
        // never an instance of QuoteDocumentPayload" - so a diagnostic can
        // never be passed where a payload is expected, and no runtime check
        // is needed or even possible. Recorded here because the absence of an
        // assertion would otherwise look like an omission.
        Assert.isNotNull(
            description.payloadHash,
            'Diagnostics report the payload hash so an administrator can compare it by hand, without ever '
                + 'being handed a renderable payload.'
        );
    }

    // -----------------------------------------------------------------------
    // Vendor neutrality
    // -----------------------------------------------------------------------

    /**
     * The grep, as an Apex assertion so CI cannot forget it. A contract is only
     * vendor-neutral if its source could be read by someone who has never
     * heard of the tool that renders it.
     */
    @IsTest
    static void payloadContainsNoVendorTokens() {
        List<ApexClass> classes = [
            SELECT Name, Body FROM ApexClass
            WHERE Name IN ('QuoteDocumentRenderService', 'QuoteDocumentPayload')
        ];
        Assert.areEqual(2, classes.size(), 'Both contract classes must be checked.');

        List<String> forbidden = new List<String>{
            'docusign', 'conga', 'springcm', 'docx', 'mergefield', 'merge field', '<#', 'adobe', 'pandadoc'
        };

        for (ApexClass cls : classes) {
            String body = cls.Body.toLowerCase();
            for (String token : forbidden) {
                Assert.isFalse(
                    body.contains(token),
                    cls.Name + ' contains the vendor token "' + token + '". The contract is only '
                        + 'vendor-neutral if this source could be read by someone who has never heard of '
                        + 'the tool that renders it.'
                );
            }
        }
    }

    // -----------------------------------------------------------------------
    // Bulk isolation
    // -----------------------------------------------------------------------

    @IsTest
    static void bulkEmptyAndNullRequestsAreSafe() {
        Test.startTest();
        Assert.areEqual(
            0,
            QuoteDocumentRenderService.getPayloads(
                new List<QuoteDocumentPayload.PayloadRequest>()
            ).size(),
            'An empty batch returns an empty result, not an error.'
        );
        Assert.areEqual(
            0,
            QuoteDocumentRenderService.getPayloads(null).size(),
            'A null batch must not throw - a caller assembling requests dynamically can legitimately end '
                + 'up with none.'
        );
        Test.stopTest();
    }

    /**
     * The criterion that matters most in a batch: a failure must never remove
     * a successful result. A partial batch that looks whole is how a document
     * run silently skips a customer.
     */
    @IsTest
    static void bulkFailureDoesNotRemoveSuccessfulResults() {
        Test.startTest();
        QuoteDocumentGenerator.GenerationOutcome outcome = launch();

        List<QuoteDocumentPayload.PayloadRequest> requests =
            new List<QuoteDocumentPayload.PayloadRequest>{
                new QuoteDocumentPayload.PayloadRequest(
                    outcome.quoteId, outcome.requestId, outcome.fingerprint
                ),
                new QuoteDocumentPayload.PayloadRequest(
                    outcome.quoteId, 'wrong-request', 'wrong-fingerprint'
                ),
                new QuoteDocumentPayload.PayloadRequest(outcome.quoteId, null, null)
            };

        List<QuoteDocumentPayload.PayloadResult> results =
            QuoteDocumentRenderService.getPayloads(requests);
        Test.stopTest();

        Assert.areEqual(3, results.size(), 'Every request gets a result, in order.');
        Assert.isTrue(results[0].success, 'The valid request must still succeed: ' + results[0].errorMessage);
        Assert.isNotNull(results[0].payload);

        Assert.isFalse(results[1].success, 'The moved request fails.');
        Assert.areEqual('SNAPSHOT_MOVED', results[1].errorCode, 'And reports its own code.');
        Assert.isNull(results[1].payload, 'A failed request carries no payload.');

        Assert.isFalse(results[2].success, 'The bypass fails.');
        Assert.areEqual('LAUNCH_CONTRACT_BYPASSED', results[2].errorCode);
    }

    @IsTest
    static void bulkOutputOrderMatchesInputOrder() {
        Test.startTest();
        QuoteDocumentGenerator.GenerationOutcome outcome = launch();

        List<QuoteDocumentPayload.PayloadRequest> requests =
            new List<QuoteDocumentPayload.PayloadRequest>{
                new QuoteDocumentPayload.PayloadRequest(outcome.quoteId, 'bad', 'bad'),
                new QuoteDocumentPayload.PayloadRequest(
                    outcome.quoteId, outcome.requestId, outcome.fingerprint
                )
            };
        List<QuoteDocumentPayload.PayloadResult> results =
            QuoteDocumentRenderService.getPayloads(requests);
        Test.stopTest();

        Assert.isFalse(results[0].success, 'Results must line up with requests positionally.');
        Assert.isTrue(results[1].success, 'Or a caller cannot tell which result belongs to which request.');
    }

    @IsTest
    static void bulkHandlesAnUnknownQuoteWithoutFailingTheBatch() {
        Test.startTest();
        QuoteDocumentGenerator.GenerationOutcome outcome = launch();

        List<QuoteDocumentPayload.PayloadResult> results = QuoteDocumentRenderService.getPayloads(
            new List<QuoteDocumentPayload.PayloadRequest>{
                new QuoteDocumentPayload.PayloadRequest(
                    outcome.quoteId, outcome.requestId, outcome.fingerprint
                ),
                new QuoteDocumentPayload.PayloadRequest(null, 'x', 'y')
            }
        );
        Test.stopTest();

        Assert.isTrue(results[0].success, 'The good request is unaffected.');
        Assert.isFalse(results[1].success);
        Assert.areEqual('PAYLOAD_REQUEST_INVALID', results[1].errorCode);
    }

    /**
     * Query count must stay flat as the number of QUOTES grows, not only as
     * tables grow. Asserted by comparing one request against three - if any
     * query moved inside the per-request loop, the second count would be
     * roughly triple the first.
     */
    @IsTest
    static void bulkQueryCountIsFlatAsQuoteCountGrows() {
        Test.startTest();
        QuoteDocumentGenerator.GenerationOutcome outcome = launch();

        Integer before = Limits.getQueries();
        QuoteDocumentRenderService.getPayloads(
            new List<QuoteDocumentPayload.PayloadRequest>{
                new QuoteDocumentPayload.PayloadRequest(
                    outcome.quoteId, outcome.requestId, outcome.fingerprint
                )
            }
        );
        Integer forOne = Limits.getQueries() - before;

        before = Limits.getQueries();
        QuoteDocumentRenderService.getPayloads(
            new List<QuoteDocumentPayload.PayloadRequest>{
                new QuoteDocumentPayload.PayloadRequest(
                    outcome.quoteId, outcome.requestId, outcome.fingerprint
                ),
                new QuoteDocumentPayload.PayloadRequest(
                    outcome.quoteId, outcome.requestId, outcome.fingerprint
                ),
                new QuoteDocumentPayload.PayloadRequest(
                    outcome.quoteId, outcome.requestId, outcome.fingerprint
                )
            }
        );
        Integer forThree = Limits.getQueries() - before;
        Test.stopTest();

        Assert.areEqual(
            forOne,
            forThree,
            'Three quotes must cost the same queries as one. Anything else means a query moved inside the '
                + 'per-request loop, and the service stops being usable from a batch.'
        );
    }

    /**
     * The dynamic SELECT must actually include configured bindings. A static
     * field list would make step 02's subscriber-field binding valid metadata
     * that never produces a value - the column would exist, validate, and
     * print blank forever.
     */
    @IsTest
    static void dynamicSelectIncludesEveryConfiguredColumnField() {
        Test.startTest();
        QuoteDocumentPayload payload = payloadFor(launch());
        Test.stopTest();

        Map<String, String> fieldByCode = new Map<String, String>();
        for (Quote_Document_Column__c column : [
            SELECT Column_Code__c, Value_Field__c FROM Quote_Document_Column__c
            WHERE Quote_Document_Table__r.Quote__c = :QuoteDocumentTestData.quoteId()
              AND Value_Field__c != null
        ]) {
            fieldByCode.put(column.Column_Code__c, column.Value_Field__c);
        }
        Assert.isFalse(fieldByCode.isEmpty(), 'The fixture must configure bound columns.');

        Boolean sawPopulatedBinding = false;
        for (QuoteDocumentPayload.Section section : payload.sections) {
            if (!'Table'.equals(section.sectionType)) {
                continue;
            }
            for (QuoteDocumentPayload.Row row : section.rows) {
                for (String code : fieldByCode.keySet()) {
                    if (row.values.containsKey(code) && row.values.get(code) != null) {
                        sawPopulatedBinding = true;
                    }
                }
            }
        }
        Assert.isTrue(
            sawPopulatedBinding,
            'At least one bound column must arrive populated, or the dynamic SELECT is not actually '
                + 'including configured fields and every subscriber binding would print blank.'
        );
    }
}
