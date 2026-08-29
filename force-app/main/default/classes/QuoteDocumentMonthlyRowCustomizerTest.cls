/**
 * The Monthly Subscription Summary, end to end, against the exact scenario it
 * was built for: a twelve-month platform subscription running the whole term,
 * with five shorter products landing in months 1-3, 5, 6, 7 and 7-10.
 *
 * Every expectation here is a business rule, not a snapshot of what the code
 * happened to produce. The two that matter most:
 *
 *   The months foot to the quote. A line's shares always sum back to its own
 *   quoted total, so the grand total equals CPQ's SBQQ__NetAmount__c to the
 *   cent - which QuoteDocumentVerification enforces independently, meaning a
 *   broken allocation fails generation rather than printing a wrong document.
 *
 *   A month a product does not run in does not carry its cost. That is the
 *   whole point of the table and the one thing a grouping could never do.
 */
@IsTest
private class QuoteDocumentMonthlyRowCustomizerTest {

    private static final String TABLE_CODE = 'MONTHLY_SUBSCRIPTION_SUMMARY';
    private static final Date TERM_START = Date.newInstance(2026, 1, 1);

    private static final String PLATFORM = 'Platform Subscription';
    private static final String PRODUCT_A = 'Product A';
    private static final String ONBOARDING = 'Onboarding Accelerator';
    private static final String MIGRATION = 'Data Migration';
    private static final String SECURITY = 'Security Review';
    private static final String TRAINING = 'Training Day';

    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Monthly Subscription Test', Industry = 'Technology');
        insert account;

        Opportunity opportunity = new Opportunity(
            Name = 'Monthly Subscription Test',
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
            new Product2(Name = TRAINING,   ProductCode = 'MSS_TRAINING',   Family = 'Service',  IsActive = true)
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
        // whole quote term - and so does the customizer.
        lines.add(line(quote.Id, byName.get(PLATFORM), 1, 12000, null, null));

        // 1000 over three months does not divide into whole cents. Chosen for
        // exactly that reason: the residual has to land somewhere visible.
        lines.add(line(quote.Id, byName.get(PRODUCT_A), 2, 1000,
                       TERM_START, Date.newInstance(2026, 3, 31)));

        lines.add(line(quote.Id, byName.get(ONBOARDING), 3, 2000,
                       Date.newInstance(2026, 7, 1), Date.newInstance(2026, 10, 31)));

        // Eleven days inside month 5. A partial month is a whole month of
        // occupancy - the product is either running that month or it is not.
        lines.add(line(quote.Id, byName.get(MIGRATION), 4, 500,
                       Date.newInstance(2026, 5, 10), Date.newInstance(2026, 5, 20)));

        lines.add(line(quote.Id, byName.get(SECURITY), 5, 750,
                       Date.newInstance(2026, 6, 1), Date.newInstance(2026, 6, 30)));

        // A single day, in a month that already has two other products.
        lines.add(line(quote.Id, byName.get(TRAINING), 6, 300,
                       Date.newInstance(2026, 7, 15), Date.newInstance(2026, 7, 15)));

        insert lines;
    }

