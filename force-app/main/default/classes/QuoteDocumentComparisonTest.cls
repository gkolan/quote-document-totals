/**
 * Before, after and the difference, against a real second quote.
 *
 * The scenario is use case 5, as written: a customer moves from 100 to 150
 * licences and drops a support package, while a third product is unchanged and
 * a fourth is new. Those four positions are the four outcomes a comparison can
 * produce, and each one is asserted separately - a table that gets three of
 * them right is a table that quietly misreports the fourth.
 */
@IsTest
private class QuoteDocumentComparisonTest {

    private static final String TABLE_CODE = 'REVISION_COMPARISON_TEST';

    private static final String LICENCES = 'User Licences';
    private static final String SUPPORT = 'Premium Support';
    private static final String PLATFORM = 'Platform Fee';
    private static final String TRAINING = 'Training Package';

    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Comparison Test', Industry = 'Technology');
        insert account;

        Opportunity opportunity = new Opportunity(
            Name = 'Comparison Test',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunity;

        List<Product2> products = new List<Product2>{
            new Product2(Name = LICENCES, ProductCode = 'CMP_LIC',   Family = 'Software', IsActive = true),
            new Product2(Name = SUPPORT,  ProductCode = 'CMP_SUP',   Family = 'Service',  IsActive = true),
            new Product2(Name = PLATFORM, ProductCode = 'CMP_PLAT',  Family = 'Software', IsActive = true),
            new Product2(Name = TRAINING, ProductCode = 'CMP_TRAIN', Family = 'Service',  IsActive = true)
        };
        insert products;

        Map<String, Id> byName = new Map<String, Id>();
        for (Product2 p : products) {
            byName.put(p.Name, p.Id);
        }

        // The baseline: what was sent last week.
        SBQQ__Quote__c previous = quote(account.Id, opportunity.Id, null);
        insert previous;
        insert new List<SBQQ__QuoteLine__c>{
            line(previous.Id, byName.get(LICENCES), 1, 100, 100),
            line(previous.Id, byName.get(SUPPORT), 2, 1, 5000),
            line(previous.Id, byName.get(PLATFORM), 3, 1, 2000)
        };

        // The revision: more licences, no support, same platform, new training.
        SBQQ__Quote__c current = quote(account.Id, opportunity.Id, previous.Id);
        insert current;
        insert new List<SBQQ__QuoteLine__c>{
            line(current.Id, byName.get(LICENCES), 1, 150, 100),
            line(current.Id, byName.get(PLATFORM), 2, 1, 2000),
            line(current.Id, byName.get(TRAINING), 3, 1, 750)
        };
    }

    private static SBQQ__Quote__c quote(Id accountId, Id opportunityId, Id sourceId) {
        return new SBQQ__Quote__c(
            SBQQ__Account__c = accountId,
            SBQQ__Opportunity2__c = opportunityId,
            SBQQ__Primary__c = false,
            SBQQ__Type__c = 'Quote',
            SBQQ__StartDate__c = Date.newInstance(2026, 1, 1),
            SBQQ__SubscriptionTerm__c = 12,
            SBQQ__Source__c = sourceId
        );
    }

    private static SBQQ__QuoteLine__c line(
        Id quoteId, Id productId, Integer lineNumber, Decimal quantity, Decimal unitPrice
    ) {
        return new SBQQ__QuoteLine__c(
            SBQQ__Quote__c = quoteId,
            SBQQ__Product__c = productId,
            SBQQ__Number__c = lineNumber,
            SBQQ__Quantity__c = quantity,
            SBQQ__ListPrice__c = unitPrice,
            SBQQ__RegularPrice__c = unitPrice
        );
    }

    private static SBQQ__Quote__c currentQuote() {
        return [SELECT Id FROM SBQQ__Quote__c WHERE SBQQ__Source__c != null LIMIT 1];
    }

    private static SBQQ__Quote__c baselineQuote() {
        return [SELECT Id FROM SBQQ__Quote__c WHERE SBQQ__Source__c = null LIMIT 1];
    }

    /** A comparison table: CHANGE measures, no grouping beyond the product. */
    private static QuoteDocumentTableDefinition comparisonTable() {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            TABLE_CODE,
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        definition.measureSet = QuoteDocumentTableDefinition.MEASURES_CHANGE;
        definition.comparisonSourceCode = QuoteDocumentSourceQuoteComparison.CODE;
        definition.comparisonSourceVersion = '1';
        return definition;
    }

