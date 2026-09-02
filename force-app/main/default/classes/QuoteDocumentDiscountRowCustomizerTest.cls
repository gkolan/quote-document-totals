/**
 * Covers the Discount row type end to end: the reference customizer picks the
 * largest Detail row, discounts it, folds the discount into that line's own
 * group Subtotal and the Grand Total, and the table still reconciles under
 * QuoteDocumentGenerator.verify()'s generalized leaf-contribution logic. Also
 * covers the same Quote Net Amount guard QuoteDocumentRoundingRowCustomizer
 * is held to.
 */
@IsTest
private class QuoteDocumentDiscountRowCustomizerTest {

    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Discount Customizer Test', Industry = 'Technology');
        insert account;

        Opportunity opportunity = new Opportunity(
            Name = 'Discount Customizer Test',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunity;

        Product2 bigProduct = new Product2(
            Name = 'Discount Test Big Product', ProductCode = 'DISC_BIG',
            Family = 'Hardware', IsActive = true
        );
        Product2 smallProduct = new Product2(
            Name = 'Discount Test Small Product', ProductCode = 'DISC_SMALL',
            Family = 'Hardware', IsActive = true
        );
        insert new List<Product2>{ bigProduct, smallProduct };

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Account__c = account.Id,
            SBQQ__Opportunity2__c = opportunity.Id,
            SBQQ__Primary__c = false,
            SBQQ__Type__c = 'Quote'
        );
        insert quote;

        insert new List<SBQQ__QuoteLine__c>{
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quote.Id, SBQQ__Product__c = bigProduct.Id, SBQQ__Number__c = 1,
                SBQQ__Quantity__c = 1, SBQQ__ListPrice__c = 1000, SBQQ__RegularPrice__c = 1000,
                SBQQ__NetPrice__c = 1000, SBQQ__CustomerPrice__c = 1000
            ),
            new SBQQ__QuoteLine__c(
                SBQQ__Quote__c = quote.Id, SBQQ__Product__c = smallProduct.Id, SBQQ__Number__c = 2,
                SBQQ__Quantity__c = 1, SBQQ__ListPrice__c = 500, SBQQ__RegularPrice__c = 500,
                SBQQ__NetPrice__c = 500, SBQQ__CustomerPrice__c = 500
            )
        };
    }

    private static Id quoteId() {
        return [SELECT Id FROM SBQQ__Quote__c LIMIT 1].Id;
    }

    private static QuoteDocumentTableDefinition definitionNamed(String tableCode, String filter) {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            tableCode,
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            filter
        );
        definition.rowCustomizerCode = 'DISCOUNT_EXAMPLE';
        return definition;
    }

    @IsTest
    static void discountAppliesToTheLargestLineAndStillReconciles() {
        QuoteDocumentTableDefinition.useDefinitions(new List<QuoteDocumentTableDefinition>{
            definitionNamed('DISCOUNT_HAPPY_PATH', QuoteDocumentTableDefinition.FILTER_ALL)
        });

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Quote_Document_Table__c table = [
            SELECT Id, Status__c, Amount_Net__c FROM Quote_Document_Table__c
            WHERE Table_Code__c = 'DISCOUNT_HAPPY_PATH'
        ];
        Assert.areEqual('Complete', table.Status__c, 'A correctly-folded Discount row must not fail verification');
        // Both lines share the Hardware family, so the pre-discount grand total is 1500.
        Assert.areEqual(1500 - 50, table.Amount_Net__c, 'The grand total must reflect the 5% discount on the $1000 line');

        SBQQ__QuoteLine__c bigLine = [
            SELECT Id FROM SBQQ__QuoteLine__c WHERE SBQQ__Product__r.ProductCode = 'DISC_BIG' LIMIT 1
        ];

        Quote_Document_Row__c discountRow = [
            SELECT Row_Type__c, Amount_Net__c, Include_In_Grand_Total__c, Include_In_Subtotal__c,
                   Group_Level__c, Quote_Line__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__c = :table.Id AND Row_Key__c = :('DISCOUNT:' + bigLine.Id)
        ];
        Assert.areEqual('Discount', discountRow.Row_Type__c);
        Assert.areEqual(-50, discountRow.Amount_Net__c, '5% of the $1000 line is a $50 discount');
        Assert.isTrue(discountRow.Include_In_Grand_Total__c, 'A Discount row must count toward the grand total');
        Assert.areEqual(bigLine.Id, discountRow.Quote_Line__c, 'A Discount row must be tied to the line it discounts');

        Quote_Document_Row__c subtotal = [
            SELECT Amount_Net__c FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__c = :table.Id AND Row_Type__c = 'Subtotal' AND Group_Value__c = 'Hardware'
        ];
        Assert.areEqual(1500 - 50, subtotal.Amount_Net__c,
            'The discounted line\'s own group Subtotal must carry the discount too, or the two reconciliation paths would disagree');
    }

    @IsTest
    static void aDiscountRowIsRejectedOnTheTableCheckedAgainstQuoteNetAmount() {
        QuoteDocumentTableDefinition.useDefinitions(new List<QuoteDocumentTableDefinition>{
            definitionNamed('DISCOUNT_ON_RECONCILED_TABLE', QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL)
        });

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
            Assert.fail('A Discount row on the PRICE_WATERFALL + EXCLUDE_OPTIONAL table must fail generation');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('Quote Net Amount'),
                'The error should explain the Quote Net Amount conflict: ' + e.getMessage());
        }
        Test.stopTest();
    }
}
