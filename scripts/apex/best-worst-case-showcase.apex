/**
 * Two quotes, built once, generated through the real button-click path
 * (QuoteDocumentGenerator.generate() - never a direct insert into
 * Quote_Document_Table__c or Quote_Document_Row__c), designed so that every
 * existing per-table-view report under Reports > CPQ Document Totals shows
 * both a best-case and a worst-case row set side by side, filterable by
 * Quote Name.
 *
 *   sf apex run --target-org <alias> --file scripts/apex/best-worst-case-showcase.apex
 *
 * WHY TWO QUOTES INSTEAD OF FIFTEEN (one per table definition):
 * QuoteDocumentGenerator.generate() runs every ACTIVE Quote_Document_Table_Def__mdt
 * record against whichever quote it's given. Two quotes, each shaped to carry
 * a wide variety of line shapes, therefore populate all fifteen shipped table
 * views (and any future one, with no change to this script) - one table per
 * report, two rows of contrast in each. Building fifteen scenario-specific
 * quotes instead would mean maintaining fifteen scripts that each need
 * updating if a new table view ships; this does not.
 *
 * BEST CASE (Quote tagged [BEST-CASE]):
 *   Everything a document table can show, shown correctly: a two-level
 *   bundle (free component + priced option), two Quote Line Groups, a
 *   recurring charge, a one-time service charge, an optional product, and
 *   one real example of every transaction type this framework can safely
 *   produce from hand-built data - Net New, Cancellation, Replacement
 *   Removed, Replacement Added. Clean numbers, modest discounts, everything
 *   reconciles.
 *
 * WORST CASE (Quote tagged [WORST-CASE]):
 *   The same shapes pushed toward the framework's real limits, still inside
 *   them - eighteen Quote Line Groups (well under the Max_Groups__c default
 *   of 50, but an order of magnitude past Best Case's two, so the contrast
 *   is visible in every QUOTE_LINE_GROUP-dimension report), a three-level
 *   deep bundle (component of a component), a 97%-discounted line to stress
 *   near-zero precision, a large quantity to stress large totals, and
 *   deliberately zero Optional lines - so the Optional Products report
 *   ([OPTIONAL_PRODUCTS], Line_Filter__c = OPTIONAL_ONLY) shows the
 *   "every line filtered out" edge case live: one clean Grand Total row,
 *   all zeros, Status__c = Complete, not an error and not a missing table.
 *
 * WHAT THIS DELIBERATELY DOES NOT DO, AND WHY:
 *   - Does not exceed Max_Groups__c. Generation would fail for that table
 *     entirely (see QuoteDocumentGeneratorTest.exceedingTheGroupCeilingFailsLoudly),
 *     leaving no rows to show in a report - a report can only display a
 *     limit that was respected, not one that was breached. The breach case
 *     is proven by that unit test instead.
 *   - Does not force a Termination transaction type. SBQQ__NetTotal__c is a
 *     CPQ formula field this script cannot safely set negative by hand, and
 *     QuoteDocumentLine.classify()'s own header comment already flags this
 *     branch as PROVISIONAL and unverified against real data - fabricating
 *     data to exercise it here would be demonstrating a claim this framework
 *     does not actually stand behind yet.
 *   - Does not hand-pick two Quote Line Group names that sanitize to the
 *     same key (e.g. "R&D" and "R D"). That collision is a hard generation
 *     failure by design (see duplicateGroupKeysAfterSanitizationFailGenerationLoudly)
 *     and is already proven by that unit test; risking it here would only
 *     threaten this script's own reliability for no new coverage.
 *
 * Re-runnable. Tags every record it creates with SHOWCASE_TAG on the Account
 * name and 'BWC-' on every Product2 code; deletes only its own prior run
 * before rebuilding. Independent of scripts/apex/quote-document-seed.apex -
 * neither script depends on the other having run first.
 */

// ---------------------------------------------------------------------------
// Teardown - only ever removes this script's own prior output.
// ---------------------------------------------------------------------------
final String SHOWCASE_TAG = '[BEST-CASE]';
final String WORST_TAG    = '[WORST-CASE]';

List<Account> priorAccounts = [
    SELECT Id FROM Account WHERE Name LIKE :('%' + SHOWCASE_TAG) OR Name LIKE :('%' + WORST_TAG)
];
if (!priorAccounts.isEmpty()) {
    delete [SELECT Id FROM SBQQ__Quote__c WHERE SBQQ__Account__c IN :priorAccounts];
    delete priorAccounts;
}
delete [SELECT Id FROM SBQQ__Subscription__c WHERE SBQQ__Product__r.ProductCode LIKE 'BWC-%'];
delete [SELECT Id FROM Product2 WHERE ProductCode LIKE 'BWC-%'];

