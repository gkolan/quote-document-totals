/**
 * Reproductions for the review findings of 2026-08-27.
 *
 * Every test here was written to FAIL on the code as it stood, so that the
 * fix is demonstrated rather than asserted. Three of these findings were
 * tests that already existed and passed for the wrong reason, which is the
 * failure mode this file exists to make impossible to repeat.
 *
 * Kept as its own class rather than folded into the suites it corrects, so
 * the reproductions stay findable next to the defects they name.
 */
@IsTest
private class QuoteDocumentReviewFindingsTest {

    @TestSetup
    static void setup() {
        QuoteDocumentTestData.setup();
    }

    private static QuoteDocumentTableDefinition definition() {
        return QuoteDocumentTableDefinition.build(
            'FINDING_TEST',
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
    // Finding 1 - table text edits could reuse a stale document
    // -----------------------------------------------------------------------

    /**
     * The presentation fields are what the customer READS. Leaving them out of
     * the fingerprint meant an admin could correct a heading, a subtitle, a
     * disclaimer or a footer, regenerate, and get the old wording back with
     * the quote still reporting Ready.
     *
     * This is the same class of defect the contributor version tokens exist to
     * prevent, and it was introduced in the same step that added the fields.
     */
    @IsTest
    static void editingAnyPresentationFieldChangesTheFingerprint() {
        Map<String, String> edits = new Map<String, String>{
            'displayTitle' => 'A corrected heading',
            'displaySubtitle' => 'A corrected subtitle',
            'introText' => 'A corrected disclaimer',
            'footerText' => 'A corrected footer'
        };

        for (String field : edits.keySet()) {
            QuoteDocumentTableDefinition before = definition();
            before.displayTitle = 'Original';
            before.displaySubtitle = 'Original';
            before.introText = 'Original';
            before.footerText = 'Original';

            QuoteDocumentTableDefinition after = definition();
            after.displayTitle = 'Original';
            after.displaySubtitle = 'Original';
            after.introText = 'Original';
            after.footerText = 'Original';

            if (field == 'displayTitle') {
                after.displayTitle = edits.get(field);
            } else if (field == 'displaySubtitle') {
                after.displaySubtitle = edits.get(field);
            } else if (field == 'introText') {
                after.introText = edits.get(field);
            } else {
                after.footerText = edits.get(field);
            }

            Assert.areNotEqual(
                fingerprintOf(before),
                fingerprintOf(after),
                'Editing ' + field + ' must force a rebuild. It is text the customer reads, so leaving it '
                    + 'out of the fingerprint means an admin corrects the wording, regenerates, and gets '
                    + 'the old wording back with the quote still reporting Ready.'
            );
        }
    }

    // -----------------------------------------------------------------------
    // Finding 3 - bulk query count, for DISTINCT quotes
    // -----------------------------------------------------------------------

    /**
     * The existing flat-query-count test requested the SAME quote three times,
     * so the per-quote integrity cache made it pass while the underlying cost
     * still scaled. This one uses three DIFFERENT quotes, which is the case
     * that actually occurs in a batch.
     */
    @IsTest
    static void queryCountIsFlatAcrossDISTINCTQuotes() {
        List<SBQQ__Quote__c> quotes = QuoteDocumentTestData.extraQuotes(2);
        Id first = QuoteDocumentTestData.quoteId();

        Test.startTest();
        List<Id> allIds = new List<Id>{ first, quotes[0].Id, quotes[1].Id };
        QuoteDocumentGenerator.generate(new Set<Id>(allIds));

        Map<Id, SBQQ__Quote__c> stamped = new Map<Id, SBQQ__Quote__c>([
            SELECT Id, Document_Data_Request_Id__c, Document_Data_Fingerprint__c
            FROM SBQQ__Quote__c WHERE Id IN :allIds
        ]);

        List<QuoteDocumentPayload.PayloadRequest> one =
            new List<QuoteDocumentPayload.PayloadRequest>{ requestFor(stamped.get(first)) };
        List<QuoteDocumentPayload.PayloadRequest> three =
            new List<QuoteDocumentPayload.PayloadRequest>();
        for (Id quoteId : allIds) {
            three.add(requestFor(stamped.get(quoteId)));
        }

        Integer before = Limits.getQueries();
        QuoteDocumentRenderService.getPayloads(one);
        Integer forOne = Limits.getQueries() - before;

        before = Limits.getQueries();
        QuoteDocumentRenderService.getPayloads(three);
        Integer forThree = Limits.getQueries() - before;
        Test.stopTest();

        Assert.areEqual(
            forOne,
            forThree,
            'Three DIFFERENT quotes must cost the same queries as one. The previous version of this test '
                + 'passed the same quote three times, so the per-quote cache hid the fact that integrity '
                + 'verification still ran four queries per quote. Observed ' + forOne + ' vs ' + forThree
        );
    }

    private static QuoteDocumentPayload.PayloadRequest requestFor(SBQQ__Quote__c quote) {
        return new QuoteDocumentPayload.PayloadRequest(
            quote.Id, quote.Document_Data_Request_Id__c, quote.Document_Data_Fingerprint__c
        );
    }

    // -----------------------------------------------------------------------
    // Finding 4 - integrity hashing missed subscriber-added column values
    // -----------------------------------------------------------------------

    /**
     * Rendering selects configured bindings dynamically; hashing used a fixed
     * list. So a column bound to a field outside that list could be edited
     * after publication, change what prints, and leave the integrity hash
     * identical - the exact hole the payload hash exists to close.
     *
     * Group_Key__c stands in for a subscriber field: the hash cannot tell core
     * fields from subscriber fields, which is what makes this a valid proxy.
     */
    @IsTest
    static void tamperingWithABoundFieldOutsideTheFixedListIsDetected() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });

