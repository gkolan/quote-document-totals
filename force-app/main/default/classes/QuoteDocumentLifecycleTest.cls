/**
 * Covers the pieces around generation rather than generation itself: the
 * readiness gate, stale marking, the per-quote Queueable, the Custom Metadata
 * definitions, and retention.
 *
 * The generation arithmetic is covered by QuoteDocumentGeneratorTest.
 */
@IsTest
private class QuoteDocumentLifecycleTest {

    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Lifecycle Test', Industry = 'Technology');
        insert account;

        Opportunity opportunity = new Opportunity(
            Name = 'Lifecycle Test',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunity;

        // Two products in different families, so grouping tests have something
        // to actually split on.
        List<Product2> products = new List<Product2>{
            new Product2(Name = 'Lifecycle Product', ProductCode = 'LIFECYCLE',
                         Family = 'Hardware', IsActive = true),
            new Product2(Name = 'Lifecycle Service', ProductCode = 'LIFECYCLE-SV',
                         Family = 'Service', IsActive = true)
        };
        insert products;
        Product2 product = products[0];

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Account__c = account.Id,
            SBQQ__Opportunity2__c = opportunity.Id,
            SBQQ__Type__c = 'Quote',
            SBQQ__Status__c = 'Draft'
        );
        insert quote;

