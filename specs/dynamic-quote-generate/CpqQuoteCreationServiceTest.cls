/**
 * Tests for CpqQuoteCreationService.
 *
 * READ THIS BEFORE RUNNING
 *
 * 1. CPQ is a managed package. Inserting SBQQ__Quote__c and
 *    SBQQ__QuoteLine__c fires its triggers inside these tests. If your org
 *    has CPQ package settings, custom scripts, price rules, or a Quote
 *    Calculator Plugin that assume data these tests do not create, failures
 *    will surface from inside SBQQ code rather than from the service. That
 *    is an environment problem, not a defect in the class under test.
 *
 * 2. PASSTHROUGH_FIELD below must be a writable custom field that exists on
 *    SBQQ__QuoteLine__c in your org. The default is a guess. Change it to a
 *    field you know exists before running.
 *
 * 3. These run with SeeAllData=false and build their own products, pricebook
 *    entries, and product options.
 */
@IsTest
private class CpqQuoteCreationServiceTest {

    // Change this to a writable custom field that exists on SBQQ__QuoteLine__c.
    private static final String PASSTHROUGH_FIELD = 'SBQQ__Description__c';
    private static final String PASSTHROUGH_VALUE = 'set-by-payload';

    private static final String BUNDLE_CODE       = 'TEST-BUNDLE';
    private static final String OPTION_CODE       = 'TEST-OPT-1';
    private static final String OPTION_CODE_2     = 'TEST-OPT-2';
    private static final String FLAT_CODE         = 'TEST-FLAT';
    private static final String OTHER_BUNDLE_CODE = 'TEST-OTHER-BUNDLE';
    private static final String OTHER_OPTION_CODE = 'TEST-OTHER-OPT';

    // ------------------------------------------------------------------
    // Setup
    // ------------------------------------------------------------------

    @TestSetup
    static void makeData() {
        Account acc = new Account(Name = 'CPQ Test Account');
        insert acc;

        Product2 bundle      = newProduct('Test Bundle',       BUNDLE_CODE);
        Product2 option1     = newProduct('Test Option 1',     OPTION_CODE);
        Product2 option2     = newProduct('Test Option 2',     OPTION_CODE_2);
        Product2 flat        = newProduct('Test Flat Product', FLAT_CODE);
        Product2 otherBundle = newProduct('Other Bundle',      OTHER_BUNDLE_CODE);
        Product2 otherOption = newProduct('Other Option',      OTHER_OPTION_CODE);

        List<Product2> products = new List<Product2>{
            bundle, option1, option2, flat, otherBundle, otherOption
        };
        insert products;

        Id standardPricebookId = Test.getStandardPricebookId();

        List<PricebookEntry> entries = new List<PricebookEntry>();
        for (Product2 p : products) {
            entries.add(new PricebookEntry(
                Pricebook2Id = standardPricebookId,
                Product2Id   = p.Id,
                UnitPrice    = 100,
                IsActive     = true
            ));
        }
        insert entries;

        // OPTION_CODE and OPTION_CODE_2 belong to BUNDLE_CODE.
        // OTHER_OPTION_CODE belongs to OTHER_BUNDLE_CODE only, which is what
        // lets us prove cross-bundle options are rejected.
        insert new List<SBQQ__ProductOption__c>{
            newOption(bundle.Id,      option1.Id,     1),
            newOption(bundle.Id,      option2.Id,     2),
            newOption(otherBundle.Id, otherOption.Id, 1)
        };

        insert new Opportunity(
            Name         = 'CPQ Test Opp',
            AccountId    = acc.Id,
            StageName    = 'Prospecting',
            CloseDate    = Date.today().addDays(30),
            Pricebook2Id = standardPricebookId
        );
    }

    private static Product2 newProduct(String name, String code) {
        return new Product2(Name = name, ProductCode = code, IsActive = true);
    }

