"""Generates the step-03 quote fixtures as anonymous Apex.

    python scripts/qdtd/build-quote-fixtures.py

Writes, into scripts/apex/:

    qdtd-quotes-01-core.apex      roster quotes 1-7
    qdtd-quotes-02-edge.apex      roster quotes 8-13
    qdtd-quotes-03-volume.apex    roster quotes 14-19, plus subscriptions

Anonymous Apex rather than a deployed class on purpose: a fixture class would
sit in the org-wide coverage denominator, and the 98% gate is already
outstanding. Scripts also match how every other fixture in this repo is shipped.

Each script is re-runnable and touches only fixture-owned records: it deletes
the quotes belonging to QDTD- accounts that it is about to rebuild, and nothing
else. Accounts, contacts, opportunities and products come from step 02 and are
never modified here.

The roster is specs/quote-document-test-data/steps/01-data-shape.md. Each quote
exists to make one part of the step-04 matrix exercisable; the `why` on every
entry below is the claim the ledger will check.
"""

import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]

FAMILY_CODES = {
    "Hardware": "HW", "Software": "SW", "Subscription": "SUB",
    "Implementation Services": "IMP", "Premier Support": "SUP", "Onsite Training": "TRN",
}

# ---------------------------------------------------------------------------
# Shared Apex preamble: catalogue lookup plus the line factory every script uses.
# ---------------------------------------------------------------------------
PREAMBLE = """
// Catalogue and account lookups. Fixture-owned records only - the QDTD- marker
// is what keeps every delete and every read inside this dataset.
Map<String, Id> productByCode = new Map<String, Id>();
for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE ProductCode LIKE 'QDTD-%']) {
    productByCode.put(p.ProductCode, p.Id);
}
if (productByCode.isEmpty()) {
    throw new IllegalArgumentException('Step 02 has not been loaded: no QDTD- products found.');
}

List<Account> fixtureAccounts = [SELECT Id, Name, BillingCountry FROM Account WHERE Name LIKE 'QDTD-%' ORDER BY Name];
Map<Id, Id> opportunityByAccount = new Map<Id, Id>();
for (Opportunity o : [SELECT Id, AccountId FROM Opportunity WHERE Account.Name LIKE 'QDTD-%']) {
    opportunityByAccount.put(o.AccountId, o.Id);
}

Id standardPricebookId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;

SBQQ__Quote__c newQuote(Account a, String quoteType, String key) {
    return new SBQQ__Quote__c(
        SBQQ__Account__c = a.Id,
        SBQQ__Opportunity2__c = opportunityByAccount.get(a.Id),
        SBQQ__Primary__c = false,
        SBQQ__Type__c = quoteType,
        SBQQ__Status__c = 'Draft',
        SBQQ__PriceBook__c = standardPricebookId,
        SBQQ__Key__c = key
    );
}

// Only writable inputs are set. ListTotal, CustomerTotal, NetTotal, RegularTotal
// and TotalDiscountAmount are formula fields - step 03 records what they compute
// rather than trying to write them.
SBQQ__QuoteLine__c newLine(Id quoteId, String productCode, Integer lineNumber, Decimal qty,
                           Decimal listPrice, Decimal discountPercent, String chargeType,
                           String billingFrequency, Boolean isOptional) {
    return new SBQQ__QuoteLine__c(
        SBQQ__Quote__c = quoteId,
        SBQQ__Product__c = productByCode.get(productCode),
        SBQQ__Number__c = lineNumber,
        SBQQ__Quantity__c = qty,
        SBQQ__ListPrice__c = listPrice,
        // SBQQ__ListTotal__c is a formula over ProratedListPrice, NOT over
        // ListPrice: leaving this null makes ListTotal null, which silently
        // zeroes every 'List Value' amount basis and turns TotalDiscountAmount
        // into -NetTotal. Established empirically - the managed formula is not
        // readable - by bisecting the writable price fields on a fixture line.
        SBQQ__ProratedListPrice__c = listPrice,
        SBQQ__RegularPrice__c = listPrice,
        // NetPrice and CustomerPrice are deliberately NOT written. CPQ's own
        // asynchronous recalculation resets a directly-written NetPrice back to
        // the list price after the insert transaction commits - proved by
        // reading the same rows twice with no writes in between and watching 206
        // of them change. A Discount percent survives that pass and is the input
        // CPQ derives NetPrice, CustomerPrice and NetTotal from, so the discount
        // is expressed here and the money is left to the org.
        SBQQ__Discount__c = discountPercent,
        SBQQ__ChargeType__c = chargeType,
        SBQQ__BillingFrequency__c = billingFrequency,
        // CPQ validates that a Recurring line carries a Billing Type. The value
        // itself is immaterial to the document pipeline, which never reads it -
        // it just has to be present or the insert is rejected.
        SBQQ__BillingType__c = chargeType == 'Recurring' ? 'Advance' : null,
        SBQQ__Optional__c = isOptional,
        SBQQ__PricebookEntryId__c = null
    );
}
"""