// ---------------------------------------------------------------------------
// Shared product catalogue - ten products, five families, reused by both
// quotes so the same family/bundle/support shapes are directly comparable
// between the best-case and worst-case rows in every report.
// ---------------------------------------------------------------------------
List<Product2> products = new List<Product2>{
    new Product2(Name = 'Server Rack Unit',          ProductCode = 'BWC-HW-SRV',   Family = 'Hardware',   IsActive = true),
    new Product2(Name = 'Redundant Power Supply',    ProductCode = 'BWC-HW-PSU',   Family = 'Hardware',   IsActive = true),
    new Product2(Name = '10G Network Interface Card',ProductCode = 'BWC-HW-NIC',   Family = 'Hardware',   IsActive = true),
    new Product2(Name = 'Platform OS License',       ProductCode = 'BWC-SW-OS',    Family = 'Software',   IsActive = true),
    new Product2(Name = 'Analytics Add-on',          ProductCode = 'BWC-SW-ANLY',  Family = 'Software',   IsActive = true),
    new Product2(Name = 'Onboarding Services',       ProductCode = 'BWC-SV-ONBRD', Family = 'Service',    IsActive = true),
    new Product2(Name = 'Gold Support Plan',         ProductCode = 'BWC-SP-GOLD',  Family = 'Support',    IsActive = true),
    new Product2(Name = 'Silver Support Plan',       ProductCode = 'BWC-SP-SILV',  Family = 'Support',    IsActive = true),
    new Product2(Name = 'Platinum Support Plan',     ProductCode = 'BWC-SP-PLAT',  Family = 'Support',    IsActive = true),
    new Product2(Name = 'Cable Kit',                 ProductCode = 'BWC-CN-CABLE', Family = 'Consumable', IsActive = true)
};
insert products;

Map<String, Id> p = new Map<String, Id>();
for (Product2 product : products) {
    p.put(product.ProductCode, product.Id);
}

Integer lineNumber = 0;
SBQQ__QuoteLine__c makeLine(Id quoteId, Id productId, Decimal qty, Decimal listPrice, Decimal discountPct) {
    lineNumber++;
    Decimal net = (listPrice * (1 - (discountPct / 100))).setScale(2);
    return new SBQQ__QuoteLine__c(
        SBQQ__Quote__c = quoteId,
        SBQQ__Product__c = productId,
        SBQQ__Number__c = lineNumber,
        SBQQ__Quantity__c = qty,
        SBQQ__ListPrice__c = listPrice,
        SBQQ__RegularPrice__c = listPrice,
        SBQQ__NetPrice__c = net,
        SBQQ__CustomerPrice__c = net,
        SBQQ__Discount__c = discountPct == 0 ? null : discountPct
    );
}

// ===========================================================================
// BEST CASE
// ===========================================================================
Account bestAccount = new Account(Name = 'Sterling Advisory Group ' + SHOWCASE_TAG, Industry = 'Technology',
    BillingCity = 'Austin', BillingCountry = 'United States');
insert bestAccount;

Opportunity bestOpportunity = new Opportunity(Name = 'Sterling - Platform Rollout ' + SHOWCASE_TAG,
    AccountId = bestAccount.Id, StageName = 'Proposal/Price Quote', CloseDate = Date.today().addDays(45));
insert bestOpportunity;

SBQQ__Quote__c bestQuote = new SBQQ__Quote__c(
    SBQQ__Account__c = bestAccount.Id, SBQQ__Opportunity2__c = bestOpportunity.Id,
    SBQQ__Primary__c = true, SBQQ__Type__c = 'Quote', SBQQ__Status__c = 'Draft',
    SBQQ__StartDate__c = Date.today(), SBQQ__SubscriptionTerm__c = 12,
    SBQQ__LineItemsGrouped__c = true
);
insert bestQuote;

List<SBQQ__QuoteLineGroup__c> bestGroups = new List<SBQQ__QuoteLineGroup__c>{
    new SBQQ__QuoteLineGroup__c(SBQQ__Quote__c = bestQuote.Id, Name = 'Phase 1 - Core Platform', SBQQ__Number__c = 1),
    new SBQQ__QuoteLineGroup__c(SBQQ__Quote__c = bestQuote.Id, Name = 'Phase 2 - Expansion', SBQQ__Number__c = 2)
};
insert bestGroups;
Id bestPhase1 = bestGroups[0].Id;
Id bestPhase2 = bestGroups[1].Id;

