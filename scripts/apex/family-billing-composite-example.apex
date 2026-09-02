/**
 * Hand-built example for docs/use-case/06-family-billing-frequency-summary.md.
 *
 * Recombines the canonical family totals from product-family-summary-example.apex
 * (Hardware 91,800 / Miscellaneous 3,500 / Service 410 / Software 7,200) into
 * composite Family/ChargeType buckets, so the two guides' numbers are directly
 * cross-checkable against the same underlying quote.
 *
 * Safe to re-run: deletes only the FAMILY_BILLING_COMPOSITE table for the
 * target quote first.
 *
 *   sf apex run --target-org your-org-alias --file scripts/apex/family-billing-composite-example.apex
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
    WHERE Quote__c = :quote.Id AND Table_Code__c = 'FAMILY_BILLING_COMPOSITE'
];

Boolean multiCurrency = UserInfo.isMultiCurrencyOrganization();

Quote_Document_Table__c table = new Quote_Document_Table__c(
    Name = quote.Name + ' - Family and Billing Composite',
    Quote__c = quote.Id,
    Table_Code__c = 'FAMILY_BILLING_COMPOSITE',
    Table_Key__c = quote.Id + ':FAMILY_BILLING_COMPOSITE',
    Display_Order__c = 70,
    Amount_Basis__c = 'Final Value',
    Group_Dimensions__c = 'SBQQ__Product__r.Family + CHARGE_TYPE',
    Line_Filter__c = 'EXCLUDE_OPTIONAL',
    Measure_Set__c = 'PRICE_WATERFALL',
    Status__c = 'Generating'
);
if (multiCurrency) { table.put('CurrencyIsoCode', (String) quote.get('CurrencyIsoCode')); }
insert table;

Integer nextOrder = 10;
List<Quote_Document_Row__c> rows = new List<Quote_Document_Row__c>();

// Every row here sits at Group_Level__c = 1 - a composite occupies one level,
// never two. That single fact is the entire distinction from a nested table.
Quote_Document_Row__c row(String rowType, String key, String label, Decimal net, Decimal qty) {
    Boolean isAggregate = rowType != 'Detail';
    Quote_Document_Row__c r = new Quote_Document_Row__c(
        Quote_Document_Table__c = table.Id,
        Row_Type__c = rowType,
        Group_Level__c = rowType == 'Grand Total' ? 0 : 1,
        Row_Key__c = key,
        Display_Label__c = label,
        Group_Dimension__c = rowType == 'Grand Total' ? null : 'SBQQ__Product__r.Family + CHARGE_TYPE',
        Group_Value__c = rowType == 'Grand Total' ? null : label,
        Display_Order__c = nextOrder,
        Is_Displayed__c = true,
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

row('Subtotal', 'SUBTOTAL:COMPOSITE:HARDWARE_ONETIME', 'Hardware / One-Time', 91800, 120);
row('Subtotal', 'SUBTOTAL:COMPOSITE:SOFTWARE_ONETIME', 'Software / One-Time', 7200, 80);
row('Subtotal', 'SUBTOTAL:COMPOSITE:SERVICE_ONETIME', 'Service / One-Time', 410, 2);
row('Subtotal', 'SUBTOTAL:COMPOSITE:MISC_ONETIME', 'Miscellaneous / One-Time', 3500, 120);
row('Subtotal', 'SUBTOTAL:COMPOSITE:RECURRING_RECURRING', 'Recurring / Recurring', 360, 1);
row('Grand Total', 'GRAND_TOTAL', 'Total', 102910, 322);

if (multiCurrency) {
    for (Quote_Document_Row__c r : rows) { r.put('CurrencyIsoCode', (String) quote.get('CurrencyIsoCode')); }
}
insert rows;

table.Row_Count__c = rows.size();
table.Amount_List__c = 102910;
table.Amount_Regular__c = 102910;
table.Amount_Discount__c = 0;
table.Amount_Net__c = 102910;
table.Amount_Customer__c = 102910;
table.Quantity__c = 322;
table.Generated_On__c = System.now();
table.Status__c = 'Complete';
update table;

for (Quote_Document_Row__c r : rows) {
    if (r.Row_Type__c == 'Subtotal') {
        System.assertEquals(1, r.Group_Level__c, 'Every composite bucket sits at level 1, never nested to 2');
    }
}
System.assertEquals(102910, table.Amount_Net__c, 'Family and Billing Composite grand total');
System.debug('Example built for ' + quote.Name + ': ' + rows.size() + ' composite rows, grand total 102,910 (cross-checks docs/use-case/01-product-family-summary.md).');