TEARDOWN = """
// Teardown: only the quotes this script rebuilds, identified by SBQQ__Key__c,
// which is set exclusively by these fixtures. Accounts, products and every other
// record from step 02 are left untouched.
// SBQQ__Key__c is a unique external id on the quote, writable, and set only by
// these fixtures - which makes it a precise handle for "the records this script
// owns". A SOQL IN clause cannot take an inline list literal, hence the bind.
List<String> fixtureKeys = {keys};
delete [SELECT Id FROM SBQQ__Quote__c WHERE SBQQ__Key__c IN :fixtureKeys];
"""


def q(value):
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    return "'" + str(value).replace("\\", "\\\\").replace("'", "\\'") + "'"


def discount_percent(spec):
    """The spec states the net it wants; CPQ only honours a percent, so convert.

    A zero or negative list price has no meaningful percentage off it, so those
    lines carry no discount and stand at their list value - which is what the
    zero-value and credit quotes are there to exercise anyway.
    """
    if "discount" in spec:
        return spec["discount"]
    list_price = spec.get("list", 1000)
    net = spec.get("net", list_price)
    if not list_price or list_price <= 0 or net == list_price:
        return 0
    return round((1 - (net / float(list_price))) * 100, 2)


def code(family, index):
    return "QDTD-{}-{}".format(FAMILY_CODES[family], index)


# Every line whose values are stated explicitly (as opposed to generated by an
# Apex loop) is recorded here as INTENT, and written to fixture-intended.csv.
# Comparing that against what the org actually persisted is the only way to
# catch a CPQ trigger or validation rule quietly rewriting a writable input.
INTENT = []


class Script:
    def __init__(self, title, keys):
        self.lines = []
        self.keys = keys
        self.w("/**")
        self.w(" * " + title)
        self.w(" *")
        self.w(" * GENERATED by scripts/qdtd/build-quote-fixtures.py - do not hand-edit.")
        self.w(" * Step 03 of specs/quote-document-test-data. Re-runnable; touches only")
        self.w(" * fixture-owned records.")
        self.w(" */")
        self.w(PREAMBLE)
        self.w(TEARDOWN.format(keys="new List<String>{" + ", ".join(q(k) for k in keys) + "}"))

    def w(self, text):
        self.lines.append(text)

    current_key = None

    def quote(self, var, key, account_index, quote_type="Quote"):
        self.current_key = key
        self.w("")
        self.w("SBQQ__Quote__c {v} = newQuote(fixtureAccounts[{i}], {t}, {k});".format(
            v=var, i=account_index, t=q(quote_type), k=q(key)))
        self.w("insert {v};".format(v=var))

    def lines_for(self, var, specs, key=None):
        """specs: list of dicts with code/qty/list/net/charge/freq/optional."""
        self.w("List<SBQQ__QuoteLine__c> {v}Lines = new List<SBQQ__QuoteLine__c>();".format(v=var))
        for n, s in enumerate(specs, start=1):
            INTENT.append({
                "quote_key": key or self.current_key,
                "line_number": n,
                "product_code": s["code"],
                "quantity": s.get("qty", 1),
                "list_price": s.get("list", 1000),
                "discount": discount_percent(s),
                "charge_type": s.get("charge", "One-Time"),
                "billing_frequency": s.get("freq") or "",
                "optional": str(s.get("optional", False)).lower(),
            })
            self.w("{v}Lines.add(newLine({v}.Id, {c}, {n}, {qty}, {lp}, {disc}, {ct}, {bf}, {opt}));".format(
                v=var, c=q(s["code"]), n=n, qty=s.get("qty", 1), lp=s.get("list", 1000),
                disc=discount_percent(s), ct=q(s.get("charge", "One-Time")),
                bf=q(s.get("freq")), opt=q(s.get("optional", False))))
        self.w("insert {v}Lines;".format(v=var))

    def text(self):
        return "\n".join(self.lines) + "\n"


