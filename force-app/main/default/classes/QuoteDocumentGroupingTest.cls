/**
 * How a table definition turns into a shape: composite vs nested levels, the
 * order groups come out in, and the guard rails that stop a bad grouping.
 *
 * Split out of QuoteDocumentLifecycleTest, which is about the machinery
 * *around* generation (readiness, staleness, async, retention). This is about
 * the grouping decision itself, and reads the same two-family fixture so a
 * grouping assertion has exactly two buckets and nothing incidental in them.
 */
@IsTest
private class QuoteDocumentGroupingTest {

    @TestSetup
    static void setup() {
        QuoteDocumentTestData.setupLifecycle();
    }

    private static Id quoteId() {
        return QuoteDocumentTestData.lifecycleQuote().Id;
    }

    private static List<QuoteDocumentLine> normalizedLines() {
        return QuoteDocumentTestData.normalizedLines();
    }

    // -----------------------------------------------------------------------
    // Definitions come from Custom Metadata
    // -----------------------------------------------------------------------

    @IsTest
    static void definitionsLoadFromCustomMetadataWithOrderedDimensions() {
        List<QuoteDocumentTableDefinition> definitions = QuoteDocumentTableDefinition.getAll();

        Assert.isFalse(definitions.isEmpty(), 'Definitions should come from Custom Metadata');

        QuoteDocumentTableDefinition nested;
        QuoteDocumentTableDefinition composite;
        for (QuoteDocumentTableDefinition d : definitions) {
            Assert.isFalse(d.groupBy.isEmpty(), d.tableCode + ' must have a grouping');
            if (d.tableCode == 'GROUP_FAMILY_DETAIL') { nested = d; }
            if (d.tableCode == 'FAMILY_BILLING_COMPOSITE') { composite = d; }
        }

        // Level decides nesting, Sequence decides order within a level. If this
        // ever reads PRODUCT_FAMILY first, the child records' Levels are wrong.
        Assert.isNotNull(nested, 'The nested definition should exist');
        Assert.areEqual(2, nested.groupBy.size(), 'Two levels means nesting');
        Assert.areEqual('QUOTE_LINE_GROUP', nested.groupBy[0].describe(), 'Outermost level comes first');
        Assert.areEqual('PRODUCT_FAMILY', nested.groupBy[1].describe());

        // The composite is the opposite shape: one level holding two parts.
        Assert.isNotNull(composite, 'The composite definition should exist');
        Assert.areEqual(1, composite.groupBy.size(), 'One level means no nesting');
        Assert.areEqual(2, composite.groupBy[0].parts.size(), 'Two parts means a composite bucket');
        Assert.isTrue(composite.groupBy[0].isComposite());
        Assert.areEqual('SBQQ__Product__r.Family + CHARGE_TYPE', composite.groupBy[0].describe(),
            'A composite mixes a field path with a computed dimension');
    }

    /**
     * toLevels is marked @TestVisible specifically for this test: the "must
     * set exactly one of Dimension or Field Path" rule can only be violated by
     * a genuinely broken Quote_Document_Grouping__mdt record, and creating one
     * as real, active Custom Metadata would break getAll() for every other
     * test in this suite - getAll() processes every active definition in one
     * pass, so one broken record fails everything, not just its own table.
     * Calling toLevels directly with a hand-built (in-memory, never deployed)
     * grouping record proves the rule without that blast radius.
     */
    @IsTest
    static void toLevelsRejectsAGroupingWithBothDimensionAndFieldPath() {
        Quote_Document_Grouping__mdt bothSet = new Quote_Document_Grouping__mdt(
            Dimension__c = 'PRODUCT_FAMILY',
            Field_Path__c = 'SBQQ__Product__r.Family',
            Level__c = 1,
            Sequence__c = 10
        );

        try {
            QuoteDocumentTableDefinition.toLevels(
                'BOTH_SET_PROBE', new List<Quote_Document_Grouping__mdt>{ bothSet });
            Assert.fail('A grouping record with both Dimension and Field Path set must be rejected');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('exactly one'), 'Message: ' + e.getMessage());
        }

