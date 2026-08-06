/**
 * Covers the cases that decide whether a signed document carries the right
 * number: a package with bundled components, a separately-priced option, an
 * optional product, a recurring charge, and the change classifications that no
 * quote in this org can currently produce.
 *
 * Line totals on SBQQ__QuoteLine__c are formula fields, so the test sets the
 * writable price and quantity inputs and lets CPQ compute the totals. Expected
 * values are then derived from what CPQ actually calculated rather than
 * hardcoded - the point of these assertions is that the generator adds up the
 * same lines CPQ did, not that a particular formula produces a particular
 * number.
 *
 * The CPQ Calculate API is deliberately not invoked: the generator reads stored
 * totals, so priced lines are all it needs, and Calculate would make the test
 * slow and non-deterministic.
 */
@IsTest
private class QuoteDocumentGeneratorTest {

    private static final String CODE_PACKAGE   = QuoteDocumentTestData.CODE_PACKAGE;
    private static final String CODE_COMPONENT = QuoteDocumentTestData.CODE_COMPONENT;
    private static final String CODE_OPTION    = QuoteDocumentTestData.CODE_OPTION;
    private static final String CODE_PLAN      = QuoteDocumentTestData.CODE_PLAN;
    private static final String CODE_OPTIONAL  = QuoteDocumentTestData.CODE_OPTIONAL;

    @TestSetup
    static void setup() {
        QuoteDocumentTestData.setup();
    }

    // Thin delegates so the assertions below read the same as they did when
    // the fixture lived in this file.

    private static SBQQ__QuoteLine__c line(
        Id quoteId, Id productId, Integer lineNumber,
        Decimal quantity, Decimal listPrice, Decimal netPrice
    ) {
        return QuoteDocumentTestData.line(quoteId, productId, lineNumber, quantity, listPrice, netPrice);
    }

    private static Decimal expectedCountedNet() {
        return QuoteDocumentTestData.expectedCountedNet();
    }

    private static Decimal expectedNetForCode(String productCode) {
        return QuoteDocumentTestData.expectedNetForCode(productCode);
    }

    private static Map<Id, SBQQ__QuoteLine__c> storedLines(List<Id> lineIds) {
        return QuoteDocumentTestData.storedLines(lineIds);
    }

    private static QuoteDocumentLine documentLine(Id lineId, SBQQ__Quote__c quote) {
        return QuoteDocumentTestData.documentLine(lineId, quote);
    }

    private static Id quoteId() {
        return QuoteDocumentTestData.quoteId();
    }

    private static Quote_Document_Table__c table(String tableCode) {
        return QuoteDocumentTestData.table(tableCode);
    }

    private static List<Quote_Document_Row__c> rows(String tableCode) {
        return QuoteDocumentTestData.rows(tableCode);
    }

    private static Quote_Document_Row__c grandTotal(String tableCode) {
        return QuoteDocumentTestData.grandTotal(tableCode);
    }

    // -----------------------------------------------------------------------

    @IsTest
    static void generatesEveryDefinedTableAsComplete() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        List<Quote_Document_Table__c> tables = [
            SELECT Table_Code__c, Status__c, Row_Count__c FROM Quote_Document_Table__c
        ];

        Assert.areEqual(QuoteDocumentTableDefinition.getAll().size(), tables.size(),
            'Every definition should produce exactly one table');

