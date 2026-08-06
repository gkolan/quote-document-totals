/**
 * Configuration, field paths, and the safety nets that reject a bad one.
 *
 * Split out of QuoteDocumentGeneratorTest: these prove that a misconfigured
 * Quote_Document_Grouping__mdt record fails loudly at generation time with a
 * message naming the problem, rather than silently producing a table with the
 * wrong shape. That is a different subject from "does a correct configuration
 * total correctly", which stays in the generator suite.
 *
 * Fixture data comes from QuoteDocumentTestData, identical to every other
 * QuoteDocument suite.
 */
@IsTest
private class QuoteDocumentConfigTest {

    @TestSetup
    static void setup() {
        QuoteDocumentTestData.setup();
    }

    private static SBQQ__QuoteLine__c line(
        Id quoteId, Id productId, Integer lineNumber,
        Decimal quantity, Decimal listPrice, Decimal netPrice
    ) {
        return QuoteDocumentTestData.line(quoteId, productId, lineNumber, quantity, listPrice, netPrice);
    }

    private static QuoteDocumentLine documentLine(Id lineId, SBQQ__Quote__c quote) {
        return QuoteDocumentTestData.documentLine(lineId, quote);
    }

    private static Id quoteId() {
        return QuoteDocumentTestData.quoteId();
    }

    // -----------------------------------------------------------------------
    // Dimensions and filters
    // -----------------------------------------------------------------------

    @IsTest
    static void unsupportedDimensionAndFilterFailLoudly() {
        SBQQ__Quote__c quote = [SELECT Id, AccountIndustry__c FROM SBQQ__Quote__c LIMIT 1];
        Id anyLineId = [SELECT Id FROM SBQQ__QuoteLine__c LIMIT 1].Id;
        QuoteDocumentLine line = documentLine(anyLineId, quote);

        try {
            line.getGroupingValue('REGION');
            Assert.fail('An unknown dimension should not silently return a value');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('REGION'), 'The message should name the dimension');
        }