def core_script():
    s = Script("Roster quotes 1-7: baseline, bundles, groups, filters",
               ["QDTD-Q1", "QDTD-Q2", "QDTD-Q3", "QDTD-Q4", "QDTD-Q5", "QDTD-Q6", "QDTD-Q7"])

    # 1 - baseline: every family, no bundles, no groups.
    s.w("\n// Quote 1 - baseline: 18 lines across all six families, no bundles.")
    s.quote("q1", "QDTD-Q1", 0)
    specs = []
    for fam in FAMILY_CODES:
        for i in (1, 6, 9):
            specs.append({"code": code(fam, i), "qty": 2, "list": 1000, "net": 900,
                          "charge": "Recurring" if fam == "Subscription" else "One-Time",
                          "freq": "Monthly" if fam == "Subscription" else None})
    s.lines_for("q1", specs)

    # 2 - the five-level bundle.
    s.w("\n// Quote 2 - two bundle trees, each nested five nodes deep. The chain is")
    s.w("// what DIM_BUNDLE, BUNDLE_PARENTS_ONLY and the depth cases all read.")
    s.quote("q2", "QDTD-Q2", 1)
    s.w("List<SBQQ__QuoteLine__c> q2Roots = new List<SBQQ__QuoteLine__c>();")
    for tree, fam in enumerate(["Hardware", "Software"]):
        s.w("SBQQ__QuoteLine__c q2t{t}L1 = newLine(q2.Id, {c}, {n}, 1, 5000, 10, 'One-Time', null, false);".format(
            t=tree, c=q(code(fam, 1)), n=tree * 10 + 1))
        s.w("q2t{t}L1.SBQQ__Bundle__c = true; q2t{t}L1.SBQQ__Bundled__c = false;".format(t=tree))
        s.w("q2Roots.add(q2t{t}L1);".format(t=tree))
    s.w("insert q2Roots;")
    for tree, fam in enumerate(["Hardware", "Software"]):
        parent = "q2t{}L1".format(tree)
        for level in range(1, 5):
            var = "q2t{t}L{l}".format(t=tree, l=level + 1)
            s.w("SBQQ__QuoteLine__c {v} = newLine(q2.Id, {c}, {n}, 1, {price}, 0, 'One-Time', null, false);".format(
                v=var, c=q(code(fam, level + 1)), n=tree * 10 + level + 1, price=1000 - level * 100))
            s.w("{v}.SBQQ__RequiredBy__c = {p}.Id; {v}.SBQQ__Bundled__c = true; {v}.SBQQ__OptionLevel__c = {lvl};".format(
                v=var, p=parent, lvl=level))
            s.w("insert {v};".format(v=var))
            # A sibling at levels 2 and 3 so nesting is a tree, not a single chain.
            if level in (1, 2):
                sib = var + "sib"
                s.w("SBQQ__QuoteLine__c {v} = newLine(q2.Id, {c}, {n}, 1, 500, 10, 'One-Time', null, false);".format(
                    v=sib, c=q(code(fam, level + 6)), n=tree * 10 + level + 5))
                s.w("{v}.SBQQ__RequiredBy__c = {p}.Id; {v}.SBQQ__Bundled__c = true; {v}.SBQQ__OptionLevel__c = {lvl};".format(
                    v=sib, p=parent, lvl=level))
                s.w("insert {v};".format(v=sib))
            parent = var

    # 3 - wide bundle, for the max-groups overflow cases.
    s.w("\n// Quote 3 - one parent with 25 direct options: the max-groups cases need a")
    s.w("// quote that genuinely produces more groups than a tight ceiling allows.")
    s.quote("q3", "QDTD-Q3", 2)
    s.w("SBQQ__QuoteLine__c q3Parent = newLine(q3.Id, {c}, 1, 1, 9000, 11.11, 'One-Time', null, false);".format(
        c=q(code("Hardware", 1))))
    s.w("q3Parent.SBQQ__Bundle__c = true;")
    s.w("insert q3Parent;")
    s.w("List<SBQQ__QuoteLine__c> q3Options = new List<SBQQ__QuoteLine__c>();")
    s.w("List<String> q3Codes = new List<String>{" + ", ".join(
        q(code(f, i)) for f in FAMILY_CODES for i in range(1, 6)) + "};")
    s.w("for (Integer i = 0; i < q3Codes.size(); i++) {")
    s.w("    SBQQ__QuoteLine__c opt = newLine(q3.Id, q3Codes[i], i + 2, 1, 100 + i, 10, 'One-Time', null, false);")
    s.w("    opt.SBQQ__RequiredBy__c = q3Parent.Id; opt.SBQQ__Bundled__c = true; opt.SBQQ__OptionLevel__c = 1;")
    s.w("    q3Options.add(opt);")
    s.w("}")
    s.w("insert q3Options;")

    # 4 - quote line groups.
    s.w("\n// Quote 4 - four quote line groups, for DIM_QUOTE_LINE_GROUP and for")
    s.w("// nesting a family level underneath a group level.")
    s.quote("q4", "QDTD-Q4", 3)
    s.w("List<SBQQ__QuoteLineGroup__c> q4Groups = new List<SBQQ__QuoteLineGroup__c>();")
    for g, name in enumerate(["Phase 1 - Platform", "Phase 2 - Rollout", "Phase 3 - Support", "Phase 4 - Training"], start=1):
        s.w("q4Groups.add(new SBQQ__QuoteLineGroup__c(SBQQ__Quote__c = q4.Id, Name = {n}, SBQQ__Number__c = {g}));".format(
            n=q(name), g=g))
    s.w("insert q4Groups;")
    s.w("List<SBQQ__QuoteLine__c> q4Lines = new List<SBQQ__QuoteLine__c>();")
    s.w("List<String> q4Codes = new List<String>{" + ", ".join(
        q(code(f, i)) for f in FAMILY_CODES for i in (1, 6)) + "};")
    s.w("for (Integer i = 0; i < q4Codes.size(); i++) {")
    s.w("    SBQQ__QuoteLine__c l = newLine(q4.Id, q4Codes[i], i + 1, 2, 800, 12.5, 'One-Time', null, false);")
    s.w("    l.SBQQ__Group__c = q4Groups[Math.mod(i, 4)].Id;")
    s.w("    q4Lines.add(l);")
    s.w("}")
    s.w("insert q4Lines;")

    # 5 - optional heavy.
    s.w("\n// Quote 5 - mostly optional lines: the non-empty witness for OPTIONAL_ONLY")
    s.w("// and the divergence case for EXCLUDE_OPTIONAL.")
    s.quote("q5", "QDTD-Q5", 4)
    s.lines_for("q5", [
        {"code": code("Hardware", 1), "qty": 1, "list": 1200, "net": 1100, "optional": False},
        {"code": code("Software", 1), "qty": 1, "list": 1000, "net": 950, "optional": False},
    ] + [
        {"code": code(f, i), "qty": 1, "list": 600, "net": 550, "optional": True}
        for f in FAMILY_CODES for i in (2, 7)
    ])

    # 6 - recurring only.
    s.w("\n// Quote 6 - every line recurring, mixed billing frequency: RECURRING_ONLY's")
    s.w("// non-empty witness, ONE_TIME_ONLY's empty witness, and the Family x Frequency")
    s.w("// composite case.")
    s.quote("q6", "QDTD-Q6", 5)
    s.lines_for("q6", [
        {"code": code("Subscription", i), "qty": 3, "list": 900, "net": 800,
         "charge": "Recurring", "freq": freq}
        for i, freq in [(1, "Monthly"), (2, "Quarterly"), (5, "Annual"), (6, "Monthly"), (9, "Annual")]
    ])

    # 7 - one-time only, no optional lines.
    s.w("\n// Quote 7 - all one-time, nothing optional: the empty witness for both")
    s.w("// OPTIONAL_ONLY and RECURRING_ONLY, and non-empty for ONE_TIME_ONLY.")
    s.quote("q7", "QDTD-Q7", 6)
    s.lines_for("q7", [
        {"code": code("Hardware", i), "qty": 2, "list": 1500, "net": 1400, "charge": "One-Time"}
        for i in (1, 2, 6)
    ] + [
        {"code": code("Implementation Services", i), "qty": 1, "list": 2500, "net": 2200, "charge": "One-Time"}
        for i in (1, 6)
    ])

    return s