        Quote_Document_Grouping__mdt neitherSet = new Quote_Document_Grouping__mdt(
            Level__c = 1,
            Sequence__c = 10
        );

        try {
            QuoteDocumentTableDefinition.toLevels(
                'NEITHER_SET_PROBE', new List<Quote_Document_Grouping__mdt>{ neitherSet });
            Assert.fail('A grouping record with neither Dimension nor Field Path set must be rejected');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('exactly one'), 'Message: ' + e.getMessage());
        }
    }

    // -----------------------------------------------------------------------
    // Grouping: composites, field paths, and the guard rails
    // -----------------------------------------------------------------------

    @IsTest
    static void compositeCombinesPartsIntoOneBucketRatherThanNesting() {
        QuoteDocumentTableDefinition composite = QuoteDocumentTableDefinition.build(
            'COMPOSITE_PROBE',
            new List<String>{ 'SBQQ__Product__r.Family', 'CHARGE_TYPE' },
            new List<Integer>{ 1, 1 },                       // same level = composite
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );

        Test.startTest();
        List<Quote_Document_Row__c> rows = new QuoteDocumentRowBuilder(composite).build(normalizedLines());
        Test.stopTest();

        Set<Decimal> levels = new Set<Decimal>();
        String label;
        for (Quote_Document_Row__c row : rows) {
            if (row.Row_Type__c == 'Group Header') {
                levels.add(row.Group_Level__c);
                label = row.Display_Label__c;
            }
        }

        // Composite means one level, not two - that is the whole distinction
        // from nesting, where the same two dimensions would give levels 1 and 2.
        Assert.areEqual(new Set<Decimal>{ 1 }, levels, 'A composite occupies a single level');
        Assert.isTrue(label.contains(' / '), 'Parts are joined by the separator: ' + label);
    }

    @IsTest
    static void nestingTheSamePartsProducesTwoLevelsInstead() {
        QuoteDocumentTableDefinition nested = QuoteDocumentTableDefinition.build(
            'NESTED_PROBE',
            new List<String>{ 'SBQQ__Product__r.Family', 'CHARGE_TYPE' },
            new List<Integer>{ 1, 2 },                       // different levels = nesting
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );

        Test.startTest();
        List<Quote_Document_Row__c> rows = new QuoteDocumentRowBuilder(nested).build(normalizedLines());
        Test.stopTest();

        Set<Decimal> levels = new Set<Decimal>();
        for (Quote_Document_Row__c row : rows) {
            if (row.Row_Type__c == 'Group Header') {
                levels.add(row.Group_Level__c);
            }
        }
        Assert.isTrue(levels.contains(1) && levels.contains(2),
            'Same two parts on different levels must nest');
    }

    @IsTest
    static void aFieldPathOnTheQuoteYieldsExactlyOneGroup() {
        // Every table is scoped to one quote, so a field on the Quote or its
        // Account has one value across all the lines. It resolves fine - it
        // just cannot discriminate. Worth a test so nobody designs around it.
        QuoteDocumentTableDefinition quoteLevel = QuoteDocumentTableDefinition.build(
            'QUOTE_FIELD_PROBE',
            new List<String>{ 'SBQQ__Quote__r.SBQQ__Account__r.Industry' },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );

        Test.startTest();
        List<Quote_Document_Row__c> rows = new QuoteDocumentRowBuilder(quoteLevel).build(normalizedLines());
        Test.stopTest();

        Integer headers = 0;
        for (Quote_Document_Row__c row : rows) {
            if (row.Row_Type__c == 'Group Header') { headers++; }
        }
        Assert.areEqual(1, headers, 'A quote-level field cannot split the lines of one quote');
    }

    @IsTest
    static void groupsSortByLineSequenceWhenConfigured() {
        // Two products in different families - Service was seeded second
        // (SBQQ__Number__c = 2), but alphabetically "Lifecycle Service" comes
        // after "Lifecycle Product" too, so a plain alphabetical sort would
        // give the same order as a sequence sort here. Flip line numbers on
        // the query results instead of relying on names, so the assertion
        // actually distinguishes the two sort modes.
        QuoteDocumentTableDefinition bySequence = QuoteDocumentTableDefinition.build(
            'SEQUENCE_PROBE',
            new List<String>{ 'SBQQ__Product__r.Family' },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        bySequence.sortGroupsBy = QuoteDocumentTableDefinition.SORT_LINE_SEQUENCE;

        List<QuoteDocumentLine> lines = normalizedLines();
        // Force the Service line to be the earliest-numbered one, so a
        // sequence sort must put its group first even though "Hardware"
        // sorts first alphabetically.
        for (QuoteDocumentLine line : lines) {
            line.sequence = 'Service'.equals(line.productFamily) ? 1 : 2;
        }

        Test.startTest();
        List<Quote_Document_Row__c> rows = new QuoteDocumentRowBuilder(bySequence).build(lines);
        Test.stopTest();

        String firstGroupLabel;
        for (Quote_Document_Row__c row : rows) {
            if (row.Row_Type__c == 'Group Header') {
                firstGroupLabel = row.Display_Label__c;
                break;
            }
        }
        Assert.areEqual('Service', firstGroupLabel,
            'LINE_SEQUENCE must order by the lowest line number in the group, not alphabetically');
    }

    @IsTest
    static void groupsSortAlphabeticallyByDefault() {
        // Same setup as above, but without opting in to LINE_SEQUENCE - the
        // default must stay alphabetical so every existing table definition
        // keeps behaving exactly as it does today.
        QuoteDocumentTableDefinition defaultSort = QuoteDocumentTableDefinition.build(
            'DEFAULT_SORT_PROBE',
            new List<String>{ 'SBQQ__Product__r.Family' },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        Assert.areEqual(QuoteDocumentTableDefinition.SORT_ALPHABETICAL, defaultSort.sortGroupsBy,
            'A definition built without an explicit sort mode must default to alphabetical');

        List<QuoteDocumentLine> lines = normalizedLines();
        for (QuoteDocumentLine line : lines) {
            line.sequence = 'Service'.equals(line.productFamily) ? 1 : 2;
        }

        Test.startTest();
        List<Quote_Document_Row__c> rows = new QuoteDocumentRowBuilder(defaultSort).build(lines);
        Test.stopTest();

        String firstGroupLabel;
        for (Quote_Document_Row__c row : rows) {
            if (row.Row_Type__c == 'Group Header') {
                firstGroupLabel = row.Display_Label__c;
                break;
            }
        }
        Assert.areEqual('Hardware', firstGroupLabel,
            'Without opting in, group order must stay alphabetical even though Service has the lower line number');
    }

    @IsTest
    static void exceedingTheGroupCeilingFailsLoudly() {
        QuoteDocumentTableDefinition tight = QuoteDocumentTableDefinition.build(
            'CEILING_PROBE',
            new List<String>{ 'SBQQ__Product__r.Name' },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        tight.maxGroups = 1;

        Test.startTest();
        try {
            new QuoteDocumentRowBuilder(tight).build(normalizedLines());
            Assert.fail('A runaway grouping must not silently emit a huge table');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('more than 1 groups'),
                'The message should name the ceiling: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void anInvalidFieldPathIsRejectedBeforeTheQueryRuns() {
        QuoteDocumentTableDefinition broken = QuoteDocumentTableDefinition.build(
            'BAD_PATH_PROBE',
            new List<String>{ 'SBQQ__Product__r.Nonexistent__c' },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ broken });

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
            Assert.fail('A typo in a configured path must not reach the database');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('Nonexistent__c'),
                'The message should name the offending segment: ' + e.getMessage());
        }
        Test.stopTest();
    }
}
