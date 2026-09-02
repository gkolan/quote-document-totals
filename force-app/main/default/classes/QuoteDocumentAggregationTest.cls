/**
 * Measures that do not add up.
 *
 * The headline case is deliberately the one that is easy to get wrong and
 * impossible to spot afterwards: a 60% discount on $1,000 beside a 10%
 * discount on $100,000. Summed, the total reads 70%. Averaged, 35%. Both are
 * numbers a customer would query and neither is the answer, which is about
 * 10.5% - and only recomputing the ratio at each level produces it.
 */
@IsTest
private class QuoteDocumentAggregationTest {

    private static final String TABLE_CODE = 'AGGREGATION_TEST';

    private static final String CHEAP = 'Heavily Discounted Widget';
    private static final String LARGE = 'Barely Discounted Platform';

    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Aggregation Test', Industry = 'Technology');
        insert account;

        Opportunity opportunity = new Opportunity(
            Name = 'Aggregation Test',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunity;

        List<Product2> products = new List<Product2>{
            new Product2(Name = CHEAP, ProductCode = 'AGG_CHEAP', Family = 'Hardware', IsActive = true),
            new Product2(Name = LARGE,  ProductCode = 'AGG_LARGE',  Family = 'Software', IsActive = true)
        };
        insert products;

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Account__c = account.Id,
            SBQQ__Opportunity2__c = opportunity.Id,
            SBQQ__Primary__c = false,
            SBQQ__Type__c = 'Quote',
            SBQQ__StartDate__c = Date.newInstance(2026, 1, 1),
            SBQQ__SubscriptionTerm__c = 12
        );
        insert quote;

        Map<String, Id> byName = new Map<String, Id>();
        for (Product2 p : products) {
            byName.put(p.Name, p.Id);
        }

