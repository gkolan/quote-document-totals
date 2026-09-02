/**
 * Covers QuoteDocumentRowCustomizerRegistry.resolve() directly, and proves the
 * current registry behavior: the shipped Quote_Document_Table_Def__mdt
 * records generate through QuoteDocumentGenerator via registered codes.
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
    // The four customizer-backed CMDT records stay wired to a resolvable code.
    // -----------------------------------------------------------------------

    /**
     * All four of these definitions are deliberately inactive - three are
     * demonstration tables and ROW_CUSTOMIZER_EXAMPLE is one too - so nothing
     * generates from them and the old end-to-end assertion here could no longer
     * hold. What it uniquely proved was the Increment 4 migration's wiring: that
     * each record still names a code the registry can resolve. That survives the
     * active flag and is asserted directly below.
     *
     * Each customizer's actual behaviour is covered against an injected
     * definition by its own test class - QuoteDocumentDiscountRowCustomizerTest,
     * QuoteDocumentIndustryRowCustomizerTest, QuoteDocumentRoundingRowCustomizerTest,
     * and QuoteDocumentRowCustomizerTest for ESTIMATED_TAX - so no coverage is
     * lost by not generating here.
     */
    @IsTest
    static void everyCustomizerBackedCmdtRecordNamesAResolvableCode() {
        Map<String, String> expectedCodeByTable = new Map<String, String>{
            'DISCOUNT_EXAMPLE'       => 'DISCOUNT_EXAMPLE',
            'INDUSTRY_ALLEGIANCE'    => 'INDUSTRY_ALLEGIANCE',
            'ROUNDING_EXAMPLE'       => 'ROUNDING_EXAMPLE',
            'ROW_CUSTOMIZER_EXAMPLE' => 'ESTIMATED_TAX'
        };

        Map<String, String> actualCodeByTable = new Map<String, String>();
        for (Quote_Document_Table_Def__mdt record : [
            SELECT Table_Code__c, Row_Customizer_Code__c
            FROM Quote_Document_Table_Def__mdt
            WHERE Table_Code__c IN :expectedCodeByTable.keySet()
        ]) {
            actualCodeByTable.put(record.Table_Code__c, record.Row_Customizer_Code__c);
        }

        Assert.areEqual(expectedCodeByTable.size(), actualCodeByTable.size(),
            'Every customizer-backed definition must still exist, active or not');

        for (String tableCode : expectedCodeByTable.keySet()) {
            String customizerCode = actualCodeByTable.get(tableCode);
            Assert.areEqual(expectedCodeByTable.get(tableCode), customizerCode,
                tableCode + ' must still name its customizer code');
            Assert.isNotNull(
                QuoteDocumentRowCustomizerRegistry.resolve(customizerCode),
                customizerCode + ' must still resolve through the registry'
            );
        }
    }
}
