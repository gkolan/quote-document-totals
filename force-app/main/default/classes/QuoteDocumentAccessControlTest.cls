/**
 * Step 06A §3.2 - locking the snapshot objects down.
 *
 * "Direct access is unsupported" was an honour-system rule until this step.
 * These tests assert the parts of the lock-down that exist in metadata today;
 * separate access levels need permission sets and a render service that do not
 * exist yet, and is listed in the step's close-out rather than faked here.
 */
@IsTest
private class QuoteDocumentAccessControlTest {

    @TestSetup
    static void setup() {
        QuoteDocumentTestData.setup();
    }

    /**
     * NOTE ON WHAT IS ASSERTED HERE, AND WHY IT IS BEHAVIOURAL.
     *
     * The obvious test would read the org-wide default off the schema and
     * assert it is Private. Apex exposes no such describe - there is no
     * getSharingModel() - so the sharing model cannot be asserted directly
     * from a test at all.
     *
     * The behavioural tests below are therefore the real guard: if someone
     * loosens Quote_Document_Table__c back to ReadWrite, the ordinary-update
     * test starts passing where it should fail, and the build breaks. That is
     * a better guard than a schema string anyway - it fails on the effect
     * rather than on the setting, and the effect is what matters.
     */

    /**
     * The behaviour the sharing change actually bought, discovered by running
     * it rather than assumed: an ordinary user-mode update of a published row
     * is now refused by the platform.
     *
     * This is the difference between "immutable" as a claim and as a
     * property. It is asserted here because it was NOT true before this step -
     * the same edit succeeded.
     */
    @IsTest
    static void anOrdinaryUpdateOfAPublishedRowIsRefused() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });

        Quote_Document_Row__c row = [
            SELECT Id, Display_Label__c FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Quote__c = :quoteId LIMIT 1
        ];
        row.Display_Label__c = 'Edited by an ordinary caller';

        Boolean refused = false;
        String detail;
        try {
            Database.update(row, true, AccessLevel.USER_MODE);
        } catch (Exception e) {
            refused = true;
            detail = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(
            refused,
            'A published row must not be editable through ordinary access. If this starts passing, the '
                + 'sharing model was loosened and "immutable snapshot" became a claim again.'
        );
        Assert.isTrue(
            String.isNotBlank(detail),
            'The refusal must say something, or nobody will understand why their edit failed.'
        );
    }

    /**
     * The other half, and the reason the integrity tests exist at all: a
     * caller with system access CAN still edit. Immutability by permission is
     * one guarantee; detection is the other, and neither replaces the other.
     */
    @IsTest
    static void aSystemContextCallerCanStillEditWhichIsWhyDetectionExists() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });

        Quote_Document_Row__c row = [
            SELECT Id, Display_Label__c FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Quote__c = :quoteId LIMIT 1
        ];
        row.Display_Label__c = 'Edited by an admin or a data loader';
        Database.update(row, true, AccessLevel.SYSTEM_MODE);
        Test.stopTest();

        SBQQ__Quote__c quote = [
            SELECT Document_Payload_Hash__c FROM SBQQ__Quote__c WHERE Id = :quoteId
        ];
        String failure;
        try {
            QuoteDocumentPayloadHash.assertIntact(quoteId, quote.Document_Payload_Hash__c);
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            failure = e.getMessage();
        }

        Assert.isNotNull(
            failure,
            'Permissions cannot stop an admin, a data loader, or a broad integration user. That is exactly '
                + 'why the payload hash exists: what cannot be prevented must at least be detected.'
        );
        Assert.isTrue(failure.contains('PAYLOAD_INTEGRITY_MISMATCH'), 'Wrong code: ' + failure);
    }

    /**
     * §3.2.4 warns explicitly that retention's cross-quote deletes must be
     * re-checked when the sharing model changes, "because a delete that
     * silently stops deleting is worse than one that fails".
     */
    @IsTest
    static void generationStillReplacesItsOwnSnapshotUnderPrivateSharing() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Integer afterFirst = [
            SELECT COUNT() FROM Quote_Document_Table__c WHERE Quote__c = :quoteId
        ];

        update new SBQQ__Quote__c(Id = quoteId, Document_Data_Fingerprint__c = 'force-rebuild');
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Integer afterSecond = [
            SELECT COUNT() FROM Quote_Document_Table__c WHERE Quote__c = :quoteId
        ];
        Test.stopTest();

        Assert.areEqual(
            afterFirst,
            afterSecond,
            'Regeneration deletes the previous snapshot before rebuilding. Under Private sharing a delete '
                + 'that silently stopped working would accumulate duplicate tables rather than fail, which '
                + 'is the worse failure and the one this asserts against.'
        );
    }
}
