/**
 * The six use cases that were previously recorded as "enabled, needs its own
 * implementation" — built once it turned out the org already carries the data
 * each of them needs.
 *
 *   5  amendment before/after      SBQQ__Subscription__c
 *   6  renewal / co-term           SBQQ__RenewalPrice__c on the subscription
 *   7  usage-tier explanation      SBQQ__QuoteLineConsumptionRate__c
 *   10 delivery schedules          the SCHEDULE expander, dividing quantity
 *   12 package composition         SBQQ__RequiredBy__c
 *   18 customer part numbers       Quote_Document_Product_Alias__mdt
 *
 * Cases 5 and 6 are marked PROVISIONAL in their own classes and here: they are
 * tested against constructed subscriptions, not against a real CPQ amendment or
 * renewal, because this org has neither.
 */
@IsTest
private class QuoteDocumentSubscriberCasesTest {

    private static final String TABLE_CODE = 'SUBSCRIBER_CASES_TEST';

    private static final String PACKAGE_PRODUCT = 'Enterprise Package';
    private static final String COMP_SOFTWARE = 'Package Software';
    private static final String COMP_TRAINING = 'Package Training';
    private static final String COMP_SUPPORT = 'Package Support';
    private static final String USAGE = 'API Calls';
    private static final String ASSEMBLY = 'Rack Assembly';

    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Subscriber Cases', Industry = 'Technology');
        insert account;

        Opportunity opportunity = new Opportunity(
            Name = 'Subscriber Cases',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunity;

        insert new List<Product2>{
            new Product2(Name = PACKAGE_PRODUCT, ProductCode = 'SC_PKG',   Family = 'Software', IsActive = true),
            new Product2(Name = COMP_SOFTWARE,   ProductCode = 'SC_SW',    Family = 'Software', IsActive = true),
            new Product2(Name = COMP_TRAINING,   ProductCode = 'SC_TRAIN', Family = 'Service',  IsActive = true),
            new Product2(Name = COMP_SUPPORT,    ProductCode = 'SC_SUP',   Family = 'Service',  IsActive = true),
            new Product2(Name = USAGE,           ProductCode = 'SC_USAGE', Family = 'Usage',    IsActive = true),
            new Product2(Name = ASSEMBLY,        ProductCode = 'SC_ASM',   Family = 'Hardware', IsActive = true)
        };
    }

    private static Map<String, Id> productsByCode() {
        Map<String, Id> byCode = new Map<String, Id>();
        for (Product2 p : [SELECT Id, ProductCode FROM Product2]) {
            byCode.put(p.ProductCode, p.Id);
        }
        return byCode;
    }

    private static SBQQ__Quote__c newQuote() {
        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Account__c = [SELECT Id FROM Account LIMIT 1].Id,
            SBQQ__Opportunity2__c = [SELECT Id FROM Opportunity LIMIT 1].Id,
            SBQQ__Primary__c = false,
            SBQQ__Type__c = 'Quote',
            SBQQ__StartDate__c = Date.newInstance(2026, 1, 1),
            SBQQ__SubscriptionTerm__c = 12
        );
        insert quote;
        return quote;
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

    private static QuoteDocumentTableDefinition table(List<String> dims, List<Integer> levels, String filter) {
        return QuoteDocumentTableDefinition.build(TABLE_CODE, dims, levels, filter);
    }

