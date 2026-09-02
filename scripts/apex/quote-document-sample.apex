/**
 * Hand-built sample of Quote Document Tables and Rows for the newest Quote.
 *
 * This is NOT generator output. It is written by hand so you can see the
 * intended saved-record shape without running the generator, and it can show
 * scenarios the current org data cannot produce (there are no amendment
 * quotes, so no cancellations or terminations exist to classify).
 *
 * Safe to re-run: it deletes the quote's existing tables first, and the
 * master-detail cascade takes the rows with them.
 *
 *   sf apex run --target-org your-org-alias --file scripts/apex/quote-document-sample.apex
 */

// ---------------------------------------------------------------------------
// Helper: accumulates rows for one table and numbers them in render order.
// ---------------------------------------------------------------------------
class RowSet {
    public List<Quote_Document_Row__c> rows = new List<Quote_Document_Row__c>();
    private Integer nextOrder = 10;

    // Aggregate rows: headers and the three kinds of total. Never counted.
    public Quote_Document_Row__c aggregate(String rowType, Integer level, String key, String label) {
        Quote_Document_Row__c r = base(rowType, level, key, label);
        r.Include_In_Subtotal__c = false;
        r.Include_In_Grand_Total__c = false;
        return r;
    }

    // Detail rows: one per Quote Line. `counted` is false for bundled
    // components (price sits in the package) and optional products.
    public Quote_Document_Row__c detail(Integer level, String key, String label, Id quoteLineId, Boolean counted) {
        Quote_Document_Row__c r = base('Detail', level, key, label);
        r.Quote_Line__c = quoteLineId;
        r.Include_In_Subtotal__c = counted;
        r.Include_In_Grand_Total__c = counted;
        return r;
    }

    private Quote_Document_Row__c base(String rowType, Integer level, String key, String label) {
        Quote_Document_Row__c r = new Quote_Document_Row__c(
            Row_Type__c = rowType,
            Group_Level__c = level,
            Row_Key__c = key,
            Display_Label__c = label,
            Display_Order__c = nextOrder,
            Is_Displayed__c = true
        );
        nextOrder += 10;
        rows.add(r);
        return r;
    }

    // The five price-waterfall measures plus quantity, in one call.
    public Quote_Document_Row__c money(Quote_Document_Row__c r, Decimal listAmount, Decimal regular,
                                       Decimal discount, Decimal net, Decimal customer, Decimal qty) {
        r.Amount_List__c = listAmount;
        r.Amount_Regular__c = regular;
        r.Amount_Discount__c = discount;
        r.Amount_Net__c = net;
        r.Amount_Customer__c = customer;
        r.Quantity__c = qty;
        return r;
    }
}

// ---------------------------------------------------------------------------
// Source records
// ---------------------------------------------------------------------------
SBQQ__Quote__c quote = [
    SELECT Id, Name, SBQQ__NetAmount__c
    FROM SBQQ__Quote__c
    ORDER BY CreatedDate DESC
    LIMIT 1
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
    SELECT Id, SBQQ__ProductCode__c
    FROM SBQQ__QuoteLine__c
    WHERE SBQQ__Quote__c = :quote.Id
]) {
    lineByCode.put(l.SBQQ__ProductCode__c, l.Id);
}

delete [SELECT Id FROM Quote_Document_Table__c WHERE Quote__c = :quote.Id];

Boolean multiCurrency = UserInfo.isMultiCurrencyOrganization();