// Bundle parent, so its component and option have something to point at.
SBQQ__QuoteLine__c bestBundleParent = makeLine(bestQuote.Id, p.get('BWC-HW-SRV'), 10, 3000, 10);
bestBundleParent.SBQQ__Bundle__c = true;
bestBundleParent.SBQQ__Group__c = bestPhase1;
insert bestBundleParent;

// Subscription needed for the Replacement Removed/Added pair below (the
// classification only reads whether the lookup is populated, but it is
// typed - see QuoteDocumentGeneratorTest.replacementPairIsClassifiedBySign).
SBQQ__Subscription__c bestSubscription = new SBQQ__Subscription__c(
    SBQQ__Account__c = bestAccount.Id, SBQQ__Product__c = p.get('BWC-SP-SILV'),
    SBQQ__Quantity__c = 1, SBQQ__SubscriptionStartDate__c = Date.today(),
    SBQQ__SubscriptionEndDate__c = Date.today().addYears(1)
);
insert bestSubscription;

List<SBQQ__QuoteLine__c> bestLines = new List<SBQQ__QuoteLine__c>();

// Bundled component: free, priced inside the parent - must show but never count.
SBQQ__QuoteLine__c bestPsu = makeLine(bestQuote.Id, p.get('BWC-HW-PSU'), 10, 0, 0);
bestPsu.SBQQ__Bundled__c = true;
bestPsu.SBQQ__OptionLevel__c = 1;
bestPsu.SBQQ__RequiredBy__c = bestBundleParent.Id;
bestPsu.SBQQ__Group__c = bestPhase1;
bestLines.add(bestPsu);

// Separately-priced option under the same bundle - this one does count.
SBQQ__QuoteLine__c bestNic = makeLine(bestQuote.Id, p.get('BWC-HW-NIC'), 10, 250, 5);
bestNic.SBQQ__OptionLevel__c = 1;
bestNic.SBQQ__RequiredBy__c = bestBundleParent.Id;
bestNic.SBQQ__Group__c = bestPhase1;
bestLines.add(bestNic);

SBQQ__QuoteLine__c bestOs = makeLine(bestQuote.Id, p.get('BWC-SW-OS'), 10, 400, 15);
bestOs.SBQQ__Group__c = bestPhase1;
bestLines.add(bestOs);

SBQQ__QuoteLine__c bestOnboarding = makeLine(bestQuote.Id, p.get('BWC-SV-ONBRD'), 1, 12000, 0);
bestOnboarding.SBQQ__Group__c = bestPhase1;
bestLines.add(bestOnboarding);

// Cancellation: an amended line ends at quantity zero; the value leaving the
// deal comes from the prior quantity at the current price, not the (now
// zero) line total - see QuoteDocumentLine.classify().
SBQQ__QuoteLine__c bestCancelled = makeLine(bestQuote.Id, p.get('BWC-SW-OS'), 0, 400, 0);
bestCancelled.SBQQ__Existing__c = true;
bestCancelled.SBQQ__PriorQuantity__c = 3;
bestCancelled.SBQQ__Group__c = bestPhase1;
bestLines.add(bestCancelled);

SBQQ__QuoteLine__c bestOptional = makeLine(bestQuote.Id, p.get('BWC-SW-ANLY'), 10, 60, 0);
bestOptional.SBQQ__Optional__c = true;
bestOptional.SBQQ__Group__c = bestPhase2;
bestLines.add(bestOptional);

SBQQ__QuoteLine__c bestCable = makeLine(bestQuote.Id, p.get('BWC-CN-CABLE'), 50, 12, 0);
bestCable.SBQQ__Group__c = bestPhase2;
bestLines.add(bestCable);

// Recurring, Net New.
SBQQ__QuoteLine__c bestGold = makeLine(bestQuote.Id, p.get('BWC-SP-GOLD'), 1, 9600, 10);
bestGold.SBQQ__ChargeType__c = 'Recurring';
bestGold.SBQQ__BillingType__c = 'Advance';
bestGold.SBQQ__BillingFrequency__c = 'Annual';
bestGold.SBQQ__SubscriptionTerm__c = 12;
bestGold.SBQQ__Group__c = bestPhase2;
bestLines.add(bestGold);

// Replacement Removed: the amended-down side, valued from prior quantity.
SBQQ__QuoteLine__c bestReplacedOut = makeLine(bestQuote.Id, p.get('BWC-SP-SILV'), 0, 8000, 0);
bestReplacedOut.SBQQ__UpgradedSubscription__c = bestSubscription.Id;
bestReplacedOut.SBQQ__PriorQuantity__c = 1;
bestReplacedOut.SBQQ__Group__c = bestPhase2;
bestLines.add(bestReplacedOut);

