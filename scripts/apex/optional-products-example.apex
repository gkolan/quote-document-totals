/**
 * Hand-built example for docs/optional-products-guide.md.
 *
 * Two optional lines across two families (Hardware, Software), richer than
 * the single-tablet OPTIONAL_PRODUCTS example in quote-document-sample.apex,
 * so the family grouping actually has something to demonstrate.
 *
 * Safe to re-run: deletes only the OPTIONAL_PRODUCTS table for the target
 * quote first.
 *
 *   sf apex run --target-org gkCPQDev --file scripts/apex/optional-products-example.apex
 */

final String QUOTE_NAME = 'Q-00053';

List<SBQQ__Quote__c> seeded = [
    SELECT Id, Name FROM SBQQ__Quote__c
    WHERE SBQQ__Account__r.Name LIKE 'Ridgeline Manufacturing%'
    ORDER BY CreatedDate DESC LIMIT 1
];
SBQQ__Quote__c quote = !seeded.isEmpty() ? seeded[0] : [
    SELECT Id, Name FROM SBQQ__Quote__c WHERE Name = :QUOTE_NAME LIMIT 1
];

delete [
    SELECT Id FROM Quote_Document_Table__c
    WHERE Quote__c = :quote.Id AND Table_Code__c = 'OPTIONAL_PRODUCTS'
];

Boolean multiCurrency = UserInfo.isMultiCurrencyOrganization();

Quote_Document_Table__c table = new Quote_Document_Table__c(
    Name = quote.Name + ' - Optional Products',
    Quote__c = quote.Id,
    Table_Code__c = 'OPTIONAL_PRODUCTS',
    Table_Key__c = quote.Id + ':OPTIONAL_PRODUCTS',
    Display_Order__c = 50,
    Amount_Basis__c = 'Final Value',
    Group_Dimensions__c = 'PRODUCT_FAMILY',
    Line_Filter__c = 'OPTIONAL_ONLY',
    Measure_Set__c = 'PRICE_WATERFALL',
    Status__c = 'Generating'
);
if (multiCurrency) { table.put('CurrencyIsoCode', (String) quote.get('CurrencyIsoCode')); }
insert table;

Integer nextOrder = 10;
List<Quote_Document_Row__c> rows = new List<Quote_Document_Row__c>();

Quote_Document_Row__c row(String rowType, Integer level, String key, String label,
                           String groupValue, String productName, Decimal net, Decimal qty) {
    Boolean isAggregate = rowType != 'Detail';
    Quote_Document_Row__c r = new Quote_Document_Row__c(
        Quote_Document_Table__c = table.Id,
        Row_Type__c = rowType,
        Group_Level__c = level,
        Row_Key__c = key,
        Display_Label__c = label,
        Group_Dimension__c = groupValue == null ? null : 'PRODUCT_FAMILY',
        Group_Value__c = groupValue,
        Product_Name__c = productName,
        Display_Order__c = nextOrder,
        Is_Displayed__c = true,
        // Every row here counts - Line_Filter__c = OPTIONAL_ONLY is the one
        // case where QuoteDocumentLine.countsIn() includes optional lines.
        Include_In_Subtotal__c = !isAggregate,
        Include_In_Grand_Total__c = !isAggregate,
        Amount_List__c = net,
        Amount_Regular__c = net,
        Amount_Discount__c = 0,
        Amount_Net__c = net,
        Amount_Customer__c = net,
        Quantity__c = qty
    );
    nextOrder += 10;
    rows.add(r);
    return r;
}

row('Group Header', 1, 'HEADER:FAMILY:HARDWARE', 'Hardware', 'Hardware', null, null, null);
row('Detail', 1, 'DETAIL:TABLET10', '10" Tablet', 'Hardware', '10" Tablet', 6000, 40);
row('Subtotal', 1, 'SUBTOTAL:FAMILY:HARDWARE', 'Hardware Subtotal', 'Hardware', null, 6000, 40);

row('Group Header', 1, 'HEADER:FAMILY:SOFTWARE', 'Software', 'Software', null, null, null);
row('Detail', 1, 'DETAIL:FCAST', 'Advanced Forecasting', 'Software', 'Advanced Forecasting', 5400, 120);
row('Subtotal', 1, 'SUBTOTAL:FAMILY:SOFTWARE', 'Software Subtotal', 'Software', null, 5400, 120);

row('Grand Total', 0, 'GRAND_TOTAL', 'Total', null, null, 11400, 160);

if (multiCurrency) {
    for (Quote_Document_Row__c r : rows) { r.put('CurrencyIsoCode', (String) quote.get('CurrencyIsoCode')); }
}
insert rows;

table.Row_Count__c = rows.size();
table.Amount_List__c = 11400;
table.Amount_Regular__c = 11400;
table.Amount_Discount__c = 0;
table.Amount_Net__c = 11400;
table.Amount_Customer__c = 11400;
table.Quantity__c = 160;
table.Generated_On__c = System.now();
table.Status__c = 'Complete';
update table;

System.assertEquals(11400, table.Amount_Net__c, 'Optional Products grand total');
for (Quote_Document_Row__c r : rows) {
    if (r.Row_Type__c == 'Detail') {
        System.assert(r.Include_In_Grand_Total__c, 'Optional lines must count in this table specifically');
    }
}
System.debug('Example built for ' + quote.Name + ': ' + rows.size() + ' rows, grand total 11,400 (not part of the committed deal).');
