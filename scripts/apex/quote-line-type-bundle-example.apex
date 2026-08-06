/**
 * Hand-built example for docs/quote-line-type-bundle-reporting-guide.md §10.
 *
 * Builds the exact "bundle with a Cancellation and a Replacement pair inside
 * it, plus a standalone Net New and a standalone Termination outside it"
 * scenario the guide walks through by hand, as real Quote_Document_Table__c /
 * Quote_Document_Row__c records, across all four views:
 *
 *   TRANSACTION_SUMMARY   - totals by transaction type (View A, already shipped)
 *   BUNDLE_PRODUCT_GRID   - the product/bundle grid, 5 columns (View B, new)
 *   BUNDLE_SUMMARY        - bundle totals incl. Uncategorized (View C, new)
 *   PRODUCT_SUMMARY       - product totals (View D, new)
 *
 * This is NOT generator output - it does not require the Custom Metadata from
 * the guide's §5-7 to be deployed, and it does not depend on QuoteDocumentLine
 * classifying anything. It exists so there is always a known-good, numerically
 * consistent example to build and test reports and the DocuSign/CLM template
 * against (guide §11 step 4's verification query, and §13.9's testing steps),
 * independent of whether the real amendment-quote data this feature ultimately
 * needs actually exists yet in this org.
 *
 * All four grand totals below agree at 6,300, on purpose - that is the same
 * cross-check the guide tells you to run before trusting a document.
 *
 * Safe to re-run: it deletes only these four table codes for the target
 * quote first (never the illustrative tables from quote-document-sample.apex,
 * which use different codes/content and are left alone).
 *
 *   sf apex run --target-org gkCPQDev --file scripts/apex/quote-line-type-bundle-example.apex
 */

// Fallback quote name, used only if no "Ridgeline Manufacturing" quote from
// quote-document-seed.apex is found (see the query below). Change this if
// you're running against an org with neither - e.g. the existing gkCPQDev
// sandbox convention used elsewhere in this repo's scripts. The quote itself
// is only a hook to hang the tables on - its real lines are untouched, and
// this script does not need the product names below to match anything that
// actually exists on it.
final String QUOTE_NAME = 'Q-00053';

final List<String> TABLE_CODES = new List<String>{
    'TRANSACTION_SUMMARY', 'BUNDLE_PRODUCT_GRID', 'BUNDLE_SUMMARY', 'PRODUCT_SUMMARY'
};

// ---------------------------------------------------------------------------
// Helper: accumulates change-measure rows for one table, numbering them in
// render order. Mirrors the RowSet pattern in quote-document-sample.apex.
// ---------------------------------------------------------------------------
class RowSet {
    public List<Quote_Document_Row__c> rows = new List<Quote_Document_Row__c>();
    private Integer nextOrder = 10;

    // Aggregate rows: headers and the two kinds of total. Never counted.
    public Quote_Document_Row__c aggregate(String rowType, Integer level, String key, String label) {
        Quote_Document_Row__c r = base(rowType, level, key, label);
        r.Include_In_Subtotal__c = false;
        r.Include_In_Grand_Total__c = false;
        return r;
    }