        // $1,000 list at 60% off, and $100,000 list at 10% off. Blended:
        // 10,600 discount over 101,000 list = 10.4950%.
        List<SBQQ__QuoteLine__c> lines = new List<SBQQ__QuoteLine__c>{
            line(quote.Id, byName.get(CHEAP), 1, 1000, 60, 10),
            line(quote.Id, byName.get(LARGE), 2, 100000, 10, 100)
        };
        insert lines;
    }

    /**
     * The discount is expressed as a PERCENT rather than by writing net prices
     * directly: CPQ recalculates the totals on insert from list price and
     * SBQQ__Discount__c, so a net price written here is simply overwritten and
     * the line arrives at zero discount. Found by probing the org rather than
     * assumed.
     */
    private static SBQQ__QuoteLine__c line(
        Id quoteId, Id productId, Integer lineNumber, Decimal listTotal,
        Decimal discountPercent, Decimal quantity
    ) {
        return new SBQQ__QuoteLine__c(
            SBQQ__Quote__c = quoteId,
            SBQQ__Product__c = productId,
            SBQQ__Number__c = lineNumber,
            SBQQ__Quantity__c = quantity,
            SBQQ__ListPrice__c = listTotal / quantity,
            SBQQ__RegularPrice__c = listTotal / quantity,
            SBQQ__Discount__c = discountPercent
        );
    }

    private static Id quoteId() {
        return [SELECT Id FROM SBQQ__Quote__c LIMIT 1].Id;
    }

    /**
     * A table grouped by product family, so the two products sit in separate
     * groups and the grand total is the only place a blend can happen.
     */
    private static QuoteDocumentTableDefinition table() {
        return QuoteDocumentTableDefinition.build(
            TABLE_CODE,
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
    }

    private static QuoteDocumentColumnDefinition column(
        String code, String field, String type, String rule, String numerator, String denominator
    ) {
        QuoteDocumentColumnDefinition definition = new QuoteDocumentColumnDefinition();
        definition.columnCode = code;
        definition.displayOrder = 10;
        definition.valueField = field;
        definition.dataType = type;
        definition.aggregationRule = rule;
        definition.aggregationNumerator = numerator;
        definition.aggregationDenominator = denominator;
        return definition;
    }

    private static Map<String, QuoteDocumentAggregation.Rule> rules(
        QuoteDocumentTableDefinition definition, QuoteDocumentColumnDefinition col
    ) {
        return QuoteDocumentAggregation.rulesFor(
            definition, new List<QuoteDocumentColumnDefinition>{ col }, null
        );
    }

    private static List<Quote_Document_Row__c> build(QuoteDocumentTableDefinition definition) {
        SBQQ__Quote__c quote = QuoteDocumentQuery.quotesWithLines(new Set<Id>{ quoteId() })[0];
        List<QuoteDocumentLine> lines = new List<QuoteDocumentLine>();
        for (SBQQ__QuoteLine__c raw : quote.SBQQ__LineItems__r) {
            lines.add(new QuoteDocumentLine(raw, quote));
        }
        return new QuoteDocumentRowBuilder(
            definition, QuoteDocumentLabels.forLocale('en_US')
        ).build(lines);
    }

    private static Quote_Document_Row__c rowOfType(List<Quote_Document_Row__c> rows, String type) {
        for (Quote_Document_Row__c row : rows) {
            if (type.equals(row.Row_Type__c)) {
                return row;
            }
        }
        return null;
    }

    // -----------------------------------------------------------------------

    /**
     * The whole point of the step. Summed this reads 0.70, averaged 0.35; the
     * answer is 0.1050 and only a recomputed ratio produces it.
     */
    @IsTest
    static void aRatioBlendsRatherThanSummingOrAveraging() {
        QuoteDocumentTableDefinition definition = table();
        QuoteDocumentColumnDefinition col = column(
            'COL_EFFECTIVE_DISCOUNT', 'Effective_Discount_Percent__c', 'Percent',
            QuoteDocumentAggregation.RATIO, 'Amount_Discount__c', 'Amount_List__c'
        );

        List<Quote_Document_Row__c> rows = build(definition);
        Map<String, QuoteDocumentAggregation.Rule> ruleMap = rules(definition, col);
        QuoteDocumentAggregation.apply(rows, ruleMap, definition);

        Quote_Document_Row__c total = rowOfType(rows, 'Grand Total');
        Assert.areEqual(
            0.1050, total.Effective_Discount_Percent__c,
            '10,600 of discount over 101,000 of list is 10.50%, not 70% and not 35%.'
        );

        for (Quote_Document_Row__c row : rows) {
            if ('Detail'.equals(row.Row_Type__c) && CHEAP.equals(row.Product_Name__c)) {
                Assert.areEqual(0.6000, row.Effective_Discount_Percent__c,
                                'A leaf row still carries its own ratio.');
            }
        }
    }

    @IsTest
    static void aRatioWithAZeroDenominatorIsBlankNotZero() {
        QuoteDocumentTableDefinition definition = table();
        QuoteDocumentColumnDefinition col = column(
            'COL_BLENDED', 'Blended_Unit_Price__c', 'Currency',
            QuoteDocumentAggregation.RATIO, 'Amount_Net__c', 'Amount_Cancellation__c'
        );

        List<Quote_Document_Row__c> rows = build(definition);
        QuoteDocumentAggregation.apply(rows, rules(definition, col), definition);

        Assert.isNull(
            rowOfType(rows, 'Grand Total').Blended_Unit_Price__c,
            'A table with no denominator has no rate - blank says so, 0.00 would state a price.'
        );
    }

    @IsTest
    static void aBlendedUnitPriceDividesRatherThanSummingUnitPrices() {
        QuoteDocumentTableDefinition definition = table();
        QuoteDocumentColumnDefinition col = column(
            'COL_BLENDED', 'Blended_Unit_Price__c', 'Currency',
            QuoteDocumentAggregation.RATIO, 'Amount_Net__c', 'Quantity__c'
        );

        List<Quote_Document_Row__c> rows = build(definition);
        QuoteDocumentAggregation.apply(rows, rules(definition, col), definition);

        // 400 + 90,000 net over 10 + 100 units = 821.8182 a unit.
        Assert.areEqual(
            821.8182, rowOfType(rows, 'Grand Total').Blended_Unit_Price__c,
            'Unit prices do not add: 40 and 900 a unit are not 940 a unit.'
        );
    }

    @IsTest
    static void maxTakesTheLargestContributingRow() {
        QuoteDocumentTableDefinition definition = table();
        QuoteDocumentColumnDefinition col = column(
            'COL_NET', 'Amount_Net__c', 'Currency', QuoteDocumentAggregation.MAX, null, null
        );

        List<Quote_Document_Row__c> rows = build(definition);
        QuoteDocumentAggregation.apply(rows, rules(definition, col), definition);

        Assert.areEqual(90000, rowOfType(rows, 'Grand Total').Amount_Net__c,
                        'The largest single row, not the sum.');
    }

    @IsTest
    static void lastFollowsDisplayOrder() {
        QuoteDocumentTableDefinition definition = table();
        QuoteDocumentColumnDefinition col = column(
            'COL_NET', 'Amount_Net__c', 'Currency', QuoteDocumentAggregation.LAST, null, null
        );

        List<Quote_Document_Row__c> rows = build(definition);
        QuoteDocumentAggregation.apply(rows, rules(definition, col), definition);

        Decimal lastLeaf;
        Decimal lastOrder;
        for (Quote_Document_Row__c row : rows) {
            if (!'Detail'.equals(row.Row_Type__c)) { continue; }
            if (lastOrder == null || row.Display_Order__c > lastOrder) {
                lastOrder = row.Display_Order__c;
                lastLeaf = row.Amount_Net__c;
            }
        }
        Assert.areEqual(lastLeaf, rowOfType(rows, 'Grand Total').Amount_Net__c,
                        'A running balance ends where the rows end.');
    }

    @IsTest
    static void noneLeavesAggregateRowsBlank() {
        QuoteDocumentTableDefinition definition = table();
        QuoteDocumentColumnDefinition col = column(
            'COL_NET', 'Amount_Net__c', 'Currency', QuoteDocumentAggregation.NONE, null, null
        );

        List<Quote_Document_Row__c> rows = build(definition);
        QuoteDocumentAggregation.apply(rows, rules(definition, col), definition);

        Assert.isNull(rowOfType(rows, 'Grand Total').Amount_Net__c, 'Blank on the total.');
        Assert.isNull(rowOfType(rows, 'Subtotal').Amount_Net__c, 'And on the subtotals.');
    }

    // -----------------------------------------------------------------------
    // Every rule is verified, none is merely skipped
    // -----------------------------------------------------------------------

    @IsTest
    static void aCorruptedRatioIsCaught() {
        QuoteDocumentTableDefinition definition = table();
        QuoteDocumentColumnDefinition col = column(
            'COL_EFFECTIVE_DISCOUNT', 'Effective_Discount_Percent__c', 'Percent',
            QuoteDocumentAggregation.RATIO, 'Amount_Discount__c', 'Amount_List__c'
        );

        List<Quote_Document_Row__c> rows = build(definition);
        Map<String, QuoteDocumentAggregation.Rule> ruleMap = rules(definition, col);
        QuoteDocumentAggregation.apply(rows, ruleMap, definition);

        rowOfType(rows, 'Grand Total').Effective_Discount_Percent__c = 0.3500;

        Quote_Document_Table__c table = new Quote_Document_Table__c(Table_Code__c = TABLE_CODE);
        try {
            QuoteDocumentAggregation.verifyRules(rows, ruleMap, table);
            Assert.fail('An unverified measure is where a wrong number ships in silence.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(QuoteDocumentAggregation.ERR_UNVERIFIED), e.getMessage());
            Assert.areEqual('Failed', table.Status__c, 'The table records the verdict.');
        }
    }

    @IsTest
    static void aCorruptedMaxIsCaught() {
        QuoteDocumentTableDefinition definition = table();
        QuoteDocumentColumnDefinition col = column(
            'COL_NET', 'Amount_Net__c', 'Currency', QuoteDocumentAggregation.MAX, null, null
        );

        List<Quote_Document_Row__c> rows = build(definition);
        Map<String, QuoteDocumentAggregation.Rule> ruleMap = rules(definition, col);
        QuoteDocumentAggregation.apply(rows, ruleMap, definition);
        rowOfType(rows, 'Grand Total').Amount_Net__c = 123456;

        try {
            QuoteDocumentAggregation.verifyRules(
                rows, ruleMap, new Quote_Document_Table__c(Table_Code__c = TABLE_CODE)
            );
            Assert.fail('MAX is checked, not excused.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(QuoteDocumentAggregation.ERR_UNVERIFIED), e.getMessage());
        }
    }

    // -----------------------------------------------------------------------
    // Configuration failures, at config load
    // -----------------------------------------------------------------------

    @IsTest
    static void sumThenMaxNeedsAnExpansionToPeakAcross() {
        QuoteDocumentTableDefinition definition = table();
        QuoteDocumentColumnDefinition col = column(
            'COL_QUANTITY', 'Quantity__c', 'Number', QuoteDocumentAggregation.SUM_THEN_MAX, null, null
        );

        try {
            rules(definition, col);
            Assert.fail('A peak across product families is not a peak of anything.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(QuoteDocumentAggregation.ERR_NEEDS_EXPANSION),
                          e.getMessage());
        }
    }

    @IsTest
    static void aRatioDefinedInTermsOfItselfIsRefused() {
        QuoteDocumentTableDefinition definition = table();
        QuoteDocumentColumnDefinition col = column(
            'COL_NET', 'Amount_Net__c', 'Currency',
            QuoteDocumentAggregation.RATIO, 'Amount_Net__c', 'Quantity__c'
        );

        try {
            rules(definition, col);
            Assert.fail('A column cannot be defined in terms of itself.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(QuoteDocumentAggregation.ERR_CYCLIC), e.getMessage());
        }
    }

    @IsTest
    static void aRatioWithoutBothOperandsIsRefused() {
        QuoteDocumentTableDefinition definition = table();
        QuoteDocumentColumnDefinition col = column(
            'COL_EFFECTIVE_DISCOUNT', 'Effective_Discount_Percent__c', 'Percent',
            QuoteDocumentAggregation.RATIO, 'Amount_Discount__c', null
        );

        try {
            rules(definition, col);
            Assert.fail('A ratio of something over nothing is not a value.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(QuoteDocumentAggregation.ERR_UNKNOWN), e.getMessage());
        }
    }

    @IsTest
    static void anUnknownRuleIsRefusedByName() {
        QuoteDocumentTableDefinition definition = table();
        QuoteDocumentColumnDefinition col = column(
            'COL_NET', 'Amount_Net__c', 'Currency', 'AVERAGE', null, null
        );

        try {
            rules(definition, col);
            Assert.fail('An unimplemented rule must not silently behave as SUM.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains('AVERAGE'), e.getMessage());
        }
    }

    /**
     * Everything deployed today is additive, and must stay that way: a blank
     * rule is SUM, and SUM changes nothing at all.
     */
    @IsTest
    static void aBlankRuleChangesNothing() {
        QuoteDocumentTableDefinition definition = table();
        QuoteDocumentColumnDefinition col = column(
            'COL_NET', 'Amount_Net__c', 'Currency', null, null, null
        );

        Map<String, QuoteDocumentAggregation.Rule> ruleMap = rules(definition, col);
        Assert.isTrue(ruleMap.isEmpty(), 'No rule means nothing is overwritten.');

        List<Quote_Document_Row__c> rows = build(definition);
        Decimal before = rowOfType(rows, 'Grand Total').Amount_Net__c;
        QuoteDocumentAggregation.apply(rows, ruleMap, definition);
        Assert.areEqual(before, rowOfType(rows, 'Grand Total').Amount_Net__c, 'Untouched.');
        Assert.areEqual(90400, before, 'And still the sum it always was.');
    }

    /**
     * The expander's own declaration still reaches the rule set without any
     * column configuration - a repeated quantity is SUM_THEN_MAX because the
     * expander says so, not because an author remembered.
     */
    @IsTest
    static void anExpanderDeclarationBecomesARuleWithoutConfiguration() {
        QuoteDocumentTableDefinition definition = table();
        definition.expanderCode = QuoteDocumentPeriodExpander.CODE;

        Map<String, QuoteDocumentAggregation.Rule> ruleMap = QuoteDocumentAggregation.rulesFor(
            definition, new List<QuoteDocumentColumnDefinition>(), new Set<String>{ 'Quantity__c' }
        );

        Assert.areEqual(1, ruleMap.size(), 'One rule, contributed by the expander.');
        Assert.areEqual(QuoteDocumentAggregation.SUM_THEN_MAX, ruleMap.get('Quantity__c').rule,
                        'Peak, not sum.');
    }
}
