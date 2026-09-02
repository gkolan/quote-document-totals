/**
 * Covers the Rounding row type end to end: the reference customizer produces
 * a row that reconciles through QuoteDocumentGenerator.verify()'s generalized
 * leaf-contribution logic, is rejected on the table checked against Quote Net
 * Amount, and the declarative Rounding_Row_Shape rule rejects a misshapen row
 * even when no Apex is involved at all.
 */
@IsTest
private class QuoteDocumentRoundingRowCustomizerTest {

    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Rounding Customizer Test', Industry = 'Technology');
        insert account;

        Opportunity opportunity = new Opportunity(
            Name = 'Rounding Customizer Test',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunity;

        Product2 product = new Product2(
            Name = 'Rounding Customizer Test Product', ProductCode = 'RND_PRODUCT',
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

        // Net price deliberately not a whole dollar amount, so the
        // customizer's rounding always has a nonzero delta to add.
        insert new SBQQ__QuoteLine__c(
            SBQQ__Quote__c = quote.Id,
            SBQQ__Product__c = product.Id,
            SBQQ__Number__c = 1,
            SBQQ__Quantity__c = 1,
            SBQQ__ListPrice__c = 1000.55,
            SBQQ__RegularPrice__c = 1000.55,
            SBQQ__NetPrice__c = 1000.55,
            SBQQ__CustomerPrice__c = 1000.55
        );
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
        definition.rowCustomizerCode = 'ROUNDING_EXAMPLE';
        return definition;
    }

    /**
     * Exercised through the real generator, not by calling the customizer
     * directly - proves the row survives insert, the declarative shape rule,
     * and verify()'s reconciliation, which is only possible because verify()
     * now treats a counted non-aggregate row as a leaf on both independent
     * paths (see QuoteDocumentGenerator.AGGREGATE_ROW_TYPES).
     */
    @IsTest
    static void roundingRowMakesThePrintedGrandTotalWholeAndStillReconciles() {
        QuoteDocumentTableDefinition.useDefinitions(new List<QuoteDocumentTableDefinition>{
            definitionNamed('ROUNDING_HAPPY_PATH', QuoteDocumentTableDefinition.FILTER_ALL)
        });

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Quote_Document_Table__c table = [
            SELECT Id, Status__c, Amount_Net__c FROM Quote_Document_Table__c
            WHERE Table_Code__c = 'ROUNDING_HAPPY_PATH'
        ];
        Assert.areEqual('Complete', table.Status__c, 'A correctly-shaped Rounding row must not fail verification');
        // Pre-discount line total is 1000.55; nearest $100 is 1000.00.
        Assert.areEqual(1000, table.Amount_Net__c, 'The stamped grand total must be rounded to the nearest $100');

        Quote_Document_Row__c roundingRow = [
            SELECT Row_Type__c, Amount_Net__c, Include_In_Grand_Total__c, Include_In_Subtotal__c,
                   Group_Level__c, Quote_Line__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__c = :table.Id AND Row_Key__c = 'ROUNDING_ADJUSTMENT'
        ];
        Assert.areEqual('Rounding', roundingRow.Row_Type__c);
        Assert.isTrue(roundingRow.Include_In_Grand_Total__c, 'A Rounding row must count toward the grand total');
        Assert.isFalse(roundingRow.Include_In_Subtotal__c, 'A Rounding row must not count toward any subtotal');
        Assert.areEqual(0, roundingRow.Group_Level__c, 'A Rounding row is a whole-table adjustment, not part of any group');
        Assert.isNull(roundingRow.Quote_Line__c, 'A Rounding row must not be tied to one quote line');
    }

    /**
     * The one place a Rounding adjustment is not allowed: the table
     * verify() checks against CPQ's own Quote Net Amount. CPQ never sees the
     * rounding delta, so letting it through there would silently break the
     * one check this whole framework exists to protect.
     */
    @IsTest
    static void aRoundingRowIsRejectedOnTheTableCheckedAgainstQuoteNetAmount() {
        QuoteDocumentTableDefinition.useDefinitions(new List<QuoteDocumentTableDefinition>{
            definitionNamed('ROUNDING_ON_RECONCILED_TABLE', QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL)
        });

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
            Assert.fail('A Rounding row on the PRICE_WATERFALL + EXCLUDE_OPTIONAL table must fail generation');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('Quote Net Amount'),
                'The error should explain the Quote Net Amount conflict: ' + e.getMessage());
        }
        Test.stopTest();
    }

    /** The shape rule protects a Rounding row even without any Apex in the path at all. */
    @IsTest
    static void insertingAMisshapenRoundingRowDirectlyIsRejectedByTheValidationRule() {
        Quote_Document_Table__c table = new Quote_Document_Table__c(
            Name = 'Validation Rule Test',
            Quote__c = quoteId(),
            Table_Code__c = 'VALIDATION_RULE_TEST',
            Table_Key__c = quoteId() + ':VALIDATION_RULE_TEST',
            Display_Order__c = 10,
            Amount_Basis__c = 'Final Value',
            Status__c = 'Complete'
        );
        insert table;

        Test.startTest();
        try {
            insert new Quote_Document_Row__c(
                Quote_Document_Table__c = table.Id,
                Row_Type__c = 'Rounding',
                Group_Level__c = 1, // wrong - must be 0
                Row_Key__c = 'BAD_ROUNDING',
                Display_Label__c = 'Bad Rounding Row',
                Include_In_Grand_Total__c = true,
                Include_In_Subtotal__c = false
            );
            Assert.fail('A Rounding row at Group Level 1 must be rejected by Rounding_Row_Shape');
        } catch (DmlException e) {
            Assert.isTrue(e.getMessage().contains('Rounding'), 'Message: ' + e.getMessage());
        }
        Test.stopTest();
    }
}
