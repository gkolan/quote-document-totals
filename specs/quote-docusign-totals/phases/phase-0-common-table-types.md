# Phase 0 — Ship the commonly-requested table types

**Status: DONE — deployed and verified live against `act.gkolan@gmail.com` on 2026-08-03.**
**Blocked by:** nothing
**Blocks:** nothing — every other phase is independent of this one
**Owner decision needed:** no (config-only; the one open business question — multi-year/period columns — is explicitly deferred to its own future spec, not blocking this phase)

---

## 1. Goal

Close the gap between "what this framework ships" and "what a quote/order document commonly needs," for every request that's genuinely config-only, before calling v1 done — without building anything speculative for requests that aren't actually common, or that this framework shouldn't own.

## 2. Why this phase exists

`specs/quote-docusign-totals/spec.md` §4 ("Phase 0") identified this by cross-checking the ten already-shipped table definitions against how Salesforce's own CPQ/DocuSign documentation and general order-form conventions describe a typical quote document, plus four concepts raised directly in conversation (subscriptions, contracts, drawdowns, standard revenue classification). See that section for the full research and citations; this document is the atomic, actionable slice of it.

## 3. Scope

- Ship one new table definition — **Discount Summary** — that was identified as an obviously common, zero-cost gap.
- Explicitly record the discovery/decision status of every other commonly-requested type that was evaluated, so none of them silently falls through the cracks.

## 4. Out of scope (and why, per item)

