/**
 * The Monthly Subscription Summary, end to end, on real data.
 *
 * Unlike the other example scripts in this folder, this one does NOT hand-build
 * Quote_Document_Table__c / Quote_Document_Row__c records for a guide to quote.
 * It creates a quote, runs QuoteDocumentGenerator against it, and prints what
 * the framework actually produced - because the whole question this table
 * answers ("does the allocation foot to the quote?") is only worth anything if
 * generation, verification and reconciliation all really ran.
 *
 * The scenario is the one the feature was asked for:
 *
 *   Platform Subscription     12,000   whole 12-month term (no dates of its own)
 *   Product A                  1,000   months 1-3
 *   Data Migration               500   11 days inside month 5
 *   Security Review              750   month 6
 *   Training Day                 300   one day in month 7
 *   Onboarding Accelerator     2,000   months 7-10
 *                             ------
 *                             16,550   = the quote's own SBQQ__NetAmount__c
 *
 * PREREQUISITE - the table definition ships INACTIVE, because activating it
 * changes every document in the org and it needs every quote to carry a term.
 * Activate it first, either in Setup (Custom Metadata Types >
 * Quote Document Table Def > Monthly Subscription Summary > Is Active) or by
 * flipping Is_Active__c to true in
 * force-app/main/default/customMetadata/Quote_Document_Table_Def.MONTHLY_SUBSCRIPTION_SUMMARY.md-meta.xml
 * and deploying that one file. This script tells you if you forgot.
 *
 * Safe to re-run: it deletes its own account and everything under it first.
 *
 *   sf apex run --target-org quotedoctotals --file scripts/apex/monthly-subscription-example.apex
 */

final String ACCOUNT_NAME = 'Monthly Subscription Example';
final String TABLE_CODE = 'MONTHLY_SUBSCRIPTION_SUMMARY';
final Date TERM_START = Date.newInstance(Date.today().year() + 1, 1, 1);

Boolean active = false;
for (Quote_Document_Table_Def__mdt definition : [
    SELECT Table_Code__c FROM Quote_Document_Table_Def__mdt
    WHERE Table_Code__c = :TABLE_CODE AND Is_Active__c = true
]) {
    active = true;
}
if (!active) {
    throw new IllegalArgumentException(
        TABLE_CODE + ' is not active, so generation will not produce it. Set Is_Active__c = true on the '
            + 'Quote Document Table Def custom metadata record and re-run - see the header of this script.'
    );
}

delete [SELECT Id FROM Account WHERE Name = :ACCOUNT_NAME];

Account account = new Account(Name = ACCOUNT_NAME, Industry = 'Technology');
insert account;

Opportunity opportunity = new Opportunity(
    Name = ACCOUNT_NAME,
    AccountId = account.Id,
    StageName = 'Prospecting',
    CloseDate = Date.today().addDays(30)
);
insert opportunity;

// ProductCode is not an external id in a stock org, so this reuses what is
// already there by code and inserts only what is missing - re-running the
// script must not pile up a second set of the same six products.
Map<String, Product2> products = new Map<String, Product2>();
for (Product2 existing : [
    SELECT Id, ProductCode FROM Product2 WHERE ProductCode LIKE 'MSX\\_%'
]) {
    products.put(existing.ProductCode, existing);
}

List<Product2> missing = new List<Product2>();
for (List<String> spec : new List<List<String>>{
    new List<String>{ 'MSX_PLATFORM',   'Platform Subscription',  'Software' },
    new List<String>{ 'MSX_PRODUCT_A',  'Product A',              'Software' },
    new List<String>{ 'MSX_MIGRATION',  'Data Migration',         'Service'  },
    new List<String>{ 'MSX_SECURITY',   'Security Review',        'Service'  },
    new List<String>{ 'MSX_TRAINING',   'Training Day',           'Service'  },
    new List<String>{ 'MSX_ONBOARDING', 'Onboarding Accelerator', 'Service'  }
}) {
    if (!products.containsKey(spec[0])) {
        missing.add(new Product2(
            ProductCode = spec[0], Name = spec[1], Family = spec[2], IsActive = true
        ));
    }
}
if (!missing.isEmpty()) {
    insert missing;
    for (Product2 product : missing) {
        products.put(product.ProductCode, product);
    }
}

