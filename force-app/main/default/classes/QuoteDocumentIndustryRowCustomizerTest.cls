/**
 * Exercises all three reassignment paths plus the unmapped default, with
 * amounts chosen specifically to land in each bucket - real quote data in
 * this org has no line between $0 and the $1,000 threshold (see
 * docs/quote-document-row-customizer-guide.md §12), so the "stays in its
 * mapped industry" path can only be proven with synthetic data like this.
 * The zero-total and overflow paths are also proven here, then proven again
 * against a real quote by scripts/apex/industry-allegiance-example.apex.
 */
@IsTest
private class QuoteDocumentIndustryRowCustomizerTest {

    private static final String PRODUCT_ZERO = 'QDRC Test Zero Product';
    private static final String PRODUCT_STAYS = 'QDRC Test Stays Product';
    private static final String PRODUCT_OVERFLOW = 'QDRC Test Overflow Product';
    private static final String PRODUCT_UNMAPPED = 'QDRC Test Unmapped Product';

    @TestSetup
    static void setup() {
        Account account = new Account(Name = 'Industry Allegiance Test', Industry = 'Technology');
        insert account;

        Opportunity opportunity = new Opportunity(
            Name = 'Industry Allegiance Test',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunity;

        List<Product2> products = new List<Product2>{
            new Product2(Name = PRODUCT_ZERO, ProductCode = 'QDRC_ZERO', Family = 'Hardware', IsActive = true),
            new Product2(Name = PRODUCT_STAYS, ProductCode = 'QDRC_STAYS', Family = 'Hardware', IsActive = true),
            new Product2(Name = PRODUCT_OVERFLOW, ProductCode = 'QDRC_OVERFLOW', Family = 'Hardware', IsActive = true),
            new Product2(Name = PRODUCT_UNMAPPED, ProductCode = 'QDRC_UNMAPPED', Family = 'Hardware', IsActive = true)
        };
        insert products;

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Account__c = account.Id,
            SBQQ__Opportunity2__c = opportunity.Id,
            SBQQ__Primary__c = false,
            SBQQ__Type__c = 'Quote'
        );
        insert quote;

        Map<String, Id> productIdByName = new Map<String, Id>();
        for (Product2 p : products) {
            productIdByName.put(p.Name, p.Id);
        }

        insert new List<SBQQ__QuoteLine__c>{
            line(quote.Id, productIdByName.get(PRODUCT_ZERO), 1, 1, 0, 0),
            line(quote.Id, productIdByName.get(PRODUCT_STAYS), 2, 1, 500, 500),
            line(quote.Id, productIdByName.get(PRODUCT_OVERFLOW), 3, 1, 5000, 5000),
            line(quote.Id, productIdByName.get(PRODUCT_UNMAPPED), 4, 1, 200, 200)
        };
    }

    private static SBQQ__QuoteLine__c line(
        Id quoteId, Id productId, Integer lineNumber, Decimal quantity, Decimal listPrice, Decimal netPrice
    ) {
        return new SBQQ__QuoteLine__c(
            SBQQ__Quote__c = quoteId,
            SBQQ__Product__c = productId,
            SBQQ__Number__c = lineNumber,
            SBQQ__Quantity__c = quantity,
            SBQQ__ListPrice__c = listPrice,
            SBQQ__RegularPrice__c = listPrice,
            SBQQ__NetPrice__c = netPrice,
            SBQQ__CustomerPrice__c = netPrice
        );
    }

    private static Id quoteId() {
        return [SELECT Id FROM SBQQ__Quote__c LIMIT 1].Id;
    }

    @IsTest
    static void allFourPathsLandInTheExpectedIndustryBucket() {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            'INDUSTRY_ALLEGIANCE_UNIT_TEST',
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        definition.rowCustomizerCode = 'INDUSTRY_ALLEGIANCE';
        // The customizer replaces grouping entirely and never re-emits Detail
        // rows (matching the real INDUSTRY_ALLEGIANCE definition's
        // Show_Details__c = false) - without this, verify() would compare the
        // grand total against Detail rows that were never rebuilt.
        definition.showDetails = false;
        QuoteDocumentTableDefinition.useDefinitions(new List<QuoteDocumentTableDefinition>{ definition });

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Quote_Document_Table__c table = [
            SELECT Id, Status__c, Amount_Net__c FROM Quote_Document_Table__c
            WHERE Table_Code__c = 'INDUSTRY_ALLEGIANCE_UNIT_TEST'
        ];
        Assert.areEqual('Complete', table.Status__c, 'Re-bucketing must still reconcile to the grand total');
        Assert.areEqual(5700, table.Amount_Net__c, '0 + 500 + 5000 + 200 across the four synthetic lines');

        Map<String, Decimal> subtotalByGroup = new Map<String, Decimal>();
        for (Quote_Document_Row__c row : [
            SELECT Group_Value__c, Amount_Net__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__c = :table.Id AND Row_Type__c = 'Subtotal'
        ]) {
            subtotalByGroup.put(row.Group_Value__c, row.Amount_Net__c);
        }

        Assert.areEqual(200, subtotalByGroup.get('Other(s)'),
            'The $0 product (reassigned) and the unmapped product (default) both land in Other(s)');
        Assert.areEqual(500, subtotalByGroup.get('Test Stays Industry'),
            'A bucket between $0 and the threshold keeps its own mapped industry name');
        Assert.areEqual(5000, subtotalByGroup.get('Key Accounts'),
            'A bucket over the threshold is reassigned to Key Accounts');
        Assert.isFalse(subtotalByGroup.containsKey('Test Zero Industry'),
            'The zero-total bucket must not survive under its original mapped name');
        Assert.isFalse(subtotalByGroup.containsKey('Test Overflow Industry'),
            'The over-threshold bucket must not survive under its original mapped name');
    }

    /**
     * The reassignment logic in customize() reads bucket.measures.amountNet,
     * which is only ever populated on a PRICE_WATERFALL table - a CHANGE
     * table's amountNet is always zero, so without this guard every bucket
     * would silently land in Other(s) regardless of its real mapping, and the
     * table would still report Complete. This proves the guard fails loudly
     * instead, naming the table and the bad configuration.
     */
    @IsTest
    static void attachingToAChangeMeasureTableFailsLoudlyInsteadOfSilentlyMisclassifying() {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            'INDUSTRY_ALLEGIANCE_CHANGE_MISUSE_PROBE',
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        definition.rowCustomizerCode = 'INDUSTRY_ALLEGIANCE';
        definition.measureSet = QuoteDocumentTableDefinition.MEASURES_CHANGE;
        QuoteDocumentTableDefinition.useDefinitions(new List<QuoteDocumentTableDefinition>{ definition });

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
            Assert.fail('Attaching this customizer to a CHANGE-measure table must not silently succeed');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('PRICE_WATERFALL'),
                'The message should name the actual required configuration: ' + e.getMessage());
            Assert.isTrue(e.getMessage().contains('INDUSTRY_ALLEGIANCE_CHANGE_MISUSE_PROBE'),
                'The message should name the misconfigured table: ' + e.getMessage());
        }
        Test.stopTest();
    }
}
