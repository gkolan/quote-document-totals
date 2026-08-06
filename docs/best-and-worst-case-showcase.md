# Best Case / Worst Case Showcase — seeing the framework's range in one place

**Status:** applied in source, deployed, and verified by running against a real CPQ-installed org (`gkcpq-dev-ed.develop.my.salesforce.com`) on 2026-08-06. Both quotes generated through the real entry point (`QuoteDocumentGenerator.generate()`, never a direct record insert) and settled to `Document_Data_Status__c = Ready`.

## 1. What this is

Two quotes — **Q-00071** (tagged `[BEST-CASE]`, account "Sterling Advisory Group") and **Q-00072** (tagged `[WORST-CASE]`, account "Aurora Municipal Consortium") — built once by [`scripts/apex/best-worst-case-showcase.apex`](../scripts/apex/best-worst-case-showcase.apex) and generated the same way a real user would: quote lines inserted first, then `QuoteDocumentGenerator.generate()` called, exactly what the [`Generate Quote Document Tables`](../force-app/main/default/flows/Generate_Quote_Document_Tables.flow-meta.xml) Flow's button does.

Because every active `Quote_Document_Table_Def__mdt` record runs against whatever quote it's given, these two quotes automatically populate **all fifteen** shipped table views — no per-view script needed, and any future table view gets exercised by these same two quotes with no change to the script.

- **Best Case** — a clean, realistic deal shaped to show every mechanism working correctly: a two-level bundle (free component + priced option), two Quote Line Groups, a recurring charge, a one-time service charge, one real optional product, and one genuine example of every transaction type this framework can safely produce from hand-built data (Net New, Cancellation, Replacement Removed, Replacement Added).
- **Worst Case** — the same shapes pushed toward the framework's real limits, while staying inside them: eighteen Quote Line Groups (well under the `Max_Groups__c` default of 50, but nine times Best Case's two), a three-level-deep bundle, a 97%-discounted line, a large-quantity/high-value line, and **deliberately zero Optional lines**.

## 2. The one edge case you can see live, in a real report

Open **Reports → CPQ Document Totals → Quote Document Optional Products**, filter to either quote by name, and compare:

| Quote | Rows | Amount_Net__c | Why |
|---|---|---|---|
| Q-00071 (Best Case) | 4 | $600.00 | Has one real Optional line — the table shows a Group Header, Subtotal, Detail, and Grand Total |
| Q-00072 (Worst Case) | **1** | **$0.00** | Zero Optional lines — `Line_Filter__c = OPTIONAL_ONLY` excludes every line, so the table still generates cleanly with exactly one Grand Total row, all zeros, `Status__c = Complete` — not an error, not a missing table |

This is the same behavior proven in isolation by `QuoteDocumentGeneratorTest.tableWithEveryLineFilteredOutStillProducesACleanZeroGrandTotal` — here it's visible in a real report against real generated data, not just a unit test assertion.

## 3. Where to look for each view

| Table Code | Report | What to compare between the two quotes |
|---|---|---|
| `PRODUCT_FAMILY_SUMMARY` | Quote Document Product Family Summary | 5 families either way — Worst Case's rotation shows more even spread |
| `CHARGE_TYPE_SUMMARY` | Quote Document Charge Type Summary | Recurring vs. one-time section totals, at very different scale |
| `BUNDLE_DETAIL` | Quote Document Bundle Detail | Best Case's 2-level bundle vs. Worst Case's 3-level nested bundle |
| `BUNDLE_PRODUCT_GRID` | Quote Document Bundle and Product Grid | Same bundle depth contrast, CHANGE-measure columns |
| `BUNDLE_SUMMARY` | Quote Document Bundle Totals | One bundle each — depth is the variable, not count |
| `GROUP_FAMILY_DETAIL` | Quote Document Group and Family Detail | **2 Quote Line Groups vs. 18** — the starkest contrast in the whole showcase |
| `OPTIONAL_PRODUCTS` | Quote Document Optional Products | Populated vs. clean-empty — see §2 |
| `DISCOUNT_SUMMARY` | Quote Document Discount Summary | Modest discounts (5–15%) vs. one 97%-discounted near-zero line |
| `FAMILY_BILLING_COMPOSITE` | Quote Document Family and Billing Composite | Composite bucket labels at small vs. large group count |
| `PRODUCT_SUMMARY` | Quote Document Product Totals | CHANGE measures across a small vs. large product spread |
| `TRANSACTION_SUMMARY` | Quote Document Transaction Type Totals | Best Case shows all four realistic transaction types; Worst Case is Net-New-heavy at volume |
| `INDUSTRY_ALLEGIANCE`, `DISCOUNT_EXAMPLE`, `ROUNDING_EXAMPLE`, `ROW_CUSTOMIZER_EXAMPLE` | *(no dedicated report — use* Quote Document - Rendered View *or query directly)* | Row-customizer-driven tables; Worst Case's larger total gives `ROUNDING_EXAMPLE` a non-zero adjustment to show |

## 4. What this deliberately does not attempt, and why

- **Does not exceed `Max_Groups__c`.** A breach fails generation entirely for that table (`QuoteDocumentGeneratorTest.exceedingTheGroupCeilingFailsLoudly` proves this) — a report can only display a limit that was respected, not one that was breached.
- **Does not force a `Termination` transaction type.** `SBQQ__NetTotal__c` is a CPQ formula field this script cannot safely set negative by hand, and `QuoteDocumentLine.classify()`'s own header comment already flags that branch as provisional and unverified against real data.
- **Does not hand-pick two Quote Line Group names that collide after sanitization.** That's a hard, by-design generation failure (`duplicateGroupKeysAfterSanitizationFailGenerationLoudly`), already proven by that unit test — risking it here would only threaten this script's reliability for no new coverage.

## 5. Running it

```bash
sf apex run --target-org <alias> --file scripts/apex/best-worst-case-showcase.apex
sf apex run --target-org <alias> --file scripts/apex/best-worst-case-showcase-settle.apex
```

**Two scripts, not one — and the gap between them matters.** CPQ recalculates several of the Quote's own rollup fields asynchronously after a batch of Quote Line inserts, finishing a few seconds after the synchronous insert returns. The build script's `generate()` call can run before that recalculation finishes, so the framework's own staleness safety net (`QuoteDocumentStaleness`) correctly flips the quote back to `Stale` moments later — this was observed directly while building this showcase, not a hypothetical. The settle script re-runs `generate()` once CPQ's recalculation has finished and asserts both quotes land on `Ready`. Both scripts are wired into [`scripts/scratch-org-bootstrap.sh`](../scripts/scratch-org-bootstrap.sh) (step 5m) with the required gap between them already handled.

Re-running either script is safe — `QuoteDocumentGenerator.generate()` reuses prior output via its fingerprint check when nothing has changed, so a repeat run costs one cheap query pass per quote, not a full rebuild.