    private static SBQQ__ProductOption__c newOption(Id configuredSku, Id optionalSku, Integer number) {
        return new SBQQ__ProductOption__c(
            SBQQ__ConfiguredSKU__c = configuredSku,
            SBQQ__OptionalSKU__c   = optionalSku,
            SBQQ__Number__c        = number
        );
    }

    // ------------------------------------------------------------------
    // Payload builders
    // ------------------------------------------------------------------

    private static Map<String, Object> line(String code, Decimal qty, Map<String, Object> fields) {
        return new Map<String, Object>{
            'productCode' => code,
            'quantity'    => qty,
            'fields'      => fields
        };
    }

    private static Map<String, Object> bundleLine(String code, List<Object> options) {
        Map<String, Object> parent = line(code, 1, null);
        parent.put('options', options);
        return parent;
    }

    private static String payload(List<Object> lines) {
        return payload(lines, null);
    }

    private static String payload(List<Object> lines, Map<String, Object> quoteFields) {
        return JSON.serialize(new Map<String, Object>{
            'quoteFields' => (quoteFields == null ? new Map<String, Object>() : quoteFields),
            'lines'       => lines
        });
    }

    private static Id oppId() {
        return [SELECT Id FROM Opportunity LIMIT 1].Id;
    }

    private static List<SBQQ__QuoteLine__c> linesOn(Id quoteId) {
        return [
            SELECT Id, SBQQ__Product__r.ProductCode, SBQQ__Quantity__c,
                   SBQQ__RequiredBy__c, SBQQ__ProductOption__c, SBQQ__Bundle__c,
                   SBQQ__PricebookEntryId__c
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :quoteId
        ];
    }

    // ------------------------------------------------------------------
    // Happy paths
    // ------------------------------------------------------------------

    @IsTest
    static void createsFlatLinesOnly() {
        String body = payload(new List<Object>{
            line(FLAT_CODE, 2, null),
            line(BUNDLE_CODE, 1, null)
        });

        Test.startTest();
        Id quoteId = CpqQuoteCreationService.create(oppId(), body);
        Test.stopTest();

        Assert.isNotNull(quoteId, 'Quote should have been created');

        List<SBQQ__QuoteLine__c> lines = linesOn(quoteId);
        Assert.areEqual(2, lines.size(), 'Expected two flat lines');

        for (SBQQ__QuoteLine__c l : lines) {
            Assert.isNull(l.SBQQ__RequiredBy__c, 'Flat lines must have no parent');
            Assert.isNull(l.SBQQ__ProductOption__c, 'Flat lines must have no product option');
            Assert.areNotEqual(true, l.SBQQ__Bundle__c, 'Flat lines must not be flagged as bundles');
        }
    }

    @IsTest
    static void createsBundleWithOptions() {
        String body = payload(new List<Object>{
            bundleLine(BUNDLE_CODE, new List<Object>{
                line(OPTION_CODE, 3, null),
                line(OPTION_CODE_2, 1, null)
            })
        });

        Test.startTest();
        Id quoteId = CpqQuoteCreationService.create(oppId(), body);
        Test.stopTest();

        List<SBQQ__QuoteLine__c> lines = linesOn(quoteId);
        Assert.areEqual(3, lines.size(), 'Expected one parent and two option lines');

        SBQQ__QuoteLine__c parent;
        Map<String, SBQQ__QuoteLine__c> childrenByCode = new Map<String, SBQQ__QuoteLine__c>();

        for (SBQQ__QuoteLine__c l : lines) {
            if (l.SBQQ__RequiredBy__c == null) {
                parent = l;
            } else {
                childrenByCode.put(l.SBQQ__Product__r.ProductCode, l);
            }
        }

        Assert.isNotNull(parent, 'A parent line should exist');
        Assert.areEqual(BUNDLE_CODE, parent.SBQQ__Product__r.ProductCode, 'Parent should be the bundle');
        Assert.areEqual(true, parent.SBQQ__Bundle__c, 'Parent must be flagged as a bundle');
        Assert.areEqual(2, childrenByCode.size(), 'Expected two children');

        for (SBQQ__QuoteLine__c child : childrenByCode.values()) {
            Assert.areEqual(parent.Id, child.SBQQ__RequiredBy__c, 'Child must point at the parent');
            Assert.isNotNull(child.SBQQ__ProductOption__c, 'Child must carry a ProductOption');
        }

        Assert.areEqual(3, childrenByCode.get(OPTION_CODE).SBQQ__Quantity__c,
            'Option quantity should come from the payload');
    }

