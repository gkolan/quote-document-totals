/**
 * The schedule expander, against the worked examples the specification wrote
 * down before any of it existed.
 *
 * Example 1 (installments) and example 3 (promotional pricing) are the two that
 * matter: the first proves a table can be a slice of the whole quote with no
 * expansion source on the line, and the second proves a free period prints as
 * exactly 0.00 rather than absorbing a rounding cent.
 */
@IsTest
private class QuoteDocumentScheduleTest {

    private static final String TABLE_CODE = 'PAYMENT_SCHEDULE_TEST';

    private static final String SERVICE = 'Implementation Service';
    private static final String LICENCE = 'User Licence';

    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Schedule Test', Industry = 'Technology');
        insert account;

        Opportunity opportunity = new Opportunity(
            Name = 'Schedule Test',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunity;

        List<Product2> products = new List<Product2>{
            new Product2(Name = SERVICE, ProductCode = 'SCH_SVC', Family = 'Service',  IsActive = true),
            new Product2(Name = LICENCE, ProductCode = 'SCH_LIC', Family = 'Software', IsActive = true)
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

        // $60,000 total: the specification's worked installment example.
        insert new List<SBQQ__QuoteLine__c>{
            line(quote.Id, byName.get(SERVICE), 1, 1, 50000),
            line(quote.Id, byName.get(LICENCE), 2, 100, 100)
        };
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

    private static Id quoteId() {
        return [SELECT Id FROM SBQQ__Quote__c LIMIT 1].Id;
    }

    /** 30% at signing, 40% at delivery, 30% at acceptance. */
    private static void useMilestoneSchedule() {
        QuoteDocumentScheduleExpander.useSchedules(
            new Map<String, List<QuoteDocumentScheduleExpander.Entry>>{
                'PAYMENT_MILESTONES' => new List<QuoteDocumentScheduleExpander.Entry>{
                    new QuoteDocumentScheduleExpander.Entry(
                        'MILESTONE_SIGNING', 'MILESTONE_SIGNING', 30, 10),
                    new QuoteDocumentScheduleExpander.Entry(
                        'MILESTONE_DELIVERY', 'MILESTONE_DELIVERY', 40, 20),
                    new QuoteDocumentScheduleExpander.Entry(
                        'MILESTONE_ACCEPTANCE', 'MILESTONE_ACCEPTANCE', 30, 30)
                }
            }
        );
    }

    private static QuoteDocumentTableDefinition scheduleTable(String scheduleCode) {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            TABLE_CODE,
            new List<String>{ QuoteDocumentTableDefinition.DIM_EXPANSION },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        definition.expanderCode = QuoteDocumentScheduleExpander.CODE;
        definition.expanderVersion = '1';
        definition.scheduleCode = scheduleCode;
        definition.allocationBasis = QuoteDocumentTableDefinition.ALLOCATION_EVEN;
        definition.allocationScale = 2;
        definition.sortGroupsBy = QuoteDocumentTableDefinition.SORT_EXPANSION_ORDER;
        return definition;
    }

    private static void use(QuoteDocumentTableDefinition definition) {
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ definition }
        );
    }

    private static Map<String, Decimal> netByRowKey() {
        Map<String, Decimal> byKey = new Map<String, Decimal>();
        for (Quote_Document_Row__c row : [
            SELECT Row_Key__c, Amount_Net__c, Quantity__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Table_Code__c = :TABLE_CODE
        ]) {
            byKey.put(row.Row_Key__c, row.Amount_Net__c);
        }
        return byKey;
    }

    // -----------------------------------------------------------------------
    // Worked example 1 - payment installments
    // -----------------------------------------------------------------------

    /**
     * The specification's numbers, to the cent: $60,000 payable 30/40/30 is
     * 18,000 / 24,000 / 18,000.
     */
    @IsTest
    static void anInstallmentScheduleSplitsTheQuoteToTheCent() {
        useMilestoneSchedule();
        use(scheduleTable('PAYMENT_MILESTONES'));

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Quote_Document_Table__c table = [
            SELECT Status__c, Amount_Net__c FROM Quote_Document_Table__c WHERE Table_Code__c = :TABLE_CODE
        ];
        Assert.areEqual('Complete', table.Status__c, 'The milestones must reconcile.');

        Map<String, Decimal> net = netByRowKey();
        Assert.areEqual(18000.00, net.get('SUBTOTAL:EXPANSION:SIGNING'), 'Signing: 30%.');
        Assert.areEqual(24000.00, net.get('SUBTOTAL:EXPANSION:DELIVERY'), 'Delivery: 40%.');
        Assert.areEqual(18000.00, net.get('SUBTOTAL:EXPANSION:ACCEPTANCE'), 'Acceptance: 30%.');

        SBQQ__Quote__c quote = [SELECT SBQQ__NetAmount__c FROM SBQQ__Quote__c LIMIT 1];
        Assert.areEqual(60000.00, quote.SBQQ__NetAmount__c, 'The worked example total.');
        Assert.areEqual(quote.SBQQ__NetAmount__c, net.get('GRAND_TOTAL'),
                        'And the milestones foot to it.');
    }

