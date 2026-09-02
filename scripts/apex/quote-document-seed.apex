/**
 * Realistic CPQ demo data for exercising the Quote Document Totals framework.
 *
 * Builds a small but coherent business: five customers across five industries,
 * an eighteen-product catalogue, and five quotes deliberately shaped to hit
 * every branch of the generator - bundles with priced and unpriced options,
 * optional products, recurring subscriptions, quote line groups, and a
 * multi-family deal large enough that the subtotals mean something.
 *
 *   sf apex run --target-org <alias> --file scripts/apex/quote-document-seed.apex
 *
 * Re-runnable. Everything it creates is tagged with SEED_TAG on the Account
 * name, and the script deletes prior seed data before rebuilding. It will not
 * touch records it did not create.
 *
 * It does NOT call the CPQ Calculate API. Prices are set directly on the lines
 * and CPQ's formula fields compute the totals, which is all the generator
 * reads. Calculate would make this slow and non-deterministic for no gain.
 */

// ---------------------------------------------------------------------------
// Teardown - only ever removes previously seeded records.
// ---------------------------------------------------------------------------
final String SEED_TAG = '[SEED]';

List<Account> priorAccounts = [SELECT Id FROM Account WHERE Name LIKE :('%' + SEED_TAG)];
if (!priorAccounts.isEmpty()) {
    // Quotes hang off Opportunity/Account by lookup, so remove them explicitly
    // before the accounts go, otherwise they are left orphaned.
    delete [SELECT Id FROM SBQQ__Quote__c WHERE SBQQ__Account__c IN :priorAccounts];
    delete priorAccounts;
}
delete [SELECT Id FROM Product2 WHERE ProductCode LIKE 'SEED-%'];

// ---------------------------------------------------------------------------
// Customers - five industries, so INDUSTRY grouping has something to show.
// ---------------------------------------------------------------------------
List<Account> accounts = new List<Account>{
    new Account(Name = 'Ridgeline Manufacturing ' + SEED_TAG, Industry = 'Manufacturing',
                BillingCity = 'Sheffield', BillingCountry = 'United Kingdom'),
    new Account(Name = 'Calder Health Trust ' + SEED_TAG, Industry = 'Healthcare',
                BillingCity = 'Leeds', BillingCountry = 'United Kingdom'),
    new Account(Name = 'Meridian Financial ' + SEED_TAG, Industry = 'Banking',
                BillingCity = 'London', BillingCountry = 'United Kingdom'),
    new Account(Name = 'Brightwell Retail Group ' + SEED_TAG, Industry = 'Retail',
                BillingCity = 'Manchester', BillingCountry = 'United Kingdom'),
    new Account(Name = 'Aldergate Logistics ' + SEED_TAG, Industry = 'Transportation',
                BillingCity = 'Bristol', BillingCountry = 'United Kingdom')
};
insert accounts;

Map<String, Id> accountByKey = new Map<String, Id>();
accountByKey.put('RIDGELINE', accounts[0].Id);
accountByKey.put('CALDER', accounts[1].Id);
accountByKey.put('MERIDIAN', accounts[2].Id);
accountByKey.put('BRIGHTWELL', accounts[3].Id);
accountByKey.put('ALDERGATE', accounts[4].Id);