    @IsTest
    static void resolvesTheCorrectProductOptionRecord() {
        String body = payload(new List<Object>{
            bundleLine(BUNDLE_CODE, new List<Object>{ line(OPTION_CODE, 1, null) })
        });

        Test.startTest();
        Id quoteId = CpqQuoteCreationService.create(oppId(), body);
        Test.stopTest();

        SBQQ__QuoteLine__c child = [
            SELECT SBQQ__ProductOption__r.SBQQ__ConfiguredSKU__r.ProductCode,
                   SBQQ__ProductOption__r.SBQQ__OptionalSKU__r.ProductCode
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :quoteId AND SBQQ__RequiredBy__c != null
            LIMIT 1
        ];

        Assert.areEqual(BUNDLE_CODE,
            child.SBQQ__ProductOption__r.SBQQ__ConfiguredSKU__r.ProductCode,
            'ProductOption must belong to the requested bundle');
        Assert.areEqual(OPTION_CODE,
            child.SBQQ__ProductOption__r.SBQQ__OptionalSKU__r.ProductCode,
            'ProductOption must reference the requested option product');
    }

    @IsTest
    static void createsMixedBundleAndFlatLines() {
        String body = payload(new List<Object>{
            bundleLine(BUNDLE_CODE, new List<Object>{ line(OPTION_CODE, 1, null) }),
            line(FLAT_CODE, 1, null)
        });

        Test.startTest();
        Id quoteId = CpqQuoteCreationService.create(oppId(), body);
        Test.stopTest();

        List<SBQQ__QuoteLine__c> lines = linesOn(quoteId);
        Assert.areEqual(3, lines.size(), 'Expected bundle parent, its option, and one flat line');

        Integer children = 0;
        for (SBQQ__QuoteLine__c l : lines) {
            if (l.SBQQ__RequiredBy__c != null) {
                children++;
            }
        }
        Assert.areEqual(1, children, 'Only the bundle option should be a child');
    }

    @IsTest
    static void quoteIsCreatedNonPrimaryAndLinkedToOpportunity() {
        Id opportunityId = oppId();

        Test.startTest();
        Id quoteId = CpqQuoteCreationService.create(
            opportunityId, payload(new List<Object>{ line(FLAT_CODE, 1, null) }));
        Test.stopTest();

        SBQQ__Quote__c q = [
            SELECT SBQQ__Primary__c, SBQQ__Opportunity2__c, SBQQ__Account__c
            FROM SBQQ__Quote__c WHERE Id = :quoteId
        ];

        Assert.areNotEqual(true, q.SBQQ__Primary__c, 'Quote must not be primary');
        Assert.areEqual(opportunityId, q.SBQQ__Opportunity2__c, 'Quote must link to the Opportunity');
        Assert.isNotNull(q.SBQQ__Account__c, 'Account should be carried over from the Opportunity');
    }

    @IsTest
    static void populatesPricebookEntry() {
        Test.startTest();
        Id quoteId = CpqQuoteCreationService.create(
            oppId(), payload(new List<Object>{ line(FLAT_CODE, 1, null) }));
        Test.stopTest();

        Assert.isNotNull(linesOn(quoteId)[0].SBQQ__PricebookEntryId__c,
            'PricebookEntry should resolve from the Opportunity pricebook');
    }

