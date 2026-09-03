/**
 * The shipped MONTHLY_SUBSCRIPTION_SUMMARY configuration, on the business
 * scenario it exists for: a twelve-month platform subscription, four shorter
 * products landing in months 1-3, 5, 6, 7 and 7-10, and an undated setup fee.
 *
 * WHAT THIS TESTS THAT QuoteDocumentExpansionTest DOES NOT
 * --------------------------------------------------------
 * Nothing about the PERIOD expander itself. The axis arithmetic, occupancy,
 * one-time placement, quantity repetition and every config rejection are that
 * suite's subject and are not repeated here.
 *
 * This is a CONFIGURATION test: it pins the combination the metadata record
 * actually ships - one-month buckets, EVEN allocation at two decimal places,
 * EXPANSION_ORDER sorting, EFFECTIVE_DATE one-time placement - against the
 * numbers a customer would read. A config change that still passes every
 * expander test can easily print the wrong document, and this is what notices.
 *
 * This table was a row customizer until it moved onto the expander seam. The
 * migration is why two expectations below are worth reading twice:
 *
 *   A one-time charge lands in ONE month. The customizer had no concept of a
 *   charge type and spread every undated line across the whole term, printing
 *   a setup fee as twelve equal monthly amounts that no line on the quote
 *   states.
 *
 *   Charge type now decides spreading. Only 'Recurring' lines spread; anything
 *   else is placed. A subscription quoted without a charge type will pile into
 *   one month, which is a data problem this table makes visible rather than one
 *   it silently averages away.
 */
@IsTest
private class QuoteDocumentMonthlyScheduleTest {

    private static final String TABLE_CODE = 'MONTHLY_SUBSCRIPTION_SUMMARY';
    private static final Date TERM_START = Date.newInstance(2026, 1, 1);

    private static final String PLATFORM = 'Platform Subscription';
    private static final String PRODUCT_A = 'Product A';
    private static final String ONBOARDING = 'Onboarding Accelerator';
    private static final String MIGRATION = 'Data Migration';
    private static final String SECURITY = 'Security Review';
    private static final String TRAINING = 'Training Day';
    private static final String SETUP = 'Setup Fee';

    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Monthly Schedule Test', Industry = 'Technology');
        insert account;

        Opportunity opportunity = new Opportunity(
            Name = 'Monthly Schedule Test',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunity;

        List<Product2> products = new List<Product2>{
            new Product2(Name = PLATFORM,   ProductCode = 'MSS_PLATFORM',   Family = 'Software', IsActive = true),
            new Product2(Name = PRODUCT_A,  ProductCode = 'MSS_PRODUCT_A',  Family = 'Software', IsActive = true),
            new Product2(Name = ONBOARDING, ProductCode = 'MSS_ONBOARDING', Family = 'Service',  IsActive = true),
            new Product2(Name = MIGRATION,  ProductCode = 'MSS_MIGRATION',  Family = 'Service',  IsActive = true),
            new Product2(Name = SECURITY,   ProductCode = 'MSS_SECURITY',   Family = 'Service',  IsActive = true),
            new Product2(Name = TRAINING,   ProductCode = 'MSS_TRAINING',   Family = 'Service',  IsActive = true),
            new Product2(Name = SETUP,      ProductCode = 'MSS_SETUP',      Family = 'Service',  IsActive = true)
        };
        insert products;

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Account__c = account.Id,
            SBQQ__Opportunity2__c = opportunity.Id,
            SBQQ__Primary__c = false,
            SBQQ__Type__c = 'Quote',
            SBQQ__StartDate__c = TERM_START,
            SBQQ__SubscriptionTerm__c = 12
        );
        insert quote;

        Map<String, Id> byName = new Map<String, Id>();
        for (Product2 p : products) {
            byName.put(p.Name, p.Id);
        }

        List<SBQQ__QuoteLine__c> lines = new List<SBQQ__QuoteLine__c>();

        // The annual product. No dates of its own, which CPQ reads as the
        // whole quote term - and so does the expander.
        lines.add(line(quote.Id, byName.get(PLATFORM), 1, 12000, 'Recurring', null, null));

        // 1000 over three months does not divide into whole cents. Chosen for
        // exactly that reason: the residual has to land somewhere visible.
        lines.add(line(quote.Id, byName.get(PRODUCT_A), 2, 1000, 'Recurring',
                       TERM_START, Date.newInstance(2026, 3, 31)));

        lines.add(line(quote.Id, byName.get(ONBOARDING), 3, 2000, 'Recurring',
                       Date.newInstance(2026, 7, 1), Date.newInstance(2026, 10, 31)));

        // Three one-off services, each dated. Under EFFECTIVE_DATE placement
        // they print in the month they are delivered, not in month 1.
        lines.add(line(quote.Id, byName.get(MIGRATION), 4, 500, null,
                       Date.newInstance(2026, 5, 10), Date.newInstance(2026, 5, 20)));
        lines.add(line(quote.Id, byName.get(SECURITY), 5, 750, null,
                       Date.newInstance(2026, 6, 1), Date.newInstance(2026, 6, 30)));
        lines.add(line(quote.Id, byName.get(TRAINING), 6, 300, null,
                       Date.newInstance(2026, 7, 15), Date.newInstance(2026, 7, 15)));