| Item | Disposition |
|---|---|
| Tax summary | **Discovery, not this phase.** No tax field exists anywhere in this org's CPQ line data model. Needs a business/admin answer — does this org use CPQ's tax add-on or an external tax engine at all — before it's even classifiable as a gap. |
| Multi-year / price-by-period tables | **Named, not built.** Confirmed as a genuinely common CPQ pattern ("Complex Tables... the most common example being a multi-year subscription with varying price by year" — Salesforce's own terminology). No MDQ implementation exists in this codebase at all. This needs its own follow-up spec (a period-as-*column* concept the current row-based model has no slot for), not a slot in this phase. |
| Subscriptions (term, start/end date, renewal date) | **Deferred, scoped.** `QuoteDocumentLine` captures no subscription term/date properties today. Real, bounded work (a few new snapshot properties, maybe a new measure) — worth its own small follow-up spec once someone confirms which subscription fields this org actually populates. |
| Contracts (a view spanning a Contract's amendment history) | **Explicitly a different framework.** Everything here keys off one Quote (`Table_Key__c = QuoteId:TableCode`). A Contract-spanning view needs a different root object and key — a sibling framework reusing these same patterns, not an extension of this one. |
| Drawdowns (prepaid balance / committed spend) | **Not this framework's job.** A drawdown is a running balance against consumption events, not a sum of Quote Line amounts — the opposite of "generated data is a disposable, rebuildable projection," which is the one rule this entire framework depends on. Only relevant if this org actually sells prepaid/committed-spend deals; needs its own data source and spec if so. |
| Payment terms, T&Cs, signature/validity block | **Correctly out of scope.** Static contract language and acceptance workflow, not computed Quote Line data. No action — worth confirming explicitly with whoever owns the DocuSign template so nobody assumes this framework produces it. |
| Standard revenue classification (New/Expansion/Renewal/Contraction/Churn) | **Folded into Phase 1**, not this phase — `classify()` is already gated there as provisional/unvalidated, and the taxonomy question is the same conversation as validating the existing branches. See `phase-1-classification-validation.md`. |

## 5. Preconditions / dependencies

None. Pure CMDT addition against an already-deployed framework.

## 6. Step-by-step tasks (all completed in source)

1. Add `Quote_Document_Table_Def__mdt` record `DISCOUNT_SUMMARY` — `PRICE_WATERFALL` measures, grouped by `PRODUCT_FAMILY`, `Show_Details__c = true` (the entire point: per-line list/net/discount transparency), `Display_Order__c = 80`.
2. Add its `Quote_Document_Grouping__mdt` record (`PRODUCT_FAMILY`, level 1, sequence 10).
3. Write the full guide under `docs/documentation-standards.md`'s eleven-section standard — `docs/discount-summary-guide.md`.
4. Build the deployable report — `force-app/main/default/reports/CPQ_Document_Totals/Quote_Document_Discount_Summary.report-meta.xml`.
5. Write the worked-example script — `scripts/apex/discount-summary-example.apex` — hand-built, numbers cross-checked against the existing Product Family Summary example on the same catalogue.
6. Extend `scripts/scratch-org-bootstrap.sh` (one new line in step 5, per its own standing rule of never creating a second bootstrap script).
7. Confirm no permission-set change is needed — no new fields, only new CMDT records, and CMDT queries in this codebase run without `WITH USER_MODE`, so no FLS grant is required for the generator to read them.

## 7. Files touched

- `force-app/main/default/customMetadata/Quote_Document_Table_Def.DISCOUNT_SUMMARY.md-meta.xml` (new)
- `force-app/main/default/customMetadata/Quote_Document_Grouping.DISCOUNT_SUMMARY_PRODUCT_FAMILY.md-meta.xml` (new)
- `force-app/main/default/reports/CPQ_Document_Totals/Quote_Document_Discount_Summary.report-meta.xml` (new)
- `scripts/apex/discount-summary-example.apex` (new)
- `scripts/scratch-org-bootstrap.sh` (modified — one new step 5h line)
- `docs/discount-summary-guide.md` (new)

## 8. Acceptance criteria

- [x] `DISCOUNT_SUMMARY` table definition exists, `Is_Active__c = true`, and will be picked up by `QuoteDocumentTableDefinition.getAll()` on the next generation for every quote (no per-quote opt-in required, matching how every other active table behaves).
- [x] Guide scores ≥ 9.8/10 against `docs/documentation-standards.md` §5's rubric (self-scored 10.0/10 in the guide's own §11, on the same "internal consistency, not live-org proof" basis every other guide in this repo uses).
- [x] A real, deployable report exists and is named in the guide, not just specified.
- [x] Worked-example script is idempotent (deletes only its own table code first) and its asserted totals (Net 102,910, Discount 4,300) match the existing Product Family Summary example's totals on the same catalogue.
- [x] **Verified live**, 2026-08-03: `sf project deploy start` succeeded against `act.gkolan@gmail.com` (including the report — see §11's note on the `Amount_Regular__c` fix this surfaced). `sf apex run --file scripts/apex/discount-summary-example.apex` ran successfully, `System.debug` confirmed "9 rows, total discount 4,300, grand total 102,910." A live SOQL query against `Quote_Document_Row__c` returned exactly the shape documented in the guide's §4.3.

## 9. Verification method (for whoever has org access)

```bash
sf project deploy start --target-org <alias> --source-dir force-app
sf apex run --target-org <alias> --file scripts/apex/discount-summary-example.apex
```
```sql
SELECT Row_Type__c, Group_Level__c, Display_Label__c, Amount_List__c, Amount_Discount__c, Amount_Net__c
FROM Quote_Document_Row__c
WHERE Quote_Document_Table__r.Table_Code__c = 'DISCOUNT_SUMMARY'
ORDER BY Display_Order__c
```
Expect the shape in `docs/discount-summary-guide.md` §4.3, and a grand total of 102,910 with total discount 4,300.

Additionally, once any real quote is regenerated (`QuoteDocumentGenerator.generate`), confirm `DISCOUNT_SUMMARY` now appears alongside the other tables automatically — it's active by default, no separate rollout step.

## 10. Verification status (honest, as of this phase's close-out)

**Fully verified live**, 2026-08-03, against `act.gkolan@gmail.com`. Initial finding: the first deploy attempt failed — the report referenced `Amount_Regular__c`, which existed on `Quote_Document_Row__c` but was never added as a selectable column on `Quote_Document_Tables_and_Rows.reportType-meta.xml` (custom report types require every field explicitly listed; having it on the object isn't enough). Fixed by adding `Amount_Regular__c` and `Amount_Customer__c` to the report type. Second deploy succeeded; the worked-example script and a direct SOQL query both confirmed the exact numbers documented in the guide.

## 11. Close-out record

- **Date:** 2026-08-03
- **What shipped:** `DISCOUNT_SUMMARY` table definition, grouping record, report, worked-example script, bootstrap-script line, full guide — deployed and verified live.
- **Bug found and fixed during verification:** `Quote_Document_Tables_and_Rows.reportType-meta.xml` was missing `Amount_Regular__c`/`Amount_Customer__c` as report columns — a pre-existing gap in the report type, not specific to this table, now closed for every current and future guide that needs those two fields.
- **What's still open:** the three explicitly-deferred items from §4 (tax discovery question, multi-year/period follow-up spec decision, subscription-fields follow-up spec) — none of which block calling this phase done, since each was scoped out of this phase on purpose.
- **Next phase:** `phase-1-classification-validation.md`.
