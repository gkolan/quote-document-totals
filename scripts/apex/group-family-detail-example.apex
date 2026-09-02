/**
 * Hand-built example for docs/use-case/05-quote-group-family-detail.md.
 *
 * Builds a two-phase, family-nested scenario (Phase 1 - Bristol Hub, Phase 2 -
 * Regional Depots) matching the shape of the seeded Aldergate quote in
 * quote-document-seed.apex, but as a standalone illustrative table - it does
 * not require SBQQ__QuoteLineGroup__c records to exist; the phase names are
 * only stamped onto Group_Value__c the way the other example scripts in this
 * set stamp their group labels.
 *
 * Safe to re-run: deletes only the GROUP_FAMILY_DETAIL table for the target
 * quote first.
 *
 *   sf apex run --target-org your-org-alias --file scripts/apex/group-family-detail-example.apex
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
    WHERE Quote__c = :quote.Id AND Table_Code__c = 'GROUP_FAMILY_DETAIL'
];

Boolean multiCurrency = UserInfo.isMultiCurrencyOrganization();

Quote_Document_Table__c table = new Quote_Document_Table__c(
    Name = quote.Name + ' - Quote Group and Family Detail',
    Quote__c = quote.Id,
    Table_Code__c = 'GROUP_FAMILY_DETAIL',
    Table_Key__c = quote.Id + ':GROUP_FAMILY_DETAIL',
    Display_Order__c = 40,
    Amount_Basis__c = 'Final Value',
    Group_Dimensions__c = 'QUOTE_LINE_GROUP > PRODUCT_FAMILY',
    Line_Filter__c = 'EXCLUDE_OPTIONAL',
    Measure_Set__c = 'PRICE_WATERFALL',
    Status__c = 'Generating'
);
if (multiCurrency) { table.put('CurrencyIsoCode', (String) quote.get('CurrencyIsoCode')); }
insert table;

Integer nextOrder = 10;
List<Quote_Document_Row__c> rows = new List<Quote_Document_Row__c>();

Quote_Document_Row__c row(String rowType, Integer level, String key, String label,
                           String groupDim, String groupVal, String productName,
                           Decimal net, Decimal qty) {
    Boolean isAggregate = rowType != 'Detail';
    Quote_Document_Row__c r = new Quote_Document_Row__c(
        Quote_Document_Table__c = table.Id,
        Row_Type__c = rowType,
        Group_Level__c = level,
        Row_Key__c = key,
        Display_Label__c = label,
        Group_Dimension__c = groupDim,
        Group_Value__c = groupVal,
        Product_Name__c = productName,
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

// Phase 1 - Bristol Hub
row('Group Header', 1, 'HEADER:GROUP:PHASE1', 'Phase 1 - Bristol Hub', 'QUOTE_LINE_GROUP', 'Phase 1 - Bristol Hub', null, null, null);
row('Group Header', 2, 'HEADER:PHASE1:HARDWARE', 'Hardware', 'PRODUCT_FAMILY', 'Hardware', null, null, null);
row('Detail', 2, 'DETAIL:PHASE1:T500', 'Field Terminal T500', 'PRODUCT_FAMILY', 'Hardware', 'Field Terminal T500', 54400, 80);
row('Detail', 2, 'DETAIL:PHASE1:T500B', 'T500 Extended Battery', 'PRODUCT_FAMILY', 'Hardware', 'T500 Extended Battery', 0, 80);
row('Detail', 2, 'DETAIL:PHASE1:T500D', 'T500 Docking Station', 'PRODUCT_FAMILY', 'Hardware', 'T500 Docking Station', 9747, 80);
row('Subtotal', 2, 'SUBTOTAL:PHASE1:HARDWARE', 'Hardware Subtotal', 'PRODUCT_FAMILY', 'Hardware', null, 64147, 240);
row('Group Header', 2, 'HEADER:PHASE1:SOFTWARE', 'Software', 'PRODUCT_FAMILY', 'Software', null, null, null);
row('Detail', 2, 'DETAIL:PHASE1:FLEET', 'Fleet Insight Platform', 'PRODUCT_FAMILY', 'Software', 'Fleet Insight Platform', 11808, 80);
row('Subtotal', 2, 'SUBTOTAL:PHASE1:SOFTWARE', 'Software Subtotal', 'PRODUCT_FAMILY', 'Software', null, 11808, 80);
row('Group Header', 2, 'HEADER:PHASE1:SERVICE', 'Service', 'PRODUCT_FAMILY', 'Service', null, null, null);
row('Detail', 2, 'DETAIL:PHASE1:IMPL', 'Implementation Services', 'PRODUCT_FAMILY', 'Service', 'Implementation Services', 15000, 1);
row('Subtotal', 2, 'SUBTOTAL:PHASE1:SERVICE', 'Service Subtotal', 'PRODUCT_FAMILY', 'Service', null, 15000, 1);
row('Subtotal', 1, 'SUBTOTAL:GROUP:PHASE1', 'Phase 1 - Bristol Hub Subtotal', 'QUOTE_LINE_GROUP', 'Phase 1 - Bristol Hub', null, 90955, 321);

// Phase 2 - Regional Depots
row('Group Header', 1, 'HEADER:GROUP:PHASE2', 'Phase 2 - Regional Depots', 'QUOTE_LINE_GROUP', 'Phase 2 - Regional Depots', null, null, null);
row('Group Header', 2, 'HEADER:PHASE2:HARDWARE', 'Hardware', 'PRODUCT_FAMILY', 'Hardware', null, null, null);
row('Detail', 2, 'DETAIL:PHASE2:S200', 'Depot Scanner S200', 'PRODUCT_FAMILY', 'Hardware', 'Depot Scanner S200', 16236, 45);
row('Detail', 2, 'DETAIL:PHASE2:G12', 'Network Gateway G12', 'PRODUCT_FAMILY', 'Hardware', 'Network Gateway G12', 8832, 4);
row('Subtotal', 2, 'SUBTOTAL:PHASE2:HARDWARE', 'Hardware Subtotal', 'PRODUCT_FAMILY', 'Hardware', null, 25068, 49);
row('Group Header', 2, 'HEADER:PHASE2:SERVICE', 'Service', 'PRODUCT_FAMILY', 'Service', null, null, null);
row('Detail', 2, 'DETAIL:PHASE2:TRAIN', 'Onsite Training (per day)', 'PRODUCT_FAMILY', 'Service', 'Onsite Training (per day)', 6000, 5);
row('Subtotal', 2, 'SUBTOTAL:PHASE2:SERVICE', 'Service Subtotal', 'PRODUCT_FAMILY', 'Service', null, 6000, 5);
row('Subtotal', 1, 'SUBTOTAL:GROUP:PHASE2', 'Phase 2 - Regional Depots Subtotal', 'QUOTE_LINE_GROUP', 'Phase 2 - Regional Depots', null, 31068, 54);

row('Grand Total', 0, 'GRAND_TOTAL', 'Total', null, null, null, 122023, 375);

if (multiCurrency) {
    for (Quote_Document_Row__c r : rows) { r.put('CurrencyIsoCode', (String) quote.get('CurrencyIsoCode')); }
}
insert rows;

table.Row_Count__c = rows.size();
table.Amount_List__c = 122023;
table.Amount_Regular__c = 122023;
table.Amount_Discount__c = 0;
table.Amount_Net__c = 122023;
table.Amount_Customer__c = 122023;
table.Quantity__c = 375;
table.Generated_On__c = System.now();
table.Status__c = 'Complete';
update table;

Integer levelOneCount = 0;
Integer levelTwoCount = 0;
for (Quote_Document_Row__c r : rows) {
    if (r.Row_Type__c == 'Group Header' && r.Group_Level__c == 1) { levelOneCount++; }
    if (r.Row_Type__c == 'Group Header' && r.Group_Level__c == 2) { levelTwoCount++; }
}
System.assertEquals(2, levelOneCount, 'Two phases at level 1');
System.assertEquals(5, levelTwoCount, 'Five family groups nested across both phases at level 2');
System.assertEquals(122023, table.Amount_Net__c, 'Group Family Detail grand total');
System.debug('Example built for ' + quote.Name + ': ' + rows.size() + ' rows, 2 nested phases, grand total 122,023.');