        try {
            line.matchesFilter('CHEAP_ONLY');
            Assert.fail('An unknown filter should not silently include everything');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('CHEAP_ONLY'), 'The message should name the filter');
        }
    }

    @IsTest
    static void industryDimensionAndRemainingFiltersAreSupported() {
        SBQQ__Quote__c quote = [SELECT Id, AccountIndustry__c FROM SBQQ__Quote__c LIMIT 1];
        List<SBQQ__QuoteLine__c> allLines = [
            SELECT Id, SBQQ__ChargeType__c, SBQQ__Bundle__c, SBQQ__Bundled__c
            FROM SBQQ__QuoteLine__c ORDER BY SBQQ__Number__c
        ];

        QuoteDocumentLine recurringLine;
        QuoteDocumentLine oneTimeLine;
        QuoteDocumentLine packageLine;
        QuoteDocumentLine bundledLine;
        for (SBQQ__QuoteLine__c raw : allLines) {
            QuoteDocumentLine dl = documentLine(raw.Id, quote);
            if (raw.SBQQ__ChargeType__c == 'Recurring') { recurringLine = dl; }
            if (raw.SBQQ__Bundle__c == true) { packageLine = dl; }
            if (raw.SBQQ__Bundled__c == true) { bundledLine = dl; }
            if (oneTimeLine == null && raw.SBQQ__ChargeType__c != 'Recurring') { oneTimeLine = dl; }
        }

        Assert.areEqual('Technology', recurringLine.getGroupingValue('INDUSTRY'),
            'INDUSTRY reads Account.Industry through the Quote - Technology, set in @TestSetup');

        Assert.isTrue(recurringLine.matchesFilter('RECURRING_ONLY'));
        Assert.isFalse(oneTimeLine.matchesFilter('RECURRING_ONLY'));
        Assert.isTrue(oneTimeLine.matchesFilter('ONE_TIME_ONLY'));
        Assert.isFalse(recurringLine.matchesFilter('ONE_TIME_ONLY'));

        Assert.isTrue(packageLine.matchesFilter('BUNDLE_PARENTS_ONLY'),
            'A package parent counts as a bundle parent');
        Assert.isFalse(bundledLine.matchesFilter('BUNDLE_PARENTS_ONLY'),
            'A bundled component is not a bundle parent');
    }

    // -----------------------------------------------------------------------
    // Field paths
    // -----------------------------------------------------------------------

    /**
     * QuoteDocumentLine.resolvePath is exercised end-to-end by every guide's
     * field-path grouping, but the null-intermediate-relationship fallback
     * specifically needs a line with an unpopulated lookup, which nothing in
     * @TestSetup produces (every seeded line either has no bundle parent at
     * all or a real one). A freshly-constructed SObject with nothing queried
     * is the simplest way to get a genuinely null relationship without an
     * SObjectException, since the "row was retrieved via SOQL without
     * querying this field" exception only applies to records that came from
     * an actual query - not to an in-memory literal.
     */
    @IsTest
    static void resolvePathFallsBackSafelyThroughNullRelationships() {
        QuoteDocumentLine dl = new QuoteDocumentLine(new SBQQ__QuoteLine__c(), new SBQQ__Quote__c());

        Assert.areEqual('Not Specified',
            dl.resolvePath('SBQQ__RequiredBy__r.SBQQ__RequiredBy__r.SBQQ__ProductName__c'),
            'A relationship that goes null partway through a 3-segment path must not throw');
        Assert.areEqual('Not Specified',
            dl.resolvePath('SBQQ__RequiredBy__r.SBQQ__ProductName__c'),
            'A 2-segment path through a single null relationship must also fall back safely');
    }

    @IsTest
    static void generateFailsLoudlyWhenAQuoteIdDoesNotResolve() {
        SBQQ__Quote__c real = [SELECT Id, SBQQ__Account__c, SBQQ__Opportunity2__c FROM SBQQ__Quote__c LIMIT 1];

        SBQQ__Quote__c throwaway = new SBQQ__Quote__c(
            SBQQ__Account__c = real.SBQQ__Account__c,
            SBQQ__Opportunity2__c = real.SBQQ__Opportunity2__c,
            SBQQ__Primary__c = false,
            SBQQ__Type__c = 'Quote'
        );
        insert throwaway;
        Id missingId = throwaway.Id;
        delete throwaway;

        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ real.Id, missingId });
            Assert.fail('A quote id that does not resolve must not be silently skipped');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains(String.valueOf(missingId)),
                'The message should name the missing id: ' + e.getMessage());
        }
    }

    /**
     * Every configured field path in this repo's shipped tables is a custom
     * relationship (SBQQ__Product__r, SBQQ__Group__r, ...), which always ends
     * in __r and resolves via the __r-to__c replace. A standard relationship
     * such as CreatedBy has no __c counterpart - its lookup field is
     * CreatedById - so resolving it needs the "try segment + Id" fallback in
     * validateFieldPath, which nothing else in this suite exercises.
     */
    @IsTest
    static void aFieldPathThroughAStandardRelationshipResolvesViaTheIdFallback() {
        QuoteDocumentTableDefinition byCreator = QuoteDocumentTableDefinition.build(
            'STANDARD_RELATIONSHIP_PROBE',
            new List<String>{ 'CreatedBy.Name' },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ byCreator });

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Assert.areEqual('Complete',
            [SELECT Status__c FROM Quote_Document_Table__c WHERE Table_Code__c = 'STANDARD_RELATIONSHIP_PROBE'].Status__c,
            'A path through a standard relationship (CreatedBy, not CreatedBy__r) must resolve via the Id fallback');
    }

    @IsTest
    static void aFieldPathThroughANonRelationshipFieldIsRejected() {
        QuoteDocumentTableDefinition broken = QuoteDocumentTableDefinition.build(
            'NOT_A_RELATIONSHIP_PROBE',
            new List<String>{ 'SBQQ__Quantity__c.Foo' },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ broken });

        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
            Assert.fail('A field path through a non-relationship field must not reach the query');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('is not a relationship'),
                'The message should explain why: ' + e.getMessage());
        }
    }

    // -----------------------------------------------------------------------
    // Verification firing on its own terms
    // -----------------------------------------------------------------------

    /**
     * verify() is called directly here specifically so its reconciliation
     * failures can be proven without needing to corrupt a real generation -
     * QuoteDocumentRowBuilder is internally consistent by construction, so no
     * legitimate configuration ever produces a genuine mismatch for verify()
     * to catch. That makes this test the only way to prove the safety net
     * itself actually fires when the numbers disagree.
     */
    @IsTest
    static void verifyFailsLoudlyWhenMeasuresDoNotReconcile() {
        Quote_Document_Row__c detail = new Quote_Document_Row__c(
            Row_Type__c = 'Detail',
            Group_Level__c = 1,
            Row_Key__c = 'DETAIL:1',
            Include_In_Grand_Total__c = true,
            Amount_Net__c = 100
        );
        Quote_Document_Row__c grandTotal = new Quote_Document_Row__c(
            Row_Type__c = 'Grand Total',
            Group_Level__c = 0,
            Row_Key__c = 'GRAND_TOTAL',
            Amount_Net__c = 999
        );

        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            'VERIFY_MISMATCH_PROBE',
            new List<String>{ 'PRODUCT_FAMILY' },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        Quote_Document_Table__c table = new Quote_Document_Table__c(Table_Code__c = 'VERIFY_MISMATCH_PROBE');

        try {
            QuoteDocumentVerification.verify(
                new SBQQ__Quote__c(), table, definition,
                new List<Quote_Document_Row__c>{ detail, grandTotal }
            );
            Assert.fail('A grand total that does not equal its detail rows must fail verification');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('Amount_Net__c'),
                'The message should name the field that disagreed: ' + e.getMessage());
        }
    }

    @IsTest
    static void verifyThrowsWhenNoGrandTotalRowExists() {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            'NO_GRAND_TOTAL_PROBE',
            new List<String>{ 'PRODUCT_FAMILY' },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        Quote_Document_Table__c table = new Quote_Document_Table__c(Table_Code__c = 'NO_GRAND_TOTAL_PROBE');
        List<Quote_Document_Row__c> rows = new List<Quote_Document_Row__c>{
            new Quote_Document_Row__c(Row_Type__c = 'Detail', Group_Level__c = 1, Row_Key__c = 'DETAIL:1')
        };

        try {
            QuoteDocumentVerification.verify(new SBQQ__Quote__c(), table, definition, rows);
            Assert.fail('A table built without a Grand Total row must fail verification');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('Grand Total'), 'Message: ' + e.getMessage());
        }
    }

    /**
     * Proves the fix from
     * specs/quote-docusign-totals/phases/phase-4-test-matrix-reconciliation.md:
     * Row_Key__c has no declarative uniqueness constraint (it can't - the same
     * key text like GRAND_TOTAL is legitimately reused across different
     * Quotes' tables), so nothing but this new assertion in verify() stops two
     * distinct grouping values that sanitize to the same key from silently
     * colliding. "R&D" and "R D" both reduce to "R_D" once buildGroupKey
     * uppercases and strips to [A-Z0-9_].
     */
    @IsTest
    static void duplicateGroupKeysAfterSanitizationFailGenerationLoudly() {
        Id qId = quoteId();
        List<Product2> collidingProducts = new List<Product2>{
            new Product2(Name = 'Collision A', ProductCode = 'COLLIDE_A', Family = 'R&D', IsActive = true),
            new Product2(Name = 'Collision B', ProductCode = 'COLLIDE_B', Family = 'R D', IsActive = true)
        };
        insert collidingProducts;

        insert new List<SBQQ__QuoteLine__c>{
            line(qId, collidingProducts[0].Id, 101, 1, 10, 10),
            line(qId, collidingProducts[1].Id, 102, 1, 10, 10)
        };

        QuoteDocumentTableDefinition collisionProbe = QuoteDocumentTableDefinition.build(
            'COLLISION_PROBE',
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ collisionProbe });

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ qId });
            Assert.fail('Two group values that sanitize to the same key must not both be inserted');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('duplicate Row_Key__c'),
                'The message should name the problem: ' + e.getMessage());
        }
        Test.stopTest();
    }
}
