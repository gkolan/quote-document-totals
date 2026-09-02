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

    /**
     * The other half of section 6a, and the one a version token cannot cover:
     * the contributor's LOGIC did not change, the DATA it reads did. Nothing
     * in this framework watches an Account field, so without hashing the
     * declared value the fingerprint would match and the document would keep
     * printing the old tier.
     */
    @IsTest
    static void changingADeclaredDependencyVALUEChangesTheFingerprint() {
        QuoteDocumentTableDefinition definition = definition();
        definition.rowCustomizerCode = 'DISCOUNT_EXAMPLE';
        definition.rowCustomizerVersion = '1';
        definition.cachePolicy = QuoteDocumentTableDefinition.CACHE_DECLARED_DEPENDENCIES;
        // Any writeable field serves: this tests the hashing mechanism, not
        // the semantics of a particular dependency. AccountIndustry__c would
        // read better but is a formula and cannot be set in a test.
        definition.contributorDependencyPaths = new List<String>{ 'Document_Data_Status__c' };

        List<QuoteDocumentTableDefinition> plan = new List<QuoteDocumentTableDefinition>{ definition };

        String before = QuoteDocumentFingerprint.canonicalize(
            new SBQQ__Quote__c(Document_Data_Status__c = 'Ready'), new List<QuoteDocumentLine>(), plan
        );
        String after = QuoteDocumentFingerprint.canonicalize(
            new SBQQ__Quote__c(Document_Data_Status__c = 'Stale'), new List<QuoteDocumentLine>(), plan
        );

        Assert.areNotEqual(
            before,
            after,
            'A declared dependency whose VALUE changed must move the fingerprint. The contributor code is '
                + 'identical, so the version token cannot help here - only the hashed value can.'
        );
    }

    /**
     * The same path under STANDARD is NOT hashed, which is the whole reason
     * reading undeclared external data under STANDARD is prohibited: the
     * framework genuinely cannot see it, and the document goes stale silently.
     * Pinned so the prohibition stays a fact rather than advice.
     */
    @IsTest
    static void aDependencyValueIsNotHashedUnderStandard() {
        QuoteDocumentTableDefinition definition = definition();
        definition.rowCustomizerCode = 'DISCOUNT_EXAMPLE';
        definition.rowCustomizerVersion = '1';
        definition.cachePolicy = QuoteDocumentTableDefinition.CACHE_STANDARD;

        List<QuoteDocumentTableDefinition> plan = new List<QuoteDocumentTableDefinition>{ definition };

        String before = QuoteDocumentFingerprint.canonicalize(
            new SBQQ__Quote__c(Document_Data_Status__c = 'Ready'), new List<QuoteDocumentLine>(), plan
        );
        String after = QuoteDocumentFingerprint.canonicalize(
            new SBQQ__Quote__c(Document_Data_Status__c = 'Stale'), new List<QuoteDocumentLine>(), plan
        );

        Assert.areEqual(
            before,
            after,
            'Under STANDARD nothing external is hashed. This is the hazard the policy exists to make '
                + 'someone choose deliberately, not a defect.'
        );
    }

    // -----------------------------------------------------------------------
    // Step 05 - the inputs steps 01 to 04 added
    // -----------------------------------------------------------------------

    /**
     * Without this, a translation fix would leave every existing snapshot
     * claiming to be current while printing the old wording.
     */
    @IsTest
    static void localeIsPartOfTheFingerprint() {
        List<QuoteDocumentTableDefinition> plan = new List<QuoteDocumentTableDefinition>{ definition() };
        SBQQ__Quote__c quote = new SBQQ__Quote__c();

        QuoteDocumentLocale.overrideLocale = 'en_US';
        String english = QuoteDocumentFingerprint.canonicalize(quote, new List<QuoteDocumentLine>(), plan);

        QuoteDocumentLocale.overrideLocale = 'fr';
        String french = QuoteDocumentFingerprint.canonicalize(quote, new List<QuoteDocumentLine>(), plan);
        QuoteDocumentLocale.overrideLocale = null;

        Assert.areNotEqual(
            english,
            french,
            'Two locales are two different documents. Reusing one for the other would print the wrong '
                + 'language while reporting Ready.'
        );
    }

    @IsTest
    static void columnDefinitionsArePartOfTheFingerprint() {
        QuoteDocumentTableDefinition before = definition();
        before.measureSet = QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL;

        QuoteDocumentTableDefinition after = definition();
        after.measureSet = QuoteDocumentTableDefinition.MEASURES_CHANGE;

        Assert.areNotEqual(
            fingerprintOf(before),
            fingerprintOf(after),
            'A different measure set produces a different default column set, and therefore a different '
                + 'printed table. The hash has to see that.'
        );
    }

    /** A quote regenerated twice with nothing changed must hash identically. */
    @IsTest
    static void twoGenerationsOfAnUnchangedQuoteMatch() {
        List<QuoteDocumentTableDefinition> plan = new List<QuoteDocumentTableDefinition>{ definition() };
        SBQQ__Quote__c quote = new SBQQ__Quote__c();

        Assert.areEqual(
            QuoteDocumentFingerprint.canonicalize(quote, new List<QuoteDocumentLine>(), plan),
            QuoteDocumentFingerprint.canonicalize(quote, new List<QuoteDocumentLine>(), plan),
            'Determinism is the property everything else rests on. If this drifts, every quote regenerates '
                + 'every time and nobody notices until the limits bite.'
        );
    }

    /**
     * The content version is one global value bumped whenever dictionary or
     * clause text changes. An org that never sets it still hashes
     * deterministically.
     */
    @IsTest
    static void anUnsetContentVersionStillHashesDeterministically() {
        Assert.areEqual(
            'UNVERSIONED',
            QuoteDocumentFingerprint.contentVersion(),
            'Absent must encode as a stable literal, not as null, or an org that has not adopted content '
                + 'versioning gets a different hash depending on how null happens to encode.'
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
