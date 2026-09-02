/**
 * Covers the Row_Customizer_Code__c extension point end to end: a definition
 * that names a real customizer gets its extra row through the actual
 * generator (not a hand-called unit), the no-customizer-configured case
 * behaves exactly as before this feature existed, and an unknown code
 * surfaces as a readable QuoteDocumentException rather than a silently
 * skipped table.
 */
@IsTest
private class QuoteDocumentRowCustomizerTest {

    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Row Customizer Test', Industry = 'Technology');
        insert account;

        Opportunity opportunity = new Opportunity(
            Name = 'Row Customizer Test',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunity;

        Product2 product = new Product2(
            Name = 'Row Customizer Test Product', ProductCode = 'RCT_PRODUCT',
            Family = 'Hardware', IsActive = true
        );
        insert product;

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Account__c = account.Id,
            SBQQ__Opportunity2__c = opportunity.Id,
            SBQQ__Primary__c = false,
            SBQQ__Type__c = 'Quote'
        );
        insert quote;

        insert new SBQQ__QuoteLine__c(
            SBQQ__Quote__c = quote.Id,
            SBQQ__Product__c = product.Id,
            SBQQ__Number__c = 1,
            SBQQ__Quantity__c = 1,
            SBQQ__ListPrice__c = 1000,
            SBQQ__RegularPrice__c = 1000,
            SBQQ__NetPrice__c = 1000,
            SBQQ__CustomerPrice__c = 1000
        );
    }

    private static Id quoteId() {
        return [SELECT Id FROM SBQQ__Quote__c LIMIT 1].Id;
    }

    private static QuoteDocumentTableDefinition definitionNamed(String tableCode, String customizerCode) {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            tableCode,
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        definition.rowCustomizerCode = customizerCode;
        return definition;
    }

    /**
     * The reference implementation, exercised the way a real quote would hit
     * it: through QuoteDocumentGenerator.generate(), not by calling the
     * customizer directly. Proves the row survives insert and verify() -
     * the Informational row type and false inclusion flags mean it never
     * enters the grand-total reconciliation.
     */
    @IsTest
    static void estimatedTaxCustomizerAddsAnInformationalRowThatDoesNotAffectTheGrandTotal() {
        QuoteDocumentTableDefinition.useDefinitions(new List<QuoteDocumentTableDefinition>{
            definitionNamed('CUSTOMIZER_HAPPY_PATH', 'ESTIMATED_TAX')
        });

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Quote_Document_Table__c table = [
            SELECT Id, Status__c, Amount_Net__c FROM Quote_Document_Table__c
            WHERE Table_Code__c = 'CUSTOMIZER_HAPPY_PATH'
        ];
        Assert.areEqual('Complete', table.Status__c, 'A customizer that only adds an Informational row must not fail verification');

        Quote_Document_Row__c taxRow = [
            SELECT Row_Type__c, Amount_Net__c, Include_In_Grand_Total__c, Include_In_Subtotal__c, Display_Label__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__c = :table.Id AND Row_Key__c = 'ESTIMATED_TAX'
        ];
        Assert.areEqual('Informational', taxRow.Row_Type__c, 'The customizer-added row must keep the Row Type it was created with');
        Assert.isFalse(taxRow.Include_In_Grand_Total__c, 'An Informational row must not count toward the grand total');
        Assert.isFalse(taxRow.Include_In_Subtotal__c, 'An Informational row must not count toward any subtotal');
        Assert.areEqual((table.Amount_Net__c * 0.08).setScale(2), taxRow.Amount_Net__c,
            'The tax row must be 8% of the same grand total the table itself carries');
    }

    /** No Row_Customizer_Code__c set is the common case and must behave exactly as before this feature existed. */
    @IsTest
    static void aDefinitionWithNoCustomizerCodeGeneratesUnchanged() {
        QuoteDocumentTableDefinition.useDefinitions(new List<QuoteDocumentTableDefinition>{
            definitionNamed('CUSTOMIZER_BLANK', null)
        });

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Integer rowCount = [
            SELECT COUNT() FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Table_Code__c = 'CUSTOMIZER_BLANK' AND Row_Key__c = 'ESTIMATED_TAX'
        ];
        Assert.areEqual(0, rowCount, 'With no customizer configured, no extra row should appear');
    }

    @IsTest
    static void anUnknownCustomizerCodeFailsGenerationWithAReadableMessage() {
        QuoteDocumentTableDefinition.useDefinitions(new List<QuoteDocumentTableDefinition>{
            definitionNamed('CUSTOMIZER_UNKNOWN_CODE', 'NOT_A_REAL_CODE')
        });

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
            Assert.fail('A Row Customizer Code the registry does not recognize must fail generation, not silently skip the table');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('NOT_A_REAL_CODE'),
                'The error should name the unknown code: ' + e.getMessage());
        }
        Test.stopTest();
    }
}