// ---------------------------------------------------------------------------
// Catalogue - spread across the families the summaries group by.
// ---------------------------------------------------------------------------
List<Product2> products = new List<Product2>{
    // Hardware - the bundle parents and their components
    new Product2(Name = 'Field Terminal T500',        ProductCode = 'SEED-HW-T500',    Family = 'Hardware', IsActive = true),
    new Product2(Name = 'T500 Ruggedised Case',       ProductCode = 'SEED-HW-T500C',   Family = 'Hardware', IsActive = true),
    new Product2(Name = 'T500 Extended Battery',      ProductCode = 'SEED-HW-T500B',   Family = 'Hardware', IsActive = true),
    new Product2(Name = 'T500 Docking Station',       ProductCode = 'SEED-HW-T500D',   Family = 'Hardware', IsActive = true),
    new Product2(Name = 'Depot Scanner S200',         ProductCode = 'SEED-HW-S200',    Family = 'Hardware', IsActive = true),
    new Product2(Name = 'S200 Charging Cradle',       ProductCode = 'SEED-HW-S200C',   Family = 'Hardware', IsActive = true),
    new Product2(Name = 'Network Gateway G12',        ProductCode = 'SEED-HW-G12',     Family = 'Hardware', IsActive = true),

    // Software
    new Product2(Name = 'Fleet Insight Platform',     ProductCode = 'SEED-SW-FLEET',   Family = 'Software', IsActive = true),
    new Product2(Name = 'Analytics Module',           ProductCode = 'SEED-SW-ANALYTX', Family = 'Software', IsActive = true),
    new Product2(Name = 'Compliance Reporting Pack',  ProductCode = 'SEED-SW-COMPLY',  Family = 'Software', IsActive = true),
    new Product2(Name = 'Advanced Forecasting',       ProductCode = 'SEED-SW-FCAST',   Family = 'Software', IsActive = true),

    // Service
    new Product2(Name = 'Implementation Services',    ProductCode = 'SEED-SV-IMPL',    Family = 'Service',  IsActive = true),
    new Product2(Name = 'Data Migration',             ProductCode = 'SEED-SV-MIGR',    Family = 'Service',  IsActive = true),
    new Product2(Name = 'Onsite Training (per day)',  ProductCode = 'SEED-SV-TRAIN',   Family = 'Service',  IsActive = true),

    // Support - the recurring lines
    new Product2(Name = 'Standard Support',           ProductCode = 'SEED-SP-STD',     Family = 'Support',  IsActive = true),
    new Product2(Name = 'Premier Support',            ProductCode = 'SEED-SP-PREM',    Family = 'Support',  IsActive = true),

    // Consumable
    new Product2(Name = 'Thermal Label Rolls (box)',  ProductCode = 'SEED-CN-LABEL',   Family = 'Consumable', IsActive = true),
    new Product2(Name = 'Replacement Styluses (10)',  ProductCode = 'SEED-CN-STYLUS',  Family = 'Consumable', IsActive = true)
};
insert products;

Map<String, Id> p = new Map<String, Id>();
for (Product2 product : products) {
    p.put(product.ProductCode, product.Id);
}

// ---------------------------------------------------------------------------
// Opportunities
// ---------------------------------------------------------------------------
List<Opportunity> opportunities = new List<Opportunity>{
    new Opportunity(Name = 'Ridgeline - Depot Modernisation ' + SEED_TAG, AccountId = accountByKey.get('RIDGELINE'),
                    StageName = 'Proposal/Price Quote', CloseDate = Date.today().addDays(45)),
    new Opportunity(Name = 'Calder - Ward Rollout ' + SEED_TAG, AccountId = accountByKey.get('CALDER'),
                    StageName = 'Negotiation/Review', CloseDate = Date.today().addDays(30)),
    new Opportunity(Name = 'Meridian - Branch Refresh ' + SEED_TAG, AccountId = accountByKey.get('MERIDIAN'),
                    StageName = 'Proposal/Price Quote', CloseDate = Date.today().addDays(60)),
    new Opportunity(Name = 'Brightwell - Store Pilot ' + SEED_TAG, AccountId = accountByKey.get('BRIGHTWELL'),
                    StageName = 'Qualification', CloseDate = Date.today().addDays(90)),
    new Opportunity(Name = 'Aldergate - Phase 1 and 2 ' + SEED_TAG, AccountId = accountByKey.get('ALDERGATE'),
                    StageName = 'Proposal/Price Quote', CloseDate = Date.today().addDays(75))
};
insert opportunities;

// ---------------------------------------------------------------------------
// Quotes
// ---------------------------------------------------------------------------
List<SBQQ__Quote__c> quotes = new List<SBQQ__Quote__c>();
for (Integer i = 0; i < opportunities.size(); i++) {
    quotes.add(new SBQQ__Quote__c(
        SBQQ__Account__c = opportunities[i].AccountId,
        SBQQ__Opportunity2__c = opportunities[i].Id,
        SBQQ__Primary__c = true,
        SBQQ__Type__c = 'Quote',
        SBQQ__Status__c = 'Draft',
        SBQQ__StartDate__c = Date.today(),
        SBQQ__SubscriptionTerm__c = 12
    ));
}
// The last quote uses CPQ's own line grouping, so the nested table has
// something real to nest by.
quotes[4].SBQQ__LineItemsGrouped__c = true;
insert quotes;