    private static SBQQ__QuoteLine__c line(
        Id quoteId, Id productId, Integer lineNumber, Decimal price, Date startDate, Date endDate
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
            SBQQ__StartDate__c = startDate,
            SBQQ__EndDate__c = endDate
        );
    }

    // -----------------------------------------------------------------------

    private static Id quoteId() {
        return [SELECT Id FROM SBQQ__Quote__c LIMIT 1].Id;
    }

    /**
     * The table as it ships: no grouping metadata at all, because the
     * customizer owns every row it produces.
     */
    private static void useMonthlyTable() {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            TABLE_CODE, new List<String>(), new List<Integer>(),
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        definition.rowCustomizerCode = QuoteDocumentMonthlyRowCustomizer.CODE;
        definition.rowCustomizerVersion = '1';
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ definition }
        );
    }

    private static List<Quote_Document_Row__c> rows() {
        return [
            SELECT Row_Type__c, Row_Key__c, Display_Label__c, Display_Order__c, Group_Key__c,
                   Group_Value__c, Group_Level__c, Product_Name__c, Amount_Net__c, Label_Key__c,
                   Label_Arg_1__c, Include_In_Grand_Total__c
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

    private static String monthKey(Integer month) {
        return 'MONTH:' + String.valueOf(month).leftPad(2, '0');
    }

    // -----------------------------------------------------------------------
    // The scenario
    // -----------------------------------------------------------------------

    @IsTest
    static void everyMonthCarriesOnlyTheProductsRunningInIt() {
        useMonthlyTable();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Quote_Document_Table__c table = [
            SELECT Status__c, Amount_Net__c FROM Quote_Document_Table__c WHERE Table_Code__c = :TABLE_CODE
        ];
        Assert.areEqual('Complete', table.Status__c, 'The monthly allocation must reconcile.');

        Map<String, Decimal> net = netByRowKey();

        // The annual product contributes 1000 to every month; the shorter
        // products are added only where they run. Product A's 1000 over three
        // months is 333.33, 333.33, 333.34 - the residual lands in month 3.
        Map<Integer, Decimal> expected = new Map<Integer, Decimal>{
            1 => 1333.33, 2 => 1333.33, 3 => 1333.34,
            4 => 1000.00,
            5 => 1500.00,
            6 => 1750.00,
            7 => 1800.00,
            8 => 1500.00, 9 => 1500.00, 10 => 1500.00,
            11 => 1000.00, 12 => 1000.00
        };

        for (Integer month = 1; month <= 12; month++) {
            Assert.areEqual(
                expected.get(month), net.get('SUBTOTAL:' + monthKey(month)),
                'Month ' + month + ' subtotal'
            );
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
        useMonthlyTable();

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
                .add(Integer.valueOf(row.Group_Key__c.substringAfter('MONTH:')));
        }

        Assert.areEqual(12, monthsByProduct.get(PLATFORM).size(), 'The annual product runs every month.');
        Assert.areEqual(
            new List<Integer>{ 1, 2, 3 }, monthsByProduct.get(PRODUCT_A),
            'Product A runs months 1 to 3.'
        );
        Assert.areEqual(
            new List<Integer>{ 7, 8, 9, 10 }, monthsByProduct.get(ONBOARDING),
            'Onboarding runs months 7 to 10.'
        );
        Assert.areEqual(
            new List<Integer>{ 5 }, monthsByProduct.get(MIGRATION),
            'Eleven days inside month 5 is one month of occupancy, not two.'
        );
        Assert.areEqual(new List<Integer>{ 6 }, monthsByProduct.get(SECURITY), 'Security review runs month 6.');
        Assert.areEqual(
            new List<Integer>{ 7 }, monthsByProduct.get(TRAINING),
            'A single day still occupies its month.'
        );
    }

    @IsTest
    static void theResidualLandsInTheLastMonthSoTheLineIsNeverShort() {
        useMonthlyTable();

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

    @IsTest
    static void theNotePrintsBelowTheTotalAsWordsNotMoney() {
        useMonthlyTable();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Quote_Document_Row__c note;
        Quote_Document_Row__c grandTotal;
        for (Quote_Document_Row__c row : rows()) {
            if (row.Row_Type__c == 'Note') {
                note = row;
            }
            if (row.Row_Type__c == 'Grand Total') {
                grandTotal = row;
            }
        }

        Assert.isNotNull(note, 'Every table that prints an allocated figure must explain that it is allocated.');
        Assert.isTrue(
            note.Display_Order__c > grandTotal.Display_Order__c,
            'The note prints below the total it explains.'
        );
        Assert.isFalse(note.Include_In_Grand_Total__c, 'A note is words, not money.');
        Assert.areEqual(
            QuoteDocumentMonthlyRowCustomizer.KEY_NOTE, note.Label_Key__c,
            'The wording must stay addressable by key, not frozen as English.'
        );
        Assert.isTrue(String.isNotBlank(note.Display_Label__c), 'The note must resolve to real wording.');
    }

    /**
     * The case that proved the note must not be conditional. Two short products
     * and no annual line at all: the first implementation required a full-term
     * line to be present and printed nothing here, which is precisely the quote
     * where a reader most needs telling that 333.33 is a third of something.
     */
    @IsTest
    static void twoShortProductsWithNoFullTermLineStillGetTheNote() {
        delete [SELECT Id FROM SBQQ__QuoteLine__c
                WHERE SBQQ__Number__c IN (1, 4, 5, 6)];
        useMonthlyTable();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Boolean noted = false;
        for (Quote_Document_Row__c row : rows()) {
            if (row.Row_Type__c == 'Note') {
                noted = true;
            }
        }
        Assert.isTrue(noted, 'Product A and Onboarding alone are still allocated across months.');
    }

    @IsTest
    static void aQuoteWhereEverythingRunsTheFullTermIsStillExplained() {
        delete [SELECT Id FROM SBQQ__QuoteLine__c WHERE SBQQ__StartDate__c != NULL];
        useMonthlyTable();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Boolean noted = false;
        for (Quote_Document_Row__c row : rows()) {
            if (row.Row_Type__c == 'Note') {
                noted = true;
            }
        }
        Assert.isTrue(
            noted,
            'One annual line is still twelve monthly figures that no line item on the quote states.'
        );
    }

    @IsTest
    static void everyMonthPrintsEvenWhenNothingShortRunsInIt() {
        useMonthlyTable();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Integer headers = 0;
        for (Quote_Document_Row__c row : rows()) {
            if (row.Row_Type__c == 'Group Header') {
                headers++;
                Assert.areEqual(
                    QuoteDocumentMonthlyRowCustomizer.KEY_MONTH, row.Label_Key__c,
                    'A month heading is dictionary wording with the ordinal as its argument.'
                );
            }
        }
        Assert.areEqual(12, headers, 'A twelve-month term prints twelve months, including the quiet ones.');
    }

    // -----------------------------------------------------------------------
    // Failure paths
    // -----------------------------------------------------------------------

    @IsTest
    static void aLineOutsideTheTermFailsRatherThanVanishing() {
        SBQQ__QuoteLine__c stray = [SELECT Id FROM SBQQ__QuoteLine__c WHERE SBQQ__Number__c = 6];
        stray.SBQQ__StartDate__c = Date.newInstance(2027, 6, 1);
        stray.SBQQ__EndDate__c = Date.newInstance(2027, 6, 30);
        update stray;

        useMonthlyTable();

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
            Assert.fail('A line that belongs to no month leaves the printed months short of the quote total.');
        } catch (QuoteDocumentGenerator.QuoteDocumentException expected) {
            Assert.isTrue(
                expected.getMessage().contains('MONTHLY_LINE_OUTSIDE_TERM'),
                'The failure must name its code: ' + expected.getMessage()
            );
        }
        Test.stopTest();

        // Not 'Failed' specifically: editing the stray line's dates already
        // marked the quote Stale through the ordinary staleness trigger, and
        // which of the two survives a rolled-back generation is
        // QuoteDocumentFailureBoundaryTest's subject, not this one. What
        // matters here is that no snapshot was published.
        SBQQ__Quote__c quote = [SELECT Document_Data_Status__c FROM SBQQ__Quote__c LIMIT 1];
        Assert.areNotEqual('Ready', quote.Document_Data_Status__c,
                           'A failed allocation must not leave a readable snapshot behind.');
    }

    @IsTest
    static void aQuoteWithNoTermFailsRatherThanGuessingOne() {
        SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
        quote.SBQQ__StartDate__c = null;
        quote.SBQQ__SubscriptionTerm__c = null;
        update quote;
        delete [SELECT Id FROM SBQQ__QuoteLine__c WHERE SBQQ__StartDate__c != NULL];

        useMonthlyTable();

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quote.Id });
            Assert.fail('A month grid guessed from nothing is worse than no table.');
        } catch (QuoteDocumentGenerator.QuoteDocumentException expected) {
            Assert.isTrue(
                expected.getMessage().contains('MONTHLY_TERM_UNRESOLVED'),
                'The failure must name its code: ' + expected.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void theChangeMeasureSetIsRefusedRatherThanPrintingZeroes() {
        // A table code with no Quote_Document_Column_Def__mdt records behind
        // it. On MONTHLY_SUBSCRIPTION_SUMMARY itself the shipped COL_NET
        // column trips COLUMN_MEASURE_MISMATCH first - a good guard, but it
        // would leave this one untested.
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            'MONTHLY_CHANGE_MEASURE_PROBE', new List<String>(), new List<Integer>(),
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        definition.rowCustomizerCode = QuoteDocumentMonthlyRowCustomizer.CODE;
        definition.rowCustomizerVersion = '1';
        definition.measureSet = QuoteDocumentTableDefinition.MEASURES_CHANGE;
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ definition }
        );

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
            Assert.fail('A table of zeroes that reconciles is the worst possible outcome.');
        } catch (QuoteDocumentGenerator.QuoteDocumentException expected) {
            Assert.isTrue(
                expected.getMessage().contains('MONTHLY_MEASURE_SET_UNSUPPORTED'),
                'The failure must name its code: ' + expected.getMessage()
            );
        }
        Test.stopTest();
    }

    // -----------------------------------------------------------------------
    // The arithmetic, without a quote in sight
    // -----------------------------------------------------------------------

    @IsTest
    static void allocationAlwaysSumsBackToTheTotal() {
        for (Decimal total : new List<Decimal>{ 1000, 0.01, 12000, -450.55, 999.99 }) {
            for (Integer parts : new List<Integer>{ 1, 3, 7, 12 }) {
                Decimal sum = 0;
                for (Decimal share : QuoteDocumentMonthlyRowCustomizer.allocate(total, parts)) {
                    sum += share;
                }
                Assert.areEqual(total, sum, total + ' split ' + parts + ' ways must not lose a cent.');
            }
        }
    }

    @IsTest
    static void monthsAreAnniversaryMonthsNotCalendarMonths() {
        QuoteDocumentMonthlyRowCustomizer.MonthGrid grid =
            new QuoteDocumentMonthlyRowCustomizer.MonthGrid(Date.newInstance(2026, 1, 15), 12);

        Assert.areEqual(Date.newInstance(2027, 1, 14), grid.endDate(),
                        'A twelve-month term from the 15th ends the day before the anniversary.');
        Assert.areEqual(1, grid.indexOf(Date.newInstance(2026, 1, 15)), 'The first day is month 1.');
        Assert.areEqual(1, grid.indexOf(Date.newInstance(2026, 2, 14)), 'The day before the anniversary is still month 1.');
        Assert.areEqual(2, grid.indexOf(Date.newInstance(2026, 2, 15)), 'The anniversary starts month 2.');
        Assert.areEqual(12, grid.indexOf(Date.newInstance(2027, 1, 14)), 'The last day is month 12.');
        Assert.isNull(grid.indexOf(Date.newInstance(2027, 1, 15)), 'A date past the term belongs to no month.');
        Assert.isNull(grid.indexOf(Date.newInstance(2025, 12, 31)), 'A date before the term belongs to no month.');
    }

    // -----------------------------------------------------------------------
    // Licences repeat; money divides
    // -----------------------------------------------------------------------

    /**
     * Sets a quantity on two lines and re-costs nothing else: the platform
     * runs all twelve months with 100 licences, Product A runs months 1-3
     * with 50. Peak occupancy is therefore months 1-3, at 150.
     */
    private static void giveLinesLicenceCounts() {
        Map<String, SBQQ__QuoteLine__c> byName = new Map<String, SBQQ__QuoteLine__c>();
        for (SBQQ__QuoteLine__c ql : [
            SELECT Id, SBQQ__Quantity__c, SBQQ__Product__r.Name FROM SBQQ__QuoteLine__c
        ]) {
            byName.put(ql.SBQQ__Product__r.Name, ql);
        }
        byName.get(PLATFORM).SBQQ__Quantity__c = 100;
        byName.get(PRODUCT_A).SBQQ__Quantity__c = 50;
        update byName.values();
    }

    private static Map<String, Decimal> quantityByRowKey() {
        Map<String, Decimal> byKey = new Map<String, Decimal>();
        for (Quote_Document_Row__c row : [
            SELECT Row_Key__c, Quantity__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Table_Code__c = :TABLE_CODE
        ]) {
            byKey.put(row.Row_Key__c, row.Quantity__c);
        }
        return byKey;
    }

    /**
     * The customer has 100 licences in every month of the term, not 8.33.
     * Dividing them was the original behaviour and it printed a quantity
     * nobody has.
     */
    @IsTest
    static void licencesRepeatInEveryMonthRatherThanBeingDividedAmongThem() {
        useMonthlyTable();
        giveLinesLicenceCounts();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        List<Quote_Document_Row__c> platformMonths = [
            SELECT Row_Key__c, Quantity__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Table_Code__c = :TABLE_CODE
              AND Row_Type__c = 'Detail'
              AND Product_Name__c = :PLATFORM
        ];
        Assert.areEqual(12, platformMonths.size(), 'The platform runs every month of the term.');
        for (Quote_Document_Row__c row : platformMonths) {
            Assert.areEqual(
                100, row.Quantity__c,
                'The platform licences are the same 100 every month, in ' + row.Row_Key__c
            );
        }
    }

    /**
     * Two products active in the same month really are 150 licences that
     * month - so a month is a sum. The next month is not another 150, so the
     * term is a peak. Both halves, because getting either one wrong prints a
     * number the customer can disprove by counting their own users.
     */
    @IsTest
    static void theTermShowsThePeakMonthNotTheSumOfEveryMonth() {
        useMonthlyTable();
        giveLinesLicenceCounts();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Map<String, Decimal> quantity = quantityByRowKey();

        Assert.areEqual(150, quantity.get('SUBTOTAL:' + monthKey(1)),
                        'Months 1-3 run both products: 100 + 50.');
        Assert.areEqual(150, quantity.get('SUBTOTAL:' + monthKey(3)), 'Month 3 still runs both.');
        Assert.areEqual(100, quantity.get('SUBTOTAL:' + monthKey(4)),
                        'Product A has ended; only the platform remains.');
        Assert.areEqual(100, quantity.get('SUBTOTAL:' + monthKey(12)), 'The last month is the platform alone.');

        Assert.areEqual(150, quantity.get('GRAND_TOTAL'),
                        'The peak is 150 simultaneous licences - not 1,400 licence-months, and not 100.');

        Quote_Document_Table__c table = [
            SELECT Quantity__c FROM Quote_Document_Table__c WHERE Table_Code__c = :TABLE_CODE
        ];
        Assert.areEqual(150, table.Quantity__c, 'The table measure follows the grand total row.');
    }

    /**
     * The half that must not regress: making licences repeat must not stop
     * money dividing. Both behaviours live in the same loop over the same
     * measure list.
     */
    @IsTest
    static void moneyStillDividesWhileLicencesRepeat() {
        useMonthlyTable();
        giveLinesLicenceCounts();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Quote_Document_Table__c table = [
            SELECT Status__c, Amount_Net__c, Quantity__c
            FROM Quote_Document_Table__c WHERE Table_Code__c = :TABLE_CODE
        ];
        Assert.areEqual('Complete', table.Status__c,
                        'A non-additive quantity must not break reconciliation of the money.');

        // CPQ prices per unit, so raising the quantities raises the money
        // with them: month 1 is the platform's 100 x 12,000 / 12 months, plus
        // Product A's 50 x 1,000 spread over its three. The point of the
        // assertion is that the money still DIVIDES by month while the
        // licences repeat - not that the figure is unchanged.
        Map<String, Decimal> net = netByRowKey();
        Assert.areEqual(116666.67, net.get('SUBTOTAL:' + monthKey(1)),
                        'Month 1 money is still one month of each line, not a whole line.');
        Assert.areEqual(100000.00, net.get('SUBTOTAL:' + monthKey(12)),
                        'Month 12 is the platform alone, still divided by twelve.');

        SBQQ__Quote__c quote = [SELECT SBQQ__NetAmount__c FROM SBQQ__Quote__c LIMIT 1];
        Assert.areEqual(quote.SBQQ__NetAmount__c, net.get('GRAND_TOTAL'),
                        'The months still foot to the quote.');
    }

    /** The primitive itself, without an org: every month gets the same value. */
    @IsTest
    static void repeatGivesEveryPartTheWholeValue() {
        List<Decimal> values = QuoteDocumentMonthlyRowCustomizer.repeat(100, 12);
        Assert.areEqual(12, values.size(), 'One value per month occupied.');
        for (Decimal value : values) {
            Assert.areEqual(100, value, 'Every month carries the whole quantity.');
        }
        Assert.areEqual(0, QuoteDocumentMonthlyRowCustomizer.repeat(null, 3)[0],
                        'A null quantity repeats as zero, never as null.');
    }
}