    /**
     * An installment table needs no expansion source on the line: a milestone
     * is a slice of the whole quote, so every line contributes to every one.
     */
    @IsTest
    static void everyLineContributesToEveryMilestone() {
        useMilestoneSchedule();
        use(scheduleTable('PAYMENT_MILESTONES'));

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Map<String, Integer> byGroup = new Map<String, Integer>();
        for (Quote_Document_Row__c row : [
            SELECT Group_Key__c FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Table_Code__c = :TABLE_CODE AND Row_Type__c = 'Detail'
        ]) {
            Integer seen = byGroup.containsKey(row.Group_Key__c) ? byGroup.get(row.Group_Key__c) : 0;
            byGroup.put(row.Group_Key__c, seen + 1);
        }

        Assert.areEqual(3, byGroup.size(), 'Three milestones.');
        for (String groupKey : byGroup.keySet()) {
            Assert.areEqual(2, byGroup.get(groupKey), groupKey + ' carries both products.');
        }
    }

    /**
     * A payment schedule repeats quantities by default: the same 100 licences
     * are covered by every instalment, so dividing them would print a third of
     * a licence per payment.
     */
    @IsTest
    static void aPaymentScheduleRepeatsQuantitiesRatherThanDividingThem() {
        useMilestoneSchedule();
        use(scheduleTable('PAYMENT_MILESTONES'));

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        for (Quote_Document_Row__c row : [
            SELECT Quantity__c, Product_Name__c FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Table_Code__c = :TABLE_CODE
              AND Row_Type__c = 'Detail' AND Product_Name__c = :LICENCE
        ]) {
            Assert.areEqual(100, row.Quantity__c, 'The same 100 licences at every milestone.');
        }
    }

    @IsTest
    static void aDepartmentScheduleDividesQuantitiesWhenToldTo() {
        QuoteDocumentScheduleExpander.useSchedules(
            new Map<String, List<QuoteDocumentScheduleExpander.Entry>>{
                'DEPARTMENTS' => new List<QuoteDocumentScheduleExpander.Entry>{
                    new QuoteDocumentScheduleExpander.Entry('HQ', 'MILESTONE_SIGNING', 50, 10),
                    new QuoteDocumentScheduleExpander.Entry('WEST', 'MILESTONE_DELIVERY', 30, 20),
                    new QuoteDocumentScheduleExpander.Entry('EAST', 'MILESTONE_ACCEPTANCE', 20, 30)
                }
            }
        );
        QuoteDocumentTableDefinition definition = scheduleTable('DEPARTMENTS');
        definition.scheduleDividesQuantity = true;
        use(definition);

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Map<String, Decimal> quantityByKey = new Map<String, Decimal>();
        for (Quote_Document_Row__c row : [
            SELECT Row_Key__c, Quantity__c, Product_Name__c FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Table_Code__c = :TABLE_CODE
              AND Row_Type__c = 'Detail' AND Product_Name__c = :LICENCE
        ]) {
            quantityByKey.put(row.Row_Key__c, row.Quantity__c);
        }

        Decimal total = 0;
        for (Decimal quantity : quantityByKey.values()) {
            total += quantity;
        }
        Assert.areEqual(100, total, '50 + 30 + 20 seats, which are different seats.');
        Assert.areEqual(3, quantityByKey.size(), 'One row per department.');
    }

    // -----------------------------------------------------------------------
    // Worked example 3 - promotional pricing
    // -----------------------------------------------------------------------