        insert new List<SBQQ__QuoteLine__c>{
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quote.Id, SBQQ__Product__c = products[0].Id,
                SBQQ__Number__c = 1, SBQQ__Quantity__c = 2,
                SBQQ__ListPrice__c = 500, SBQQ__RegularPrice__c = 500,
                SBQQ__NetPrice__c = 450, SBQQ__CustomerPrice__c = 450
            ),
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quote.Id, SBQQ__Product__c = products[1].Id,
                SBQQ__Number__c = 2, SBQQ__Quantity__c = 1,
                SBQQ__ListPrice__c = 1200, SBQQ__RegularPrice__c = 1200,
                SBQQ__NetPrice__c = 1200, SBQQ__CustomerPrice__c = 1200
            )
        };
    }

    private static SBQQ__Quote__c quote() {
        return [
            SELECT Id, Name, Document_Data_Status__c, Document_Data_Generated_On__c, Document_Data_Error__c
            FROM SBQQ__Quote__c LIMIT 1
        ];
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

    private static Id quoteId() {
        return quote().Id;
    }

    /**
     * Normalized lines for the seeded quote, ready to hand to a row builder.
     * The field list mirrors the generator's, plus the paths these tests group
     * by - a path that is not queried resolves to Not Specified rather than
     * throwing, which would make the assertions meaningless.
     */
    private static List<QuoteDocumentLine> normalizedLines() {
        SBQQ__Quote__c q = [SELECT Id, AccountIndustry__c FROM SBQQ__Quote__c LIMIT 1];

        List<QuoteDocumentLine> lines = new List<QuoteDocumentLine>();
        for (SBQQ__QuoteLine__c raw : [
            SELECT Id, SBQQ__Number__c, SBQQ__Product__c, SBQQ__ProductName__c, SBQQ__ProductCode__c,
                   SBQQ__Product__r.Family, SBQQ__Product__r.Name, SBQQ__ChargeType__c,
                   SBQQ__Bundle__c, SBQQ__Bundled__c, SBQQ__Optional__c, SBQQ__OptionLevel__c,
                   SBQQ__RequiredBy__c, SBQQ__RequiredBy__r.SBQQ__ProductName__c,
                   SBQQ__Group__c, SBQQ__Group__r.Name, SBQQ__Quantity__c,
                   SBQQ__ListTotal__c, SBQQ__RegularTotal__c, SBQQ__TotalDiscountAmount__c,
                   SBQQ__NetTotal__c, SBQQ__CustomerTotal__c, SBQQ__NetPrice__c,
                   SBQQ__Existing__c, SBQQ__PriorQuantity__c,
                   SBQQ__UpgradedSubscription__c, SBQQ__RenewedSubscription__c,
                   SBQQ__Quote__r.SBQQ__Account__r.Industry
            FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :q.Id
        ]) {
            lines.add(new QuoteDocumentLine(raw, q));
        }
        return lines;
    }

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

    // -----------------------------------------------------------------------
    // Readiness gate
    // -----------------------------------------------------------------------

    @IsTest
    static void generationMarksTheQuoteReady() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quote().Id });
        Test.stopTest();

        SBQQ__Quote__c after = quote();
        Assert.areEqual('Ready', after.Document_Data_Status__c,
            'Only a completed generation may open the document gate');
        Assert.isNotNull(after.Document_Data_Generated_On__c);
        Assert.isNull(after.Document_Data_Error__c);
    }

    @IsTest
    static void editingALineMarksTheQuoteStale() {
        QuoteDocumentGenerator.generate(new Set<Id>{ quote().Id });
        Assert.areEqual('Ready', quote().Document_Data_Status__c, 'Precondition: Ready');

        Test.startTest();
        SBQQ__QuoteLine__c line = [SELECT Id, SBQQ__Quantity__c FROM SBQQ__QuoteLine__c LIMIT 1];
        line.SBQQ__Quantity__c = 5;
        update line;
        Test.stopTest();

        // Test.stopTest() above is what runs the deferred future call.
        Assert.areEqual('Stale', quote().Document_Data_Status__c,
            'A changed line means the generated totals no longer describe the quote');
    }

    @IsTest
    static void deletingALineMarksTheQuoteStale() {
        QuoteDocumentGenerator.generate(new Set<Id>{ quote().Id });

        Test.startTest();
        delete [SELECT Id FROM SBQQ__QuoteLine__c LIMIT 1];
        Test.stopTest();

        Assert.areEqual('Stale', quote().Document_Data_Status__c);
    }

    @IsTest
    static void anUngeneratedQuoteIsNeverMarkedStale() {
        Assert.areEqual('Not Generated', quote().Document_Data_Status__c, 'Precondition');

        Test.startTest();
        SBQQ__QuoteLine__c line = [SELECT Id, SBQQ__Quantity__c FROM SBQQ__QuoteLine__c LIMIT 1];
        line.SBQQ__Quantity__c = 7;
        update line;
        Test.stopTest();

        Assert.areEqual('Not Generated', quote().Document_Data_Status__c,
            'Nothing has been generated, so there is nothing to go stale');
    }

    @IsTest
    static void writingTheStatusDoesNotRetriggerStaleMarking() {
        QuoteDocumentGenerator.generate(new Set<Id>{ quote().Id });

        // Document_Data_Status__c is not a watched field, so this update must
        // not bounce the quote straight back to Stale.
        Test.startTest();
        update new SBQQ__Quote__c(Id = quote().Id, Document_Data_Error__c = 'touched');
        Test.stopTest();

        Assert.areEqual('Ready', quote().Document_Data_Status__c,
            'Only fields that change the generated content should invalidate it');
    }

    // -----------------------------------------------------------------------
    // Async
    // -----------------------------------------------------------------------

    @IsTest
    static void queueableSkipsAQuoteThatIsNoLongerStale() {
        Id quoteId = quote().Id;
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Datetime firstRun = quote().Document_Data_Generated_On__c;

        // Ready, not Stale - so a queued job from an earlier save must exit
        // rather than regenerate. This is what makes duplicate requests free.
        Test.startTest();
        System.enqueueJob(new QuoteDocumentGenerateJob(quoteId));
        Test.stopTest();

        Assert.areEqual(firstRun, quote().Document_Data_Generated_On__c,
            'A non-stale quote should not be regenerated');
    }

    @IsTest
    static void queueableRegeneratesAStaleQuote() {
        Id quoteId = quote().Id;
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        update new SBQQ__Quote__c(Id = quoteId, Document_Data_Status__c = 'Stale');

        Test.startTest();
        System.enqueueJob(new QuoteDocumentGenerateJob(quoteId));
        Test.stopTest();

        Assert.areEqual('Ready', quote().Document_Data_Status__c,
            'A stale quote should be brought back to Ready');
    }

    @IsTest
    static void generateAsyncBackfillsAQuoteThatWasNeverGenerated() {
        Id quoteId = quote().Id;
        Assert.areEqual('Not Generated', quote().Document_Data_Status__c, 'Precondition');

        // A backfill must not skip quotes just because they are not Stale -
        // "never generated" is precisely the case it exists to handle.
        Test.startTest();
        QuoteDocumentGenerator.generateAsync(new Set<Id>{ quoteId });
        Test.stopTest();

        Assert.areEqual('Ready', quote().Document_Data_Status__c,
            'A backfill should generate unconditionally');
        Assert.isTrue([SELECT COUNT() FROM Quote_Document_Table__c] > 0);
    }

    // -----------------------------------------------------------------------
    // Flow entry point
    // -----------------------------------------------------------------------

    @IsTest
    static void invocableReturnsCountsForTheConfirmationScreen() {
        QuoteDocumentGenerator.Request request = new QuoteDocumentGenerator.Request();
        request.quoteId = quote().Id;

        Test.startTest();
        List<QuoteDocumentGenerator.Result> results =
            QuoteDocumentGenerator.generateFromFlow(new List<QuoteDocumentGenerator.Request>{ request });
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.isTrue(results[0].success, results[0].message);
        Assert.isTrue(results[0].tableCount > 0, 'The screen should be able to state a table count');
        Assert.isTrue(results[0].rowCount > 0, 'The screen should be able to state a row count');
        Assert.isTrue(results[0].message.contains('ready'), 'The message should be usable as-is');
    }

    @IsTest
    static void invocableReportsFailureRatherThanThrowing() {
        QuoteDocumentGenerator.Request request = new QuoteDocumentGenerator.Request();
        request.quoteId = null;

        Test.startTest();
        List<QuoteDocumentGenerator.Result> results =
            QuoteDocumentGenerator.generateFromFlow(new List<QuoteDocumentGenerator.Request>{ request });
        Test.stopTest();

        // A flow should show the user an error screen, not an unhandled fault.
        Assert.isFalse(results[0].success);
        Assert.isNotNull(results[0].message);
    }

    // -----------------------------------------------------------------------
    // Retention
    // -----------------------------------------------------------------------

    @IsTest
    static void retentionPurgesRejectedQuotesAndResetsTheGate() {
        Id quoteId = quote().Id;
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Assert.isTrue([SELECT COUNT() FROM Quote_Document_Table__c] > 0, 'Precondition: tables exist');

        update new SBQQ__Quote__c(Id = quoteId, SBQQ__Status__c = 'Rejected');

        Test.startTest();
        Database.executeBatch(new QuoteDocumentRetention(), 200);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Quote_Document_Table__c],
            'A rejected quote will never produce a document');
        Assert.areEqual(0, [SELECT COUNT() FROM Quote_Document_Row__c],
            'Rows go with their table through the master-detail cascade');
        Assert.areEqual('Not Generated', quote().Document_Data_Status__c,
            'The gate must close when the data behind it is gone');
    }

    @IsTest
    static void retentionLeavesAnAcceptedQuoteAlone() {
        Id quoteId = quote().Id;
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });

        update new SBQQ__Quote__c(Id = quoteId, SBQQ__Status__c = 'Accepted');
        QuoteDocumentRetention.retentionDays = 0; // everything is past the window

        Test.startTest();
        Database.executeBatch(new QuoteDocumentRetention(), 200);
        Test.stopTest();

        Assert.isTrue([SELECT COUNT() FROM Quote_Document_Table__c] > 0,
            'An accepted quote may sit behind a signed document - never purge it automatically');
    }

    /**
     * Every other retention test calls Database.executeBatch directly against
     * a new QuoteDocumentRetention() - correct for proving the batch logic,
     * but it never actually exercises the Schedulable.execute entry point
     * System.schedule() calls. The batch behavior itself is already proven by
     * the two tests above; this one exists only to cover that entry point.
     */
    @IsTest
    static void scheduledExecuteEnqueuesTheRetentionBatch() {
        Test.startTest();
        new QuoteDocumentRetention().execute(null);
        Test.stopTest();

        Assert.isTrue(true, 'Scheduling the retention batch must not throw');
    }

    // -----------------------------------------------------------------------
    // Request ownership
    // -----------------------------------------------------------------------

    @IsTest
    static void generatingIsAWritableRestrictedPicklistValue() {
        Id quoteId = quote().Id;

        Test.startTest();
        update new SBQQ__Quote__c(Id = quoteId, Document_Data_Status__c = 'Generating');
        Test.stopTest();

        Assert.areEqual('Generating', quote().Document_Data_Status__c,
            'Generating must be a real value in the restricted picklist, not just documentation');
    }

    // -----------------------------------------------------------------------
    // Staleness - branches not reached by the trigger-driven tests above
    // -----------------------------------------------------------------------

    /**
     * Every trigger-driven staleness test above supplies a real prior version
     * (Salesforce always does, in a genuine update trigger). Calling
     * markStaleFromQuotes directly with a prior map that is deliberately
     * missing an entry proves the "nothing to compare against, so skip rather
     * than guess" branch without needing a contrived trigger scenario.
     */
    @IsTest
    static void markStaleFromQuotesSkipsAQuoteWithNoPriorVersion() {
        Id qId = quote().Id;
        SBQQ__Quote__c updated = new SBQQ__Quote__c(Id = qId);
        Map<Id, SBQQ__Quote__c> priorById = new Map<Id, SBQQ__Quote__c>();

        Test.startTest();
        QuoteDocumentStaleness.markStaleFromQuotes(new List<SBQQ__Quote__c>{ updated }, priorById);
        Test.stopTest();

        Assert.areNotEqual('Stale', quote().Document_Data_Status__c,
            'With no prior version to compare against, the quote must be skipped, not guessed at');
    }

    private class MarkStaleFromQueueable implements Queueable {
        private Id quoteId;
        MarkStaleFromQueueable(Id quoteId) { this.quoteId = quoteId; }
        public void execute(QueueableContext context) {
            QuoteDocumentStaleness.markStale(new Set<Id>{ quoteId });
        }
    }

    /**
     * canDefer() is false inside any async context (Queueable included) -
     * Apex does not allow a @future call from inside another async context,
     * so markStale must apply the write inline there rather than deferring.
     * Every other staleness test runs from a synchronous trigger context and
     * so only ever exercises the deferred branch; this proves the other one.
     */
    @IsTest
    static void markStaleAppliesSynchronouslyWhenCalledFromAnAsyncContext() {
        Id qId = quote().Id;
        update new SBQQ__Quote__c(Id = qId, Document_Data_Status__c = 'Ready');

        Test.startTest();
        System.enqueueJob(new MarkStaleFromQueueable(qId));
        Test.stopTest();

        Assert.areEqual('Stale', quote().Document_Data_Status__c,
            'Inside an async context the write must happen inline - a future call cannot be queued from here');
    }
}