// Replacement Added: the upgraded-to side.
SBQQ__QuoteLine__c bestReplacedIn = makeLine(bestQuote.Id, p.get('BWC-SP-PLAT'), 1, 11000, 0);
bestReplacedIn.SBQQ__UpgradedSubscription__c = bestSubscription.Id;
bestReplacedIn.SBQQ__Group__c = bestPhase2;
bestLines.add(bestReplacedIn);

insert bestLines;

// ===========================================================================
// WORST CASE
// ===========================================================================
Account worstAccount = new Account(Name = 'Aurora Municipal Consortium ' + WORST_TAG, Industry = 'Government',
    BillingCity = 'Sacramento', BillingCountry = 'United States');
insert worstAccount;

Opportunity worstOpportunity = new Opportunity(Name = 'Aurora - Region-Wide Deployment ' + WORST_TAG,
    AccountId = worstAccount.Id, StageName = 'Proposal/Price Quote', CloseDate = Date.today().addDays(90));
insert worstOpportunity;

SBQQ__Quote__c worstQuote = new SBQQ__Quote__c(
    SBQQ__Account__c = worstAccount.Id, SBQQ__Opportunity2__c = worstOpportunity.Id,
    SBQQ__Primary__c = true, SBQQ__Type__c = 'Quote', SBQQ__Status__c = 'Draft',
    SBQQ__StartDate__c = Date.today(), SBQQ__SubscriptionTerm__c = 12,
    SBQQ__LineItemsGrouped__c = true
);
insert worstQuote;

// Eighteen Quote Line Groups - well under Max_Groups__c's default of 50, but
// nine times Best Case's two, so the contrast is unmistakable in every
// QUOTE_LINE_GROUP-dimension report (e.g. Group and Family Detail).
List<SBQQ__QuoteLineGroup__c> worstGroups = new List<SBQQ__QuoteLineGroup__c>();
for (Integer i = 1; i <= 18; i++) {
    worstGroups.add(new SBQQ__QuoteLineGroup__c(
        SBQQ__Quote__c = worstQuote.Id,
        Name = 'District ' + (i < 10 ? '0' + i : String.valueOf(i)),
        SBQQ__Number__c = i
    ));
}
insert worstGroups;

// Three-level bundle: parent -> priced option -> priced sub-option under that
// option, to stress indentation past the two levels Best Case demonstrates.
SBQQ__QuoteLine__c worstBundleParent = makeLine(worstQuote.Id, p.get('BWC-HW-SRV'), 200, 150, 5);
worstBundleParent.SBQQ__Bundle__c = true;
worstBundleParent.SBQQ__Group__c = worstGroups[0].Id;
insert worstBundleParent;

SBQQ__QuoteLine__c worstOption = makeLine(worstQuote.Id, p.get('BWC-HW-NIC'), 200, 40, 0);
worstOption.SBQQ__OptionLevel__c = 1;
worstOption.SBQQ__RequiredBy__c = worstBundleParent.Id;
worstOption.SBQQ__Group__c = worstGroups[0].Id;
insert worstOption;

List<SBQQ__QuoteLine__c> worstLines = new List<SBQQ__QuoteLine__c>();

// Nested sub-option, priced (not bundled/free), one level deeper again -
// required by the option above rather than by the bundle parent directly.
SBQQ__QuoteLine__c worstSubOption = makeLine(worstQuote.Id, p.get('BWC-HW-PSU'), 200, 15, 0);
worstSubOption.SBQQ__OptionLevel__c = 2;
worstSubOption.SBQQ__RequiredBy__c = worstOption.Id;
worstSubOption.SBQQ__Group__c = worstGroups[0].Id;
worstLines.add(worstSubOption);

// One line per remaining district (2-16), rotating through the non-bundle,
// non-support products, so PRODUCT_FAMILY and CHARGE_TYPE groupings have
// real variety across all eighteen buckets, not just one product repeated.
List<String> rotatingCodes = new List<String>{ 'BWC-SW-OS', 'BWC-SW-ANLY', 'BWC-SV-ONBRD', 'BWC-CN-CABLE' };
for (Integer i = 1; i < 15; i++) {
    String code = rotatingCodes[Math.mod(i, rotatingCodes.size())];
    SBQQ__QuoteLine__c line = makeLine(worstQuote.Id, p.get(code), 20 + i, 100 + (i * 7), Math.mod(i, 5) * 3);
    line.SBQQ__Group__c = worstGroups[i].Id;
    worstLines.add(line);
}