// ===========================================================================
// Table 1 - Product Family Summary
// Subtotal per family, then Section Totals splitting recurring from one-time,
// then the grand total. Optional products are excluded, so the grand total
// Net reconciles to the Quote's Net Amount of 102,910.
// ===========================================================================
Quote_Document_Table__c familyTable = new Quote_Document_Table__c(
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

// ===========================================================================
// Table 2 - Bundle Detail
// Packages with their components indented at level 2. Bundled components show
// zero and are not counted; separately-priced options are counted. The
// optional tablet is displayed in its own row but excluded from every total.
// ===========================================================================
Quote_Document_Table__c bundleTable = new Quote_Document_Table__c(
    Name = quote.Name + ' - Bundle Detail',
    Quote__c = quote.Id,
    Table_Code__c = 'BUNDLE_DETAIL',
    Table_Key__c = quote.Id + ':BUNDLE_DETAIL',
    Display_Order__c = 20,
    Amount_Basis__c = 'Final Value',
    Group_Dimensions__c = 'BUNDLE',
    Line_Filter__c = 'EXCLUDE_OPTIONAL',
    Measure_Set__c = 'PRICE_WATERFALL',
    Status__c = 'Generating'
);

// ===========================================================================
// Table 3 - Transaction Summary
// Illustrative only. No amendment quotes exist in this org, so these amounts
// are invented to show the change measure set and the negative-sign rule.
// ===========================================================================
Quote_Document_Table__c changeTable = new Quote_Document_Table__c(
    Name = quote.Name + ' - Transaction Summary (illustrative)',
    Quote__c = quote.Id,
    Table_Code__c = 'TRANSACTION_SUMMARY',
    Table_Key__c = quote.Id + ':TRANSACTION_SUMMARY',
    Display_Order__c = 30,
    Amount_Basis__c = 'Net Change',
    Group_Dimensions__c = 'TRANSACTION_TYPE',
    Line_Filter__c = 'EXCLUDE_OPTIONAL',
    Measure_Set__c = 'CHANGE',
    Status__c = 'Generating'
);

List<Quote_Document_Table__c> tables =
    new List<Quote_Document_Table__c>{ familyTable, bundleTable, changeTable };

if (multiCurrency) {
    for (Quote_Document_Table__c t : tables) {
        t.put('CurrencyIsoCode', (String) quote.get('CurrencyIsoCode'));
    }
}
insert tables;

// ---------------------------------------------------------------------------
// Table 1 rows
// ---------------------------------------------------------------------------
RowSet fam = new RowSet();

fam.money(fam.aggregate('Group Header', 1, 'HEADER:FAMILY:HARDWARE', 'Hardware'),
          null, null, null, null, null, null);
fam.money(fam.aggregate('Subtotal', 1, 'SUBTOTAL:FAMILY:HARDWARE', 'Hardware Subtotal'),
          102000, 102000, 1600, 91800, 100400, 120);

fam.money(fam.aggregate('Group Header', 1, 'HEADER:FAMILY:MISCELLANEOUS', 'Miscellaneous'),
          null, null, null, null, null, null);
fam.money(fam.aggregate('Subtotal', 1, 'SUBTOTAL:FAMILY:MISCELLANEOUS', 'Miscellaneous Subtotal'),
          3800, 3800, 300, 3500, 3500, 120);

fam.money(fam.aggregate('Group Header', 1, 'HEADER:FAMILY:SERVICE', 'Service'),
          null, null, null, null, null, null);
fam.money(fam.aggregate('Subtotal', 1, 'SUBTOTAL:FAMILY:SERVICE', 'Service Subtotal'),
          410, 410, 0, 410, 410, 2);

fam.money(fam.aggregate('Group Header', 1, 'HEADER:FAMILY:SOFTWARE', 'Software'),
          null, null, null, null, null, null);
fam.money(fam.aggregate('Subtotal', 1, 'SUBTOTAL:FAMILY:SOFTWARE', 'Software Subtotal'),
          9600, 9600, 2400, 7200, 7200, 80);

// Section totals cut the same lines a different way - by charge type rather
// than by family. They sit alongside the family subtotals, not underneath them.
fam.money(fam.aggregate('Section Total', 0, 'SECTION:CHARGE_TYPE:ONE_TIME', 'Total One-Time Charges'),
          115450, 115450, 4300, 102550, 111150, 321);
fam.money(fam.aggregate('Section Total', 0, 'SECTION:CHARGE_TYPE:RECURRING', 'Total Recurring Charges'),
          360, 360, 0, 360, 360, 1);

// An informational row: displayed, but contributing to nothing.
Quote_Document_Row__c note = fam.aggregate('Informational', 0, 'INFO:OPTIONAL_EXCLUDED',
    'Optional products are quoted separately and are not included in the totals above.');

fam.money(fam.aggregate('Grand Total', 0, 'GRAND_TOTAL', 'Total'),
          115810, 115810, 4300, 102910, 111510, 322);

for (Quote_Document_Row__c r : fam.rows) { r.Quote_Document_Table__c = familyTable.Id; }

// ---------------------------------------------------------------------------
// Table 2 rows
// ---------------------------------------------------------------------------
RowSet bun = new RowSet();

// Package 1 - the laptop. Components are visible at zero and not counted,
// because their price is already inside the package price.
bun.money(bun.aggregate('Group Header', 1, 'HEADER:BUNDLE:LAPTOP15', '15" Laptop'),
          null, null, null, null, null, null);
bun.money(bun.detail(1, 'DETAIL:LAPTOP15', '15" Laptop', lineByCode.get('LAPTOP15'), true),
          60000, 60000, 0, 54000, 60000, 40);
bun.money(bun.detail(2, 'DETAIL:CPU22GHZI7', 'CPU 2.2GHz i7', lineByCode.get('CPU22GHZI7'), false),
          0, 0, 0, 0, 0, 40);
bun.money(bun.detail(2, 'DETAIL:RAM8GB', 'RAM 8GB', lineByCode.get('RAM8GB'), false),
          0, 0, 0, 0, 0, 40);
bun.money(bun.detail(2, 'DETAIL:SSD256', 'SSD Hard Drive 256GB', lineByCode.get('SSD256'), false),
          0, 0, 0, 0, 0, 40);
bun.money(bun.aggregate('Subtotal', 1, 'SUBTOTAL:BUNDLE:LAPTOP15', '15" Laptop Subtotal'),
          60000, 60000, 0, 54000, 60000, 40);

// Package 2 - the smartphone. Charger and cable are bundled and uncounted;
// activation and case carry their own price and are counted.
bun.money(bun.aggregate('Group Header', 1, 'HEADER:BUNDLE:SMARTPHONE6', '6" Smartphone'),
          null, null, null, null, null, null);
bun.money(bun.detail(1, 'DETAIL:SMARTPHONE6', '6" Smartphone', lineByCode.get('SMARTPHONE6'), true),
          26000, 26000, 0, 23400, 26000, 40);
bun.money(bun.detail(2, 'DETAIL:SMARTPHONECHARGER', 'Smartphone Charger', lineByCode.get('SMARTPHONECHARGER'), false),
          0, 0, 0, 0, 0, 40);
bun.money(bun.detail(2, 'DETAIL:USBCCHARGE1M', 'USB-C Charge Cable 1m', lineByCode.get('USBCCHARGE1M'), false),
          0, 0, 0, 0, 0, 40);
bun.money(bun.detail(2, 'DETAIL:SMARTPHONEACTIVATION', 'Smartphone Activation', lineByCode.get('SMARTPHONEACTIVATION'), true),
          50, 50, 0, 50, 50, 1);
bun.money(bun.detail(2, 'DETAIL:SMARTPHONECASE', 'Smartphone Case', lineByCode.get('SMARTPHONECASE'), true),
          800, 800, 0, 800, 800, 40);
bun.money(bun.aggregate('Subtotal', 1, 'SUBTOTAL:BUNDLE:SMARTPHONE6', '6" Smartphone Subtotal'),
          26850, 26850, 0, 24250, 26850, 81);

// Everything that is not part of a package.
bun.money(bun.aggregate('Group Header', 1, 'HEADER:BUNDLE:STANDALONE', 'Standalone Products'),
          null, null, null, null, null, null);
bun.money(bun.detail(1, 'DETAIL:MONITOR4K', '4K Monitor', lineByCode.get('MONITOR4K'), true),
          16000, 16000, 1600, 14400, 14400, 40);
bun.money(bun.detail(1, 'DETAIL:USBWEBCAMMIC', 'USB Webcam w/ Integrated Microphone', lineByCode.get('USBWEBCAMMIC'), true),
          1400, 1400, 140, 1260, 1260, 40);
bun.money(bun.detail(1, 'DETAIL:2FAUSBKEY', '2 Factor Authentication USB Key', lineByCode.get('2FAUSBKEY'), true),
          1600, 1600, 160, 1440, 1440, 40);
bun.money(bun.detail(1, 'DETAIL:VPNLICENSE', 'VPN License', lineByCode.get('VPNLICENSE'), true),
          4800, 4800, 1200, 3600, 3600, 40);
bun.money(bun.detail(1, 'DETAIL:PRODUCTIVITYSUITE', 'Productivity Suite', lineByCode.get('PRODUCTIVITYSUITE'), true),
          4800, 4800, 1200, 3600, 3600, 40);
bun.money(bun.detail(1, 'DETAIL:SMARTPHONESTANDARDPLAN', 'Smartphone Standard Plan', lineByCode.get('SMARTPHONESTANDARDPLAN'), true),
          360, 360, 0, 360, 360, 1);
bun.money(bun.aggregate('Subtotal', 1, 'SUBTOTAL:BUNDLE:STANDALONE', 'Standalone Products Subtotal'),
          28960, 28960, 4300, 24660, 24660, 201);

// The optional product. Shown so the customer sees the price, counted nowhere.
Quote_Document_Row__c tablet = bun.detail(1, 'DETAIL:TABLET10', '10" Tablet (optional)',
                                          lineByCode.get('TABLET10'), false);
bun.money(tablet, 6000, 6000, 0, 6000, 6000, 40);

bun.money(bun.aggregate('Grand Total', 0, 'GRAND_TOTAL', 'Total'),
          115810, 115810, 4300, 102910, 111510, 322);

for (Quote_Document_Row__c r : bun.rows) { r.Quote_Document_Table__c = bundleTable.Id; }

// ---------------------------------------------------------------------------
// Table 3 rows - the change measure set. Removals are negative, always.
// ---------------------------------------------------------------------------
RowSet chg = new RowSet();

Quote_Document_Row__c netNew = chg.aggregate('Subtotal', 1, 'SUBTOTAL:TXN:NET_NEW', 'Net New');
netNew.Transaction_Type__c = 'Net New';
netNew.Amount_Net_New__c = 45000;
netNew.Amount_Net_Change__c = 45000;

Quote_Document_Row__c cancel = chg.aggregate('Subtotal', 1, 'SUBTOTAL:TXN:CANCELLATION', 'Cancellations');
cancel.Transaction_Type__c = 'Cancellation';
cancel.Amount_Cancellation__c = -12000;
cancel.Amount_Net_Change__c = -12000;

Quote_Document_Row__c replOut = chg.aggregate('Subtotal', 1, 'SUBTOTAL:TXN:REPL_REMOVED', 'Products Replaced');
replOut.Transaction_Type__c = 'Replacement Removed';
replOut.Amount_Replacement_Removed__c = -8000;
replOut.Amount_Net_Change__c = -8000;

Quote_Document_Row__c replIn = chg.aggregate('Subtotal', 1, 'SUBTOTAL:TXN:REPL_ADDED', 'Replacement Products');
replIn.Transaction_Type__c = 'Replacement Added';
replIn.Amount_Replacement_Added__c = 9500;
replIn.Amount_Net_Change__c = 9500;

Quote_Document_Row__c term = chg.aggregate('Subtotal', 1, 'SUBTOTAL:TXN:TERMINATION', 'Terminations');
term.Transaction_Type__c = 'Termination';
term.Amount_Termination__c = -5000;
term.Amount_Net_Change__c = -5000;

Quote_Document_Row__c chgTotal = chg.aggregate('Grand Total', 0, 'GRAND_TOTAL', 'Net Change');
chgTotal.Amount_Net_New__c = 45000;
chgTotal.Amount_Cancellation__c = -12000;
chgTotal.Amount_Replacement_Removed__c = -8000;
chgTotal.Amount_Replacement_Added__c = 9500;
chgTotal.Amount_Termination__c = -5000;
chgTotal.Amount_Net_Change__c = 29500;

for (Quote_Document_Row__c r : chg.rows) { r.Quote_Document_Table__c = changeTable.Id; }

// ---------------------------------------------------------------------------
// Persist, then stamp each table from its own grand total row.
// ---------------------------------------------------------------------------
List<Quote_Document_Row__c> allRows = new List<Quote_Document_Row__c>();
allRows.addAll(fam.rows);
allRows.addAll(bun.rows);
allRows.addAll(chg.rows);

if (multiCurrency) {
    for (Quote_Document_Row__c r : allRows) {
        r.put('CurrencyIsoCode', (String) quote.get('CurrencyIsoCode'));
    }
}
insert allRows;

familyTable.Row_Count__c = fam.rows.size();
familyTable.Amount_List__c = 115810;
familyTable.Amount_Regular__c = 115810;
familyTable.Amount_Discount__c = 4300;
familyTable.Amount_Net__c = 102910;
familyTable.Amount_Customer__c = 111510;
familyTable.Quantity__c = 322;

bundleTable.Row_Count__c = bun.rows.size();
bundleTable.Amount_List__c = 115810;
bundleTable.Amount_Regular__c = 115810;
bundleTable.Amount_Discount__c = 4300;
bundleTable.Amount_Net__c = 102910;
bundleTable.Amount_Customer__c = 111510;
bundleTable.Quantity__c = 322;

changeTable.Row_Count__c = chg.rows.size();
changeTable.Amount_Net_New__c = 45000;
changeTable.Amount_Cancellation__c = -12000;
changeTable.Amount_Replacement_Removed__c = -8000;
changeTable.Amount_Replacement_Added__c = 9500;
changeTable.Amount_Termination__c = -5000;
changeTable.Amount_Net_Change__c = 29500;

for (Quote_Document_Table__c t : tables) {
    t.Generated_On__c = System.now();
    t.Status__c = 'Complete';
}
update tables;

// The check that matters: the price-waterfall grand total must equal the
// Quote's own Net Amount, or a signed document would carry a wrong number.
System.assertEquals(quote.SBQQ__NetAmount__c, familyTable.Amount_Net__c,
    'Product Family Summary must reconcile to the Quote Net Amount');
System.assertEquals(quote.SBQQ__NetAmount__c, bundleTable.Amount_Net__c,
    'Bundle Detail must reconcile to the Quote Net Amount');

System.debug('Sample built for ' + quote.Name + ': ' + tables.size() + ' tables, '
    + allRows.size() + ' rows, reconciled to ' + quote.SBQQ__NetAmount__c);

