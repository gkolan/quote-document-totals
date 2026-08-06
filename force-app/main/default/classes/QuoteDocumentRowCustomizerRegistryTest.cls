/**
 * Covers QuoteDocumentRowCustomizerRegistry.resolve() directly, and proves the
 * migration in specs/quote-docusign-launch/spec.md Increment 4 is behavior
 * preserving: the four real Quote_Document_Table_Def__mdt records generate
 * through QuoteDocumentGenerator exactly as before, but via the registry
 * rather than the retired Type.forName lookup.
 */
@IsTest
private class QuoteDocumentRowCustomizerRegistryTest {

    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Registry Test', Industry = 'Technology');
        insert account;

        Opportunity opportunity = new Opportunity(
            Name = 'Registry Test',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunity;

        Product2 product = new Product2(
            Name = 'Registry Test Product', ProductCode = 'REGISTRY_PRODUCT',
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

        // 733.50 is deliberately not a multiple of $100, so ROUNDING_EXAMPLE's
        // customizer has a nonzero delta to add a Rounding row for.
        insert new SBQQ__QuoteLine__c(
            SBQQ__Quote__c = quote.Id,
            SBQQ__Product__c = product.Id,
            SBQQ__Number__c = 1,
            SBQQ__Quantity__c = 1,
            SBQQ__ListPrice__c = 733.50,
            SBQQ__RegularPrice__c = 733.50,
            SBQQ__NetPrice__c = 733.50,
            SBQQ__CustomerPrice__c = 733.50
        );
    }

    private static Id quoteId() {
        return [SELECT Id FROM SBQQ__Quote__c LIMIT 1].Id;
    }

    // -----------------------------------------------------------------------
    // resolve()
    // -----------------------------------------------------------------------

    @IsTest
    static void resolveReturnsTheCustomizerForEveryKnownCode() {
        Assert.isInstanceOfType(
            QuoteDocumentRowCustomizerRegistry.resolve('DISCOUNT_EXAMPLE'),
            QuoteDocumentDiscountRowCustomizer.class,
            'DISCOUNT_EXAMPLE must resolve to the discount customizer'
        );
        Assert.isInstanceOfType(
            QuoteDocumentRowCustomizerRegistry.resolve('INDUSTRY_ALLEGIANCE'),
            QuoteDocumentIndustryRowCustomizer.class,
            'INDUSTRY_ALLEGIANCE must resolve to the industry customizer'
        );
        Assert.isInstanceOfType(
            QuoteDocumentRowCustomizerRegistry.resolve('ROUNDING_EXAMPLE'),
            QuoteDocumentRoundingRowCustomizer.class,
            'ROUNDING_EXAMPLE must resolve to the rounding customizer'
        );
        Assert.isInstanceOfType(
            QuoteDocumentRowCustomizerRegistry.resolve('ESTIMATED_TAX'),
            QuoteDocumentEstimatedTaxRowCustomizer.class,
            'ESTIMATED_TAX must resolve to the estimated tax customizer'
        );
    }

    @IsTest
    static void resolveThrowsOnAnUnknownCodeAndNamesIt() {
        try {
            QuoteDocumentRowCustomizerRegistry.resolve('NOT_A_REAL_CODE');
            Assert.fail('An unknown customizer code must throw');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('NOT_A_REAL_CODE'),
                'The error should name the unknown code: ' + e.getMessage());
        }
    }

    // -----------------------------------------------------------------------
    // The four real, migrated CMDT records generate identically through the
    // registry - proves the migration in specs/quote-docusign-launch/spec.md
    // Increment 4 is behavior preserving, not just that resolve() works alone.
    // -----------------------------------------------------------------------

    @IsTest
    static void theFourMigratedCmdtRecordsStillGenerateCorrectlyThroughTheRegistry() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Map<String, Quote_Document_Table__c> tablesByCode = new Map<String, Quote_Document_Table__c>();
        for (Quote_Document_Table__c table : [
            SELECT Id, Table_Code__c, Status__c
            FROM Quote_Document_Table__c
            WHERE Table_Code__c IN ('DISCOUNT_EXAMPLE', 'INDUSTRY_ALLEGIANCE', 'ROUNDING_EXAMPLE', 'ROW_CUSTOMIZER_EXAMPLE')
        ]) {
            tablesByCode.put(table.Table_Code__c, table);
        }

        Assert.areEqual(4, tablesByCode.size(), 'All four migrated table definitions must still generate a table');
        for (Quote_Document_Table__c table : tablesByCode.values()) {
            Assert.areEqual('Complete', table.Status__c,
                table.Table_Code__c + ' must still complete generation and verification through the registry');
        }

        Integer discountRows = [
            SELECT COUNT() FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__c = :tablesByCode.get('DISCOUNT_EXAMPLE').Id AND Row_Type__c = 'Discount'
        ];
        Assert.areEqual(1, discountRows, 'DISCOUNT_EXAMPLE must still add its Discount row via the registry');

        Integer industrySubtotals = [
            SELECT COUNT() FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__c = :tablesByCode.get('INDUSTRY_ALLEGIANCE').Id
              AND Row_Type__c = 'Subtotal' AND Group_Dimension__c = 'INDUSTRY_ALLEGIANCE'
        ];
        Assert.isTrue(industrySubtotals > 0, 'INDUSTRY_ALLEGIANCE must still re-bucket rows via the registry');

        Integer roundingRows = [
            SELECT COUNT() FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__c = :tablesByCode.get('ROUNDING_EXAMPLE').Id AND Row_Key__c = 'ROUNDING_ADJUSTMENT'
        ];
        Assert.areEqual(1, roundingRows, 'ROUNDING_EXAMPLE must still add its Rounding row via the registry for a non-round total');

        Integer taxRows = [
            SELECT COUNT() FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__c = :tablesByCode.get('ROW_CUSTOMIZER_EXAMPLE').Id AND Row_Key__c = 'ESTIMATED_TAX'
        ];
        Assert.areEqual(1, taxRows, 'ROW_CUSTOMIZER_EXAMPLE must still add its Estimated Tax row via the registry');
    }
}