    @IsTest
    static void quantityDefaultsToOneWhenOmitted() {
        String body = payload(new List<Object>{ line(FLAT_CODE, null, null) });

        Test.startTest();
        Id quoteId = CpqQuoteCreationService.create(oppId(), body);
        Test.stopTest();

        Assert.areEqual(1, linesOn(quoteId)[0].SBQQ__Quantity__c,
            'Quantity should default to 1');
    }

    @IsTest
    static void passesThroughCustomLineFields() {
        // Skip cleanly if the configured field does not exist in this org,
        // so an environment mismatch does not masquerade as a code failure.
        if (!Schema.SObjectType.SBQQ__QuoteLine__c.fields.getMap()
                .containsKey(PASSTHROUGH_FIELD.toLowerCase())) {
            Assert.isTrue(true, 'PASSTHROUGH_FIELD not present in this org; test skipped');
            return;
        }

        String body = payload(new List<Object>{
            line(FLAT_CODE, 1, new Map<String, Object>{ PASSTHROUGH_FIELD => PASSTHROUGH_VALUE })
        });

        Test.startTest();
        Id quoteId = CpqQuoteCreationService.create(oppId(), body);
        Test.stopTest();

        SBQQ__QuoteLine__c l = Database.query(
            'SELECT ' + String.escapeSingleQuotes(PASSTHROUGH_FIELD) +
            ' FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c = :quoteId LIMIT 1');

        Assert.areEqual(PASSTHROUGH_VALUE, l.get(PASSTHROUGH_FIELD),
            'Payload field value should land on the quote line');
    }

    // ------------------------------------------------------------------
    // Validation failures
    // ------------------------------------------------------------------

    @IsTest
    static void rejectsUnknownProductCode() {
        String body = payload(new List<Object>{ line('DOES-NOT-EXIST', 1, null) });

        Test.startTest();
        String message = expectFailure(oppId(), body);
        Test.stopTest();

        Assert.isTrue(message.contains('Unresolvable product codes'),
            'Expected unresolvable product code error, got: ' + message);
        Assert.areEqual(0, [SELECT COUNT() FROM SBQQ__Quote__c], 'No quote should survive');
    }

    @IsTest
    static void rejectsOptionThatBelongsToAnotherBundle() {
        String body = payload(new List<Object>{
            bundleLine(BUNDLE_CODE, new List<Object>{ line(OTHER_OPTION_CODE, 1, null) })
        });

        Test.startTest();
        String message = expectFailure(oppId(), body);
        Test.stopTest();

        Assert.isTrue(message.contains('is not a configured option of'),
            'Expected cross-bundle option rejection, got: ' + message);
    }

    @IsTest
    static void rejectsUnknownFieldName() {
        String body = payload(new List<Object>{
            line(FLAT_CODE, 1, new Map<String, Object>{ 'Not_A_Real_Field__c' => 'x' })
        });

        Test.startTest();
        String message = expectFailure(oppId(), body);
        Test.stopTest();

        Assert.isTrue(message.contains('Unknown field'),
            'Expected unknown field error, got: ' + message);
    }

    @IsTest
    static void rejectsServiceOwnedField() {
        String body = payload(new List<Object>{
            line(FLAT_CODE, 1, new Map<String, Object>{ 'SBQQ__Bundle__c' => true })
        });

        Test.startTest();
        String message = expectFailure(oppId(), body);
        Test.stopTest();

        Assert.isTrue(message.contains('set by this service'),
            'Expected blocked field error, got: ' + message);
    }

    @IsTest
    static void rejectsServiceOwnedQuoteField() {
        String body = payload(
            new List<Object>{ line(FLAT_CODE, 1, null) },
            new Map<String, Object>{ 'SBQQ__Primary__c' => true });

        Test.startTest();
        String message = expectFailure(oppId(), body);
        Test.stopTest();

        Assert.isTrue(message.contains('set by this service'),
            'Expected blocked quote field error, got: ' + message);
    }

