/**
 * The expansion seam end to end: a quote line becoming several document rows
 * along a period axis, with its money divided and its licences repeated.
 *
 * The scenario is a 36-month quote so that an annual axis has three buckets to
 * order (proving 10-before-2 alphabetical sorting is actually fixed) and a
 * monthly axis has 36. One product runs the whole term, one runs part of it,
 * and one is a one-time charge - the three occupancy cases that matter.
 */
@IsTest
private class QuoteDocumentExpansionTest {

    private static final String TABLE_CODE = 'ANNUAL_SCHEDULE_TEST';
    private static final Date TERM_START = Date.newInstance(2026, 1, 1);

    private static final String PLATFORM = 'Platform Subscription';
    private static final String ADDON = 'Add-On Module';
    private static final String SETUP = 'Implementation Setup';

    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Expansion Test', Industry = 'Technology');
        insert account;

        Opportunity opportunity = new Opportunity(
            Name = 'Expansion Test',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunity;

        List<Product2> products = new List<Product2>{
            new Product2(Name = PLATFORM, ProductCode = 'EXP_PLATFORM', Family = 'Software', IsActive = true),
            new Product2(Name = ADDON,    ProductCode = 'EXP_ADDON',    Family = 'Software', IsActive = true),
            new Product2(Name = SETUP,    ProductCode = 'EXP_SETUP',    Family = 'Service',  IsActive = true)
        };
        insert products;

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Account__c = account.Id,
            SBQQ__Opportunity2__c = opportunity.Id,
            SBQQ__Primary__c = false,
            SBQQ__Type__c = 'Quote',
            SBQQ__StartDate__c = TERM_START,
            SBQQ__SubscriptionTerm__c = 36
        );
        insert quote;

        Map<String, Id> byName = new Map<String, Id>();
        for (Product2 p : products) {
            byName.put(p.Name, p.Id);
        }

        List<SBQQ__QuoteLine__c> lines = new List<SBQQ__QuoteLine__c>();

        // Whole term, 100 licences. No dates, which CPQ reads as the full term.
        lines.add(line(quote.Id, byName.get(PLATFORM), 1, 36000, 100, 'Recurring', null, null));

        // Months 1-12 only: year 1 of three.
        lines.add(line(quote.Id, byName.get(ADDON), 2, 1200, 50, 'Recurring',
                       TERM_START, Date.newInstance(2026, 12, 31)));

        // A one-time charge with no dates of its own.
        lines.add(line(quote.Id, byName.get(SETUP), 3, 5000, 1, null, null, null));