SBQQ__Quote__c quote = new SBQQ__Quote__c(
    SBQQ__Account__c = account.Id,
    SBQQ__Opportunity2__c = opportunity.Id,
    SBQQ__Primary__c = false,
    SBQQ__Type__c = 'Quote',
    SBQQ__StartDate__c = TERM_START,
    SBQQ__SubscriptionTerm__c = 12
);
insert quote;

List<SBQQ__QuoteLine__c> lines = new List<SBQQ__QuoteLine__c>();
Integer lineNumber = 0;

// productCode => {net price, start, end}. A null window means the whole term,
// which is what CPQ's own effective-date formulas mean by a blank start date.
List<List<Object>> plan = new List<List<Object>>{
    new List<Object>{ 'MSX_PLATFORM',   12000, null, null },
    new List<Object>{ 'MSX_PRODUCT_A',   1000, TERM_START, TERM_START.addMonths(3).addDays(-1) },
    new List<Object>{ 'MSX_MIGRATION',    500, TERM_START.addMonths(4).addDays(9), TERM_START.addMonths(4).addDays(19) },
    new List<Object>{ 'MSX_SECURITY',     750, TERM_START.addMonths(5), TERM_START.addMonths(6).addDays(-1) },
    new List<Object>{ 'MSX_TRAINING',     300, TERM_START.addMonths(6).addDays(14), TERM_START.addMonths(6).addDays(14) },
    new List<Object>{ 'MSX_ONBOARDING',  2000, TERM_START.addMonths(6), TERM_START.addMonths(10).addDays(-1) }
};

for (List<Object> row : plan) {
    lineNumber++;
    Decimal price = (Decimal) row[1];
    lines.add(new SBQQ__QuoteLine__c(
        SBQQ__Quote__c = quote.Id,
        SBQQ__Product__c = products.get((String) row[0]).Id,
        SBQQ__Number__c = lineNumber,
        SBQQ__Quantity__c = 1,
        SBQQ__ListPrice__c = price,
        SBQQ__RegularPrice__c = price,
        SBQQ__NetPrice__c = price,
        SBQQ__CustomerPrice__c = price,
        SBQQ__StartDate__c = (Date) row[2],
        SBQQ__EndDate__c = (Date) row[3]
    ));
}
insert lines;

QuoteDocumentGenerator.generate(new Set<Id>{ quote.Id });

Quote_Document_Table__c table = [
    SELECT Id, Display_Title__c, Status__c, Amount_Net__c
    FROM Quote_Document_Table__c
    WHERE Quote__c = :quote.Id AND Table_Code__c = :TABLE_CODE
];

System.debug('== ' + table.Display_Title__c + ' (' + table.Status__c + ') ==');

for (Quote_Document_Row__c row : [
    SELECT Row_Type__c, Display_Label__c, Amount_Net__c, Group_Level__c
    FROM Quote_Document_Row__c
    WHERE Quote_Document_Table__c = :table.Id
    ORDER BY Display_Order__c
]) {
    String indent = ''.rightPad(Integer.valueOf(row.Group_Level__c) * 2, ' ');
    String amount = row.Amount_Net__c == null ? '' : String.valueOf(row.Amount_Net__c.setScale(2));
    System.debug(
        (indent + row.Display_Label__c).rightPad(52, ' ') + amount.leftPad(12, ' ')
            + '   [' + row.Row_Type__c + ']'
    );
}

SBQQ__Quote__c reread = [SELECT SBQQ__NetAmount__c FROM SBQQ__Quote__c WHERE Id = :quote.Id];
System.debug('Quote SBQQ__NetAmount__c: ' + reread.SBQQ__NetAmount__c);
System.debug('Table grand total:        ' + table.Amount_Net__c);
System.debug(
    reread.SBQQ__NetAmount__c == table.Amount_Net__c
        ? 'The months foot to the quote.'
        : 'MISMATCH - generation should have refused to publish this.'
);
