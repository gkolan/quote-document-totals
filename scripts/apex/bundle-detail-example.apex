/**
 * Hand-built example for docs/use-case/04-bundle-detail.md.
 *
 * Rebuilds the canonical laptop/smartphone/standalone scenario from
 * quote-document-sample.apex as a standalone BUNDLE_DETAIL table, so this
 * guide has its own script per docs/documentation-standard.md.
 *
 * Safe to re-run: deletes only the BUNDLE_DETAIL table for the target quote
 * first.
 *
 *   sf apex run --target-org your-org-alias --file scripts/apex/bundle-detail-example.apex
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

Map<String, Id> lineByCode = new Map<String, Id>();
for (SBQQ__QuoteLine__c l : [
    SELECT Id, SBQQ__ProductCode__c FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c = :quote.Id
]) {
    lineByCode.put(l.SBQQ__ProductCode__c, l.Id);
}

delete [
    SELECT Id FROM Quote_Document_Table__c
    WHERE Quote__c = :quote.Id AND Table_Code__c = 'BUNDLE_DETAIL'
];

Boolean multiCurrency = UserInfo.isMultiCurrencyOrganization();

Quote_Document_Table__c table = new Quote_Document_Table__c(
    Name = quote.Name + ' - Bundle Detail',
    Quote__c = quote.Id,
    Table_Code__c = 'BUNDLE_DETAIL',
    Table_Key__c = quote.Id + ':BUNDLE_DETAIL',
    Display_Order__c = 30,
    Amount_Basis__c = 'Final Value',
    Group_Dimensions__c = 'BUNDLE',
    Line_Filter__c = 'EXCLUDE_OPTIONAL',
    Measure_Set__c = 'PRICE_WATERFALL',
    Status__c = 'Generating'
);
if (multiCurrency) { table.put('CurrencyIsoCode', (String) quote.get('CurrencyIsoCode')); }
insert table;

Integer nextOrder = 10;
List<Quote_Document_Row__c> rows = new List<Quote_Document_Row__c>();

Quote_Document_Row__c row(String rowType, Integer level, String key, String label, String bundleValue,
                           Id quoteLineId, Boolean counted,
                           Decimal listAmt, Decimal regular, Decimal discount, Decimal net, Decimal customer, Decimal qty) {
    Boolean isAggregate = rowType != 'Detail';
    Quote_Document_Row__c r = new Quote_Document_Row__c(
        Quote_Document_Table__c = table.Id,
        Row_Type__c = rowType,
        Group_Level__c = level,
        Row_Key__c = key,
        Display_Label__c = label,
        Group_Dimension__c = 'BUNDLE',
        Group_Value__c = bundleValue,
        Quote_Line__c = quoteLineId,
        Product_Name__c = rowType == 'Detail' ? label : null,
        Display_Order__c = nextOrder,
        Is_Displayed__c = true,
        Include_In_Subtotal__c = isAggregate ? false : counted,
        Include_In_Grand_Total__c = isAggregate ? false : counted,
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

// 15" Laptop bundle
row('Group Header', 1, 'HEADER:BUNDLE:LAPTOP15', '15" Laptop', '15" Laptop', null, true, null, null, null, null, null, null);
row('Detail', 1, 'DETAIL:LAPTOP15', '15" Laptop', '15" Laptop', lineByCode.get('LAPTOP15'), true, 60000, 60000, 0, 54000, 60000, 40);
row('Detail', 2, 'DETAIL:CPU22GHZI7', 'CPU 2.2GHz i7', '15" Laptop', lineByCode.get('CPU22GHZI7'), false, 0, 0, 0, 0, 0, 40);
row('Detail', 2, 'DETAIL:RAM8GB', 'RAM 8GB', '15" Laptop', lineByCode.get('RAM8GB'), false, 0, 0, 0, 0, 0, 40);
row('Detail', 2, 'DETAIL:SSD256', 'SSD Hard Drive 256GB', '15" Laptop', lineByCode.get('SSD256'), false, 0, 0, 0, 0, 0, 40);
row('Subtotal', 1, 'SUBTOTAL:BUNDLE:LAPTOP15', '15" Laptop Subtotal', '15" Laptop', null, true, 60000, 60000, 0, 54000, 60000, 40);

// 6" Smartphone bundle
row('Group Header', 1, 'HEADER:BUNDLE:SMARTPHONE6', '6" Smartphone', '6" Smartphone', null, true, null, null, null, null, null, null);
row('Detail', 1, 'DETAIL:SMARTPHONE6', '6" Smartphone', '6" Smartphone', lineByCode.get('SMARTPHONE6'), true, 26000, 26000, 0, 23400, 26000, 40);
row('Detail', 2, 'DETAIL:SMARTPHONECHARGER', 'Smartphone Charger', '6" Smartphone', lineByCode.get('SMARTPHONECHARGER'), false, 0, 0, 0, 0, 0, 40);
row('Detail', 2, 'DETAIL:USBCCHARGE1M', 'USB-C Charge Cable 1m', '6" Smartphone', lineByCode.get('USBCCHARGE1M'), false, 0, 0, 0, 0, 0, 40);
row('Detail', 2, 'DETAIL:SMARTPHONEACTIVATION', 'Smartphone Activation', '6" Smartphone', lineByCode.get('SMARTPHONEACTIVATION'), true, 50, 50, 0, 50, 50, 1);
row('Detail', 2, 'DETAIL:SMARTPHONECASE', 'Smartphone Case', '6" Smartphone', lineByCode.get('SMARTPHONECASE'), true, 800, 800, 0, 800, 800, 40);
row('Subtotal', 1, 'SUBTOTAL:BUNDLE:SMARTPHONE6', '6" Smartphone Subtotal', '6" Smartphone', null, true, 26850, 26850, 0, 24250, 26850, 81);

// Standalone products
row('Group Header', 1, 'HEADER:BUNDLE:STANDALONE', 'Standalone Products', 'Standalone Products', null, true, null, null, null, null, null, null);
row('Detail', 1, 'DETAIL:MONITOR4K', '4K Monitor', 'Standalone Products', lineByCode.get('MONITOR4K'), true, 16000, 16000, 1600, 14400, 14400, 40);
row('Detail', 1, 'DETAIL:USBWEBCAMMIC', 'USB Webcam w/ Integrated Microphone', 'Standalone Products', lineByCode.get('USBWEBCAMMIC'), true, 1400, 1400, 140, 1260, 1260, 40);
row('Detail', 1, 'DETAIL:2FAUSBKEY', '2 Factor Authentication USB Key', 'Standalone Products', lineByCode.get('2FAUSBKEY'), true, 1600, 1600, 160, 1440, 1440, 40);
row('Detail', 1, 'DETAIL:VPNLICENSE', 'VPN License', 'Standalone Products', lineByCode.get('VPNLICENSE'), true, 4800, 4800, 1200, 3600, 3600, 40);
row('Detail', 1, 'DETAIL:PRODUCTIVITYSUITE', 'Productivity Suite', 'Standalone Products', lineByCode.get('PRODUCTIVITYSUITE'), true, 4800, 4800, 1200, 3600, 3600, 40);
row('Detail', 1, 'DETAIL:SMARTPHONESTANDARDPLAN', 'Smartphone Standard Plan', 'Standalone Products', lineByCode.get('SMARTPHONESTANDARDPLAN'), true, 360, 360, 0, 360, 360, 1);
row('Subtotal', 1, 'SUBTOTAL:BUNDLE:STANDALONE', 'Standalone Products Subtotal', 'Standalone Products', null, true, 28960, 28960, 4300, 24660, 24660, 201);

row('Grand Total', 0, 'GRAND_TOTAL', 'Total', null, null, true, 115810, 115810, 4300, 102910, 111510, 322);

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

System.assertEquals(102910, table.Amount_Net__c, 'Bundle Detail grand total');
System.debug('Example built for ' + quote.Name + ': ' + rows.size() + ' rows, grand total 102,910.');