def edge_script():
    s = Script("Roster quotes 8-13: zero, negative, rounding, degenerate, empty, unnamed",
               ["QDTD-Q8", "QDTD-Q9", "QDTD-Q10", "QDTD-Q11", "QDTD-Q12", "QDTD-Q13"])

    s.w("\n// Quote 8 - every amount zero: division-by-zero in discount %, and a")
    s.w("// grand total that must still reconcile at zero rather than erroring.")
    s.quote("q8", "QDTD-Q8", 7)
    s.lines_for("q8", [{"code": code(f, 3), "qty": 1, "list": 0, "net": 0} for f in FAMILY_CODES])

    s.w("\n// Quote 9 - credits and negative amounts: sign handling through grouping,")
    s.w("// section totals and the grand-total reconciliation.")
    s.quote("q9", "QDTD-Q9", 8)
    s.lines_for("q9", [
        {"code": code("Hardware", 1), "qty": 2, "list": 1200, "net": 1000},
        {"code": code("Hardware", 4), "qty": 1, "list": -450, "net": -450},
        {"code": code("Software", 4), "qty": 3, "list": -450, "net": -400},
    ])

    s.w("\n// Quote 10 - prices that do not divide cleanly: the rounding customizer's")
    s.w("// penny reconciliation has to have something to reconcile.")
    s.quote("q10", "QDTD-Q10", 9)
    s.lines_for("q10", [
        {"code": code("Hardware", 5), "qty": 3, "list": 333.333, "net": 333.333},
        {"code": code("Software", 2), "qty": 7, "list": 899.995, "net": 899.995},
        {"code": code("Subscription", 8), "qty": 11, "list": 12.005, "net": 12.005,
         "charge": "Recurring", "freq": "Monthly"},
    ])

    s.w("\n// Quote 11 - a single line: degenerate grouping, and a section total that")
    s.w("// covers exactly one row.")
    s.quote("q11", "QDTD-Q11", 10)
    s.lines_for("q11", [{"code": code("Hardware", 1), "qty": 1, "list": 1200, "net": 1200}])

    s.w("\n// Quote 12 - every line optional: the empty witness for EXCLUDE_OPTIONAL,")
    s.w("// which is where suppression has to hold.")
    s.quote("q12", "QDTD-Q12", 11)
    s.lines_for("q12", [
        {"code": code(f, 2), "qty": 1, "list": 700, "net": 650, "optional": True} for f in FAMILY_CODES
    ])

    s.w("\n// Quote 13 - products whose Family is blank, so the grouping label has to")
    s.w("// come from the GROUP_UNNAMED dictionary entry. The renderer must never")
    s.w("// print a hard-coded '(unnamed)'.")
    s.w("// Family is cleared on fixture-owned copies only - the shared catalogue keeps its families.")
    s.w("List<Product2> q13Products = new List<Product2>{")
    s.w("    new Product2(Name = 'QDTD Unfamilied A', ProductCode = 'QDTD-NOFAM-1', IsActive = true, Description = 'QDTD- blank family fixture'),")
    s.w("    new Product2(Name = 'QDTD Unfamilied B', ProductCode = 'QDTD-NOFAM-2', IsActive = true, Description = 'QDTD- blank family fixture')")
    s.w("};")
    s.w("List<Product2> q13Existing = [SELECT Id FROM Product2 WHERE ProductCode LIKE 'QDTD-NOFAM-%'];")
    s.w("if (q13Existing.isEmpty()) { insert q13Products; } else { q13Products = q13Existing; }")
    s.w("for (Product2 p : q13Products) { productByCode.put('QDTD-NOFAM-' + (q13Products.indexOf(p) + 1), p.Id); }")
    s.w("List<PricebookEntry> q13Entries = [SELECT Id FROM PricebookEntry WHERE Product2.ProductCode LIKE 'QDTD-NOFAM-%'];")
    s.w("if (q13Entries.isEmpty()) {")
    s.w("    List<PricebookEntry> toAdd = new List<PricebookEntry>();")
    s.w("    for (Product2 p : q13Products) {")
    s.w("        toAdd.add(new PricebookEntry(Pricebook2Id = standardPricebookId, Product2Id = p.Id, UnitPrice = 500, IsActive = true, UseStandardPrice = false));")
    s.w("    }")
    s.w("    insert toAdd;")
    s.w("}")
    s.quote("q13quote", "QDTD-Q13", 0)
    s.lines_for("q13quote", [
        {"code": "QDTD-NOFAM-1", "qty": 1, "list": 500, "net": 450},
        {"code": "QDTD-NOFAM-2", "qty": 2, "list": 500, "net": 500},
        {"code": code("Hardware", 1), "qty": 1, "list": 1200, "net": 1200},
    ])

    return s