    /**
     * Months 1-2 free, 3-6 at half rate, 7-12 at full rate. The free months
     * must print as exactly 0.00 - a promotional month showing a cent because
     * the rounding had to go somewhere is the defect the last-non-zero rule
     * exists to prevent.
     */
    @IsTest
    static void aFreePeriodPrintsExactlyZeroAndNeverTheResidual() {
        List<QuoteDocumentScheduleExpander.Entry> entries =
            new List<QuoteDocumentScheduleExpander.Entry>();
        for (Integer month = 1; month <= 12; month++) {
            Decimal weight = month <= 2 ? 0 : (month <= 6 ? 1 : 2);
            // One parameterised dictionary entry for all twelve months, which
            // is what Label_Arg_1__c exists for.
            entries.add(new QuoteDocumentScheduleExpander.Entry(
                'M' + String.valueOf(month).leftPad(2, '0'),
                QuoteDocumentPeriodExpander.KEY_MONTH,
                String.valueOf(month),
                weight,
                month * 10
            ));
        }
        QuoteDocumentScheduleExpander.useSchedules(
            new Map<String, List<QuoteDocumentScheduleExpander.Entry>>{ 'PROMOTION' => entries }
        );

        QuoteDocumentTableDefinition definition = scheduleTable('PROMOTION');
        definition.maxGroups = 20;
        use(definition);

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        List<Quote_Document_Row__c> subtotals = [
            SELECT Row_Key__c, Amount_Net__c, Display_Order__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Table_Code__c = :TABLE_CODE AND Row_Type__c = 'Subtotal'
            ORDER BY Display_Order__c
        ];

        Assert.areEqual(12, subtotals.size(), 'Every month prints, including the free ones.');
        Assert.areEqual(0, subtotals[0].Amount_Net__c, 'Month 1 is free - exactly zero, not a cent.');
        Assert.areEqual(0, subtotals[1].Amount_Net__c, 'And so is month 2.');

        // Weight total 16: a half-rate month is 60,000/16 = 3,750.
        Assert.areEqual(3750.00, subtotals[2].Amount_Net__c, 'Month 3 at half rate.');
        Assert.areEqual(7500.00, subtotals[11].Amount_Net__c, 'Month 12 at full rate.');

        SBQQ__Quote__c quote = [SELECT SBQQ__NetAmount__c FROM SBQQ__Quote__c LIMIT 1];
        Assert.areEqual(quote.SBQQ__NetAmount__c, netByRowKey().get('GRAND_TOTAL'),
                        'The promotion changes the shape, never the total.');
    }

    // -----------------------------------------------------------------------
    // Refusals
    // -----------------------------------------------------------------------

    @IsTest
    static void aScheduleTableWithoutAScheduleCodeIsRefused() {
        QuoteDocumentTableDefinition definition = scheduleTable(null);

        try {
            definition.validateExpansionConfig();
            Assert.fail('There is nothing on a quote that says "30% at signing".');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('Schedule_Code__c'), e.getMessage());
        }
    }

    @IsTest
    static void anUnknownScheduleFailsRatherThanProducingAnEmptyTable() {
        QuoteDocumentScheduleExpander.useSchedules(
            new Map<String, List<QuoteDocumentScheduleExpander.Entry>>()
        );
        use(scheduleTable('DOES_NOT_EXIST'));

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
            Assert.fail('An empty schedule would produce a total nobody can check.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(QuoteDocumentScheduleExpander.ERR_EMPTY),
                          'Coded failure: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void anAllZeroScheduleIsRefused() {
        QuoteDocumentScheduleExpander.useSchedules(
            new Map<String, List<QuoteDocumentScheduleExpander.Entry>>{
                'NOWHERE' => new List<QuoteDocumentScheduleExpander.Entry>{
                    new QuoteDocumentScheduleExpander.Entry('A', 'MILESTONE_SIGNING', 0, 10),
                    new QuoteDocumentScheduleExpander.Entry('B', 'MILESTONE_DELIVERY', 0, 20)
                }
            }
        );
        use(scheduleTable('NOWHERE'));

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
            Assert.fail('There is nowhere for the money to land.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(QuoteDocumentScheduleExpander.ERR_WEIGHTS),
                          'Coded failure: ' + e.getMessage());
        }
        Test.stopTest();
    }

    /**
     * Weights are relative, so a schedule summing to 90 still allocates
     * everything. It generates - and warns - because only the author knows
     * whether that was a ratio or a typo.
     */
    @IsTest
    static void weightsThatDoNotSumToOneHundredStillAllocateTheWholeQuote() {
        QuoteDocumentScheduleExpander.useSchedules(
            new Map<String, List<QuoteDocumentScheduleExpander.Entry>>{
                'SLIGHTLY_OFF' => new List<QuoteDocumentScheduleExpander.Entry>{
                    new QuoteDocumentScheduleExpander.Entry('A', 'MILESTONE_SIGNING', 30, 10),
                    new QuoteDocumentScheduleExpander.Entry('B', 'MILESTONE_DELIVERY', 40, 20),
                    new QuoteDocumentScheduleExpander.Entry('C', 'MILESTONE_ACCEPTANCE', 25, 30)
                }
            }
        );
        use(scheduleTable('SLIGHTLY_OFF'));

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        SBQQ__Quote__c quote = [SELECT SBQQ__NetAmount__c FROM SBQQ__Quote__c LIMIT 1];
        Assert.areEqual(quote.SBQQ__NetAmount__c, netByRowKey().get('GRAND_TOTAL'),
                        'Nothing is left behind: the split is 32/42/26 of the whole.');
    }

    @IsTest
    static void theScheduleExpanderIsRegistered() {
        Assert.isTrue(
            QuoteDocumentExpanderRegistry.resolve(QuoteDocumentScheduleExpander.CODE)
                instanceof QuoteDocumentScheduleExpander,
            'SCHEDULE must resolve to the schedule expander.'
        );
    }
}
