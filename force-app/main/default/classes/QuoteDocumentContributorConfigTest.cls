/**
 * Step 01A sections 6 and 6a - the declarations a contributor must make
 * before it is allowed to run, and the fingerprint tokens that make changed
 * contributor logic visible to reuse.
 *
 * The fingerprint half is the one that matters most. canReuse() returns
 * BEFORE customization, so without these tokens a changed customizer or an
 * edited Flow leaves the fingerprint identical and generation reuses a
 * snapshot the new logic would never have produced - a wrong document, not a
 * hygiene problem.
 */
@IsTest
private class QuoteDocumentContributorConfigTest {

    private static QuoteDocumentTableDefinition definition() {
        return QuoteDocumentTableDefinition.build(
            'CONFIG_TEST',
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
    }

    private static String fingerprintOf(QuoteDocumentTableDefinition definition) {
        return QuoteDocumentFingerprint.canonicalize(
            new SBQQ__Quote__c(),
            new List<QuoteDocumentLine>(),
            new List<QuoteDocumentTableDefinition>{ definition }
        );
    }

    // -----------------------------------------------------------------------
    // Fingerprint - the correctness fix
    // -----------------------------------------------------------------------

    @IsTest
    static void bumpingTheApexCustomizerVersionChangesTheFingerprint() {
        QuoteDocumentTableDefinition before = definition();
        before.rowCustomizerCode = 'DISCOUNT_EXAMPLE';
        before.rowCustomizerVersion = '1';
        before.cachePolicy = QuoteDocumentTableDefinition.CACHE_STANDARD;

        QuoteDocumentTableDefinition after = definition();
        after.rowCustomizerCode = 'DISCOUNT_EXAMPLE';
        after.rowCustomizerVersion = '2';
        after.cachePolicy = QuoteDocumentTableDefinition.CACHE_STANDARD;

        Assert.areNotEqual(
            fingerprintOf(before),
            fingerprintOf(after),
            'Bumping Row_Customizer_Version__c must move the fingerprint. It is the only signal that '
                + 'deployed customizer Apex changed - the platform cannot see an Apex body change.'
        );
    }

    @IsTest
    static void bumpingTheFlowVersionChangesTheFingerprint() {
        QuoteDocumentTableDefinition before = definition();
        before.rowCustomizerFlow = 'SomeContributorFlow';
        before.rowCustomizerFlowVersion = '1';
        before.cachePolicy = QuoteDocumentTableDefinition.CACHE_STANDARD;

        QuoteDocumentTableDefinition after = definition();
        after.rowCustomizerFlow = 'SomeContributorFlow';
        after.rowCustomizerFlowVersion = '2';
        after.cachePolicy = QuoteDocumentTableDefinition.CACHE_STANDARD;

        Assert.areNotEqual(
            fingerprintOf(before),
            fingerprintOf(after),
            'Editing a Flow does not change its API name, so without this token the change is invisible.'
        );
    }

    /**
     * The documented hazard, pinned deliberately. Leaving the token alone
     * after deploying changed logic REUSES - that is the failure mode the
     * field help text and the release checklist exist to prevent, and a test
     * that asserts it is how the hazard stays visible instead of becoming
     * folklore.
     */
    @IsTest
    static void leavingTheVersionUnchangedReusesEvenIfTheLogicChanged() {
        QuoteDocumentTableDefinition before = definition();
        before.rowCustomizerCode = 'DISCOUNT_EXAMPLE';
        before.rowCustomizerVersion = '1';
        before.cachePolicy = QuoteDocumentTableDefinition.CACHE_STANDARD;

        QuoteDocumentTableDefinition after = definition();
        after.rowCustomizerCode = 'DISCOUNT_EXAMPLE';
        after.rowCustomizerVersion = '1';
        after.cachePolicy = QuoteDocumentTableDefinition.CACHE_STANDARD;

        Assert.areEqual(
            fingerprintOf(before),
            fingerprintOf(after),
            'This is the hazard, not a bug: identical tokens produce an identical fingerprint whatever the '
                + 'Apex behind the code now does. Bumping the token is an operational discipline core can '
                + 'only make possible, never enforce.'
        );
    }

    @IsTest
    static void changingTheCachePolicyChangesTheFingerprint() {
        QuoteDocumentTableDefinition before = definition();
        before.rowCustomizerCode = 'DISCOUNT_EXAMPLE';
        before.rowCustomizerVersion = '1';
        before.cachePolicy = QuoteDocumentTableDefinition.CACHE_STANDARD;

        QuoteDocumentTableDefinition after = definition();
        after.rowCustomizerCode = 'DISCOUNT_EXAMPLE';
        after.rowCustomizerVersion = '1';
        after.cachePolicy = QuoteDocumentTableDefinition.CACHE_ALWAYS_REBUILD;

        Assert.areNotEqual(
            fingerprintOf(before),
            fingerprintOf(after),
            'The policy decides whether reuse is legal at all, so changing it must regenerate rather than '
                + 'wait for an unrelated edit to move the hash.'
        );
    }

    @IsTest
    static void changingADeclaredDependencyPathChangesTheFingerprint() {
        QuoteDocumentTableDefinition before = definition();
        before.rowCustomizerCode = 'DISCOUNT_EXAMPLE';
        before.rowCustomizerVersion = '1';
        before.cachePolicy = QuoteDocumentTableDefinition.CACHE_DECLARED_DEPENDENCIES;
        before.contributorDependencyPaths = new List<String>{ 'SBQQ__Account__r.Industry' };

        QuoteDocumentTableDefinition after = definition();
        after.rowCustomizerCode = 'DISCOUNT_EXAMPLE';
        after.rowCustomizerVersion = '1';
        after.cachePolicy = QuoteDocumentTableDefinition.CACHE_DECLARED_DEPENDENCIES;
        after.contributorDependencyPaths = new List<String>{ 'SBQQ__Account__r.Type' };

        Assert.areNotEqual(
            fingerprintOf(before),
            fingerprintOf(after),
            'Declaring a different dependency is a different generation plan.'
        );
    }

    // -----------------------------------------------------------------------
    // Helpers on the definition itself
    // -----------------------------------------------------------------------

    @IsTest
    static void alwaysRebuildIsRecognised() {
        QuoteDocumentTableDefinition definition = definition();
        definition.rowCustomizerCode = 'DISCOUNT_EXAMPLE';
        definition.cachePolicy = QuoteDocumentTableDefinition.CACHE_ALWAYS_REBUILD;

        Assert.isTrue(definition.alwaysRebuilds(), 'ALWAYS_REBUILD must be recognised.');
        Assert.isTrue(definition.hasContributor(), 'A table with a customizer code has a contributor.');
    }

    @IsTest
    static void aTableWithNoContributorNeedsNoDeclarations() {
        QuoteDocumentTableDefinition definition = definition();

        Assert.isFalse(definition.hasContributor(), 'A plain declarative table has no contributor.');
        Assert.isFalse(definition.alwaysRebuilds(), 'No policy means no forced rebuild.');
    }

    @IsTest
    static void aFlowOnlyTableStillCountsAsHavingAContributor() {
        QuoteDocumentTableDefinition definition = definition();
        definition.rowCustomizerFlow = 'SomeContributorFlow';

        Assert.isTrue(
            definition.hasContributor(),
            'A Flow contributor is a contributor - it must be held to the same declarations as Apex.'
        );
    }
}