        // One-off and undated: falls back to the first month.
        lines.add(line(quote.Id, byName.get(SETUP), 7, 600, null, null, null));

        insert lines;
    }

    private static SBQQ__QuoteLine__c line(
        Id quoteId, Id productId, Integer lineNumber, Decimal price,
        String chargeType, Date startDate, Date endDate
    ) {
        return new SBQQ__QuoteLine__c(
            SBQQ__Quote__c = quoteId,
            SBQQ__Product__c = productId,
            SBQQ__Number__c = lineNumber,
            SBQQ__Quantity__c = 1,
            SBQQ__ListPrice__c = price,
            SBQQ__RegularPrice__c = price,
            SBQQ__NetPrice__c = price,
            SBQQ__CustomerPrice__c = price,
            SBQQ__ChargeType__c = chargeType,
            // CPQ rejects a recurring charge without one.
            SBQQ__BillingType__c = 'Recurring'.equals(chargeType) ? 'Advance' : null,
            SBQQ__StartDate__c = startDate,
            SBQQ__EndDate__c = endDate
        );
    }

    private static Id quoteId() {
        return [SELECT Id FROM SBQQ__Quote__c LIMIT 1].Id;
    }

    /**
     * The definition as the metadata record ships it. Kept in one place so a
     * drift between this fixture and
     * Quote_Document_Table_Def.MONTHLY_SUBSCRIPTION_SUMMARY is a single edit
     * to notice, not seven.
     */
    private static QuoteDocumentTableDefinition shippedDefinition() {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            TABLE_CODE,
            new List<String>{ QuoteDocumentTableDefinition.DIM_EXPANSION },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        definition.expanderCode = QuoteDocumentPeriodExpander.CODE;
        definition.expanderVersion = '1';
        definition.periodMonths = 1;
        definition.periodOneTimePlacement = QuoteDocumentPeriodExpander.PLACE_EFFECTIVE;
        definition.allocationBasis = QuoteDocumentTableDefinition.ALLOCATION_EVEN;
        definition.allocationScale = 2;
        definition.sortGroupsBy = QuoteDocumentTableDefinition.SORT_EXPANSION_ORDER;
        definition.maxGroups = 24;
        // Generation refuses to publish without this block. Set here rather
        // than in the one test that asserts it, so every test below runs the
        // configuration the metadata record actually ships - a fixture that
        // omits it would pass while the real table failed to generate.
        definition.assumptionsBlockCode = 'MONTHLY_ALLOCATION';
        return definition;
    }

    private static void useShippedTable() {
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ shippedDefinition() }
        );
    }

    private static List<Quote_Document_Row__c> rows() {
        return [
            SELECT Row_Type__c, Row_Key__c, Display_Label__c, Display_Order__c, Group_Key__c,
                   Group_Value__c, Group_Level__c, Product_Name__c, Amount_Net__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Table_Code__c = :TABLE_CODE
            ORDER BY Display_Order__c
        ];
    }

    private static Map<String, Decimal> netByRowKey() {
        Map<String, Decimal> byKey = new Map<String, Decimal>();
        for (Quote_Document_Row__c row : rows()) {
            byKey.put(row.Row_Key__c, row.Amount_Net__c);
        }
        return byKey;
    }

    private static String subtotalKey(Integer month) {
        return 'SUBTOTAL:EXPANSION:MONTH_' + month;
    }

    // -----------------------------------------------------------------------
    // The scenario
    // -----------------------------------------------------------------------

    @IsTest
    static void everyMonthCarriesOnlyTheProductsRunningInIt() {
        useShippedTable();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Quote_Document_Table__c table = [
            SELECT Status__c, Amount_Net__c FROM Quote_Document_Table__c WHERE Table_Code__c = :TABLE_CODE
        ];
        Assert.areEqual('Complete', table.Status__c, 'The monthly allocation must reconcile.');

        Map<String, Decimal> net = netByRowKey();

        // The platform contributes 1000 to every month. Product A's 1000 over
        // three months is 333.33, 333.33, 333.34 - the residual lands in month
        // 3. The setup fee sits in month 1; the three dated one-offs sit in
        // the month each is delivered.
        Map<Integer, Decimal> expected = new Map<Integer, Decimal>{
            1 => 1933.33, 2 => 1333.33, 3 => 1333.34,
            4 => 1000.00,
            5 => 1500.00,
            6 => 1750.00,
            7 => 1800.00,
            8 => 1500.00, 9 => 1500.00, 10 => 1500.00,
            11 => 1000.00, 12 => 1000.00
        };

        for (Integer month = 1; month <= 12; month++) {
            Assert.areEqual(expected.get(month), net.get(subtotalKey(month)), 'Month ' + month + ' subtotal');
        }

        SBQQ__Quote__c quote = [SELECT SBQQ__NetAmount__c FROM SBQQ__Quote__c LIMIT 1];
        Assert.areEqual(
            quote.SBQQ__NetAmount__c, net.get('GRAND_TOTAL'),
            'The months must foot to the quote CPQ itself calculated.'
        );
        Assert.areEqual(
            quote.SBQQ__NetAmount__c, table.Amount_Net__c,
            'The table measure must match the grand total row.'
        );
    }

    @IsTest
    static void aProductAppearsOnceInEachMonthItRunsAndNowhereElse() {
        useShippedTable();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Map<String, List<Integer>> monthsByProduct = new Map<String, List<Integer>>();
        for (Quote_Document_Row__c row : rows()) {
            if (row.Row_Type__c != 'Detail') {
                continue;
            }
            if (!monthsByProduct.containsKey(row.Product_Name__c)) {
                monthsByProduct.put(row.Product_Name__c, new List<Integer>());
            }
            monthsByProduct.get(row.Product_Name__c)
                .add(Integer.valueOf(row.Group_Key__c.substringAfter('MONTH_')));
        }

        Assert.areEqual(12, monthsByProduct.get(PLATFORM).size(), 'The annual product runs every month.');
        Assert.areEqual(new List<Integer>{ 1, 2, 3 }, monthsByProduct.get(PRODUCT_A), 'Product A runs months 1 to 3.');
        Assert.areEqual(
            new List<Integer>{ 7, 8, 9, 10 }, monthsByProduct.get(ONBOARDING), 'Onboarding runs months 7 to 10.'
        );
        Assert.areEqual(
            new List<Integer>{ 5 }, monthsByProduct.get(MIGRATION),
            'Eleven days inside month 5 is one month of occupancy, not two.'
        );
        Assert.areEqual(new List<Integer>{ 6 }, monthsByProduct.get(SECURITY), 'Security review runs month 6.');
        Assert.areEqual(new List<Integer>{ 7 }, monthsByProduct.get(TRAINING), 'A single day still occupies its month.');
    }

    @IsTest
    static void theResidualLandsInTheLastMonthSoTheLineIsNeverShort() {
        useShippedTable();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Decimal total = 0;
        List<Decimal> shares = new List<Decimal>();
        for (Quote_Document_Row__c row : rows()) {
            if (row.Row_Type__c == 'Detail' && row.Product_Name__c == PRODUCT_A) {
                shares.add(row.Amount_Net__c);
                total += row.Amount_Net__c;
            }
        }

        Assert.areEqual(new List<Decimal>{ 333.33, 333.33, 333.34 }, shares,
                        'The rounding residual belongs to the last month, not to nobody.');
        Assert.areEqual(1000, total, 'A three-way split must still sum to the quoted 1000.');
    }

    /**
     * The defect the migration off the row customizer fixed. The customizer
     * had no concept of a charge type: an undated setup fee was "the whole
     * term", so 600 printed as twelve monthly charges of 50 that appear
     * nowhere on the quote.
     */
    @IsTest
    static void anUndatedOneTimeChargeLandsInOneMonthRatherThanSpreading() {
        useShippedTable();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        List<Integer> months = new List<Integer>();
        Decimal printed = 0;
        for (Quote_Document_Row__c row : rows()) {
            if (row.Row_Type__c == 'Detail' && row.Product_Name__c == SETUP) {
                months.add(Integer.valueOf(row.Group_Key__c.substringAfter('MONTH_')));
                printed += row.Amount_Net__c;
            }
        }

        Assert.areEqual(new List<Integer>{ 1 }, months, 'A setup fee is incurred once, not every month.');
        Assert.areEqual(600, printed, 'And it prints its whole amount there.');
    }

    @IsTest
    static void everyMonthPrintsEvenWhenNothingShortRunsInIt() {
        useShippedTable();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Integer headers = 0;
        List<String> order = new List<String>();
        for (Quote_Document_Row__c row : rows()) {
            if (row.Row_Type__c == 'Group Header') {
                headers++;
                order.add(row.Group_Value__c);
            }
        }

        Assert.areEqual(12, headers, 'A twelve-month term prints twelve months, including the quiet ones.');
        // Alphabetically "Month 10" precedes "Month 2"; EXPANSION_ORDER is
        // what stops the document reading 1, 10, 11, 12, 2, 3.
        Assert.areEqual('Month 1', order[0], 'Months print in term order.');
        Assert.areEqual('Month 2', order[1], 'Not alphabetical order.');
        Assert.areEqual('Month 12', order[11], 'And the last month prints last.');
    }

    /**
     * The note moved from a customizer-emitted Note row to an assumptions
     * block, which is locale-resolved and which generation refuses to publish
     * without - a stronger guarantee than the row ever had.
     */
    @IsTest
    static void theAllocationIsExplainedByABlockTheTableCannotPublishWithout() {
        useShippedTable();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        List<Quote_Document_Block__c> blocks = [
            SELECT Body__c, Heading__c FROM Quote_Document_Block__c
            WHERE Block_Code__c = 'MONTHLY_ALLOCATION'
        ];
        Assert.areEqual(1, blocks.size(), 'The table ships with the block that explains its arithmetic.');
        Assert.isTrue(
            String.isNotBlank(blocks[0].Body__c),
            'An allocated figure with no explanation is a number a reader will act on blind.'
        );
    }
}