// Near-zero precision stress: a 97% discount on a real list price.
SBQQ__QuoteLine__c worstDeepDiscount = makeLine(worstQuote.Id, p.get('BWC-SW-ANLY'), 1, 5000, 97);
worstDeepDiscount.SBQQ__Group__c = worstGroups[15].Id;
worstLines.add(worstDeepDiscount);

// Recurring, large quantity - stresses both CHARGE_TYPE_SUMMARY and the
// overall total's magnitude.
SBQQ__QuoteLine__c worstRecurring = makeLine(worstQuote.Id, p.get('BWC-SP-GOLD'), 150, 9600, 8);
worstRecurring.SBQQ__ChargeType__c = 'Recurring';
worstRecurring.SBQQ__BillingType__c = 'Advance';
worstRecurring.SBQQ__BillingFrequency__c = 'Annual';
worstRecurring.SBQQ__SubscriptionTerm__c = 12;
worstRecurring.SBQQ__Group__c = worstGroups[16].Id;
worstLines.add(worstRecurring);

// Large one-time service value, in its own district.
SBQQ__QuoteLine__c worstService = makeLine(worstQuote.Id, p.get('BWC-SV-ONBRD'), 1, 480000, 12);
worstService.SBQQ__Group__c = worstGroups[17].Id;
worstLines.add(worstService);

// Deliberately zero Optional lines - see the file header for why this is
// the safe way to demonstrate "every line filtered out of one table" live.

insert worstLines;

// ===========================================================================
// Generate through the real entry point - never a direct insert into
// Quote_Document_Table__c or Quote_Document_Row__c.
// ===========================================================================
Set<Id> showcaseQuoteIds = new Set<Id>{ bestQuote.Id, worstQuote.Id };
QuoteDocumentGenerator.generate(showcaseQuoteIds);

// ---------------------------------------------------------------------------
// Verify, per quote, per table - status, row count, and reconciliation.
// ---------------------------------------------------------------------------
System.debug('=== Best Case vs Worst Case: table-by-table ===');
for (SBQQ__Quote__c quote : [
    SELECT Name, SBQQ__NetAmount__c, Document_Data_Status__c,
           (SELECT Table_Code__c, Status__c, Row_Count__c, Amount_Net__c
            FROM DocumentTables__r ORDER BY Table_Code__c)
    FROM SBQQ__Quote__c WHERE Id IN :showcaseQuoteIds ORDER BY Name
]) {
    System.debug('--- ' + quote.Name + ' | Quote Net Amount = ' + quote.SBQQ__NetAmount__c
        + ' | ' + quote.Document_Data_Status__c + ' ---');
    for (Quote_Document_Table__c t : quote.DocumentTables__r) {
        System.debug('  ' + t.Table_Code__c + ': ' + t.Status__c
            + ' | rows=' + t.Row_Count__c + ' | Amount_Net__c=' + t.Amount_Net__c);
    }
}

Quote_Document_Table__c bestOptionalTable = [
    SELECT Row_Count__c, Amount_Net__c FROM Quote_Document_Table__c
    WHERE Quote__c = :bestQuote.Id AND Table_Code__c = 'OPTIONAL_PRODUCTS'
];
Quote_Document_Table__c worstOptionalTable = [
    SELECT Row_Count__c, Amount_Net__c FROM Quote_Document_Table__c
    WHERE Quote__c = :worstQuote.Id AND Table_Code__c = 'OPTIONAL_PRODUCTS'
];
System.debug('=== Optional Products contrast ===');
System.debug('Best Case  : rows=' + bestOptionalTable.Row_Count__c + ' Amount_Net__c=' + bestOptionalTable.Amount_Net__c
    + ' (has a real optional line)');
System.debug('Worst Case : rows=' + worstOptionalTable.Row_Count__c + ' Amount_Net__c=' + worstOptionalTable.Amount_Net__c
    + ' (zero optional lines - clean empty Grand Total, not an error)');

System.assertEquals('Ready', [SELECT Document_Data_Status__c FROM SBQQ__Quote__c WHERE Id = :bestQuote.Id].Document_Data_Status__c,
    'Best Case must generate cleanly');
System.assertEquals('Ready', [SELECT Document_Data_Status__c FROM SBQQ__Quote__c WHERE Id = :worstQuote.Id].Document_Data_Status__c,
    'Worst Case must still generate cleanly - stressed, not broken');
System.assertEquals(1, worstOptionalTable.Row_Count__c,
    'Worst Case Optional Products must be exactly one clean Grand Total row - zero groups, zero details');