Id qRidgeline  = quotes[0].Id;
Id qCalder     = quotes[1].Id;
Id qMeridian   = quotes[2].Id;
Id qBrightwell = quotes[3].Id;
Id qAldergate  = quotes[4].Id;

// Quote line groups for the phased deal.
List<SBQQ__QuoteLineGroup__c> groups = new List<SBQQ__QuoteLineGroup__c>{
    new SBQQ__QuoteLineGroup__c(SBQQ__Quote__c = qAldergate, Name = 'Phase 1 - Bristol Hub', SBQQ__Number__c = 1),
    new SBQQ__QuoteLineGroup__c(SBQQ__Quote__c = qAldergate, Name = 'Phase 2 - Regional Depots', SBQQ__Number__c = 2)
};
insert groups;

// ---------------------------------------------------------------------------
// Line helpers
// ---------------------------------------------------------------------------
Integer lineNumber = 0;

// Only prices and quantity are writable - ListTotal, NetTotal and the rest are
// formula fields that CPQ derives from these.
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

// ---------------------------------------------------------------------------
// Pass 1 - bundle parents, so components have something to point at.
// ---------------------------------------------------------------------------
SBQQ__QuoteLine__c ridgelineTerminal = makeLine(qRidgeline, p.get('SEED-HW-T500'), 120, 850, 12);
ridgelineTerminal.SBQQ__Bundle__c = true;

SBQQ__QuoteLine__c calderTerminal = makeLine(qCalder, p.get('SEED-HW-T500'), 40, 850, 5);
calderTerminal.SBQQ__Bundle__c = true;

SBQQ__QuoteLine__c meridianScanner = makeLine(qMeridian, p.get('SEED-HW-S200'), 65, 410, 8);
meridianScanner.SBQQ__Bundle__c = true;

SBQQ__QuoteLine__c aldergateTerminal = makeLine(qAldergate, p.get('SEED-HW-T500'), 80, 850, 15);
aldergateTerminal.SBQQ__Bundle__c = true;
aldergateTerminal.SBQQ__Group__c = groups[0].Id;

List<SBQQ__QuoteLine__c> parents = new List<SBQQ__QuoteLine__c>{
    ridgelineTerminal, calderTerminal, meridianScanner, aldergateTerminal
};
insert parents;

// ---------------------------------------------------------------------------
// Pass 2 - everything else.
// ---------------------------------------------------------------------------
List<SBQQ__QuoteLine__c> lines = new List<SBQQ__QuoteLine__c>();

// --- Ridgeline: the big multi-family deal, bundle with mixed options --------
// Bundled components: price sits in the package, so they show at zero.
for (String code : new List<String>{ 'SEED-HW-T500C', 'SEED-HW-T500B' }) {
    SBQQ__QuoteLine__c component = makeLine(qRidgeline, p.get(code), 120, 0, 0);
    component.SBQQ__Bundled__c = true;
    component.SBQQ__OptionLevel__c = 1;
    component.SBQQ__RequiredBy__c = ridgelineTerminal.Id;
    lines.add(component);
}
// A separately-priced option under the same bundle - this one does count.
SBQQ__QuoteLine__c ridgelineDock = makeLine(qRidgeline, p.get('SEED-HW-T500D'), 120, 95, 10);
ridgelineDock.SBQQ__OptionLevel__c = 1;
ridgelineDock.SBQQ__RequiredBy__c = ridgelineTerminal.Id;
lines.add(ridgelineDock);

lines.add(makeLine(qRidgeline, p.get('SEED-HW-G12'), 6, 2400, 5));
lines.add(makeLine(qRidgeline, p.get('SEED-SW-FLEET'), 120, 180, 20));
lines.add(makeLine(qRidgeline, p.get('SEED-SW-ANALYTX'), 120, 65, 20));
lines.add(makeLine(qRidgeline, p.get('SEED-SV-IMPL'), 1, 24000, 0));
lines.add(makeLine(qRidgeline, p.get('SEED-SV-TRAIN'), 8, 1200, 0));
lines.add(makeLine(qRidgeline, p.get('SEED-CN-LABEL'), 200, 34, 0));