        for (Quote_Document_Table__c t : tables) {
            Assert.areEqual('Complete', t.Status__c, t.Table_Code__c + ' should be Complete');
            Assert.isTrue(t.Row_Count__c > 0, t.Table_Code__c + ' should have rows');
        }
    }

    @IsTest
    static void bundledComponentIsShownButNotCounted() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Quote_Document_Row__c component;
        for (Quote_Document_Row__c row : rows('BUNDLE_DETAIL')) {
            if (row.Product_Name__c == 'Test Component') {
                component = row;
            }
        }

        Assert.isNotNull(component, 'The bundled component should appear as a detail row');
        Assert.isTrue(component.Is_Displayed__c, 'A bundled component is still printed');
        Assert.isFalse(component.Include_In_Subtotal__c,
            'A bundled component must not count - its price sits in the package');
        Assert.isFalse(component.Include_In_Grand_Total__c,
            'A bundled component must not count toward the grand total either');
        Assert.areEqual(2, component.Group_Level__c,
            'A component indents one level below its package');
    }

    @IsTest
    static void optionalProductIsExcludedFromOrdinaryTotalsAndCountedInItsOwn() {
        Decimal counted = expectedCountedNet();
        Decimal optional = expectedNetForCode(CODE_OPTIONAL);

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Assert.areEqual(counted, grandTotal('PRODUCT_FAMILY_SUMMARY').Amount_Net__c,
            'The ordinary summary must exclude the optional product');

        // A zero total on a table whose entire subject is optional products
        // would be absurd, so the filter has to override the exclusion.
        Assert.areEqual(optional, grandTotal('OPTIONAL_PRODUCTS').Amount_Net__c,
            'The Optional Products table must count its own lines');
        Assert.isTrue(optional > 0, 'The optional line should carry a real price');
    }

    @IsTest
    static void grandTotalReconcilesToTheQuoteNetAmount() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        SBQQ__Quote__c quote = [SELECT SBQQ__NetAmount__c FROM SBQQ__Quote__c LIMIT 1];

        // CPQ's own roll-up excludes optional lines, and so must the document.
        Assert.areEqual(quote.SBQQ__NetAmount__c, grandTotal('PRODUCT_FAMILY_SUMMARY').Amount_Net__c,
            'Product Family Summary must agree with the Quote');
        Assert.areEqual(quote.SBQQ__NetAmount__c, grandTotal('BUNDLE_DETAIL').Amount_Net__c,
            'Bundle Detail must agree with the Quote');
        Assert.areEqual(quote.SBQQ__NetAmount__c, grandTotal('CHARGE_TYPE_SUMMARY').Amount_Net__c,
            'Charge Type Summary must agree with the Quote');
    }

    @IsTest
    static void aggregateRowsNeverCountTowardTotals() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Set<String> aggregates = new Set<String>{
            'Group Header', 'Subtotal', 'Section Total', 'Grand Total'
        };

        for (Quote_Document_Row__c row : [
            SELECT Row_Type__c, Group_Level__c, Quote_Line__c,
                   Include_In_Subtotal__c, Include_In_Grand_Total__c
            FROM Quote_Document_Row__c
        ]) {
            if (!aggregates.contains(row.Row_Type__c)) { continue; }

            Assert.isFalse(row.Include_In_Subtotal__c, row.Row_Type__c + ' must not feed a subtotal');
            Assert.isFalse(row.Include_In_Grand_Total__c, row.Row_Type__c + ' must not feed the grand total');
            Assert.isNull(row.Quote_Line__c, row.Row_Type__c + ' spans lines, so it references none');

            if (row.Row_Type__c == 'Grand Total') {
                Assert.areEqual(0, row.Group_Level__c, 'A grand total belongs to the table, at level 0');
            }
        }
    }

    @IsTest
    static void rowsAreOrderedAndEveryLineAppearsOnce() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Decimal previousOrder = -1;
        Set<Id> seenLines = new Set<Id>();

        for (Quote_Document_Row__c row : rows('BUNDLE_DETAIL')) {
            Assert.isTrue(row.Display_Order__c > previousOrder, 'Display order must strictly increase');
            previousOrder = row.Display_Order__c;

            if (row.Quote_Line__c != null) {
                Assert.isFalse(seenLines.contains(row.Quote_Line__c),
                    'A quote line must appear at most once per table');
                seenLines.add(row.Quote_Line__c);
            }
        }

        // Four of the five lines - the optional one is filtered out entirely.
        Assert.areEqual(4, seenLines.size(), 'Every non-optional line should appear exactly once');
    }

    @IsTest
    static void sectionTotalsSplitRecurringFromOneTime() {
        Decimal recurring = expectedNetForCode(CODE_PLAN);
        Decimal oneTime = expectedCountedNet() - recurring;

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Map<String, Decimal> netBySection = new Map<String, Decimal>();
        for (Quote_Document_Row__c row : rows('PRODUCT_FAMILY_SUMMARY')) {
            if (row.Row_Type__c == 'Section Total') {
                netBySection.put(row.Group_Value__c, row.Amount_Net__c);
            }
        }

        Assert.areEqual(recurring, netBySection.get('Recurring'), 'Only the plan is recurring');
        Assert.areEqual(oneTime, netBySection.get('One-Time'), 'Everything else is a one-off charge');
    }

    @IsTest
    static void nestedGroupingProducesTwoLevelsOfSubtotal() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Set<Decimal> subtotalLevels = new Set<Decimal>();
        for (Quote_Document_Row__c row : rows('GROUP_FAMILY_DETAIL')) {
            if (row.Row_Type__c == 'Subtotal') {
                subtotalLevels.add(row.Group_Level__c);
            }
        }

        Assert.isTrue(subtotalLevels.contains(1), 'Outer grouping should produce a level-1 subtotal');
        Assert.isTrue(subtotalLevels.contains(2), 'Inner grouping should produce a level-2 subtotal');
    }

    /**
     * Drives an injected definition rather than the real TRANSACTION_SUMMARY
     * record, which is inactive until classify() is validated against a genuine
     * amendment (docs/quote-document-totals.md §3). The classification
     * arithmetic still needs covering while the table itself stays off, and a
     * test that depended on the active flag would go quiet exactly when the
     * flag was flipped for safety.
     */
    // Transaction classification moved to QuoteDocumentClassificationTest -
    // it is the one area still open pending phase-1 validation, so it keeps
    // its own suite.

    // Dimensions, filters, field paths and the verification failures they can
    // trigger moved to QuoteDocumentConfigTest.

    /**
     * QuoteDocumentRowBuilder is fed lines in query order everywhere else in
     * this suite (generateOne always queries ORDER BY SBQQ__Number__c), which
     * never exercises the "a later line has a lower sequence than the group's
     * first-seen line" branch in groupLines, or the actual swap inside
     * sortedBySequence's insertion sort. Calling the builder directly - which
     * every guide's own config still goes through in production, this is not
     * a bypass of anything - with lines deliberately out of order proves both
     * without assuming the caller always supplies ascending input.
     */
    @IsTest
    static void groupingTracksTheEarliestLineSequenceEvenWhenFedOutOfOrder() {
        SBQQ__Quote__c quote = [SELECT Id, AccountIndustry__c FROM SBQQ__Quote__c LIMIT 1];
        List<SBQQ__QuoteLine__c> hardwareLines = [
            SELECT Id FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Product__r.ProductCode IN :new List<String>{ CODE_PACKAGE, CODE_COMPONENT }
            ORDER BY SBQQ__Number__c
        ];
        QuoteDocumentLine packageLine = documentLine(hardwareLines[0].Id, quote);
        QuoteDocumentLine componentLine = documentLine(hardwareLines[1].Id, quote);

        QuoteDocumentTableDefinition probe = QuoteDocumentTableDefinition.build(
            'ORDER_PROBE',
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );

        List<Quote_Document_Row__c> rows = new QuoteDocumentRowBuilder(probe)
            .build(new List<QuoteDocumentLine>{ componentLine, packageLine });

        List<Quote_Document_Row__c> details = new List<Quote_Document_Row__c>();
        for (Quote_Document_Row__c row : rows) {
            if (row.Row_Type__c == 'Detail') { details.add(row); }
        }
        Assert.areEqual(2, details.size());
        Assert.areEqual(packageLine.quoteLineId, details[0].Quote_Line__c,
            'Detail rows must sort by sequence, not by input order');
        Assert.areEqual(componentLine.quoteLineId, details[1].Quote_Line__c);
    }

    /**
     * Proves the concern raised in
     * specs/quote-docusign-totals/phases/phase-3-atomicity-test.md: a failed
     * regeneration must leave the previous complete tables exactly as they
     * were, not partially replaced. generateOne takes one savepoint per Quote
     * before its delete-and-reinsert, and every DML for that Quote - including
     * the delete - runs inside the same try/catch that rolls back to that
     * savepoint on any exception. This forces a failure after the delete has
     * already executed (a definition that produces more groups than
     * Max_Groups__c allows, thrown from inside QuoteDocumentRowBuilder.build,
     * partway through generateOne's per-definition loop and therefore after
     * the delete but before any reinsert) and confirms the rollback actually
     * restores the prior records - same Ids, same values - rather than merely
     * leaving the Quote in a state that happens to look untouched.
     */
    @IsTest
    static void aFailedRegenerationLeavesThePreviousCompleteTablesUntouched() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        List<Quote_Document_Table__c> before = [
            SELECT Id, Table_Code__c, Row_Count__c, Amount_Net__c, Generated_On__c
            FROM Quote_Document_Table__c
            WHERE Quote__c = :quoteId()
            ORDER BY Table_Code__c
        ];
        Integer rowCountBefore = [
            SELECT COUNT() FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Quote__c = :quoteId()
        ];
        Assert.isTrue(before.size() > 0, 'The first generation must have produced tables to protect');

        QuoteDocumentTableDefinition broken = QuoteDocumentTableDefinition.build(
            'ATOMICITY_PROBE',
            new List<String>{ 'SBQQ__Product__r.Name' },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        broken.maxGroups = 1;
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ broken });

        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
            Assert.fail('A definition that exceeds Max Groups must fail generation, not silently truncate it');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            // Expected - the failure itself is proven elsewhere
            // (exceedingTheGroupCeilingFailsLoudly). What this test proves is
            // what happens to the *prior* data once this throws.
            Assert.isTrue(e.getMessage().contains('more than 1 groups'),
                'Sanity check that this failed for the expected reason: ' + e.getMessage());
        }

        List<Quote_Document_Table__c> after = [
            SELECT Id, Table_Code__c, Row_Count__c, Amount_Net__c, Generated_On__c
            FROM Quote_Document_Table__c
            WHERE Quote__c = :quoteId()
            ORDER BY Table_Code__c
        ];
        Integer rowCountAfter = [
            SELECT COUNT() FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Quote__c = :quoteId()
        ];

        Assert.areEqual(before.size(), after.size(), 'A failed regeneration must not change the number of tables');
        Assert.areEqual(rowCountBefore, rowCountAfter, 'A failed regeneration must not change the number of rows');
        for (Integer i = 0; i < before.size(); i++) {
            Assert.areEqual(before[i].Id, after[i].Id,
                'The rollback must restore the exact prior records, not merely equivalent new ones');
            Assert.areEqual(before[i].Row_Count__c, after[i].Row_Count__c, 'Row Count must be unchanged');
            Assert.areEqual(before[i].Amount_Net__c, after[i].Amount_Net__c, 'Amount Net must be unchanged');
            Assert.areEqual(before[i].Generated_On__c, after[i].Generated_On__c,
                'Generated On must be unchanged - proving the rollback, not a lucky re-match');
        }
    }

    @IsTest
    static void regeneratingReplacesRatherThanDuplicates() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Integer afterFirst = [SELECT COUNT() FROM Quote_Document_Row__c];
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Integer afterSecond = [SELECT COUNT() FROM Quote_Document_Row__c];
        Test.stopTest();

        Assert.areEqual(afterFirst, afterSecond, 'Regenerating must replace, not accumulate');
        Assert.areEqual(QuoteDocumentTableDefinition.getAll().size(),
            [SELECT COUNT() FROM Quote_Document_Table__c],
            'Regenerating must not leave orphaned tables');
    }

    /**
     * Guards the FOR UPDATE lock added to queryQuotes: a single Apex transaction
     * cannot deadlock or block against its own lock, so this cannot exercise two
     * genuinely concurrent transactions racing for the same Quote - that would
     * need two real transactions, which a unit test cannot create. What this
     * does prove: FOR UPDATE combined with WITH USER_MODE and a child subquery
     * is valid SOQL that still returns the Quote and generates correctly, and
     * that calling generate() twice - which now acquires and releases the lock
     * twice - still completes cleanly (the second call reuses the first's
     * output via the fingerprint check rather than regenerating, since
     * nothing changed - see QuoteDocumentFingerprintTest for that behavior in
     * isolation). A true concurrent-access
     * test belongs in an integration/manual test against a real org (see
     * specs/quote-docusign-totals/phases/phase-2-concurrency-lock.md).
     */
    @IsTest
    static void generateSucceedsWithTheQuoteRowLocked() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Quote_Document_Table__c grandTotalTable = [
            SELECT Status__c FROM Quote_Document_Table__c
            WHERE Quote__c = :quoteId() LIMIT 1
        ];
        Assert.areEqual('Complete', grandTotalTable.Status__c,
            'Generation must still complete normally with FOR UPDATE in the query');
    }

    @IsTest
    static void invocableEntryPointGenerates() {
        QuoteDocumentGenerator.Request request = new QuoteDocumentGenerator.Request();
        request.quoteId = quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generateFromFlow(new List<QuoteDocumentGenerator.Request>{ request });
        Test.stopTest();

        Assert.areEqual(QuoteDocumentTableDefinition.getAll().size(),
            [SELECT COUNT() FROM Quote_Document_Table__c],
            'The Flow entry point should generate the same tables');
    }

    // Edge cases identified in review moved to QuoteDocumentEdgeCaseTest.
}