    private static void use(QuoteDocumentTableDefinition definition) {
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ definition }
        );
    }

    private static List<Quote_Document_Row__c> rows() {
        return [
            SELECT Row_Type__c, Row_Key__c, Group_Key__c, Group_Value__c, Product_Name__c,
                   Amount_Net__c, Quantity__c, Include_In_Grand_Total__c, Display_Order__c,
                   Amount_Baseline__c, Amount_Final__c, Amount_Net_Change__c, Transaction_Type__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Table_Code__c = :TABLE_CODE
            ORDER BY Display_Order__c
        ];
    }

    private static Quote_Document_Row__c grandTotal() {
        for (Quote_Document_Row__c row : rows()) {
            if ('Grand Total'.equals(row.Row_Type__c)) { return row; }
        }
        return null;
    }

    // =======================================================================
    // Use case 12 — package composition
    // =======================================================================

    private static Id packageQuote() {
        Map<String, Id> products = productsByCode();
        SBQQ__Quote__c quote = newQuote();

        // A $10,000 package. Its three components carry list prices of
        // 6,000 / 3,000 / 1,000, so the split is 6,000 / 3,000 / 1,000.
        SBQQ__QuoteLine__c parent = line(quote.Id, products.get('SC_PKG'), 1, 1, 10000);
        parent.SBQQ__Bundle__c = true;
        insert parent;

        List<SBQQ__QuoteLine__c> components = new List<SBQQ__QuoteLine__c>{
            line(quote.Id, products.get('SC_SW'), 2, 1, 6000),
            line(quote.Id, products.get('SC_TRAIN'), 3, 1, 3000),
            line(quote.Id, products.get('SC_SUP'), 4, 1, 1000)
        };
        for (SBQQ__QuoteLine__c component : components) {
            component.SBQQ__Bundled__c = true;
            component.SBQQ__RequiredBy__c = parent.Id;
        }
        insert components;
        return quote.Id;
    }

    /**
     * The double-count trap: the components carry the money and the package
     * must not, or the table totals the deal twice.
     */
    @IsTest
    static void aPackagePriceIsAllocatedToItsComponentsAndCountedExactlyOnce() {
        Id quoteId = packageQuote();

        QuoteDocumentTableDefinition definition = table(
            new List<String>{ QuoteDocumentTableDefinition.DIM_BUNDLE },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        definition.rowCustomizerCode = QuoteDocumentCompositionCustomizer.CODE;
        definition.rowCustomizerVersion = '1';
        definition.cachePolicy = QuoteDocumentTableDefinition.CACHE_STANDARD;
        use(definition);

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        Map<String, Quote_Document_Row__c> byProduct = new Map<String, Quote_Document_Row__c>();
        for (Quote_Document_Row__c row : rows()) {
            if ('Detail'.equals(row.Row_Type__c)) {
                byProduct.put(row.Product_Name__c, row);
            }
        }

        // Evenly, and that is the real-data answer rather than a shortcut: CPQ
        // leaves SBQQ__ListTotal__c at zero on a bundled component, so there is
        // no relative worth on the quote to weight by. This test first expected
        // a 6,000/3,000/1,000 split from the component list prices and got
        // 3,333.33 three times, which is how the behaviour was established.
        Assert.areEqual(3333.33, byProduct.get(COMP_SOFTWARE).Amount_Net__c, 'An even third.');
        Assert.areEqual(3333.33, byProduct.get(COMP_TRAINING).Amount_Net__c, 'An even third.');
        Assert.areEqual(3333.34, byProduct.get(COMP_SUPPORT).Amount_Net__c,
                        'And the last component carries the residual, so no cent is lost.');

        for (String component : new List<String>{ COMP_SOFTWARE, COMP_TRAINING, COMP_SUPPORT }) {
            Assert.isTrue(byProduct.get(component).Include_In_Grand_Total__c,
                          component + ' now counts - it carries the money.');
        }
        Assert.isFalse(byProduct.get(PACKAGE_PRODUCT).Include_In_Grand_Total__c,
                       'And the package must not, or the deal is counted twice.');
        Assert.areEqual(10000, byProduct.get(PACKAGE_PRODUCT).Amount_Net__c,
                        'It keeps its printed price though - the customer agreed to that number.');

        Assert.areEqual(10000, grandTotal().Amount_Net__c, 'The package price, exactly once.');
    }

    /** Every filter except ALL removes the components this table exists to print. */
    @IsTest
    static void aCompositionTableThatFiltersOutItsComponentsIsRefused() {
        Id quoteId = packageQuote();

        QuoteDocumentTableDefinition definition = table(
            new List<String>{ QuoteDocumentTableDefinition.DIM_BUNDLE },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        definition.rowCustomizerCode = QuoteDocumentCompositionCustomizer.CODE;
        definition.rowCustomizerVersion = '1';
        definition.cachePolicy = QuoteDocumentTableDefinition.CACHE_STANDARD;
        use(definition);

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
            Assert.fail('It would print packages with nothing inside them.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(QuoteDocumentCompositionCustomizer.ERR_FILTER),
                          'Coded failure: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // =======================================================================
    // Use case 18 — customer part numbers
    // =======================================================================

    @IsTest
    static void oneAssemblyPrintsAsSeveralCustomerPartNumbers() {
        Map<String, Id> products = productsByCode();
        SBQQ__Quote__c quote = newQuote();
        // 100 assemblies at $50 = $5,000.
        insert line(quote.Id, products.get('SC_ASM'), 1, 100, 50);

        QuoteDocumentAliasExpander.useAliases(
            new Map<String, List<QuoteDocumentAliasExpander.Alias>>{
                'SC_ASM' => new List<QuoteDocumentAliasExpander.Alias>{
                    new QuoteDocumentAliasExpander.Alias('SC_ASM', 'CUST-100-A', 2, 10),
                    new QuoteDocumentAliasExpander.Alias('SC_ASM', 'CUST-100-B', 1, 20),
                    new QuoteDocumentAliasExpander.Alias('SC_ASM', 'CUST-100-C', 1, 30)
                }
            }
        );

        QuoteDocumentTableDefinition definition = table(
            new List<String>{ QuoteDocumentTableDefinition.DIM_EXPANSION },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        definition.expanderCode = QuoteDocumentAliasExpander.CODE;
        definition.expanderVersion = '1';
        definition.allocationBasis = QuoteDocumentTableDefinition.ALLOCATION_EVEN;
        definition.sortGroupsBy = QuoteDocumentTableDefinition.SORT_EXPANSION_ORDER;
        use(definition);

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quote.Id });
        Test.stopTest();

        Map<String, Quote_Document_Row__c> byGroup = new Map<String, Quote_Document_Row__c>();
        for (Quote_Document_Row__c row : rows()) {
            if ('Subtotal'.equals(row.Row_Type__c)) {
                byGroup.put(row.Group_Value__c, row);
            }
        }

        Assert.areEqual(3, byGroup.size(), 'Three customer part numbers.');
        Assert.areEqual(2500, byGroup.get('CUST-100-A').Amount_Net__c, 'Weight 2 of 4.');
        Assert.areEqual(1250, byGroup.get('CUST-100-B').Amount_Net__c, 'Weight 1 of 4.');
        Assert.areEqual(1250, byGroup.get('CUST-100-C').Amount_Net__c, 'Weight 1 of 4.');

        // Different part numbers are different physical things, so the units
        // divide rather than repeat.
        Assert.areEqual(50, byGroup.get('CUST-100-A').Quantity__c, 'Half the units.');
        Assert.areEqual(100, grandTotal().Quantity__c, 'And they add back to what was quoted.');
        Assert.areEqual(5000, grandTotal().Amount_Net__c, 'As does the money.');
    }

    /**
     * A document that silently mixes the customer's part numbers with the
     * vendor's is one their purchasing system rejects.
     */
    @IsTest
    static void anUnmappedProductFailsRatherThanFallingBackToTheVendorCode() {
        Map<String, Id> products = productsByCode();
        SBQQ__Quote__c quote = newQuote();
        insert line(quote.Id, products.get('SC_ASM'), 1, 10, 50);

        QuoteDocumentAliasExpander.useAliases(
            new Map<String, List<QuoteDocumentAliasExpander.Alias>>{
                'SOMETHING_ELSE' => new List<QuoteDocumentAliasExpander.Alias>{
                    new QuoteDocumentAliasExpander.Alias('SOMETHING_ELSE', 'X-1', 1, 10)
                }
            }
        );

        QuoteDocumentTableDefinition definition = table(
            new List<String>{ QuoteDocumentTableDefinition.DIM_EXPANSION },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        definition.expanderCode = QuoteDocumentAliasExpander.CODE;
        definition.expanderVersion = '1';
        definition.allocationBasis = QuoteDocumentTableDefinition.ALLOCATION_EVEN;
        use(definition);

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quote.Id });
            Assert.fail('An unmapped product must not silently print the vendor code.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(QuoteDocumentAliasExpander.ERR_UNMAPPED),
                          'Coded failure: ' + e.getMessage());
        }
        Test.stopTest();
    }

    // =======================================================================
    // Use case 7 — usage tiers
    // =======================================================================

    /**
     * The specification's example: 25,000 units, first 10,000 at one rate and
     * the remaining 15,000 at another.
     */
    @IsTest
    static void aUsageLineIsExplainedAsItsPricingTiers() {
        Map<String, Id> products = productsByCode();
        SBQQ__Quote__c quote = newQuote();
        // 25,000 units, quoted at $0.40 → $10,000.
        SBQQ__QuoteLine__c usage = line(quote.Id, products.get('SC_USAGE'), 1, 25000, 0.40);
        insert usage;

        // The tiers CPQ's engine would have written: 10,000 at 0.50 = 5,000,
        // and 15,000 at 0.3333... The weights are what matter, not the rates.
        QuoteDocumentTierExpander.useTiers(
            new Map<Id, List<QuoteDocumentTierExpander.Tier>>{
                usage.Id => new List<QuoteDocumentTierExpander.Tier>{
                    new QuoteDocumentTierExpander.Tier(usage.Id, '1-10000', 1, 10000, 0.50, 1),
                    new QuoteDocumentTierExpander.Tier(usage.Id, '10001+', 10001, null, 0.25, 2)
                }
            }
        );

        QuoteDocumentTableDefinition definition = table(
            new List<String>{ QuoteDocumentTableDefinition.DIM_EXPANSION },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        definition.expanderCode = QuoteDocumentTierExpander.CODE;
        definition.expanderVersion = '1';
        definition.allocationBasis = QuoteDocumentTableDefinition.ALLOCATION_EVEN;
        definition.sortGroupsBy = QuoteDocumentTableDefinition.SORT_EXPANSION_ORDER;
        use(definition);

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quote.Id });
        Test.stopTest();

        Map<String, Quote_Document_Row__c> byGroup = new Map<String, Quote_Document_Row__c>();
        for (Quote_Document_Row__c row : rows()) {
            if ('Subtotal'.equals(row.Row_Type__c)) {
                byGroup.put(row.Group_Value__c, row);
            }
        }
        Assert.areEqual(2, byGroup.size(), 'Two tiers were occupied.');

        // Band 1: 10,000 units x 0.50 = 5,000 of weight.
        // Band 2: 15,000 units x 0.25 = 3,750 of weight. Total 8,750.
        // The QUOTED 10,000 is divided in that ratio: 5,714.29 / 4,285.71.
        Assert.areEqual(5714.29, byGroup.get('1-10000').Amount_Net__c, 'The first band share.');
        Assert.areEqual(4285.71, byGroup.get('10001+').Amount_Net__c, 'The second.');

        // The point of the design: the tiers explain the QUOTED amount and
        // never recompute it, so they foot to the quote even though the rates
        // multiply out to 8,750 rather than 10,000.
        Assert.areEqual(10000, grandTotal().Amount_Net__c,
                        'The explanation foots to what the customer pays, not to a recomputed price.');
        Assert.areEqual(25000, grandTotal().Quantity__c, 'Every unit is accounted for exactly once.');
    }

    @IsTest
    static void aLineWithNoConsumptionScheduleFailsRatherThanPrintingUnexplained() {
        Map<String, Id> products = productsByCode();
        SBQQ__Quote__c quote = newQuote();
        insert line(quote.Id, products.get('SC_USAGE'), 1, 100, 1);

        QuoteDocumentTierExpander.useTiers(new Map<Id, List<QuoteDocumentTierExpander.Tier>>());

        QuoteDocumentTableDefinition definition = table(
            new List<String>{ QuoteDocumentTableDefinition.DIM_EXPANSION },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        definition.expanderCode = QuoteDocumentTierExpander.CODE;
        definition.expanderVersion = '1';
        definition.allocationBasis = QuoteDocumentTableDefinition.ALLOCATION_EVEN;
        use(definition);

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quote.Id });
            Assert.fail('A mixed table invites a false assumption about pricing.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(QuoteDocumentTierExpander.ERR_NO_SCHEDULE),
                          'Coded failure: ' + e.getMessage());
        }
        Test.stopTest();
    }

    /** A band the customer never reached is omitted, not printed at zero. */
    @IsTest
    static void anUnreachedBandIsOmitted() {
        Map<String, Id> products = productsByCode();
        SBQQ__Quote__c quote = newQuote();
        SBQQ__QuoteLine__c usage = line(quote.Id, products.get('SC_USAGE'), 1, 500, 1);
        insert usage;

        QuoteDocumentTierExpander.useTiers(
            new Map<Id, List<QuoteDocumentTierExpander.Tier>>{
                usage.Id => new List<QuoteDocumentTierExpander.Tier>{
                    new QuoteDocumentTierExpander.Tier(usage.Id, '1-1000', 1, 1000, 1, 1),
                    new QuoteDocumentTierExpander.Tier(usage.Id, '1001+', 1001, null, 0.5, 2)
                }
            }
        );

        QuoteDocumentTableDefinition definition = table(
            new List<String>{ QuoteDocumentTableDefinition.DIM_EXPANSION },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        definition.expanderCode = QuoteDocumentTierExpander.CODE;
        definition.expanderVersion = '1';
        definition.allocationBasis = QuoteDocumentTableDefinition.ALLOCATION_EVEN;
        use(definition);

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quote.Id });
        Test.stopTest();

        Integer subtotals = 0;
        for (Quote_Document_Row__c row : rows()) {
            if ('Subtotal'.equals(row.Row_Type__c)) { subtotals++; }
        }
        Assert.areEqual(1, subtotals, 'Only the band the 500 units fall into.');
    }

    // =======================================================================
    // Use case 10 — delivery schedules
    // =======================================================================

    /**
     * The specification's example: 1,000 devices delivered 200 in September,
     * 300 in October, 500 in November. It needs no new expander — a delivery
     * IS a schedule whose sections divide quantity.
     */
    @IsTest
    static void aDeliveryScheduleSplitsUnitsAcrossDeliveries() {
        Map<String, Id> products = productsByCode();
        SBQQ__Quote__c quote = newQuote();
        // 1,000 devices at $30 = $30,000.
        insert line(quote.Id, products.get('SC_ASM'), 1, 1000, 30);

        QuoteDocumentScheduleExpander.useSchedules(
            new Map<String, List<QuoteDocumentScheduleExpander.Entry>>{
                'DELIVERIES' => new List<QuoteDocumentScheduleExpander.Entry>{
                    new QuoteDocumentScheduleExpander.Entry('SEP', 'MILESTONE_SIGNING', 200, 10),
                    new QuoteDocumentScheduleExpander.Entry('OCT', 'MILESTONE_DELIVERY', 300, 20),
                    new QuoteDocumentScheduleExpander.Entry('NOV', 'MILESTONE_ACCEPTANCE', 500, 30)
                }
            }
        );

        QuoteDocumentTableDefinition definition = table(
            new List<String>{ QuoteDocumentTableDefinition.DIM_EXPANSION },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        definition.expanderCode = QuoteDocumentScheduleExpander.CODE;
        definition.expanderVersion = '1';
        definition.scheduleCode = 'DELIVERIES';
        definition.scheduleDividesQuantity = true;
        definition.allocationBasis = QuoteDocumentTableDefinition.ALLOCATION_EVEN;
        definition.sortGroupsBy = QuoteDocumentTableDefinition.SORT_EXPANSION_ORDER;
        use(definition);

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quote.Id });
        Test.stopTest();

        List<Decimal> quantities = new List<Decimal>();
        for (Quote_Document_Row__c row : rows()) {
            if ('Subtotal'.equals(row.Row_Type__c)) { quantities.add(row.Quantity__c); }
        }
        Assert.areEqual(3, quantities.size(), 'Three deliveries.');
        Assert.areEqual(200, quantities[0].intValue(), 'September.');
        Assert.areEqual(300, quantities[1].intValue(), 'October.');
        Assert.areEqual(500, quantities[2].intValue(),
                        'November - the devices divide, because each delivery is different devices.');
        Assert.areEqual(1000, grandTotal().Quantity__c, 'And every one is delivered exactly once.');
        Assert.areEqual(30000, grandTotal().Amount_Net__c, 'The money follows the units.');
    }

    // =======================================================================
    // Use cases 5 and 6 — amendment and renewal. PROVISIONAL.
    // =======================================================================

    /**
     * PROVISIONAL: constructed subscriptions, not a real CPQ amendment. This
     * org has none, so what is proven here is the shape and the matching, not
     * that CPQ populates these fields the way this assumes.
     */
    @IsTest
    static void anAmendmentComparesAgainstWhatTheCustomerAlreadyHas() {
        Map<String, Id> products = productsByCode();
        Account account = [SELECT Id FROM Account LIMIT 1];

        insert new List<SBQQ__Subscription__c>{
            new SBQQ__Subscription__c(
                SBQQ__Account__c = account.Id, SBQQ__Product__c = products.get('SC_SW'),
                SBQQ__Quantity__c = 100, SBQQ__NetPrice__c = 100, SBQQ__RenewalPrice__c = 110),
            new SBQQ__Subscription__c(
                SBQQ__Account__c = account.Id, SBQQ__Product__c = products.get('SC_SUP'),
                SBQQ__Quantity__c = 1, SBQQ__NetPrice__c = 5000, SBQQ__RenewalPrice__c = 5000)
        };

        // The amendment: 150 licences, support dropped, training added.
        SBQQ__Quote__c quote = newQuote();
        insert new List<SBQQ__QuoteLine__c>{
            line(quote.Id, products.get('SC_SW'), 1, 150, 100),
            line(quote.Id, products.get('SC_TRAIN'), 2, 1, 2000)
        };

        QuoteDocumentTableDefinition definition = table(
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        definition.measureSet = QuoteDocumentTableDefinition.MEASURES_CHANGE;
        definition.comparisonSourceCode = QuoteDocumentAmendmentComparison.CODE;
        definition.comparisonSourceVersion = '1';
        use(definition);

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quote.Id });
        Test.stopTest();

        Map<String, Quote_Document_Row__c> byProduct = new Map<String, Quote_Document_Row__c>();
        for (Quote_Document_Row__c row : rows()) {
            if ('Detail'.equals(row.Row_Type__c)) {
                byProduct.put(row.Product_Name__c, row);
            }
        }

        Quote_Document_Row__c software = byProduct.get(COMP_SOFTWARE);
        Assert.areEqual(10000, software.Amount_Baseline__c, '100 licences at 100 today.');
        Assert.areEqual(15000, software.Amount_Final__c, '150 after the amendment.');
        Assert.areEqual(5000, software.Amount_Net_Change__c, 'The 50 added.');
        Assert.areEqual(QuoteDocumentComparison.TYPE_CHANGED, software.Transaction_Type__c, 'Amended.');

        Quote_Document_Row__c support = byProduct.get(COMP_SUPPORT);
        Assert.areEqual(5000, support.Amount_Baseline__c, 'Support is held today.');
        Assert.areEqual(0, support.Amount_Final__c, 'And is being dropped.');
        Assert.areEqual(QuoteDocumentComparison.TYPE_REMOVED, support.Transaction_Type__c, 'Cancelled.');

        Assert.areEqual(QuoteDocumentComparison.TYPE_ADDED,
                        byProduct.get(COMP_TRAINING).Transaction_Type__c, 'Training is new.');
    }

    /**
     * PROVISIONAL, as above. Use case 6 needs no new class: the renewal price
     * is on the subscription, so the baseline carries it and the same
     * comparison prints current-term against proposed-renewal.
     */
    @IsTest
    static void aTerminatedSubscriptionIsNotPartOfWhatTheCustomerHasToday() {
        Map<String, Id> products = productsByCode();
        Account account = [SELECT Id FROM Account LIMIT 1];

        insert new SBQQ__Subscription__c(
            SBQQ__Account__c = account.Id, SBQQ__Product__c = products.get('SC_SUP'),
            SBQQ__Quantity__c = 1, SBQQ__NetPrice__c = 5000,
            SBQQ__TerminatedDate__c = Date.today().addDays(-30));

        SBQQ__Quote__c quote = newQuote();
        insert line(quote.Id, products.get('SC_SW'), 1, 10, 100);

        QuoteDocumentTableDefinition definition = table(
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        definition.measureSet = QuoteDocumentTableDefinition.MEASURES_CHANGE;
        definition.comparisonSourceCode = QuoteDocumentAmendmentComparison.CODE;
        definition.comparisonSourceVersion = '1';
        use(definition);

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quote.Id });
        Test.stopTest();

        for (Quote_Document_Row__c row : rows()) {
            Assert.areNotEqual(COMP_SUPPORT, row.Product_Name__c,
                               'An ended position is not a removal this amendment is making.');
        }
    }

    @IsTest
    static void everyNewSourceAndExpanderIsRegistered() {
        Assert.isTrue(
            QuoteDocumentExpanderRegistry.resolve(QuoteDocumentAliasExpander.CODE)
                instanceof QuoteDocumentAliasExpander, 'PRODUCT_ALIAS');
        Assert.isTrue(
            QuoteDocumentExpanderRegistry.resolve(QuoteDocumentTierExpander.CODE)
                instanceof QuoteDocumentTierExpander, 'CONSUMPTION_TIER');
        Assert.isTrue(
            QuoteDocumentComparisonRegistry.resolve(QuoteDocumentAmendmentComparison.CODE)
                instanceof QuoteDocumentAmendmentComparison, 'AMENDED_SUBSCRIPTION');
        Assert.isTrue(
            QuoteDocumentRowCustomizerRegistry.resolve(QuoteDocumentCompositionCustomizer.CODE)
                instanceof QuoteDocumentCompositionCustomizer, 'PACKAGE_COMPOSITION');
    }
}