        Quote_Document_Table__c table = [
            SELECT Id FROM Quote_Document_Table__c WHERE Quote__c = :quoteId LIMIT 1
        ];
        // A column bound to a field the hash's fixed list never mentioned.
        insert new Quote_Document_Column__c(
            Quote_Document_Table__c = table.Id,
            Column_Code__c = 'COL_SUBSCRIBER',
            Display_Label__c = 'Subscriber Field',
            Display_Order__c = 900,
            Value_Field__c = 'Group_Key__c',
            Data_Type__c = 'Text',
            Is_Displayed__c = true
        );
        String baseline = QuoteDocumentPayloadHash.compute(quoteId);

        Quote_Document_Row__c row = [
            SELECT Id, Group_Key__c FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__c = :table.Id LIMIT 1
        ];
        row.Group_Key__c = 'TAMPERED';
        Database.update(row, true, AccessLevel.SYSTEM_MODE);
        Test.stopTest();

        Assert.areNotEqual(
            baseline,
            QuoteDocumentPayloadHash.compute(quoteId),
            'A value that PRINTS must be hashed. Rendering selects configured bindings dynamically, so a '
                + 'hash using a fixed field list lets a subscriber column be edited after publication, '
                + 'change the document, and leave the integrity hash identical.'
        );
    }

    // -----------------------------------------------------------------------
    // Finding 5 - locale contradicted its own documented contract
    // -----------------------------------------------------------------------

    /**
     * QuoteDocumentLocale's class comment says the locale is "DELIBERATELY NOT
     * the running user's locale", because that would make the snapshot depend
     * on who clicked generate and break deterministic replay.
     *
     * `orgDefault()` returned `UserInfo.getLocale()` - the running user's
     * locale. The comment and the code said opposite things, and the code won.
     *
     * WHY THIS IS NOT A `System.runAs` TEST, THOUGH IT SHOULD BE.
     * Custom Metadata SOQL with a bind variable throws inside `System.runAs`
     * ("Variable does not exist: tmpVar1"), and the resolver reads its
     * configuration from Custom Metadata. That is a platform limitation, not a
     * property of this code - verified with a standalone probe before writing
     * it off. So the two-user scenario is established as REAL (the users do
     * have different platform locales), and the independence is pinned two
     * other ways: the resolver is deterministic across calls, and its source
     * no longer reads the running user's locale at all.
     *
     * The source assertion is the one that actually guards the defect. It
     * cannot be satisfied by anything except removing the dependency.
     */
    @IsTest
    static void theDefaultLocaleDoesNotDependOnWhoIsRunning() {
        QuoteDocumentLocale.overrideLocale = null;

        String runningUserLocale = UserInfo.getLocale();
        User other = buildUserWithLocale('de_DE');
        insert other;

        String otherUserLocale;
        System.runAs(other) {
            // Reads no Custom Metadata, so this is safe under runAs.
            otherUserLocale = UserInfo.getLocale();
        }

        Assert.areNotEqual(
            runningUserLocale,
            otherUserLocale,
            'The scenario has to be real: if both users had the same platform locale, a resolver that '
                + 'depended on it would look correct.'
        );

        String first = QuoteDocumentLocale.orgDefault();
        String second = QuoteDocumentLocale.orgDefault();
        Assert.areEqual(first, second, 'The default must be deterministic.');
        Assert.isTrue(String.isNotBlank(first), 'There must be a default at all.');

        ApexClass resolver = [
            SELECT Body FROM ApexClass WHERE Name = 'QuoteDocumentLocale' LIMIT 1
        ];
        // Comments stripped first. The class comment legitimately NAMES the
        // thing it must not do - an assertion that matched its own
        // documentation would fail forever and teach the next person to delete
        // the explanation rather than keep the guarantee.
        Assert.isFalse(
            withoutComments(resolver.Body).contains('UserInfo.getLocale'),
            'QuoteDocumentLocale must not read the running user\'s locale. Two sales users with '
                + 'different personal settings would otherwise generate two different documents from the '
                + 'same quote, and deterministic replay - which the fingerprint, the payload hash and the '
                + 'whole reuse decision rest on - would silently not hold.'
        );
    }

    /**
     * Comment lines removed, so a source assertion checks CODE rather than
     * prose.
     *
     * A line scan rather than a regex: the class comment legitimately NAMES
     * the thing the code must not do, and an assertion that matched its own
     * documentation would fail forever - teaching the next person to delete
     * the explanation rather than keep the guarantee.
     */
    private static String withoutComments(String body) {
        List<String> kept = new List<String>();
        for (String line : body.split('\n')) {
            String trimmed = line.trim();
            if (trimmed.startsWith('//') || trimmed.startsWith('*') || trimmed.startsWith('/*')) {
                continue;
            }
            kept.add(line);
        }
        return String.join(kept, ' ');
    }

    /** Built, not inserted - the caller decides, because some tests need the record and some do not. */
    private static User buildUserWithLocale(String localeKey) {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String unique = 'qdlocale' + String.valueOf(Datetime.now().getTime()).right(8);
        return new User(
            FirstName = 'Locale',
            LastName = 'Probe',
            Alias = 'locp',
            Email = unique + '@example.com',
            Username = unique + '@example.com.qdtest',
            ProfileId = standard.Id,
            TimeZoneSidKey = 'GMT',
            LocaleSidKey = localeKey,
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    /**
     * A configured locale field path must be QUERIED, or it silently resolves
     * to nothing and every quote falls back to the default - which looks
     * exactly like "nobody configured one".
     */
    @IsTest
    static void aConfiguredLocalePathIsActuallyQueried() {
        SBQQ__Quote__c queried = QuoteDocumentQuery.quotesWithLines(
            new Set<Id>{ QuoteDocumentTestData.quoteId() }
        )[0];

        String configured = QuoteDocumentKeyValueMap.get('DOCUMENT_CONFIG').get('LOCALE_FIELD_PATH');
        if (String.isBlank(configured)) {
            // Nothing configured in this org: assert the contract instead, so
            // this test still says something rather than passing vacuously.
            Assert.isTrue(
                QuoteDocumentQuery.localePathIsQueried(),
                'When a locale field path is configured, the generation query must select it. An '
                    + 'unqueried field reads as absent, so every quote would fall back to the default and '
                    + 'nobody would be able to tell that from "nobody configured one".'
            );
            return;
        }

        Assert.isTrue(
            queried.getPopulatedFieldsAsMap().containsKey(configured.split('\\.')[0]),
            'The configured locale path must be in the query result: ' + configured
        );
    }

    // -----------------------------------------------------------------------
    // Finding 6 - the payload lost its currency
    // -----------------------------------------------------------------------

    /**
     * The render service never selected CurrencyIsoCode, but the projection
     * read it from getPopulatedFieldsAsMap(). It therefore returned null in
     * every org, including a multi-currency one - and both adapters format
     * money from it.
     */
    @IsTest
    static void thePayloadCarriesTheCurrencyInAMultiCurrencyOrg() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.GenerationOutcome outcome =
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId })[0];
        QuoteDocumentPayload payload = QuoteDocumentRenderService.getPayload(
            quoteId, outcome.requestId, outcome.fingerprint
        );
        Test.stopTest();

        if (!UserInfo.isMultiCurrencyOrganization()) {
            Assert.isNull(
                payload.currencyIsoCode,
                'In a single-currency org the field does not exist, so null is correct here - and this '
                    + 'test cannot prove the multi-currency behaviour. The service-side assertion below '
                    + 'is what covers it.'
            );
            Assert.isTrue(
                QuoteDocumentRenderService.selectsCurrency(),
                'The render service must select CurrencyIsoCode when the org is multi-currency. Without '
                    + 'it the projection reads an unqueried field, gets null, and both adapters format '
                    + 'money with no currency at all.'
            );
            return;
        }

        Assert.isTrue(
            String.isNotBlank(payload.currencyIsoCode),
            'A multi-currency org must deliver the currency to the renderer. Both adapters format money '
                + 'from it, so null means every amount prints without a currency.'
        );
    }
}