// Recurring support - CPQ rejects a recurring charge with no billing type.
SBQQ__QuoteLine__c ridgelineSupport = makeLine(qRidgeline, p.get('SEED-SP-PREM'), 1, 18500, 10);
ridgelineSupport.SBQQ__ChargeType__c = 'Recurring';
ridgelineSupport.SBQQ__BillingType__c = 'Advance';
ridgelineSupport.SBQQ__BillingFrequency__c = 'Annual';
ridgelineSupport.SBQQ__SubscriptionTerm__c = 12;
lines.add(ridgelineSupport);

// Optional: quoted, priced, excluded from every ordinary total.
SBQQ__QuoteLine__c ridgelineOptional = makeLine(qRidgeline, p.get('SEED-SW-FCAST'), 120, 45, 0);
ridgelineOptional.SBQQ__Optional__c = true;
lines.add(ridgelineOptional);

// --- Calder: smaller, heavy on services and compliance ----------------------
SBQQ__QuoteLine__c calderCase = makeLine(qCalder, p.get('SEED-HW-T500C'), 40, 0, 0);
calderCase.SBQQ__Bundled__c = true;
calderCase.SBQQ__OptionLevel__c = 1;
calderCase.SBQQ__RequiredBy__c = calderTerminal.Id;
lines.add(calderCase);

lines.add(makeLine(qCalder, p.get('SEED-SW-COMPLY'), 40, 220, 0));
lines.add(makeLine(qCalder, p.get('SEED-SV-IMPL'), 1, 9500, 0));
lines.add(makeLine(qCalder, p.get('SEED-SV-MIGR'), 1, 6200, 15));

SBQQ__QuoteLine__c calderSupport = makeLine(qCalder, p.get('SEED-SP-STD'), 1, 4800, 0);
calderSupport.SBQQ__ChargeType__c = 'Recurring';
calderSupport.SBQQ__BillingType__c = 'Advance';
calderSupport.SBQQ__BillingFrequency__c = 'Annual';
calderSupport.SBQQ__SubscriptionTerm__c = 12;
lines.add(calderSupport);

// --- Meridian: bundle plus consumables, no services -------------------------
SBQQ__QuoteLine__c meridianCradle = makeLine(qMeridian, p.get('SEED-HW-S200C'), 65, 0, 0);
meridianCradle.SBQQ__Bundled__c = true;
meridianCradle.SBQQ__OptionLevel__c = 1;
meridianCradle.SBQQ__RequiredBy__c = meridianScanner.Id;
lines.add(meridianCradle);

lines.add(makeLine(qMeridian, p.get('SEED-HW-G12'), 3, 2400, 0));
lines.add(makeLine(qMeridian, p.get('SEED-SW-FLEET'), 65, 180, 10));
lines.add(makeLine(qMeridian, p.get('SEED-CN-LABEL'), 120, 34, 5));
lines.add(makeLine(qMeridian, p.get('SEED-CN-STYLUS'), 65, 18, 0));

// --- Brightwell: deliberately tiny, one family, no bundles ------------------
// A quote where most tables collapse to a single group is a useful edge case.
lines.add(makeLine(qBrightwell, p.get('SEED-SW-FLEET'), 12, 180, 0));
lines.add(makeLine(qBrightwell, p.get('SEED-SW-ANALYTX'), 12, 65, 0));

// --- Aldergate: two quote line groups, for the nested table -----------------
SBQQ__QuoteLine__c aldergateBattery = makeLine(qAldergate, p.get('SEED-HW-T500B'), 80, 0, 0);
aldergateBattery.SBQQ__Bundled__c = true;
aldergateBattery.SBQQ__OptionLevel__c = 1;
aldergateBattery.SBQQ__RequiredBy__c = aldergateTerminal.Id;
aldergateBattery.SBQQ__Group__c = groups[0].Id;
lines.add(aldergateBattery);