def volume_script():
    s = Script("Roster quotes 14-19: volume, amendment, renewal, locale, unicode, empty",
               ["QDTD-Q14", "QDTD-Q15", "QDTD-Q16", "QDTD-Q17", "QDTD-Q18", "QDTD-Q19"])

    s.w("\n// Quote 14 - 200 lines. Emitted as a loop rather than 200 statements so the")
    s.w("// script stays under the 32KB anonymous-Apex ceiling.")
    s.quote("q14", "QDTD-Q14", 1)
    s.w("List<String> q14Codes = new List<String>{" + ", ".join(
        q(code(f, i)) for f in FAMILY_CODES for i in range(1, 11)) + "};")
    s.w("List<SBQQ__QuoteLine__c> q14Lines = new List<SBQQ__QuoteLine__c>();")
    s.w("for (Integer i = 0; i < 200; i++) {")
    s.w("    String c = q14Codes[Math.mod(i, q14Codes.size())];")
    s.w("    q14Lines.add(newLine(q14.Id, c, i + 1, 1 + Math.mod(i, 5), 100 + i, 10,")
    s.w("        Math.mod(i, 3) == 0 ? 'Recurring' : 'One-Time', Math.mod(i, 3) == 0 ? 'Monthly' : null, false));")
    s.w("}")
    s.w("insert q14Lines;")

    s.w("\n// Subscriptions - fixture-owned, and the only reason the Replacement Added /")
    s.w("// Replacement Removed branches of QuoteDocumentLine.classify are reachable at")
    s.w("// all: they turn on SBQQ__RenewedSubscription__c / SBQQ__UpgradedSubscription__c")
    s.w("// being non-null, and those are lookups to SBQQ__Subscription__c.")
    s.w("delete [SELECT Id FROM SBQQ__Subscription__c WHERE SBQQ__Product__r.ProductCode LIKE 'QDTD-%'];")
    s.w("List<SBQQ__Subscription__c> subs = new List<SBQQ__Subscription__c>();")
    s.w("for (Integer i = 0; i < 6; i++) {")
    s.w("    subs.add(new SBQQ__Subscription__c(")
    s.w("        SBQQ__Product__c = productByCode.get('QDTD-SUB-' + (i + 1)),")
    s.w("        SBQQ__Quantity__c = 5,")
    s.w("        SBQQ__NetPrice__c = 800,")
    s.w("        SBQQ__SubscriptionStartDate__c = Date.today().addMonths(-6),")
    s.w("        SBQQ__SubscriptionEndDate__c = Date.today().addMonths(6)")
    s.w("    ));")
    s.w("}")
    s.w("insert subs;")

    s.w("\n// Quote 15 - amendment. Each replacement is a pair: the removed side sits at")
    s.w("// quantity zero carrying a prior quantity, the added side carries the new one.")
    s.quote("q15", "QDTD-Q15", 2, quote_type="Amendment")
    s.w("List<SBQQ__QuoteLine__c> q15Lines = new List<SBQQ__QuoteLine__c>();")
    s.w("SBQQ__QuoteLine__c q15Removed = newLine(q15.Id, 'QDTD-SUB-1', 1, 0, 900, 11.11, 'Recurring', 'Monthly', false);")
    s.w("q15Removed.SBQQ__PriorQuantity__c = 5; q15Removed.SBQQ__Existing__c = true;")
    s.w("q15Removed.SBQQ__UpgradedSubscription__c = subs[0].Id;")
    s.w("q15Lines.add(q15Removed);")
    s.w("SBQQ__QuoteLine__c q15Added = newLine(q15.Id, 'QDTD-SUB-2', 2, 8, 900, 5.56, 'Recurring', 'Monthly', false);")
    s.w("q15Added.SBQQ__PriorQuantity__c = 0;")
    s.w("q15Added.SBQQ__UpgradedSubscription__c = subs[1].Id;")
    s.w("q15Lines.add(q15Added);")
    s.w("SBQQ__QuoteLine__c q15Existing = newLine(q15.Id, 'QDTD-SUB-5', 3, 5, 900, 0, 'Recurring', 'Monthly', false);")
    s.w("q15Existing.SBQQ__PriorQuantity__c = 5; q15Existing.SBQQ__Existing__c = true;")
    s.w("q15Lines.add(q15Existing);")
    s.w("SBQQ__QuoteLine__c q15New = newLine(q15.Id, 'QDTD-HW-1', 4, 2, 1200, 8.33, 'One-Time', null, false);")
    s.w("q15Lines.add(q15New);")
    s.w("insert q15Lines;")

    s.w("\n// Quote 16 - renewal, driving the renewed side of the same two branches and")
    s.w("// the second value of DIM_TRANSACTION_TYPE.")
    s.quote("q16", "QDTD-Q16", 3, quote_type="Renewal")
    s.w("List<SBQQ__QuoteLine__c> q16Lines = new List<SBQQ__QuoteLine__c>();")
    s.w("SBQQ__QuoteLine__c q16Removed = newLine(q16.Id, 'QDTD-SUB-3', 1, 0, 900, 5.56, 'Recurring', 'Annual', false);")
    s.w("q16Removed.SBQQ__PriorQuantity__c = 4; q16Removed.SBQQ__Existing__c = true;")
    s.w("q16Removed.SBQQ__RenewedSubscription__c = subs[2].Id;")
    s.w("q16Lines.add(q16Removed);")
    s.w("SBQQ__QuoteLine__c q16Added = newLine(q16.Id, 'QDTD-SUB-4', 2, 6, 900, 2.22, 'Recurring', 'Annual', false);")
    s.w("q16Added.SBQQ__RenewedSubscription__c = subs[3].Id;")
    s.w("q16Lines.add(q16Added);")
    s.w("insert q16Lines;")

    s.w("\n// Quote 17 - French-billing account, for the locale dictionary and the fr")
    s.w("// narrative content records.")
    s.w("Account frenchAccount = null;")
    s.w("for (Account a : fixtureAccounts) { if (a.BillingCountry == 'France') { frenchAccount = a; break; } }")
    s.w("if (frenchAccount == null) { throw new IllegalArgumentException('No French-billing QDTD- account: step 02 needs regenerating.'); }")
    s.w("SBQQ__Quote__c q17 = new SBQQ__Quote__c(SBQQ__Account__c = frenchAccount.Id,")
    s.w("    SBQQ__Opportunity2__c = opportunityByAccount.get(frenchAccount.Id), SBQQ__Primary__c = false,")
    s.w("    SBQQ__Type__c = 'Quote', SBQQ__Status__c = 'Draft', SBQQ__PriceBook__c = standardPricebookId,")
    s.w("    SBQQ__Key__c = 'QDTD-Q17');")
    s.w("insert q17;")
    s.lines_for("q17", [
        {"code": code("Software", 1), "qty": 2, "list": 1000, "net": 900},
        {"code": code("Premier Support", 1), "qty": 1, "list": 2000, "net": 1800},
    ], key="QDTD-Q17")

    s.w("\n// Quote 18 - the unicode and long-name product. The quote line's name is a")
    s.w("// formula off Product2, so the long string has to live on the product.")
    s.quote("q18", "QDTD-Q18", 4)
    s.lines_for("q18", [
        {"code": "QDTD-UNI-1", "qty": 1, "list": 1234.567, "net": 1234.567},
        {"code": code("Hardware", 1), "qty": 1, "list": 1200, "net": 1200},
    ])

    s.w("\n// Quote 19 - no lines at all. The only witness for an empty ALL filter, and")
    s.w("// the case whose expected outcome step 04 declares up front rather than assuming.")
    s.quote("q19", "QDTD-Q19", 5)

    return s


def main():
    outputs = [
        ("qdtd-quotes-01-core.apex", core_script()),
        ("qdtd-quotes-02-edge.apex", edge_script()),
        ("qdtd-quotes-03-volume.apex", volume_script()),
    ]
    import csv
    intended = ROOT / "specs/quote-document-test-data/results/fixture-intended.csv"
    intended.parent.mkdir(parents=True, exist_ok=True)
    with intended.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(INTENT[0].keys()))
        writer.writeheader()
        writer.writerows(INTENT)
    print("wrote {} ({} explicitly specified lines)".format(intended.relative_to(ROOT), len(INTENT)))

    for name, script in outputs:
        target = ROOT / "scripts/apex" / name
        text = script.text()
        target.write_text(text, encoding="utf-8")
        flag = "  ** OVER 32KB **" if len(text) > 32000 else ""
        print("wrote {} ({} bytes){}".format(target.relative_to(ROOT), len(text), flag))


if __name__ == "__main__":
    main()
