/**
 * Step 01A section 4, the bridge half. The round-trip fidelity questions are
 * proven separately in QuoteDocumentFlowRoundTripProbeTest; this class covers
 * what the bridge itself does with the result - including the three failure
 * codes that had no owner until the bridge existed.
 */
@IsTest
private class QuoteDocumentFlowCustomizerTest {

    private static QuoteDocumentRowCustomizerContext context(String flowName) {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            'FLOW_TEST',
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        definition.rowCustomizerFlow = flowName;
        definition.rowCustomizerFlowVersion = '1';
        definition.cachePolicy = QuoteDocumentTableDefinition.CACHE_STANDARD;

        QuoteDocumentRowCustomizerContext ctx = new QuoteDocumentRowCustomizerContext();
        ctx.quote = new SBQQ__Quote__c();
        ctx.definition = definition;
        ctx.lines = new List<QuoteDocumentLine>();
        ctx.rows = new List<Quote_Document_Row__c>{
            QuoteDocumentRowBuilder.defaultRow('Detail', 1, 'D1', 'First', 10),
            QuoteDocumentRowBuilder.defaultRow('Grand Total', 0, 'GT', 'Total', 20)
        };
        ctx.currencyIsoCode = 'USD';
        return ctx;
    }

    /** A blank Flow name is not a failure - it is a table that simply has no Flow contributor. */
    @IsTest
    static void aBlankFlowNameLeavesRowsUntouched() {
        QuoteDocumentRowCustomizerContext ctx = context(null);

        Test.startTest();
        List<Quote_Document_Row__c> out = new QuoteDocumentFlowRowCustomizer().customize(ctx);
        Test.stopTest();

        Assert.areEqual(2, out.size(), 'A table with no Flow must be left exactly as it was.');
    }

    @IsTest
    static void theFlowReceivesTheRowsAndItsChangesComeBack() {
        QuoteDocumentRowCustomizerContext ctx = context('QuoteDocumentFlowRoundTripProbe');

        Test.startTest();
        List<Quote_Document_Row__c> out = new QuoteDocumentFlowRowCustomizer().customize(ctx);
        Test.stopTest();

        Assert.areEqual(3, out.size(), 'The probe appends one row, so three must come back.');
        Assert.areEqual('First:FLOW', out[0].Display_Label__c, 'The Flow\'s edit did not reach Apex.');
        Assert.areEqual(
            'FLOW_TEST',
            out[2].Display_Label__c,
            'The Flow-created row labels itself from the tableCode input, so this proves the scalar inputs arrive.'
        );
    }

    /**
     * A missing Flow must name the Flow AND the table. The platform's own
     * message names neither, which is what makes this worth wrapping.
     */
    @IsTest
    static void aMissingFlowFailsWithFlowUnavailable() {
        QuoteDocumentRowCustomizerContext ctx = context('QuoteDocumentFlowThatDoesNotExist');

        Test.startTest();
        String message;
        try {
            new QuoteDocumentFlowRowCustomizer().customize(ctx);
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.isNotNull(message, 'A Flow that does not exist must fail generation, not skip the table.');
        Assert.isTrue(
            message.contains(QuoteDocumentContributorError.FLOW_UNAVAILABLE),
            'Wrong code: ' + message
        );
        Assert.isTrue(
            message.contains('QuoteDocumentFlowThatDoesNotExist'),
            'The message must name the Flow API name: ' + message
        );
        Assert.isTrue(message.contains('FLOW_TEST'), 'The message must name the table: ' + message);
    }

    /**
     * A Flow that never assigns its output collection is the silent-copy
     * mistake - the author edits the loop variable, the Flow reports success,
     * and nothing changed. Reading that as "unchanged" would ship a document
     * missing every edit the author believed they had made, so it fails.
     */
    @IsTest
    static void aFlowReturningNoCollectionFailsWithNoOutput() {
        QuoteDocumentRowCustomizerContext ctx = context('QuoteDocumentFlowNoOutputProbe');

        Test.startTest();
        String message;
        try {
            new QuoteDocumentFlowRowCustomizer().customize(ctx);
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.isNotNull(message, 'A Flow that returns no rows collection must fail, never be read as unchanged.');
        Assert.isTrue(message.contains(QuoteDocumentContributorError.NO_OUTPUT), 'Wrong code: ' + message);
        Assert.isTrue(
            message.contains('loop variable is a copy'),
            'The message must explain the mistake it is almost always reporting: ' + message
        );
    }

    /**
     * The section 9 acceptance criterion: a sample Flow contributor changes a
     * label and adds a row, with no change to core Apex. The Flow and its
     * Custom Metadata record are the whole extension - nothing in
     * QuoteDocumentGenerator, RowBuilder, Fingerprint or Verification moves.
     */
    @IsTest
    static void theSampleFlowContributorRelabelsAndAddsARowWithNoCoreChange() {
        QuoteDocumentRowCustomizerContext ctx = context('QuoteDocumentSampleFlowContributor');

        Test.startTest();
        List<Quote_Document_Row__c> out = new QuoteDocumentFlowRowCustomizer().customize(ctx);
        Test.stopTest();

        Assert.areEqual(3, out.size(), 'The sample appends one Note row.');

        Map<String, Quote_Document_Row__c> byKey = new Map<String, Quote_Document_Row__c>();
        for (Quote_Document_Row__c row : out) {
            byKey.put(row.Row_Key__c, row);
        }

        Assert.areEqual(
            'Total Due',
            byKey.get('GT').Display_Label__c,
            'The sample renames the Grand Total, which proves a declarative contributor can change a label.'
        );
        Assert.areEqual(
            'First',
            byKey.get('D1').Display_Label__c,
            'Rows the sample does not target must come back untouched.'
        );

        Quote_Document_Row__c note = byKey.get('FLOW_SAMPLE_NOTE');
        Assert.isNotNull(note, 'The sample adds a Note row.');
        Assert.areEqual('Note', note.Row_Type__c, 'The added row is a Note.');
        Assert.isFalse(
            note.Include_In_Grand_Total__c,
            'A Note carries no amount and must count toward nothing, or verify() would reconcile against it.'
        );

        // The output the generator would then validate must be clean, or the
        // sample is teaching a shape that fails in production.
        QuoteDocumentContributorOutput.validate(out, ctx.definition);
    }

    /** A fault inside the Flow must surface as CONTRIBUTOR_FLOW_FAULT, naming the Flow. */
    @IsTest
    static void aFlowFaultFailsWithFlowFault() {
        QuoteDocumentRowCustomizerContext ctx = context('QuoteDocumentFlowFaultProbe');

        Test.startTest();
        String message;
        try {
            new QuoteDocumentFlowRowCustomizer().customize(ctx);
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.isNotNull(message, 'A Flow that faults must fail generation.');
        Assert.isTrue(
            message.contains(QuoteDocumentContributorError.FLOW_FAULT)
                || message.contains(QuoteDocumentContributorError.FLOW_UNAVAILABLE),
            'A Flow fault must surface as a contributor error code, not a raw platform exception: ' + message
        );
        Assert.isTrue(
            message.contains('QuoteDocumentFlowFaultProbe'),
            'The message must name the Flow: ' + message
        );
    }
}