SBQQ__QuoteLine__c aldergatePhase1Software = makeLine(qAldergate, p.get('SEED-SW-FLEET'), 80, 180, 18);
aldergatePhase1Software.SBQQ__Group__c = groups[0].Id;
lines.add(aldergatePhase1Software);

SBQQ__QuoteLine__c aldergatePhase1Impl = makeLine(qAldergate, p.get('SEED-SV-IMPL'), 1, 15000, 0);
aldergatePhase1Impl.SBQQ__Group__c = groups[0].Id;
lines.add(aldergatePhase1Impl);

SBQQ__QuoteLine__c aldergatePhase2Scanner = makeLine(qAldergate, p.get('SEED-HW-S200'), 45, 410, 12);
aldergatePhase2Scanner.SBQQ__Group__c = groups[1].Id;
lines.add(aldergatePhase2Scanner);

SBQQ__QuoteLine__c aldergatePhase2Gateway = makeLine(qAldergate, p.get('SEED-HW-G12'), 4, 2400, 8);
aldergatePhase2Gateway.SBQQ__Group__c = groups[1].Id;
lines.add(aldergatePhase2Gateway);

SBQQ__QuoteLine__c aldergatePhase2Training = makeLine(qAldergate, p.get('SEED-SV-TRAIN'), 5, 1200, 0);
aldergatePhase2Training.SBQQ__Group__c = groups[1].Id;
lines.add(aldergatePhase2Training);

SBQQ__QuoteLine__c aldergateSupport = makeLine(qAldergate, p.get('SEED-SP-PREM'), 1, 12000, 5);
aldergateSupport.SBQQ__ChargeType__c = 'Recurring';
aldergateSupport.SBQQ__BillingType__c = 'Advance';
aldergateSupport.SBQQ__BillingFrequency__c = 'Annual';
aldergateSupport.SBQQ__SubscriptionTerm__c = 12;
aldergateSupport.SBQQ__Group__c = groups[1].Id;
lines.add(aldergateSupport);

SBQQ__QuoteLine__c aldergateOptional = makeLine(qAldergate, p.get('SEED-HW-T500D'), 80, 95, 0);
aldergateOptional.SBQQ__Optional__c = true;
aldergateOptional.SBQQ__Group__c = groups[1].Id;
lines.add(aldergateOptional);

insert lines;

// ---------------------------------------------------------------------------
// Generate document tables for every seeded quote.
// ---------------------------------------------------------------------------
Set<Id> quoteIds = new Set<Id>{ qRidgeline, qCalder, qMeridian, qBrightwell, qAldergate };
QuoteDocumentGenerator.generate(quoteIds);

// ---------------------------------------------------------------------------
// Report what was built, and prove each quote reconciles.
// ---------------------------------------------------------------------------
System.debug('=== Seeded quotes ===');
for (SBQQ__Quote__c quote : [
    SELECT Name, SBQQ__Account__r.Name, SBQQ__LineItemCount__c, SBQQ__NetAmount__c,
           Document_Data_Status__c,
           (SELECT Table_Code__c, Amount_Net__c, Row_Count__c
            FROM DocumentTables__r WHERE Table_Code__c = 'PRODUCT_FAMILY_SUMMARY')
    FROM SBQQ__Quote__c WHERE Id IN :quoteIds ORDER BY Name
]) {
    Decimal generated = quote.DocumentTables__r.isEmpty() ? null : quote.DocumentTables__r[0].Amount_Net__c;
    System.debug(quote.Name + ' | ' + quote.SBQQ__Account__r.Name
        + ' | lines=' + quote.SBQQ__LineItemCount__c
        + ' | quote net=' + quote.SBQQ__NetAmount__c
        + ' | generated net=' + generated
        + ' | ' + quote.Document_Data_Status__c
        + ' | reconciles=' + (quote.SBQQ__NetAmount__c == generated));
}

System.debug('=== Totals ===');
System.debug('tables=' + [SELECT COUNT() FROM Quote_Document_Table__c WHERE Quote__c IN :quoteIds]
    + ' rows=' + [SELECT COUNT() FROM Quote_Document_Row__c WHERE Quote_Document_Table__r.Quote__c IN :quoteIds]);