    // Detail rows: one per quote line. Every row here counts - this example
    // has no bundled components or optional products to exclude.
    public Quote_Document_Row__c detail(Integer level, String key, String label, String productName) {
        Quote_Document_Row__c r = base('Detail', level, key, label);
        r.Product_Name__c = productName;
        r.Include_In_Subtotal__c = true;
        r.Include_In_Grand_Total__c = true;
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

    // The five change measures plus the net-change delta, in one call.
    public Quote_Document_Row__c change(
        Quote_Document_Row__c r, String transactionType,
        Decimal netNew, Decimal cancellation, Decimal replRemoved, Decimal replAdded, Decimal termination
    ) {
        if (transactionType != null) { r.Transaction_Type__c = transactionType; }
        r.Amount_Net_New__c = netNew;
        r.Amount_Cancellation__c = cancellation;
        r.Amount_Replacement_Removed__c = replRemoved;
        r.Amount_Replacement_Added__c = replAdded;
        r.Amount_Termination__c = termination;
        r.Amount_Net_Change__c = netNew + cancellation + replRemoved + replAdded + termination;
        r.Amount_Final__c = r.Amount_Net_Change__c;
        return r;
    }
}

// ---------------------------------------------------------------------------
// Source quote
//
// Prefers the "Ridgeline Manufacturing" quote from quote-document-seed.apex,
// so the two scripts compose cleanly in a fresh scratch org without editing
// anything. Falls back to QUOTE_NAME (the convention used against the
// existing gkCPQDev sandbox, where the seed script has not necessarily run).
// ---------------------------------------------------------------------------
List<SBQQ__Quote__c> seeded = [
    SELECT Id, Name FROM SBQQ__Quote__c
    WHERE SBQQ__Account__r.Name LIKE 'Ridgeline Manufacturing%'
    ORDER BY CreatedDate DESC
    LIMIT 1
];
SBQQ__Quote__c quote = !seeded.isEmpty() ? seeded[0] : [
    SELECT Id, Name
    FROM SBQQ__Quote__c
    WHERE Name = :QUOTE_NAME
    LIMIT 1
];

delete [
    SELECT Id FROM Quote_Document_Table__c
    WHERE Quote__c = :quote.Id AND Table_Code__c IN :TABLE_CODES
];

Boolean multiCurrency = UserInfo.isMultiCurrencyOrganization();

// ===========================================================================
// Table A - Transaction Summary (View A)
// ===========================================================================
Quote_Document_Table__c txnTable = new Quote_Document_Table__c(
    Name = quote.Name + ' - Transaction Summary',
    Quote__c = quote.Id,
    Table_Code__c = 'TRANSACTION_SUMMARY',
    Table_Key__c = quote.Id + ':TRANSACTION_SUMMARY',
    Display_Order__c = 60,
    Amount_Basis__c = 'Net Change',
    Group_Dimensions__c = 'TRANSACTION_TYPE',
    Line_Filter__c = 'EXCLUDE_OPTIONAL',
    Measure_Set__c = 'CHANGE',
    Status__c = 'Generating'
);

// ===========================================================================
// Table B - Bundle & Product Detail Grid (View B)
// ===========================================================================
Quote_Document_Table__c gridTable = new Quote_Document_Table__c(
    Name = quote.Name + ' - Bundle & Product Detail Grid',
    Quote__c = quote.Id,
    Table_Code__c = 'BUNDLE_PRODUCT_GRID',
    Table_Key__c = quote.Id + ':BUNDLE_PRODUCT_GRID',
    Display_Order__c = 35,
    Amount_Basis__c = 'Net Change',
    Group_Dimensions__c = 'BUNDLE',
    Line_Filter__c = 'EXCLUDE_OPTIONAL',
    Measure_Set__c = 'CHANGE',
    Status__c = 'Generating'
);

// ===========================================================================
// Table C - Bundle Totals (View C)
// ===========================================================================
Quote_Document_Table__c bundleSummaryTable = new Quote_Document_Table__c(
    Name = quote.Name + ' - Bundle Totals',
    Quote__c = quote.Id,
    Table_Code__c = 'BUNDLE_SUMMARY',
    Table_Key__c = quote.Id + ':BUNDLE_SUMMARY',
    Display_Order__c = 65,
    Amount_Basis__c = 'Net Change',
    Group_Dimensions__c = 'BUNDLE',
    Line_Filter__c = 'EXCLUDE_OPTIONAL',
    Measure_Set__c = 'CHANGE',
    Status__c = 'Generating'
);

// ===========================================================================
// Table D - Product Totals (View D)
// ===========================================================================
Quote_Document_Table__c productSummaryTable = new Quote_Document_Table__c(
    Name = quote.Name + ' - Product Totals',
    Quote__c = quote.Id,
    Table_Code__c = 'PRODUCT_SUMMARY',
    Table_Key__c = quote.Id + ':PRODUCT_SUMMARY',
    Display_Order__c = 70,
    Amount_Basis__c = 'Net Change',
    Group_Dimensions__c = 'SBQQ__ProductName__c',
    Line_Filter__c = 'EXCLUDE_OPTIONAL',
    Measure_Set__c = 'CHANGE',
    Status__c = 'Generating'
);

List<Quote_Document_Table__c> tables = new List<Quote_Document_Table__c>{
    txnTable, gridTable, bundleSummaryTable, productSummaryTable
};

if (multiCurrency) {
    for (Quote_Document_Table__c t : tables) {
        t.put('CurrencyIsoCode', (String) quote.get('CurrencyIsoCode'));
    }
}
insert tables;

// ---------------------------------------------------------------------------
// Table A rows - one Subtotal per type, plus the grand total.
// ---------------------------------------------------------------------------
RowSet txn = new RowSet();

txn.change(txn.aggregate('Subtotal', 1, 'SUBTOTAL:TXN:NET_NEW', 'Net New'),
           'Net New', 8000, 0, 0, 0, 0);
txn.change(txn.aggregate('Subtotal', 1, 'SUBTOTAL:TXN:CANCELLATION', 'Cancellation'),
           'Cancellation', 0, -4000, 0, 0, 0);
txn.change(txn.aggregate('Subtotal', 1, 'SUBTOTAL:TXN:REPL_REMOVED', 'Replacement Removed'),
           'Replacement Removed', 0, 0, -2500, 0, 0);
txn.change(txn.aggregate('Subtotal', 1, 'SUBTOTAL:TXN:REPL_ADDED', 'Replacement Added'),
           'Replacement Added', 0, 0, 0, 6000, 0);
txn.change(txn.aggregate('Subtotal', 1, 'SUBTOTAL:TXN:TERMINATION', 'Termination'),
           'Termination', 0, 0, 0, 0, -1200);
txn.change(txn.aggregate('Grand Total', 0, 'GRAND_TOTAL', 'Total'),
           null, 8000, -4000, -2500, 6000, -1200);

for (Quote_Document_Row__c r : txn.rows) { r.Quote_Document_Table__c = txnTable.Id; }

// ---------------------------------------------------------------------------
// Table B rows - the grid: Security Suite (bundle) then Uncategorized.
// ---------------------------------------------------------------------------
RowSet grid = new RowSet();

grid.aggregate('Group Header', 1, 'HEADER:BUNDLE:SECURITY_SUITE', 'Security Suite');
Quote_Document_Row__c gOldAgent = grid.detail(2, 'DETAIL:OLD_ENDPOINT_AGENT', 'Old Endpoint Agent', 'Old Endpoint Agent');
grid.change(gOldAgent, 'Cancellation', 0, -4000, 0, 0, 0);
Quote_Document_Row__c gLegacyAv = grid.detail(2, 'DETAIL:LEGACY_AV_LICENSE', 'Legacy AV License', 'Legacy AV License');
grid.change(gLegacyAv, 'Replacement Removed', 0, 0, -2500, 0, 0);
Quote_Document_Row__c gNextGenAv = grid.detail(2, 'DETAIL:NEXTGEN_AV_LICENSE', 'Next-Gen AV License', 'Next-Gen AV License');
grid.change(gNextGenAv, 'Replacement Added', 0, 0, 0, 6000, 0);
Quote_Document_Row__c gSecuritySubtotal = grid.aggregate('Subtotal', 1, 'SUBTOTAL:BUNDLE:SECURITY_SUITE', 'Security Suite Subtotal');
grid.change(gSecuritySubtotal, null, 0, -4000, -2500, 6000, 0);

grid.aggregate('Group Header', 1, 'HEADER:BUNDLE:UNCATEGORIZED', 'Uncategorized');
Quote_Document_Row__c gServices = grid.detail(2, 'DETAIL:PROFESSIONAL_SERVICES_HOURS', 'Professional Services Hours', 'Professional Services Hours');
grid.change(gServices, 'Net New', 8000, 0, 0, 0, 0);
Quote_Document_Row__c gExpiredAddon = grid.detail(2, 'DETAIL:EXPIRED_ADDON', 'Expired Add-On', 'Expired Add-On');
grid.change(gExpiredAddon, 'Termination', 0, 0, 0, 0, -1200);
Quote_Document_Row__c gUncatSubtotal = grid.aggregate('Subtotal', 1, 'SUBTOTAL:BUNDLE:UNCATEGORIZED', 'Uncategorized Subtotal');
grid.change(gUncatSubtotal, null, 8000, 0, 0, 0, -1200);

Quote_Document_Row__c gGrandTotal = grid.aggregate('Grand Total', 0, 'GRAND_TOTAL', 'Total');
grid.change(gGrandTotal, null, 8000, -4000, -2500, 6000, -1200);

// Grouping metadata, matching what the real generator would stamp.
for (Quote_Document_Row__c r : grid.rows) {
    r.Quote_Document_Table__c = gridTable.Id;
    if (r.Row_Key__c.contains('SECURITY_SUITE')) {
        r.Group_Dimension__c = 'BUNDLE';
        r.Group_Value__c = 'Security Suite';
    } else if (r.Row_Key__c.contains('UNCATEGORIZED')) {
        r.Group_Dimension__c = 'BUNDLE';
        r.Group_Value__c = 'Uncategorized';
    }
}

// ---------------------------------------------------------------------------
// Table C rows - one Subtotal per bundle, plus the grand total.
// ---------------------------------------------------------------------------
RowSet bundleSummary = new RowSet();

Quote_Document_Row__c bSecurity = bundleSummary.aggregate('Subtotal', 1, 'SUBTOTAL:BUNDLE:SECURITY_SUITE', 'Security Suite');
bundleSummary.change(bSecurity, null, 0, -4000, -2500, 6000, 0);
bSecurity.Group_Dimension__c = 'BUNDLE';
bSecurity.Group_Value__c = 'Security Suite';

Quote_Document_Row__c bUncategorized = bundleSummary.aggregate('Subtotal', 1, 'SUBTOTAL:BUNDLE:UNCATEGORIZED', 'Uncategorized');
bundleSummary.change(bUncategorized, null, 8000, 0, 0, 0, -1200);
bUncategorized.Group_Dimension__c = 'BUNDLE';
bUncategorized.Group_Value__c = 'Uncategorized';

Quote_Document_Row__c bTotal = bundleSummary.aggregate('Grand Total', 0, 'GRAND_TOTAL', 'Total');
bundleSummary.change(bTotal, null, 8000, -4000, -2500, 6000, -1200);

for (Quote_Document_Row__c r : bundleSummary.rows) { r.Quote_Document_Table__c = bundleSummaryTable.Id; }

// ---------------------------------------------------------------------------
// Table D rows - one Subtotal per product name, plus the grand total.
// ---------------------------------------------------------------------------
RowSet productSummary = new RowSet();

Map<String, Decimal[]> productDeltas = new Map<String, Decimal[]>{
    // netNew, cancellation, replRemoved, replAdded, termination
    'Old Endpoint Agent'           => new Decimal[]{ 0, -4000, 0, 0, 0 },
    'Legacy AV License'            => new Decimal[]{ 0, 0, -2500, 0, 0 },
    'Next-Gen AV License'          => new Decimal[]{ 0, 0, 0, 6000, 0 },
    'Professional Services Hours'  => new Decimal[]{ 8000, 0, 0, 0, 0 },
    'Expired Add-On'                => new Decimal[]{ 0, 0, 0, 0, -1200 }
};

for (String productName : new List<String>{
    'Old Endpoint Agent', 'Legacy AV License', 'Next-Gen AV License',
    'Professional Services Hours', 'Expired Add-On'
}) {
    Decimal[] d = productDeltas.get(productName);
    Quote_Document_Row__c row = productSummary.aggregate(
        'Subtotal', 1, 'SUBTOTAL:PRODUCT:' + productName.toUpperCase().replaceAll('[^A-Z0-9]+', '_'), productName
    );
    productSummary.change(row, null, d[0], d[1], d[2], d[3], d[4]);
    row.Group_Dimension__c = 'SBQQ__ProductName__c';
    row.Group_Value__c = productName;
}

Quote_Document_Row__c pTotal = productSummary.aggregate('Grand Total', 0, 'GRAND_TOTAL', 'Total');
productSummary.change(pTotal, null, 8000, -4000, -2500, 6000, -1200);

for (Quote_Document_Row__c r : productSummary.rows) { r.Quote_Document_Table__c = productSummaryTable.Id; }

// ---------------------------------------------------------------------------
// Persist, then stamp each table from its own grand total row.
// ---------------------------------------------------------------------------
List<Quote_Document_Row__c> allRows = new List<Quote_Document_Row__c>();
allRows.addAll(txn.rows);
allRows.addAll(grid.rows);
allRows.addAll(bundleSummary.rows);
allRows.addAll(productSummary.rows);

if (multiCurrency) {
    for (Quote_Document_Row__c r : allRows) {
        r.put('CurrencyIsoCode', (String) quote.get('CurrencyIsoCode'));
    }
}
insert allRows;

txnTable.Row_Count__c = txn.rows.size();
txnTable.Amount_Net_New__c = 8000;
txnTable.Amount_Cancellation__c = -4000;
txnTable.Amount_Replacement_Removed__c = -2500;
txnTable.Amount_Replacement_Added__c = 6000;
txnTable.Amount_Termination__c = -1200;
txnTable.Amount_Net_Change__c = 6300;

gridTable.Row_Count__c = grid.rows.size();
gridTable.Amount_Net_New__c = 8000;
gridTable.Amount_Cancellation__c = -4000;
gridTable.Amount_Replacement_Removed__c = -2500;
gridTable.Amount_Replacement_Added__c = 6000;
gridTable.Amount_Termination__c = -1200;
gridTable.Amount_Net_Change__c = 6300;

bundleSummaryTable.Row_Count__c = bundleSummary.rows.size();
bundleSummaryTable.Amount_Net_New__c = 8000;
bundleSummaryTable.Amount_Cancellation__c = -4000;
bundleSummaryTable.Amount_Replacement_Removed__c = -2500;
bundleSummaryTable.Amount_Replacement_Added__c = 6000;
bundleSummaryTable.Amount_Termination__c = -1200;
bundleSummaryTable.Amount_Net_Change__c = 6300;

productSummaryTable.Row_Count__c = productSummary.rows.size();
productSummaryTable.Amount_Net_New__c = 8000;
productSummaryTable.Amount_Cancellation__c = -4000;
productSummaryTable.Amount_Replacement_Removed__c = -2500;
productSummaryTable.Amount_Replacement_Added__c = 6000;
productSummaryTable.Amount_Termination__c = -1200;
productSummaryTable.Amount_Net_Change__c = 6300;

for (Quote_Document_Table__c t : tables) {
    t.Generated_On__c = System.now();
    t.Status__c = 'Complete';
}
update tables;

// The check that matters: all four views must agree, because they are four
// different cuts of the exact same five lines.
System.assertEquals(6300, txnTable.Amount_Net_Change__c, 'Transaction Summary grand total');
System.assertEquals(6300, gridTable.Amount_Net_Change__c, 'Bundle & Product Grid grand total');
System.assertEquals(6300, bundleSummaryTable.Amount_Net_Change__c, 'Bundle Totals grand total');
System.assertEquals(6300, productSummaryTable.Amount_Net_Change__c, 'Product Totals grand total');

System.debug('Example built for ' + quote.Name + ': ' + tables.size() + ' tables, '
    + allRows.size() + ' rows, all four grand totals reconcile at 6,300.');
