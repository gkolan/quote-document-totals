/**
 * One quote, several independently totalled tables.
 *
 * The distinction this whole step rests on: grouping nests rows inside ONE
 * table under one grand total; partitioning produces several tables, each
 * reconciling against its own share, with nothing spanning them unless the
 * author says a spanning total is meaningful. The tests that matter most are
 * the two that check the totals do not leak into each other.
 */
@IsTest
private class QuoteDocumentPartitionTest {

    private static final String TABLE_CODE = 'PARTITION_TEST';

    private static final String SOFTWARE_A = 'Platform Licence';
    private static final String SOFTWARE_B = 'Analytics Module';
    private static final String HARDWARE = 'Edge Appliance';

    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Partition Test', Industry = 'Technology');
        insert account;

        Opportunity opportunity = new Opportunity(
            Name = 'Partition Test',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunity;

        List<Product2> products = new List<Product2>{
            new Product2(Name = SOFTWARE_A, ProductCode = 'PT_SW_A', Family = 'Software', IsActive = true),
            new Product2(Name = SOFTWARE_B, ProductCode = 'PT_SW_B', Family = 'Software', IsActive = true),
            new Product2(Name = HARDWARE,   ProductCode = 'PT_HW',   Family = 'Hardware', IsActive = true)
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

        // Software 6,000 + 4,000. Hardware 2,500. Quote total 12,500.
        insert new List<SBQQ__QuoteLine__c>{
            line(quote.Id, byName.get(SOFTWARE_A), 1, 6000),
            line(quote.Id, byName.get(SOFTWARE_B), 2, 4000),
            line(quote.Id, byName.get(HARDWARE), 3, 2500)
        };
    }

    private static SBQQ__QuoteLine__c line(Id quoteId, Id productId, Integer lineNumber, Decimal total) {
        return new SBQQ__QuoteLine__c(
            SBQQ__Quote__c = quoteId,
            SBQQ__Product__c = productId,
            SBQQ__Number__c = lineNumber,
            SBQQ__Quantity__c = 1,
            SBQQ__ListPrice__c = total,
            SBQQ__RegularPrice__c = total
        );
    }

    private static Id quoteId() {
        return [SELECT Id FROM SBQQ__Quote__c LIMIT 1].Id;
    }

    /**
     * Partitioned by product family, grouped by charge type inside each
     * partition - so the two mechanisms are exercised together and can be seen
     * not to be the same thing.
     */
    private static QuoteDocumentTableDefinition partitioned(String crossTotal) {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            TABLE_CODE,
            new List<String>{ QuoteDocumentTableDefinition.DIM_CHARGE_TYPE },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        definition.partitionDimension = QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY;
        definition.crossPartitionTotal = crossTotal;
        return definition;
    }

    private static void use(QuoteDocumentTableDefinition definition) {
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ definition }
        );
    }

    /** Payload sections are tables AND narrative blocks; these assertions mean tables. */
    private static List<QuoteDocumentPayload.Section> tableSections(QuoteDocumentPayload payload) {
        List<QuoteDocumentPayload.Section> sections = new List<QuoteDocumentPayload.Section>();
        for (QuoteDocumentPayload.Section section : payload.sections) {
            if ('Table'.equals(section.sectionType)) {
                sections.add(section);
            }
        }
        return sections;
    }

    private static List<Quote_Document_Table__c> tables() {
        return [
            SELECT Id, Table_Code__c, Table_Key__c, Display_Title__c, Display_Order__c,
                   Partition_Value__c, Partition_Dimension__c, Cross_Partition_Total__c,
                   Amount_Net__c, Status__c
            FROM Quote_Document_Table__c
            WHERE Table_Code__c = :TABLE_CODE
            ORDER BY Display_Order__c
        ];
    }

    // -----------------------------------------------------------------------

    @IsTest
    static void aPartitionedDefinitionProducesOneTablePerValue() {
        use(partitioned(QuoteDocumentTableDefinition.CROSS_PARTITION_SUM));

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        List<Quote_Document_Table__c> result = tables();
        Assert.areEqual(2, result.size(), 'Hardware and Software are two tables, not two groups.');
        Assert.areEqual('Hardware', result[0].Partition_Value__c, 'In value order.');
        Assert.areEqual('Software', result[1].Partition_Value__c, 'In value order.');

        for (Quote_Document_Table__c table : result) {
            Assert.areEqual('Complete', table.Status__c, 'Each partition reconciles on its own.');
            Assert.areEqual(QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY, table.Partition_Dimension__c,
                            'The dimension is recorded on the record, not only in the key.');
        }
    }

    /**
     * The failure this step exists to prevent is a total that leaks across
     * partitions. Each one must equal its own lines and nothing else.
     */
    @IsTest
    static void eachPartitionTotalsOnlyItsOwnLines() {
        use(partitioned(QuoteDocumentTableDefinition.CROSS_PARTITION_SUM));

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Map<String, Quote_Document_Table__c> byValue = new Map<String, Quote_Document_Table__c>();
        for (Quote_Document_Table__c table : tables()) {
            byValue.put(table.Partition_Value__c, table);
        }

        Assert.areEqual(2500, byValue.get('Hardware').Amount_Net__c, 'The appliance alone.');
        Assert.areEqual(10000, byValue.get('Software').Amount_Net__c, 'The two software lines alone.');

        for (String value : byValue.keySet()) {
            Quote_Document_Row__c total = [
                SELECT Amount_Net__c FROM Quote_Document_Row__c
                WHERE Quote_Document_Table__c = :byValue.get(value).Id AND Row_Type__c = 'Grand Total'
            ];
            Assert.areEqual(byValue.get(value).Amount_Net__c, total.Amount_Net__c,
                            value + ': the table measure follows its own grand total row.');
        }
    }

    @IsTest
    static void everyPartitionGetsItsOwnKeyAndOrder() {
        use(partitioned(QuoteDocumentTableDefinition.CROSS_PARTITION_SUM));

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Set<String> keys = new Set<String>();
        Set<Decimal> orders = new Set<Decimal>();
        for (Quote_Document_Table__c table : tables()) {
            Assert.isTrue(keys.add(table.Table_Key__c), 'Duplicate key: ' + table.Table_Key__c);
            Assert.isTrue(orders.add(table.Display_Order__c),
                          'Two tables at order ' + table.Display_Order__c + ' would print in either order.');
            Assert.isTrue(table.Table_Key__c.endsWith(':' + table.Partition_Value__c),
                          'The key carries the partition: ' + table.Table_Key__c);
        }
    }

    /**
     * A renderer may not compose a heading, so the partition has to reach the
     * printed title - through the dictionary, not through concatenation.
     */
    @IsTest
    static void thePartitionReachesThePrintedTitle() {
        use(partitioned(QuoteDocumentTableDefinition.CROSS_PARTITION_SUM));

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        for (Quote_Document_Table__c table : tables()) {
            Assert.isTrue(table.Display_Title__c.contains(table.Partition_Value__c),
                          'The heading names the partition: ' + table.Display_Title__c);
            Assert.isTrue(table.Display_Title__c.contains(TABLE_CODE),
                          'And still carries the definition title.');
        }
    }

    @IsTest
    static void crossPartitionSumMustActuallyAddUp() {
        use(partitioned(QuoteDocumentTableDefinition.CROSS_PARTITION_SUM));

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Decimal total = 0;
        for (Quote_Document_Table__c table : tables()) {
            total += table.Amount_Net__c;
        }

        SBQQ__Quote__c quote = [SELECT SBQQ__NetAmount__c FROM SBQQ__Quote__c LIMIT 1];
        Assert.areEqual(quote.SBQQ__NetAmount__c, total,
                        'Complementary partitions add to the quote - and generation checks it.');
    }

    /**
     * With NONE, nothing in the snapshot may state a total spanning the
     * partitions. Asserted by query rather than by inspection.
     */
    @IsTest
    static void nothingSpansThePartitionsWhenNone() {
        use(partitioned(QuoteDocumentTableDefinition.CROSS_PARTITION_NONE));

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        SBQQ__Quote__c quote = [SELECT SBQQ__NetAmount__c FROM SBQQ__Quote__c LIMIT 1];

        for (Quote_Document_Table__c table : tables()) {
            Assert.areEqual(QuoteDocumentTableDefinition.CROSS_PARTITION_NONE,
                            table.Cross_Partition_Total__c,
                            'Every partition record says so, so a renderer reading one knows.');
            Assert.areNotEqual(quote.SBQQ__NetAmount__c, table.Amount_Net__c,
                               'No single table carries the whole-quote number.');
        }

        for (Quote_Document_Row__c row : [
            SELECT Amount_Net__c FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Table_Code__c = :TABLE_CODE AND Row_Type__c = 'Grand Total'
        ]) {
            Assert.areNotEqual(quote.SBQQ__NetAmount__c, row.Amount_Net__c,
                               'And no row does either.');
        }
    }

    /**
     * Retention deletes by quote. A pass that left two of three partitions
     * behind would leak them into the next generation.
     */
    @IsTest
    static void regeneratingReplacesEveryPartition() {
        use(partitioned(QuoteDocumentTableDefinition.CROSS_PARTITION_SUM));

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Integer first = tables().size();

        // Force a rebuild rather than a reuse.
        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            Id = quoteId(), Document_Data_Fingerprint__c = 'forced-rebuild'
        );
        update quote;
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Assert.areEqual(first, tables().size(),
                        'A regeneration replaces every partition rather than adding to them.');
    }

    // -----------------------------------------------------------------------
    // Unpartitioned behaviour must not move
    // -----------------------------------------------------------------------

    @IsTest
    static void anUnpartitionedTableKeepsItsOldIdentity() {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            TABLE_CODE,
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        use(definition);

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        List<Quote_Document_Table__c> result = tables();
        Assert.areEqual(1, result.size(), 'One definition, one table.');
        Assert.areEqual(quoteId() + ':' + TABLE_CODE, result[0].Table_Key__c,
                        'The two-segment key is byte-identical to what it always was.');
        Assert.isNull(result[0].Partition_Value__c, 'And nothing partition-shaped is stamped.');
        Assert.isNull(result[0].Cross_Partition_Total__c, 'Including the cross-partition claim.');

        SBQQ__Quote__c quote = [SELECT SBQQ__NetAmount__c FROM SBQQ__Quote__c LIMIT 1];
        Assert.areEqual(quote.SBQQ__NetAmount__c, result[0].Amount_Net__c, 'One total, as before.');
    }

    // -----------------------------------------------------------------------
    // Configuration failures
    // -----------------------------------------------------------------------

    @IsTest
    static void aPartitionedDefinitionMustDeclareItsCrossPartitionClaim() {
        QuoteDocumentTableDefinition definition = partitioned(null);

        try {
            definition.validatePartitionConfig();
            Assert.fail('The wrong default prints a number the customer is not being asked to pay.');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('Cross_Partition_Total__c'), e.getMessage());
        }
    }

    @IsTest
    static void anUnknownCrossPartitionClaimIsRefused() {
        QuoteDocumentTableDefinition definition = partitioned('AVERAGE');

        try {
            definition.validatePartitionConfig();
            Assert.fail('Only NONE and SUM are implemented.');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('NONE or SUM'), e.getMessage());
        }
    }

    @IsTest
    static void aCrossPartitionClaimWithoutPartitionsIsRefused() {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            TABLE_CODE, new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 }, QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        definition.crossPartitionTotal = QuoteDocumentTableDefinition.CROSS_PARTITION_SUM;

        try {
            definition.validatePartitionConfig();
            Assert.fail('There are no partitions for a total to span.');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('Partition_Dimension__c'), e.getMessage());
        }
    }

    @IsTest
    static void partitioningAndComparingAtOnceIsRefused() {
        QuoteDocumentTableDefinition definition =
            partitioned(QuoteDocumentTableDefinition.CROSS_PARTITION_NONE);
        definition.comparisonSourceCode = QuoteDocumentSourceQuoteComparison.CODE;
        definition.comparisonSourceVersion = '1';

        try {
            definition.validatePartitionConfig();
            Assert.fail('Which partition a baseline line belongs to has no agreed answer.');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('change document'), e.getMessage());
        }
    }

    // -----------------------------------------------------------------------
    // One document per partition
    // -----------------------------------------------------------------------

    /**
     * The purchasing-entity case: one negotiated quote, a separate document for
     * each party, each showing only its own products and its own payable total.
     *
     * A VIEW of one snapshot rather than a second snapshot - the whole payload
     * is retrieved and verified first, so both documents provably came from the
     * same generation.
     */
    @IsTest
    static void aPartitionCanBeRetrievedAsItsOwnDocument() {
        use(partitioned(QuoteDocumentTableDefinition.CROSS_PARTITION_SUM));

        Test.startTest();
        List<QuoteDocumentGenerator.GenerationOutcome> outcomes =
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        QuoteDocumentGenerator.GenerationOutcome outcome = outcomes[0];

        QuoteDocumentPayload whole = QuoteDocumentRenderService.getPayload(
            quoteId(), outcome.requestId, outcome.fingerprint
        );
        QuoteDocumentPayload hardware = QuoteDocumentRenderService.getPayloadForPartition(
            quoteId(), outcome.requestId, outcome.fingerprint, 'Hardware'
        );

        Assert.areEqual(2, tableSections(whole).size(), 'The whole quote carries both partitions.');

        List<QuoteDocumentPayload.Section> theirs = tableSections(hardware);
        Assert.areEqual(1, theirs.size(), 'One party sees one table.');
        Assert.areEqual('Hardware', theirs[0].partitionValue, 'And it is theirs.');
        Assert.areEqual(QuoteDocumentTableDefinition.CROSS_PARTITION_SUM, theirs[0].crossPartitionTotal,
                        'The section states whether a spanning total exists, so a renderer never guesses.');

        // Narrative blocks belong to nobody exclusively - an introduction or a
        // terms block is in every party's copy, so filtering must not drop them.
        Assert.areEqual(
            whole.sections.size() - tableSections(whole).size(),
            hardware.sections.size() - theirs.size(),
            'Every unpartitioned section survives the filter.'
        );
    }

    /**
     * Returning the unpartitioned remainder would hand a signer a document with
     * their own products missing and nothing to say so.
     */
    @IsTest
    static void anUnknownPartitionFailsRatherThanReturningARemainder() {
        use(partitioned(QuoteDocumentTableDefinition.CROSS_PARTITION_SUM));

        Test.startTest();
        List<QuoteDocumentGenerator.GenerationOutcome> outcomes =
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        try {
            QuoteDocumentRenderService.getPayloadForPartition(
                quoteId(), outcomes[0].requestId, outcomes[0].fingerprint, 'Nonexistent Entity'
            );
            Assert.fail('A document missing its whole point must not be produced.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains('PARTITION_NOT_FOUND'), e.getMessage());
        }
    }

    /** No selector means the whole quote, exactly as before. */
    @IsTest
    static void anUnpartitionedRetrievalIsUnchanged() {
        use(partitioned(QuoteDocumentTableDefinition.CROSS_PARTITION_SUM));

        Test.startTest();
        List<QuoteDocumentGenerator.GenerationOutcome> outcomes =
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        QuoteDocumentPayload payload = QuoteDocumentRenderService.getPayloadForPartition(
            quoteId(), outcomes[0].requestId, outcomes[0].fingerprint, null
        );
        Assert.areEqual(2, tableSections(payload).size(), 'A blank selector is the whole document.');
    }

    // -----------------------------------------------------------------------
    // Estimates cannot print without their assumptions
    // -----------------------------------------------------------------------

    /**
     * The guard exists for the case where the block was deactivated, or has no
     * wording in the resolved locale, while the table that depends on it kept
     * generating happily. The number would print and the caveat would not.
     */
    @IsTest
    static void aTableRequiringAssumptionsWillNotPublishWithoutThem() {
        QuoteDocumentTableDefinition definition =
            partitioned(QuoteDocumentTableDefinition.CROSS_PARTITION_NONE);
        definition.assumptionsBlockCode = 'CONSUMPTION_ASSUMPTIONS_THAT_DO_NOT_EXIST';
        use(definition);

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
            Assert.fail('An estimate without its assumptions must not reach a customer.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains('SCENARIO_ASSUMPTIONS_MISSING'),
                          'Coded failure: ' + e.getMessage());
            Assert.isTrue(e.getMessage().contains('CONSUMPTION_ASSUMPTIONS_THAT_DO_NOT_EXIST'),
                          'And it names the block that is missing.');
        }
        Test.stopTest();
    }

    /** A table that requires nothing is unaffected, which is every table today. */
    @IsTest
    static void aTableRequiringNoAssumptionsIsUnaffected() {
        use(partitioned(QuoteDocumentTableDefinition.CROSS_PARTITION_SUM));

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Assert.areEqual(2, tables().size(), 'Generation is untouched when nothing is required.');
    }

    @IsTest
    static void partitionConfigMovesTheFingerprint() {
        SBQQ__Quote__c quote = QuoteDocumentQuery.quotesWithLinesReadOnly(
            new Set<Id>{ quoteId() }
        )[0];
        List<QuoteDocumentLine> lines = new List<QuoteDocumentLine>();
        for (SBQQ__QuoteLine__c raw : quote.SBQQ__LineItems__r) {
            lines.add(new QuoteDocumentLine(raw, quote));
        }

        QuoteDocumentTableDefinition plain = QuoteDocumentTableDefinition.build(
            TABLE_CODE, new List<String>{ QuoteDocumentTableDefinition.DIM_CHARGE_TYPE },
            new List<Integer>{ 1 }, QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );

        String before = QuoteDocumentFingerprint.compute(
            quote, lines, new List<QuoteDocumentTableDefinition>{ plain }
        );
        String after = QuoteDocumentFingerprint.compute(
            quote, lines,
            new List<QuoteDocumentTableDefinition>{
                partitioned(QuoteDocumentTableDefinition.CROSS_PARTITION_SUM)
            }
        );
        Assert.areNotEqual(before, after, 'Several tables is a different document from one.');

        String asNone = QuoteDocumentFingerprint.compute(
            quote, lines,
            new List<QuoteDocumentTableDefinition>{
                partitioned(QuoteDocumentTableDefinition.CROSS_PARTITION_NONE)
            }
        );
        Assert.areNotEqual(after, asNone, 'And so is a different claim about their totals.');
    }
}