    @IsTest
    static void rejectsMalformedJson() {
        Test.startTest();
        String message = expectFailure(oppId(), '{ not valid json');
        Test.stopTest();

        Assert.isTrue(message.contains('not valid JSON'),
            'Expected JSON parse error, got: ' + message);
    }

    @IsTest
    static void rejectsEmptyLineList() {
        Test.startTest();
        String message = expectFailure(oppId(), payload(new List<Object>()));
        Test.stopTest();

        Assert.isTrue(message.contains('no lines'),
            'Expected empty payload error, got: ' + message);
    }

    @IsTest
    static void rejectsLineWithoutProductCode() {
        String body = payload(new List<Object>{ line(null, 1, null) });

        Test.startTest();
        String message = expectFailure(oppId(), body);
        Test.stopTest();

        Assert.isTrue(message.contains('requires a productCode'),
            'Expected missing product code error, got: ' + message);
    }

    @IsTest
    static void rejectsNullArguments() {
        Test.startTest();
        Assert.isTrue(
            expectFailure(null, payload(new List<Object>{ line(FLAT_CODE, 1, null) }))
                .contains('Opportunity Id is required'),
            'Null Opportunity Id should be rejected');
        Assert.isTrue(
            expectFailure(oppId(), null).contains('Payload JSON is required'),
            'Null payload should be rejected');
        Test.stopTest();
    }

    private static String expectFailure(Id opportunityId, String body) {
        try {
            CpqQuoteCreationService.create(opportunityId, body);
            Assert.fail('Expected QuoteCreationException');
        } catch (CpqQuoteCreationService.QuoteCreationException e) {
            return e.getMessage();
        }
        return '';
    }

    // ------------------------------------------------------------------
    // Invocable
    // ------------------------------------------------------------------

    @IsTest
    static void invocableReturnsSuccess() {
        CpqQuoteCreationService.Request req = new CpqQuoteCreationService.Request();
        req.opportunityId = oppId();
        req.payloadJson = payload(new List<Object>{
            bundleLine(BUNDLE_CODE, new List<Object>{ line(OPTION_CODE, 1, null) })
        });

        Test.startTest();
        List<CpqQuoteCreationService.Result> results =
            CpqQuoteCreationService.createQuotes(
                new List<CpqQuoteCreationService.Request>{ req });
        Test.stopTest();

        Assert.areEqual(1, results.size(), 'One result per request');
        Assert.areEqual(true, results[0].success, 'Should succeed: ' + results[0].errorMessage);
        Assert.isNotNull(results[0].quoteId, 'Quote Id should be returned');
        Assert.areEqual(2, results[0].lineCount, 'Parent plus one option');
        Assert.isNull(results[0].errorMessage, 'No error expected');
    }

    @IsTest
    static void invocableReturnsErrorInsteadOfThrowing() {
        CpqQuoteCreationService.Request req = new CpqQuoteCreationService.Request();
        req.opportunityId = oppId();
        req.payloadJson = payload(new List<Object>{ line('NOPE', 1, null) });

        Test.startTest();
        List<CpqQuoteCreationService.Result> results =
            CpqQuoteCreationService.createQuotes(
                new List<CpqQuoteCreationService.Request>{ req });
        Test.stopTest();

        Assert.areEqual(false, results[0].success, 'Should report failure, not throw');
        Assert.isNotNull(results[0].errorMessage, 'Error message should be populated');
        Assert.isNull(results[0].quoteId, 'No quote Id on failure');
        Assert.areEqual(0, results[0].lineCount, 'No lines on failure');
    }

