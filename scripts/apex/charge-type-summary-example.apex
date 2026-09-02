/**
 * Hand-built example for docs/use-case/02-charge-type-summary.md.
 *
 * Reuses the canonical One-Time (102,550) / Recurring (360) split from
 * quote-document-sample.apex's Section Totals, rebuilt as its own table so
 * this guide has a standalone script per docs/documentation-standard.md.
 *
 * Safe to re-run: deletes only the CHARGE_TYPE_SUMMARY table for the target
 * quote first.
 *
 *   sf apex run --target-org your-org-alias --file scripts/apex/charge-type-summary-example.apex
 */

List<SBQQ__Quote__c> seeded = [
    SELECT Id, Name FROM SBQQ__Quote__c
    WHERE SBQQ__Account__r.Name LIKE 'Ridgeline Manufacturing%'
    ORDER BY CreatedDate DESC LIMIT 1
];
SBQQ__Quote__c quote = !seeded.isEmpty() ? seeded[0] : [
    SELECT Id, Name FROM SBQQ__Quote__c ORDER BY CreatedDate DESC LIMIT 1
];

// CurrencyIsoCode cannot be named in the static SOQL above: the field only
// exists when multi-currency is on, so a single-currency org would fail to
// compile it. This script stamps the table with the quote's currency, so
// re-read the quote through dynamic SOQL that adds the field only when the
// org actually has it - the same guard QuoteDocumentQuery uses.
Id qdtdQuoteId = quote.Id;
quote = (SBQQ__Quote__c) Database.query(
    'SELECT Id, Name'
    + (UserInfo.isMultiCurrencyOrganization() ? ', CurrencyIsoCode' : '')
    + ' FROM SBQQ__Quote__c WHERE Id = :qdtdQuoteId LIMIT 1'
);

delete [
    SELECT Id FROM Quote_Document_Table__c
    WHERE Quote__c = :quote.Id AND Table_Code__c = 'CHARGE_TYPE_SUMMARY'
];

Boolean multiCurrency = UserInfo.isMultiCurrencyOrganization();

Quote_Document_Table__c table = new Quote_Document_Table__c(
    Name = quote.Name + ' - Charge Type Summary',
    Quote__c = quote.Id,
    Table_Code__c = 'CHARGE_TYPE_SUMMARY',
    Table_Key__c = quote.Id + ':CHARGE_TYPE_SUMMARY',
    Display_Order__c = 20,
    Amount_Basis__c = 'Final Value',
    Group_Dimensions__c = 'CHARGE_TYPE',
    Line_Filter__c = 'EXCLUDE_OPTIONAL',
    Measure_Set__c = 'PRICE_WATERFALL',
    Status__c = 'Generating'
);
if (multiCurrency) { table.put('CurrencyIsoCode', (String) quote.get('CurrencyIsoCode')); }
insert table;

Integer nextOrder = 10;
List<Quote_Document_Row__c> rows = new List<Quote_Document_Row__c>();

Quote_Document_Row__c row(String rowType, Integer level, String key, String label, String groupValue,
                           Decimal listAmt, Decimal regular, Decimal discount, Decimal net, Decimal customer, Decimal qty) {
    Boolean isAggregate = rowType != 'Detail';
    Quote_Document_Row__c r = new Quote_Document_Row__c(
        Quote_Document_Table__c = table.Id,
        Row_Type__c = rowType,
        Group_Level__c = level,
        Row_Key__c = key,
        Display_Label__c = label,
        Group_Dimension__c = groupValue == null ? null : 'CHARGE_TYPE',
        Group_Value__c = groupValue,
        Display_Order__c = nextOrder,
        Is_Displayed__c = true,
        Include_In_Subtotal__c = !isAggregate,
        Include_In_Grand_Total__c = !isAggregate,
        Amount_List__c = listAmt,
        Amount_Regular__c = regular,
        Amount_Discount__c = discount,
        Amount_Net__c = net,
        Amount_Customer__c = customer,
        Quantity__c = qty
    );
    nextOrder += 10;
    rows.add(r);
    return r;
}

row('Subtotal', 1, 'SUBTOTAL:CHARGE:ONE_TIME', 'One-Time Subtotal', 'One-Time',
    115450, 115450, 4300, 102550, 111150, 321);
row('Subtotal', 1, 'SUBTOTAL:CHARGE:RECURRING', 'Recurring Subtotal', 'Recurring',
    360, 360, 0, 360, 360, 1);
row('Grand Total', 0, 'GRAND_TOTAL', 'Total', null,
    115810, 115810, 4300, 102910, 111510, 322);

if (multiCurrency) {
    for (Quote_Document_Row__c r : rows) { r.put('CurrencyIsoCode', (String) quote.get('CurrencyIsoCode')); }
}
insert rows;

table.Row_Count__c = rows.size();
table.Amount_List__c = 115810;
table.Amount_Regular__c = 115810;
table.Amount_Discount__c = 4300;
table.Amount_Net__c = 102910;
table.Amount_Customer__c = 111510;
table.Quantity__c = 322;
table.Generated_On__c = System.now();
table.Status__c = 'Complete';
update table;

System.assertEquals(102910, table.Amount_Net__c, 'Charge Type Summary grand total');
System.debug('Example built for ' + quote.Name + ': ' + rows.size() + ' rows, grand total 102,910.');