        insert lines;
    }

    private static SBQQ__QuoteLine__c line(
        Id quoteId, Id productId, Integer lineNumber, Decimal total, Decimal quantity,
        String chargeType, Date startDate, Date endDate
    ) {
        Decimal unit = total / quantity;
        return new SBQQ__QuoteLine__c(
            SBQQ__Quote__c = quoteId,
            SBQQ__Product__c = productId,
            SBQQ__Number__c = lineNumber,
            SBQQ__Quantity__c = quantity,
            SBQQ__ListPrice__c = unit,
            SBQQ__RegularPrice__c = unit,
            SBQQ__NetPrice__c = unit,
            SBQQ__CustomerPrice__c = unit,
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
     * A period table, built in memory. Grouped by EXPANSION, sorted by the
     * bucket's own order - which is the configuration a real definition uses.
     */
    private static QuoteDocumentTableDefinition periodTable(Integer periodMonths) {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            TABLE_CODE,
            new List<String>{ QuoteDocumentTableDefinition.DIM_EXPANSION },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        definition.expanderCode = QuoteDocumentPeriodExpander.CODE;
        definition.expanderVersion = '1';
        definition.periodMonths = periodMonths;
        definition.allocationBasis = QuoteDocumentTableDefinition.ALLOCATION_EVEN;
        definition.allocationScale = 2;
        definition.sortGroupsBy = QuoteDocumentTableDefinition.SORT_EXPANSION_ORDER;
        definition.maxGroups = 60;
        return definition;
    }

    private static void use(QuoteDocumentTableDefinition definition) {
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ definition }
        );
    }

    private static List<Quote_Document_Row__c> rows() {
        return [
            SELECT Row_Type__c, Row_Key__c, Display_Label__c, Display_Order__c, Group_Key__c,
                   Group_Value__c, Group_Level__c, Product_Name__c, Amount_Net__c, Quantity__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Table_Code__c = :TABLE_CODE
            ORDER BY Display_Order__c
        ];
    }

    /**
     * Group keys are derived from the bucket LABEL by the row builder, exactly
     * as they are for every other dimension - so a year bucket keys as
     * EXPANSION:YEAR_1, not by the expander internal bucket key.
     */
    private static Map<String, Decimal> netByRowKey() {
        Map<String, Decimal> byKey = new Map<String, Decimal>();
        for (Quote_Document_Row__c row : rows()) {
            byKey.put(row.Row_Key__c, row.Amount_Net__c);
        }
        return byKey;
    }

    // -----------------------------------------------------------------------
    // The axis, without an org
    // -----------------------------------------------------------------------

    @IsTest
    static void anAnnualAxisOverThirtySixMonthsIsThreeBuckets() {
        QuoteDocumentPeriodExpander.Axis axis =
            new QuoteDocumentPeriodExpander.Axis(TERM_START, 36, 12);

        Assert.areEqual(3, axis.periods, 'Three years.');
        Assert.areEqual(Date.newInstance(2028, 12, 31), axis.endDate(), 'Ending the day before the anniversary.');
        Assert.areEqual(1, axis.indexOf(TERM_START), 'The first day is year 1.');
        Assert.areEqual(1, axis.indexOf(Date.newInstance(2026, 12, 31)), 'Still year 1.');
        Assert.areEqual(2, axis.indexOf(Date.newInstance(2027, 1, 1)), 'The anniversary starts year 2.');
        Assert.areEqual(3, axis.indexOf(Date.newInstance(2028, 12, 31)), 'The last day is year 3.');
        Assert.isNull(axis.indexOf(Date.newInstance(2029, 1, 1)), 'Past the term belongs to no period.');
    }

    /**
     * A remainder gets a SHORTER last bucket, not an empty extra one. A
     * customer signing 30 months reads three periods, not four with the last
     * one blank.
     */
    @IsTest
    static void aTermThatDoesNotDivideEvenlyGetsAShorterFinalPeriod() {
        QuoteDocumentPeriodExpander.Axis axis =
            new QuoteDocumentPeriodExpander.Axis(TERM_START, 30, 12);

        Assert.areEqual(3, axis.periods, 'Thirty months is three annual periods, the last of them six.');
        Assert.areEqual(Date.newInstance(2028, 6, 30), axis.endDate(), 'And the term ends when it ends.');
        Assert.areEqual(3, axis.indexOf(Date.newInstance(2028, 6, 30)), 'The short period is still a period.');
    }

    // -----------------------------------------------------------------------
    // Expansion end to end
    // -----------------------------------------------------------------------

    @IsTest
    static void anAnnualScheduleSectionsTheQuoteByYearAndFootsToIt() {
        use(periodTable(12));

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Quote_Document_Table__c table = [
            SELECT Status__c, Amount_Net__c FROM Quote_Document_Table__c WHERE Table_Code__c = :TABLE_CODE
        ];
        Assert.areEqual('Complete', table.Status__c, 'The allocation must reconcile.');

        Map<String, Decimal> net = netByRowKey();

        // Year 1: the whole platform year (12,000), the add-on's twelve months
        // (1,200), and the one-time setup (5,000) which lands in period 1.
        // Years 2 and 3: the platform alone.
        Assert.areEqual(18200.00, net.get('SUBTOTAL:EXPANSION:YEAR_1'), 'Year 1.');
        Assert.areEqual(12000.00, net.get('SUBTOTAL:EXPANSION:YEAR_2'), 'Year 2.');
        Assert.areEqual(12000.00, net.get('SUBTOTAL:EXPANSION:YEAR_3'), 'Year 3.');

        SBQQ__Quote__c quote = [SELECT SBQQ__NetAmount__c FROM SBQQ__Quote__c LIMIT 1];
        Assert.areEqual(quote.SBQQ__NetAmount__c, net.get('GRAND_TOTAL'),
                        'The years must foot to the quote CPQ itself calculated.');
    }

    @IsTest
    static void aLineOnlyAppearsInTheYearsItRunsIn() {
        use(periodTable(12));

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Set<String> addOnGroups = new Set<String>();
        Set<String> platformGroups = new Set<String>();
        for (Quote_Document_Row__c row : rows()) {
            if (row.Row_Type__c != 'Detail') { continue; }
            if (ADDON.equals(row.Product_Name__c))    { addOnGroups.add(row.Group_Key__c); }
            if (PLATFORM.equals(row.Product_Name__c)) { platformGroups.add(row.Group_Key__c); }
        }

        Assert.areEqual(1, addOnGroups.size(), 'The add-on runs in year 1 only.');
        Assert.areEqual(3, platformGroups.size(), 'The platform runs in all three.');
    }

    /**
     * The defect an expansion introduces if nobody thinks about it: the same
     * line in three buckets producing three rows with the same key.
     */
    @IsTest
    static void everyRowKeyStaysUniqueAcrossBuckets() {
        use(periodTable(12));

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Set<String> keys = new Set<String>();
        for (Quote_Document_Row__c row : rows()) {
            Assert.isTrue(keys.add(row.Row_Key__c), 'Duplicate row key: ' + row.Row_Key__c);
        }
    }

    /**
     * A one-time charge is incurred once. Spreading a setup fee across the term
     * prints a recurring charge that does not exist.
     */
    @IsTest
    static void aOneTimeChargeLandsInOnePeriodOnly() {
        use(periodTable(12));

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        List<Quote_Document_Row__c> setupRows = new List<Quote_Document_Row__c>();
        for (Quote_Document_Row__c row : rows()) {
            if ('Detail'.equals(row.Row_Type__c) && SETUP.equals(row.Product_Name__c)) {
                setupRows.add(row);
            }
        }

        Assert.areEqual(1, setupRows.size(), 'Once, not once per year.');
        Assert.areEqual('EXPANSION:YEAR_1', setupRows[0].Group_Key__c, 'In the first period.');
        Assert.areEqual(5000.00, setupRows[0].Amount_Net__c, 'At its whole value.');
    }

    @IsTest
    static void spreadingAOneTimeChargeIsAvailableButMustBeChosen() {
        QuoteDocumentTableDefinition definition = periodTable(12);
        definition.periodOneTimePlacement = QuoteDocumentPeriodExpander.PLACE_SPREAD;
        use(definition);

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Integer setupRows = 0;
        for (Quote_Document_Row__c row : rows()) {
            if ('Detail'.equals(row.Row_Type__c) && SETUP.equals(row.Product_Name__c)) {
                setupRows++;
            }
        }
        Assert.areEqual(3, setupRows, 'SPREAD puts it in every period - deliberately, not by default.');

        SBQQ__Quote__c quote = [SELECT SBQQ__NetAmount__c FROM SBQQ__Quote__c LIMIT 1];
        Assert.areEqual(quote.SBQQ__NetAmount__c, netByRowKey().get('GRAND_TOTAL'),
                        'The same money, a different shape.');
    }

    /** Licences repeat across periods; money divides. Both in one table. */
    @IsTest
    static void licencesRepeatWhileMoneyDivides() {
        use(periodTable(12));

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        for (Quote_Document_Row__c row : rows()) {
            if ('Detail'.equals(row.Row_Type__c) && PLATFORM.equals(row.Product_Name__c)) {
                Assert.areEqual(100, row.Quantity__c,
                                'The same 100 licences in every year, in ' + row.Row_Key__c);
                Assert.areEqual(12000.00, row.Amount_Net__c, 'A third of the money, in ' + row.Row_Key__c);
            }
        }

        Map<String, Decimal> quantityByKey = new Map<String, Decimal>();
        for (Quote_Document_Row__c row : rows()) {
            quantityByKey.put(row.Row_Key__c, row.Quantity__c);
        }
        // Year 1 runs platform (100), add-on (50) and setup (1).
        Assert.areEqual(151, quantityByKey.get('SUBTOTAL:EXPANSION:YEAR_1'),
                        'A period is a sum of what is active in it.');
        Assert.areEqual(151, quantityByKey.get('GRAND_TOTAL'),
                        'And the term is the peak period, not the sum of all three.');
    }

    /**
     * Sorted alphabetically, "Month 10" prints before "Month 2". This is the
     * whole reason SORT_EXPANSION_ORDER exists, so it is asserted on a monthly
     * axis where the two orderings genuinely disagree.
     */
    @IsTest
    static void bucketOrderBeatsAlphabetical() {
        use(periodTable(1));

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        List<String> headerKeys = new List<String>();
        for (Quote_Document_Row__c row : rows()) {
            if ('Group Header'.equals(row.Row_Type__c)) {
                headerKeys.add(row.Group_Key__c);
            }
        }

        Assert.areEqual(36, headerKeys.size(), 'Thirty-six months.');
        Assert.areEqual('EXPANSION:MONTH_2', headerKeys[1], 'Month 2 is second, not month 10.');
        Assert.areEqual('EXPANSION:MONTH_10', headerKeys[9], 'And month 10 is tenth.');
    }

    // -----------------------------------------------------------------------
    // Configuration failures, at config load
    // -----------------------------------------------------------------------

    @IsTest
    static void anExpansionWithoutAllocationIsRefused() {
        QuoteDocumentTableDefinition definition = periodTable(12);
        definition.allocationBasis = null;

        try {
            definition.validateExpansionConfig();
            Assert.fail('Every bucket would carry the line\'s full amount.');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('Allocation_Basis__c'), e.getMessage());
        }
    }

    @IsTest
    static void anExpansionThatSuppressesAmountsNeedsNoAllocation() {
        QuoteDocumentTableDefinition definition = periodTable(12);
        definition.allocationBasis = null;
        definition.suppressAmounts = true;

        definition.validateExpansionConfig();
        Assert.isTrue(true, 'A coverage calendar carries no money and needs no basis.');
    }

    @IsTest
    static void anExpanderWithoutAVersionIsRefused() {
        QuoteDocumentTableDefinition definition = periodTable(12);
        definition.expanderVersion = null;

        try {
            definition.validateExpansionConfig();
            Assert.fail('Changed expander Apex would be invisible to the fingerprint.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains('Expander_Version__c'), e.getMessage());
        }
    }

    @IsTest
    static void aPeriodTableWithoutALengthIsRefused() {
        QuoteDocumentTableDefinition definition = periodTable(12);
        definition.periodMonths = null;

        try {
            definition.validateExpansionConfig();
            Assert.fail('A schedule at the wrong granularity is wrong throughout.');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('Period_Months__c'), e.getMessage());
        }
    }

    @IsTest
    static void allocationWithoutAnExpanderIsRefused() {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            TABLE_CODE, new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 }, QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        definition.allocationBasis = QuoteDocumentTableDefinition.ALLOCATION_EVEN;

        try {
            definition.validateExpansionConfig();
            Assert.fail('There is nothing to allocate across.');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('Expander_Code__c'), e.getMessage());
        }
    }

    @IsTest
    static void anUnknownExpanderCodeFailsByName() {
        try {
            QuoteDocumentExpanderRegistry.resolve('NOT_REGISTERED');
            Assert.fail('An unregistered code must not resolve.');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('NOT_REGISTERED'), e.getMessage());
        }
    }

    /**
     * The no-expander path must be exactly what it was. A definition with no
     * expander is every table that existed before this seam.
     */
    @IsTest
    static void aTableWithNoExpanderIsUnchanged() {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            TABLE_CODE, new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 }, QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        use(definition);

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        SBQQ__Quote__c quote = [SELECT SBQQ__NetAmount__c FROM SBQQ__Quote__c LIMIT 1];
        Assert.areEqual(quote.SBQQ__NetAmount__c, netByRowKey().get('GRAND_TOTAL'),
                        'One row per line, one total, exactly as before.');

        Integer detailRows = 0;
        for (Quote_Document_Row__c row : rows()) {
            if ('Detail'.equals(row.Row_Type__c)) { detailRows++; }
        }
        Assert.areEqual(3, detailRows, 'Three lines, three detail rows - nothing was multiplied.');
    }

    /**
     * A quote with no term and no dated lines has no axis. Failing is the
     * point: an axis guessed from nothing puts every product in a period
     * nobody chose.
     */
    @IsTest
    static void aQuoteWithNoResolvableTermFails() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        quote.SBQQ__StartDate__c = null;
        quote.SBQQ__SubscriptionTerm__c = null;
        update quote;
        update new List<SBQQ__QuoteLine__c>([
            SELECT Id, SBQQ__StartDate__c, SBQQ__EndDate__c FROM SBQQ__QuoteLine__c
        ]);

        for (SBQQ__QuoteLine__c line : [SELECT Id FROM SBQQ__QuoteLine__c]) {
            line.SBQQ__StartDate__c = null;
            line.SBQQ__EndDate__c = null;
            update line;
        }

        use(periodTable(12));

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quote.Id });
            Assert.fail('A period table with a guessed term is worse than none.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(QuoteDocumentPeriodExpander.ERR_AXIS),
                          'Coded failure: ' + e.getMessage());
        }
        Test.stopTest();
    }

    /**
     * Expansion changes how many rows exist and how the money is divided, with
     * no quote field moving. Without it in the fingerprint, adding an expander
     * would leave every quote reusing a snapshot built the old way.
     */
    @IsTest
    static void expansionConfigMovesTheFingerprint() {
        SBQQ__Quote__c quote = QuoteDocumentQuery.quotesWithLines(new Set<Id>{ quoteId() })[0];
        List<QuoteDocumentLine> lines = new List<QuoteDocumentLine>();
        for (SBQQ__QuoteLine__c raw : quote.SBQQ__LineItems__r) {
            lines.add(new QuoteDocumentLine(raw, quote));
        }

        QuoteDocumentTableDefinition plain = QuoteDocumentTableDefinition.build(
            TABLE_CODE, new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 }, QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        String before = QuoteDocumentFingerprint.compute(
            quote, lines, new List<QuoteDocumentTableDefinition>{ plain }
        );

        QuoteDocumentTableDefinition expanded = periodTable(12);
        String after = QuoteDocumentFingerprint.compute(
            quote, lines, new List<QuoteDocumentTableDefinition>{ expanded }
        );
        Assert.areNotEqual(before, after, 'An expansion is a different document.');

        QuoteDocumentTableDefinition bumped = periodTable(12);
        bumped.expanderVersion = '2';
        Assert.areNotEqual(
            after,
            QuoteDocumentFingerprint.compute(quote, lines, new List<QuoteDocumentTableDefinition>{ bumped }),
            'Changed expander behaviour under an unchanged code must move it too.'
        );

        QuoteDocumentTableDefinition monthly = periodTable(1);
        Assert.areNotEqual(
            after,
            QuoteDocumentFingerprint.compute(quote, lines, new List<QuoteDocumentTableDefinition>{ monthly }),
            'Monthly and annual are different documents.'
        );
    }
}