    @IsTest
    static void invocableIsolatesFailureToItsOwnRequest() {
        Id opportunityId = oppId();

        CpqQuoteCreationService.Request good = new CpqQuoteCreationService.Request();
        good.opportunityId = opportunityId;
        good.payloadJson = payload(new List<Object>{ line(FLAT_CODE, 1, null) });

        CpqQuoteCreationService.Request bad = new CpqQuoteCreationService.Request();
        bad.opportunityId = opportunityId;
        bad.payloadJson = payload(new List<Object>{ line('NOPE', 1, null) });

        Test.startTest();
        List<CpqQuoteCreationService.Result> results =
            CpqQuoteCreationService.createQuotes(
                new List<CpqQuoteCreationService.Request>{ good, bad });
        Test.stopTest();

        Assert.areEqual(true, results[0].success, 'First request should succeed');
        Assert.areEqual(false, results[1].success, 'Second request should fail');
        Assert.areEqual(1, [SELECT COUNT() FROM SBQQ__Quote__c],
            'The successful quote must survive its neighbour rolling back');
    }

    @IsTest
    static void invocableRejectsBlankInputs() {
        CpqQuoteCreationService.Request noOpp = new CpqQuoteCreationService.Request();
        noOpp.payloadJson = payload(new List<Object>{ line(FLAT_CODE, 1, null) });

        CpqQuoteCreationService.Request noPayload = new CpqQuoteCreationService.Request();
        noPayload.opportunityId = oppId();

        CpqQuoteCreationService.Request badId = new CpqQuoteCreationService.Request();
        badId.opportunityId = 'not-an-id';
        badId.payloadJson = payload(new List<Object>{ line(FLAT_CODE, 1, null) });

        Test.startTest();
        List<CpqQuoteCreationService.Result> results =
            CpqQuoteCreationService.createQuotes(
                new List<CpqQuoteCreationService.Request>{ noOpp, noPayload, badId });
        Test.stopTest();

        for (CpqQuoteCreationService.Result r : results) {
            Assert.areEqual(false, r.success, 'All three should fail');
            Assert.isNotNull(r.errorMessage, 'Each failure should explain itself');
        }
    }

    @IsTest
    static void invocableEnforcesLineCeilingBeforeAnyInsert() {
        CpqQuoteCreationService.maxLinesPerInvocation = 3;

        CpqQuoteCreationService.Request req = new CpqQuoteCreationService.Request();
        req.opportunityId = oppId();
        req.payloadJson = payload(new List<Object>{
            line(FLAT_CODE, 1, null),
            line(FLAT_CODE, 1, null),
            line(FLAT_CODE, 1, null),
            line(FLAT_CODE, 1, null)
        });

        Test.startTest();
        List<CpqQuoteCreationService.Result> results =
            CpqQuoteCreationService.createQuotes(
                new List<CpqQuoteCreationService.Request>{ req });
        Test.stopTest();

        Assert.areEqual(false, results[0].success, 'Should be refused');
        Assert.isTrue(results[0].errorMessage.contains('exceeding the synchronous ceiling'),
            'Expected ceiling error, got: ' + results[0].errorMessage);
        Assert.areEqual(0, [SELECT COUNT() FROM SBQQ__Quote__c],
            'Ceiling must be enforced before any DML');
    }

    @IsTest
    static void invocableCeilingAccumulatesAcrossRequests() {
        CpqQuoteCreationService.maxLinesPerInvocation = 2;
        Id opportunityId = oppId();

        List<CpqQuoteCreationService.Request> requests =
            new List<CpqQuoteCreationService.Request>();

        for (Integer i = 0; i < 2; i++) {
            CpqQuoteCreationService.Request r = new CpqQuoteCreationService.Request();
            r.opportunityId = opportunityId;
            r.payloadJson = payload(new List<Object>{
                line(FLAT_CODE, 1, null),
                line(BUNDLE_CODE, 1, null)
            });
            requests.add(r);
        }

        Test.startTest();
        List<CpqQuoteCreationService.Result> results =
            CpqQuoteCreationService.createQuotes(requests);
        Test.stopTest();

        Assert.areEqual(true, results[0].success, 'First request fits under the ceiling');
        Assert.areEqual(false, results[1].success, 'Second request pushes past it');
        Assert.isTrue(results[1].errorMessage.contains('already processed in this transaction'),
            'Error should reference the running total, got: ' + results[1].errorMessage);
    }
}