    private static void use(QuoteDocumentTableDefinition definition) {
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ definition }
        );
    }

    private static Map<String, Quote_Document_Row__c> detailsByProduct() {
        Map<String, Quote_Document_Row__c> byProduct = new Map<String, Quote_Document_Row__c>();
        for (Quote_Document_Row__c row : [
            SELECT Product_Name__c, Row_Type__c, Transaction_Type__c, Quantity__c,
                   Amount_Baseline__c, Amount_Final__c, Amount_Net_Change__c,
                   Amount_Net_New__c, Amount_Cancellation__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Table_Code__c = :TABLE_CODE
              AND Row_Type__c = 'Detail'
        ]) {
            byProduct.put(row.Product_Name__c, row);
        }
        return byProduct;
    }

    private static void generate() {
        QuoteDocumentGenerator.generate(new Set<Id>{ currentQuote().Id });
    }

    // -----------------------------------------------------------------------
    // The four outcomes
    // -----------------------------------------------------------------------

    @IsTest
    static void aChangedPositionCarriesBeforeAfterAndTheDifference() {
        use(comparisonTable());

        Test.startTest();
        generate();
        Test.stopTest();

        Quote_Document_Row__c licences = detailsByProduct().get(LICENCES);
        Assert.isNotNull(licences, 'The changed position must appear.');
        Assert.areEqual(QuoteDocumentComparison.TYPE_CHANGED, licences.Transaction_Type__c,
                        'It moved, so it is amended.');
        Assert.areEqual(10000, licences.Amount_Baseline__c, '100 licences at 100.');
        Assert.areEqual(15000, licences.Amount_Final__c, '150 licences at 100.');
        Assert.areEqual(5000, licences.Amount_Net_Change__c, 'And the difference is the 50 added.');
    }

    @IsTest
    static void aRemovedPositionAppearsOnceWithNoCurrentAmount() {
        use(comparisonTable());

        Test.startTest();
        generate();
        Test.stopTest();

        Quote_Document_Row__c support = detailsByProduct().get(SUPPORT);
        Assert.isNotNull(support, 'A dropped product is the whole point of a change document.');
        Assert.areEqual(QuoteDocumentComparison.TYPE_REMOVED, support.Transaction_Type__c, 'Cancelled.');
        Assert.areEqual(5000, support.Amount_Baseline__c, 'It was worth 5,000.');
        Assert.areEqual(0, support.Amount_Final__c, 'And is worth nothing now.');
        Assert.areEqual(-5000, support.Amount_Net_Change__c, 'A removal is negative.');
        Assert.areEqual(-5000, support.Amount_Cancellation__c, 'And lands on the cancellation measure.');
    }

    @IsTest
    static void anAddedPositionHasNoBaseline() {
        use(comparisonTable());

        Test.startTest();
        generate();
        Test.stopTest();

        Quote_Document_Row__c training = detailsByProduct().get(TRAINING);
        Assert.isNotNull(training, 'A newly added product must appear.');
        Assert.areEqual(QuoteDocumentComparison.TYPE_ADDED, training.Transaction_Type__c, 'Net new.');
        Assert.areEqual(0, training.Amount_Baseline__c, 'It was not there before.');
        Assert.areEqual(750, training.Amount_Final__c, 'And is worth 750 now.');
        Assert.areEqual(750, training.Amount_Net_Change__c, 'All of which is the difference.');
    }

    /**
     * Printed by default. A customer scanning a change document for what moved
     * is entitled to see what did not - suppressing it is a filter decision,
     * not a matching one.
     */
    @IsTest
    static void anUnchangedPositionStillGetsARowWithAZeroDifference() {
        use(comparisonTable());

        Test.startTest();
        generate();
        Test.stopTest();

        Quote_Document_Row__c platform = detailsByProduct().get(PLATFORM);
        Assert.isNotNull(platform, 'Unchanged is an answer, not an omission.');
        Assert.areEqual(QuoteDocumentComparison.TYPE_UNCHANGED, platform.Transaction_Type__c, 'Unchanged.');
        Assert.areEqual(2000, platform.Amount_Baseline__c, 'Same before.');
        Assert.areEqual(2000, platform.Amount_Final__c, 'Same after.');
        Assert.areEqual(0, platform.Amount_Net_Change__c, 'No difference.');
    }

    @IsTest
    static void everyPositionAppearsExactlyOnce() {
        use(comparisonTable());

        Test.startTest();
        generate();
        Test.stopTest();

        Map<String, Integer> counts = new Map<String, Integer>();
        for (Quote_Document_Row__c row : [
            SELECT Product_Name__c FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Table_Code__c = :TABLE_CODE AND Row_Type__c = 'Detail'
        ]) {
            Integer seen = counts.containsKey(row.Product_Name__c) ? counts.get(row.Product_Name__c) : 0;
            counts.put(row.Product_Name__c, seen + 1);
        }

        Assert.areEqual(4, counts.size(), 'Three current products plus the one that went.');
        for (String product : counts.keySet()) {
            Assert.areEqual(1, counts.get(product), product + ' must appear once, not twice.');
        }
    }

    /**
     * The difference column has to foot: the sum of every change equals the
     * difference between the two quotes. This is what makes the table
     * trustworthy rather than merely plausible.
     */
    @IsTest
    static void theDifferencesSumToTheChangeBetweenTheTwoQuotes() {
        use(comparisonTable());

        Test.startTest();
        generate();
        Test.stopTest();

        Quote_Document_Row__c total = [
            SELECT Amount_Baseline__c, Amount_Final__c, Amount_Net_Change__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Table_Code__c = :TABLE_CODE AND Row_Type__c = 'Grand Total'
        ];

        // Baseline 10,000 + 5,000 + 2,000. Current 15,000 + 2,000 + 750.
        Assert.areEqual(17000, total.Amount_Baseline__c, 'What was quoted last week.');
        Assert.areEqual(17750, total.Amount_Final__c, 'What is quoted now.');
        Assert.areEqual(750, total.Amount_Net_Change__c, 'And the change between them.');
        Assert.areEqual(
            total.Amount_Final__c - total.Amount_Baseline__c, total.Amount_Net_Change__c,
            'The difference column must be the difference, not merely a plausible number.'
        );
    }

    // -----------------------------------------------------------------------
    // Refusals
    // -----------------------------------------------------------------------

    /**
     * An empty baseline and an unreadable one produce the same document -
     * "everything is new" - and mean opposite things. Only one of them is
     * allowed to print.
     */
    @IsTest
    static void aQuoteWithNoSourceFailsRatherThanReportingEverythingAsNew() {
        use(comparisonTable());

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ baselineQuote().Id });
            Assert.fail('A comparison with nothing to compare against must not print.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(QuoteDocumentComparison.ERR_SOURCE_MISSING),
                          'Coded failure: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void aPriceWaterfallComparisonIsRefused() {
        QuoteDocumentTableDefinition definition = comparisonTable();
        definition.measureSet = QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL;
        use(definition);

        Test.startTest();
        try {
            generate();
            Assert.fail('Every difference would have been silently zero.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(QuoteDocumentComparison.ERR_MEASURES),
                          'Coded failure: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void twoLinesSharingAMatchKeyAreRefused() {
        // A second licences line, identical in product, charge type and dates -
        // so the key cannot tell the two positions apart.
        SBQQ__Quote__c current = currentQuote();
        Product2 licences = [SELECT Id FROM Product2 WHERE ProductCode = 'CMP_LIC' LIMIT 1];
        insert line(current.Id, licences.Id, 9, 25, 100);

        use(comparisonTable());

        Test.startTest();
        try {
            generate();
            Assert.fail('Pairing one arbitrarily would print a confidently wrong difference.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(QuoteDocumentComparison.ERR_AMBIGUOUS),
                          'Coded failure: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void aComparisonWithoutAVersionIsRefused() {
        QuoteDocumentTableDefinition definition = comparisonTable();
        definition.comparisonSourceVersion = null;

        try {
            definition.validateComparisonConfig();
            Assert.fail('Changed matching logic would be invisible to the fingerprint.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains('Comparison_Source_Version__c'), e.getMessage());
        }
    }

    @IsTest
    static void comparingAndExpandingAtOnceIsRefused() {
        QuoteDocumentTableDefinition definition = comparisonTable();
        definition.expanderCode = QuoteDocumentPeriodExpander.CODE;

        try {
            definition.validateComparisonConfig();
            Assert.fail('Nobody has defined what that table would mean.');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('Choose one'), e.getMessage());
        }
    }

    @IsTest
    static void anUnknownComparisonSourceFailsByName() {
        try {
            QuoteDocumentComparisonRegistry.resolve('NOT_REGISTERED');
            Assert.fail('An unregistered code must not resolve.');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('NOT_REGISTERED'), e.getMessage());
        }
    }

    /**
     * The match key is product plus charge type plus window, deliberately: the
     * same product on two different terms is two positions, and pairing them
     * would report a change that is really two separate lines.
     */
    @IsTest
    static void theMatchKeySeparatesTheSameProductOnDifferentTerms() {
        QuoteDocumentSourceQuoteComparison source = new QuoteDocumentSourceQuoteComparison();

        SBQQ__Quote__c quote = QuoteDocumentQuery.quotesWithLinesReadOnly(
            new Set<Id>{ currentQuote().Id }
        )[0];
        QuoteDocumentLine first = new QuoteDocumentLine(quote.SBQQ__LineItems__r[0], quote);

        QuoteDocumentLine second = new QuoteDocumentLine(quote.SBQQ__LineItems__r[0], quote);
        second.subscriptionEndDate = Date.newInstance(2027, 6, 30);

        Assert.areNotEqual(source.matchKey(first), source.matchKey(second),
                           'Different terms are different positions.');
    }

    @IsTest
    static void comparisonConfigMovesTheFingerprint() {
        SBQQ__Quote__c quote = QuoteDocumentQuery.quotesWithLinesReadOnly(
            new Set<Id>{ currentQuote().Id }
        )[0];
        List<QuoteDocumentLine> lines = new List<QuoteDocumentLine>();
        for (SBQQ__QuoteLine__c raw : quote.SBQQ__LineItems__r) {
            lines.add(new QuoteDocumentLine(raw, quote));
        }

        QuoteDocumentTableDefinition plain = QuoteDocumentTableDefinition.build(
            TABLE_CODE, new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 }, QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        plain.measureSet = QuoteDocumentTableDefinition.MEASURES_CHANGE;

        String before = QuoteDocumentFingerprint.compute(
            quote, lines, new List<QuoteDocumentTableDefinition>{ plain }
        );
        String after = QuoteDocumentFingerprint.compute(
            quote, lines, new List<QuoteDocumentTableDefinition>{ comparisonTable() }
        );

        Assert.areNotEqual(before, after, 'A comparison is a different document.');
    }
}
