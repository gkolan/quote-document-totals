/**
 * Hand-built example for docs/product-family-summary-guide.md.
 *
 * Reuses the canonical family/section numbers from quote-document-sample.apex
 * (Hardware 91,800 / Miscellaneous 3,500 / Service 410 / Software 7,200, and
 * the One-Time/Recurring section split), rebuilt in isolation so this guide
 * has its own script per the standard in docs/documentation-standards.md,
 * without depending on quote-document-sample.apex having been run first.
 *
 * Safe to re-run: deletes only the PRODUCT_FAMILY_SUMMARY table for the
 * target quote first.
 *
 *   sf apex run --target-org gkCPQDev --file scripts/apex/product-family-summary-example.apex
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
    WHERE Quote__c = :quote.Id AND Table_Code__c = 'PRODUCT_FAMILY_SUMMARY'
];

Boolean multiCurrency = UserInfo.isMultiCurrencyOrganization();

Quote_Document_Table__c table = new Quote_Document_Table__c(
    Name = quote.Name + ' - Product Family Summary',
    Quote__c = quote.Id,
    Table_Code__c = 'PRODUCT_FAMILY_SUMMARY',
    Table_Key__c = quote.Id + ':PRODUCT_FAMILY_SUMMARY',
    Display_Order__c = 10,
    Amount_Basis__c = 'Final Value',
    Group_Dimensions__c = 'PRODUCT_FAMILY',
    Line_Filter__c = 'EXCLUDE_OPTIONAL',
    Measure_Set__c = 'PRICE_WATERFALL',
    Status__c = 'Generating'
);
if (multiCurrency) { table.put('CurrencyIsoCode', (String) quote.get('CurrencyIsoCode')); }
insert table;

Integer nextOrder = 10;
List<Quote_Document_Row__c> rows = new List<Quote_Document_Row__c>();

Quote_Document_Row__c row(String rowType, Integer level, String key, String label,
                           Decimal listAmt, Decimal regular, Decimal discount, Decimal net, Decimal customer, Decimal qty) {
    Boolean isAggregate = rowType != 'Detail';
    Quote_Document_Row__c r = new Quote_Document_Row__c(
        Quote_Document_Table__c = table.Id,
        Row_Type__c = rowType,
        Group_Level__c = level,
        Row_Key__c = key,
        Display_Label__c = label,
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

Quote_Document_Row__c hw = row('Subtotal', 1, 'SUBTOTAL:FAMILY:HARDWARE', 'Hardware Subtotal',
    102000, 102000, 1600, 91800, 100400, 120);
hw.Group_Dimension__c = 'PRODUCT_FAMILY'; hw.Group_Value__c = 'Hardware';

Quote_Document_Row__c misc = row('Subtotal', 1, 'SUBTOTAL:FAMILY:MISC', 'Miscellaneous Subtotal',
    3800, 3800, 300, 3500, 3500, 120);
misc.Group_Dimension__c = 'PRODUCT_FAMILY'; misc.Group_Value__c = 'Miscellaneous';

Quote_Document_Row__c svc = row('Subtotal', 1, 'SUBTOTAL:FAMILY:SERVICE', 'Service Subtotal',
    410, 410, 0, 410, 410, 2);
svc.Group_Dimension__c = 'PRODUCT_FAMILY'; svc.Group_Value__c = 'Service';

Quote_Document_Row__c sw = row('Subtotal', 1, 'SUBTOTAL:FAMILY:SOFTWARE', 'Software Subtotal',
    9600, 9600, 2400, 7200, 7200, 80);
sw.Group_Dimension__c = 'PRODUCT_FAMILY'; sw.Group_Value__c = 'Software';

Quote_Document_Row__c oneTime = row('Section Total', 0, 'SECTION:CHARGE_TYPE:ONE_TIME', 'Total One-Time Charges',
    115450, 115450, 4300, 102550, 111150, 321);
oneTime.Group_Dimension__c = 'CHARGE_TYPE'; oneTime.Group_Value__c = 'One-Time';

Quote_Document_Row__c recurring = row('Section Total', 0, 'SECTION:CHARGE_TYPE:RECURRING', 'Total Recurring Charges',
    360, 360, 0, 360, 360, 1);
recurring.Group_Dimension__c = 'CHARGE_TYPE'; recurring.Group_Value__c = 'Recurring';

row('Grand Total', 0, 'GRAND_TOTAL', 'Total', 115810, 115810, 4300, 102910, 111510, 322);

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

System.assertEquals(102910, table.Amount_Net__c, 'Product Family Summary grand total');
System.debug('Example built for ' + quote.Name + ': ' + rows.size() + ' rows, grand total 102,910.');
