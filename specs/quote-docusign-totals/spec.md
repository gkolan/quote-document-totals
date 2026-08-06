# CPQ Quote Document Framework — hardening spec

**Status of this file:** planning spec, not a build log. It turns the five research conversations in [`research/1.md`](research/1.md)–[`research/5.md`](research/5.md) into a gap analysis against what is actually deployed today, and a step-by-step plan to close the gaps that are still worth closing. It does not re-describe the architecture — [`docs/quote-document-totals.md`](../../docs/quote-document-totals.md) is the single source of truth for that and should be read first.

**Working name:** *CPQ Quote Document Framework* (options and reasoning below — trivial to change, it's a doc title, not a namespace).

---

## 0. Naming options

You asked for three-word options. The code itself already committed to a prefix — every object, class, trigger, CMDT type, report folder and permission set uses `Quote Document` / `QuoteDocument` / `Quote_Document_*` (`QuoteDocumentGenerator`, `Quote_Document_Table_Def__mdt`, `CPQ_Document_Totals` permission set, `CPQ Document Totals` report folder). Renaming the *framework's spoken name* doesn't touch any of that — it's just what you call it in conversation and in doc titles.

| Option | Reads as | Fit |
|---|---|---|
| **CPQ Quote Document** *(recommended)* | ties to the existing `CPQ_Document_Totals` permission set / report folder name | closest match to what's already in the org — least translation tax when talking to someone who's seen the permission set or reports |
| Quote Document Framework | generic, descriptive | matches the `QuoteDocument*` class prefix exactly, reads well as a doc title |
| CPQ Document Engine | emphasizes it's a generation engine, not just storage | good if you want to signal "this computes," slightly diverges from existing naming |
| Quote Total Ledger | emphasizes the reconciliation/audit angle from research/1 | most distinct, but doesn't match anything already deployed — would need a mental remap every time |

I used **CPQ Quote Document** as the working title below since it's a one-word tweak from your own suggestion and lines up with the permission set name you already deployed. Say the word and I'll swap it everywhere — it's a find-and-replace on this file only.

---

## 1. Where this actually stands today

The five research files argued about how much abstraction the generator needs (Apex-only tables vs. a full grouping engine, CMDT now vs. later, Quote-level readiness gating, platform-event orchestration). The repo has since resolved almost all of those arguments in code, not just in this spec:

| Research question | Research's answer | What's actually deployed |
|---|---|---|
| Object hierarchy | Quote → Table → Row, Quote stores only readiness ([1.md](research/1.md)) | Exactly this. `Document_Data_Status__c` etc. live on `SBQQ__Quote__c`; measures live only on `Quote_Document_Table__c` / `Quote_Document_Row__c`. |
| Grouping engine shape | Don't build the full `GroupingDimension`/`MeasureSet`/interface framework in [2.md](research/2.md) — [3.md](research/3.md) walked it back to three classes and a `switch` | Landed even closer to [3.md](research/3.md)'s v1: `QuoteDocumentLine.getGroupingValue` is a `when`-block, `QuoteDocumentRowBuilder` does one recursive grouping method. No interface hierarchy exists. |
| Where table definitions live | Apex constants first, CMDT once admins need to author without a developer or the count passes ~5 ([4.md](research/4.md)) | Already on CMDT (`Quote_Document_Table_Def__mdt` + `Quote_Document_Grouping__mdt`, 10 table defs, 12 groupings) — ahead of research's stated trigger point, and it's paying off: six of ten table guides needed zero Apex. |
| Reconciliation assertions | Grand total = sum of level-1 subtotals = sum of included details; table measures = grand total row ([1.md](research/1.md), [2.md](research/2.md) test matrix) | Implemented as `QuoteDocumentGenerator.verify()`, four assertions, throws and rolls back to a savepoint on failure. Assertion 4 (`Amount_Net__c` ties to `SBQQ__NetAmount__c`) is live-verified against real data. |
| Platform-event orchestration | Treat as a stale-refresh request, not one-event-per-generation; keep it optional for v1 ([2.md](research/2.md), [3.md](research/3.md)) | Correctly *not* built yet. Staleness marking exists (`QuoteDocumentStaleness`, async via `@future`); generation is on-demand from a quick action. The doc explicitly scopes out platform events until automatic generation is wanted. |
| Inclusion-flag equivalence (`Include_In_Subtotal__c == Include_In_Grand_Total__c` for v1) | Recommended constraint ([2.md](research/2.md) §6B) | Matches current behavior — aggregate rows carry both false, counted rows both true. |

This is the important finding for this spec: **the architecture arguments in the research are already settled and correctly resolved in code.** What's left is not "should we build the framework" — it's a short list of specific robustness gaps the research flagged that the current implementation hasn't picked up yet. That's what the rest of this document is.

---

## 2. Request coverage boundary — what "handles any request" actually means here

"Can the framework handle any type of request thrown at it" is the wrong shape of question to say yes to. No system can absorb a genuinely unbounded request set without either (a) becoming the fully generic `GroupingDimension`/`MeasureSet`/interface framework that [3.md](research/3.md) explicitly rejected, or (b) quietly doing the wrong thing for the requests it wasn't built for. This codebase deliberately chose the safer trade: a config surface wide enough to cover the realistic request space, plus a hard, loud failure (`throw`, not a silent default) for anything outside it. That's a design decision worth stating precisely rather than leaving implicit, so here is the actual boundary, checked directly against `QuoteDocumentLine.cls` and the `Quote_Document_Table_Def__mdt` / `Quote_Document_Grouping__mdt` field lists.

### A — Zero code. A business user or admin can do this today by adding CMDT records.

| Request | How |
|---|---|
| "New table, grouped by \[any existing dimension or field\], in this order" | New `Quote_Document_Table_Def__mdt` + one `Quote_Document_Grouping__mdt` per level/part |
| Reorder nesting (`Industry > Family` → `Family > Industry`) | Swap `Level__c` |
| Turn nested groups into one composite bucket (`"Hardware / Recurring"`) | Give the parts the same `Level__c`; set `Composite_Separator__c` |
| Group by any plain field on the line, product, group, or a relationship off them | `Field_Path__c`, e.g. `SBQQ__Group__r.SBQQ__BillingFrequency__c` — schema-validated at load, `WITH USER_MODE` enforced |
| Show/hide detail rows, show/hide section totals | `Show_Details__c`, `Show_Section_Totals__c` |
| Cap or raise how many groups a table can produce | `Max_Groups__c` |
| Restrict a table to one of the six existing filters (all lines / exclude optional / optional only / recurring only / one-time only / bundle parents only) | `Line_Filter__c` |
| Switch a table between the price-waterfall and change-measure families | `Measure_Set__c` |
| Turn a table off entirely | `Is_Active__c = false` |

This category is genuinely open-ended within its axes — any combination of existing dimensions, filters, nesting order, and measure family is a new CMDT record, not a new code path. It's also where most real requests land: the doc's own worked example is six shipped tables built entirely this way, and the last documentation pass covered ten table views with **zero Apex changes** in six of them.

### B — One small, additive Apex change. Still config-first, but a developer touches one `when` branch.

| Request | Touch point |
|---|---|
| A new *computed* dimension — a value that isn't sitting on one field (a bucketed range, a mapped category, anything needing logic) | One `when` in `QuoteDocumentLine.getGroupingValue(String)` |
| A new *filter* — some inclusion rule the six existing ones don't express | One `when` in `QuoteDocumentLine.matchesFilter` |
| A new measure | Two fields on both objects, two lines in `Measures.add`/`writeTo`, one entry in `measureFields()`, and the permission set (four touch points, all named in the doc's §9 index) |

Each of these is a few lines, not a redesign — the `when`-block shape is intentional per [3.md](research/3.md)'s own argument ("a switch with four or five cases is easier to read than an interface hierarchy"). The line to watch: research/4.md's own stated threshold — once a switch is pushing ~15 cases, or a new table needs its own bespoke branch beyond a single `when`, config has stopped paying for itself and it's time to extract an interface. Not before.

### C — Not supported today, and not free to add. Real design work, or explicitly rejected on purpose.

| Request | Why it's out |
|---|---|
| A line counted in more than one group (e.g., allocate 40% to Region A, 60% to Region B) | Explicitly excluded by design ([2.md](research/2.md) invariant A) — multi-membership risks double-counting without an allocation model that doesn't exist |
| A row that's in the subtotal but not the grand total, or vice versa | `Include_In_Subtotal__c` is currently equal to `Include_In_Grand_Total__c` by construction (`countsIn` returns one boolean, used for both) — the split fields exist on the schema but the code doesn't yet let them diverge, per [2.md](research/2.md) invariant B |
| Detail grain other than "one row per Quote Line" (e.g., one row per Product, aggregating several lines) | No `DetailPolicy` exists; deferred on purpose (`Source_Line_Count__c` is in the schema's own Deferred list) |
| A table spanning more than one quote (account rollups, quote-to-quote comparisons) | The entire architecture is scoped to one quote per table (`Table_Key__c = QuoteId:TableCode`); no cross-quote aggregation path exists |
| "What did this table look like before the last edit" from Salesforce data (not the signed PDF) | No generation versioning (`Generation_Key__c`/`Is_Current__c`) — this is gap **G2** in §3 below |
| A grouping value from outside the Quote Line's own record graph (an external system call, a second unrelated SOQL query per line) | `resolvePath` walks the in-memory record graph only; nothing async or cross-object |
| MDQ dynamic period columns as actual table columns (not rows) | Explicitly out of scope in the schema's "Known boundaries" — periods render as rows via a grouping dimension, not as columns |
| Letting the DocuSign template calculate anything (a subtotal, a bundle inclusion decision) | Rejected by design, not by omission — see [1.md](research/1.md): "CLM should print the values... CLM should not recalculate subtotals" |

### The part that makes this actually safe rather than just documented

An unrecognized dimension or filter value doesn't fall through to "include everything" or return a default group — `getGroupingValue` and `matchesFilter` both `throw` on an unmapped value. So a request that lands outside category A or B doesn't produce a silently wrong document; generation fails loudly, `Status__c = 'Failed'`, `Error_Message__c` populated, and nothing gets marked `Ready` for DocuSign to consume. That's the actual answer to "any request": the framework doesn't silently absorb everything, but it also never quietly mishandles something it wasn't built for — every request either succeeds through A/B, or fails visibly before it reaches a signed document.

---

## 3. Gap analysis — what research flagged that isn't in yet

Checked directly against `QuoteDocumentGenerator.cls`, `Quote_Document_Table__c`, and `Quote_Document_Row__c` field lists.

| # | Gap | Source | Current state | Risk if left alone |
|---|---|---|---|---|
| G1 | No `FOR UPDATE` lock on the Quote during generation | [2.md](research/2.md) §12 | `QuoteDocumentGenerator` queries the quote without `FOR UPDATE` | Two near-simultaneous generation requests for the same quote (e.g. a doubled quick-action click, or a future platform-event subscriber) can interleave and leave inconsistent tables. Currently low-probability because generation is a manual, single-user click — but this is exactly the gap that becomes load-bearing the day automatic generation ships. |
| G2 | No `Generation_Key__c` / `Is_Current__c`, no historical retention of *source* snapshots | [1.md](research/1.md) "Recommended publication model"; explicitly deferred in [5.md](research/5.md) "Deferred" list | Regeneration is delete-and-reinsert (`Table_Key__c = QuoteId:TableCode`). Confirmed correct per the existing doc §2.1/§6, but there is no way to see what a *previous* generation looked like once regenerated. | Acceptable today because the signed PDF in DocuSign is the durable artifact and `QuoteDocumentRetention` already protects Accepted quotes from purge. Becomes a real gap only if someone needs to answer "what did the document say before this edit" from Salesforce data itself, not the signed PDF. |
| G3 | Whole-quote generation isn't guaranteed atomic across *all* tables in one transaction in a way that's asserted, only implied by "one savepoint per quote" | [1.md](research/1.md) "Quote-level consistency" risk | `generateOne(quote)` does appear to be one savepoint per quote covering all its tables (confirmed via the doc's runtime-flow diagram) — this is likely already satisfied, but there's no explicit test asserting "a mid-generation failure leaves the *previous* complete generation untouched," only that failure sets `Status__c = 'Failed'`. | Low risk given the savepoint pattern, but unverified by name in the test suite — worth a named test, not a redesign. |
| G4 | Test matrix from [2.md](research/2.md) §14 not cross-checked line-by-line against `QuoteDocumentGeneratorTest` / `QuoteDocumentLifecycleTest` | [2.md](research/2.md) | Both test classes exist (499 + 524 lines) and the doc names specific guard tests (`editingALineMarksTheQuoteStale`, `grandTotalReconcilesToTheQuoteNetAmount`, `aFieldPathOnTheQuoteYieldsExactlyOneGroup`) | Can't currently state with confidence that every row in research's matrix (duplicate Quote Line, group path length, blank dimension, negative cancellation, etc.) has a named test. Documentation debt, not a code gap — but "robust" isn't provable without this. |
| G5 | Amendment/renewal classification (`classify()` / `countsIn`) is explicitly provisional | [2.md](research/2.md) §7 bundle rules match; classification itself flagged provisional in the existing doc §3, not research | No amendment quotes exist in `gkCPQDev` to validate the five `classify()` branches against real data | This is the single highest-consequence gap in the whole framework: a wrong classification puts a wrong number on a signed document, and it is currently untested against reality by construction (no test data exists), not by oversight. |
| G6 | Bulk/backfill path is manual and capped at 50 Queueable jobs per run | [2.md](research/2.md) §11, existing doc §6 | `quote-document-backfill.apex` requires re-running until it reports zero remaining | Operationally fine at current data volume; becomes friction at scale. Not urgent. |

Everything else the research raised — grouping-value sources for bundles, section totals vs. group nodes, detail-grain policy, stable non-label keys, `Parent_Row__c` semantics — is already correctly implemented per the architecture doc and does not need rework.

---

## 4. Execution plan

Ordered by consequence, not by effort, with one exception: Phase 0 goes first because it's about what ships in v1, not what's fixed after.

### Phase 0 — Ship the commonly-requested table types, not just the ones already built

**Atomic doc:** [`phases/phase-0-common-table-types.md`](phases/phase-0-common-table-types.md) — **Status: DONE** — deployed and verified live against a real org on 2026-08-03

The ten shipped table definitions grew out of this project's own history, not a survey of what quote/order documents typically contain. Before calling v1 done, it's worth checking the shipped set against what's actually common, so launch doesn't miss an obvious request on day one. Two searches against Salesforce's own CPQ/DocuSign documentation and general order-form conventions confirm the standard shape of a quote/order document: header/identification, an itemized line table, subtotal/discount/tax/grand-total, payment terms, terms & conditions, and a validity/signature block — and specifically call out **multi-year subscriptions with price varying by year** as "the most common example" of Salesforce's own "Complex Tables" concept. ([Docusign](https://www.docusign.com/blog/document-generation-sales-quotes-and-contracts), [Salesforce Geek](https://salesforcegeek.in/document-generation-in-salesforce-cpq/), [Salesforce Help — CPQ Quote Document Management](https://help.salesforce.com/s/articleView?id=sales.cpq_quote_document_overview.htm&language=en_US&type=5))

Mapped against the A/B/C boundary from §2:

| Common request | Coverage today | Action before launch |
|---|---|---|
| Itemized line detail | **A** — shipped (`PRODUCT_SUMMARY`, ungrouped tables supported natively) | None |
| Subtotal by product family / category | **A** — shipped (`PRODUCT_FAMILY_SUMMARY`) | None |
| Recurring vs. one-time breakdown | **A** — shipped (`CHARGE_TYPE_SUMMARY`) | None |
| Bundle/option hierarchy detail | **A** — shipped (`BUNDLE_DETAIL`, `BUNDLE_PRODUCT_GRID`, `BUNDLE_SUMMARY`) | None |
| Optional products called out separately | **A** — shipped (`OPTIONAL_PRODUCTS`) | None |
| Grand total / final contract value | **A** — every table's Grand Total row; `Amount_Basis__c` already has a `Final Value` option | None |
| **Discount summary** (list vs. net, discount amount) | **A but not shipped** — the price-waterfall measure family already carries `Amount_List__c`/`Amount_Discount__c`/`Amount_Net__c` on every row; there's just no table definition presenting them as their own view | **Build now — zero Apex.** Add an 11th `Quote_Document_Table_Def__mdt` record (`DISCOUNT_SUMMARY`, `PRICE_WATERFALL`, grouped by `PRODUCT_FAMILY` or ungrouped) plus its guide, following the existing six-guide pattern. This is the one gap in the "obviously common, currently missing" category that costs nothing to close. |
| Amendment/change summary | **A config-wise, gated by G5** — shipped (`TRANSACTION_SUMMARY`) but sits behind Phase 1's classification validation | Ship the config; don't rely on it for real amendment quotes until Phase 1 closes |
| Payment terms, T&Cs, validity/signature block | **Out of scope, correctly** — this is static contract language and acceptance workflow, not a computed summary of Quote Line data | No action — confirm this expectation explicitly with whoever owns the DocuSign template, so nobody assumes this framework produces it |
| **Tax summary** | **Not evaluable yet** — no tax field exists anywhere in this org's CPQ line data model (`Tax__c` or equivalent doesn't appear on `SBQQ__QuoteLine__c` in this codebase) | **Discovery, not code.** Before treating this as a Category B gap, confirm whether this org uses Salesforce CPQ's tax calculation add-on or an external tax engine at all. If it does, tax becomes a straightforward new measure (Category B); if it doesn't, there's nothing to summarize and this drops off the list entirely. |
| **Multi-year / price-by-period breakdown** ("Year 1 / Year 2 / Year 3" columns, MDQ segments) | **Category C, currently out of scope** — no MDQ implementation exists anywhere in this codebase (`SBQQ__Segment*` fields, period dimensions — none found), and the schema's own "Known boundaries" note defers dynamic period *columns* specifically | **Flag, don't build yet, but stop calling it deferred-and-forgotten.** This is the one Category C item the research directly confirms is common rather than exotic. Recommend: confirm with the business whether multi-year quotes with per-year pricing are actually in this org's near-term roadmap. If yes, this becomes the real justification for the `DetailPolicy`/period-dimension work that [2.md](research/2.md) explicitly deferred — worth its own follow-up spec rather than folding into Phase 5, since it's a document-column concept (period as column) that the current row-based model doesn't have a slot for at all, not just a missing dimension. |

Four more came up directly in conversation — subscriptions, contracts, drawdowns, standard revenue classification. Checked against the codebase and against how these terms are actually used in CPQ/SaaS practice:

| Common request | Coverage today | Action before launch |
|---|---|---|
| **Subscriptions** (term length, start/end date, renewal date, annualized value) | **Not captured at all.** `QuoteDocumentLine` normalizes product, family, charge type, bundle context and the two measure families — no subscription term, start date, end date, or renewal date property exists anywhere in the class | **Category B/C, not zero-cost.** A Subscription Summary (e.g., "renewals due next 90 days," ARR by subscription) needs new snapshot properties (`subscriptionStartDate`, `subscriptionEndDate`, `subscriptionTerm`) sourced from CPQ's own subscription fields, plus possibly a new annualization measure. Real but bounded — a few new properties and one new dimension/measure, not a redesign. Worth its own small spec once someone confirms which subscription fields this org actually populates. |
| **Contracts** | **Out of scope by architecture, not by oversight.** Every object in this framework keys off one Quote (`Table_Key__c = QuoteId:TableCode`). Salesforce CPQ Contracts are a downstream object (Quote → Order → Contract) this framework never queries | **Category C, and arguably a different framework.** A "Contract Summary" spanning a Contract's amendment history (multiple quotes over time) needs a different root and a different key (`ContractId:...`, not `QuoteId:...`). Don't fold this into the existing object model — if it's needed, it's a sibling framework that reuses the same design patterns (Table/Row, `Row_Type__c`, CMDT-driven definitions), not an extension of `Quote_Document_Table__c`. |
| **Drawdowns** (prepaid credit balance consumed over time, committed-spend/usage overage) | **Not this framework's job, on architectural grounds.** A drawdown is a running balance against consumption events (credits purchased minus credits used, checked against a commit), not a sum of Quote Line amounts. Confirmed against how CPQ/billing platforms actually model this: it's a balance-and-ledger problem, typically owned by a billing/usage-metering system, not the quoting layer. ([Zuora — minimum commitment](https://docs.zuora.com/en/zuora-billing/bill-your-customer/usage-billing/minimum-commitment), [Metronome — enterprise commit contracts](https://metronome.com/blog/a-practical-guide-to-enterprise-commit-contracts)) | **No action unless this org actually sells prepaid/committed-spend deals.** If it does, this needs its own data source (a consumption/balance object, likely from Salesforce Billing or an external usage-metering system) and its own spec — grafting a running balance onto a stateless "regenerate from Quote Lines" model would break the one rule this whole framework depends on (§1: generated data is a disposable, rebuildable projection; a balance is the opposite of that). |
| **Standard revenue classification** (New / Expansion / Renewal / Contraction / Churn — the six-category ARR taxonomy SaaS finance teams actually use) | **Partially covered, and not by the standard names.** `classify()` currently produces *Net New, Cancellation, Replacement Removed, Replacement Added, Termination* — five categories that overlap the industry-standard six (New, Expansion, Renewal, Contraction, Churn, Resurrected) but don't map cleanly onto them. Notably: there's no distinct **Renewal** bucket — a line with `SBQQ__RenewedSubscription__c` populated currently falls into Replacement Added/Removed instead of being labeled Renewal; there's no **Expansion vs. new-customer New Business** distinction; there's no **Resurrected** category at all. ([SaaS revenue hierarchy — six ARR categories](https://www.thesaascfo.com/the-saas-revenue-hierarchy-why-defining-your-revenue-streams-matter/)) | **Fold into Phase 1, don't schedule separately.** `classify()` is already gated by G5 (provisional, unvalidated against real amendment data). Deciding whether to adopt the standard six-category taxonomy is the same conversation as validating the existing five branches against a real amendment quote — doing it twice (validate current logic now, redefine categories later) means touching the same method and the same tests twice for one decision. Add "confirm whether finance expects the standard ARR taxonomy, and if so remap the branches" as an explicit sub-step of Phase 1 below. |

**Net effect on scope:** one new CMDT record (Discount Summary) ships before launch at zero engineering cost. Tax and subscription fields get a discovery check before any code is written. Contracts and drawdowns are named explicitly as *not this framework* rather than silently unsupported, so nobody assumes they're covered. Multi-year/period columns and the revenue-classification taxonomy both get folded into existing gates (a follow-up spec decision, and Phase 1, respectively) instead of becoming new untracked scope.

### Phase 1 — Close the one gap that can produce a wrong signed document (G5)

**Atomic doc:** [`phases/phase-1-classification-validation.md`](phases/phase-1-classification-validation.md) — **Status: BLOCKED** (taxonomy decision made and recorded; `classify()` change deliberately not applied without org access to validate — see the doc's §10)

**Goal:** validate `classify()` against a real amendment/renewal quote before this framework is used on one, per the existing doc's own explicit warning in §3.

1. **Before building test data:** confirm with finance/RevOps whether `TRANSACTION_SUMMARY` needs to speak the standard six-category ARR taxonomy (New, Expansion, Renewal, Contraction, Churn, Resurrected) instead of the current five branches. This is a business-definition question, not a technical one — answer it once, here, rather than validating the current branches now and re-deriving them later when someone asks "why doesn't this say Expansion."
2. Build one amendment quote in a sandbox by hand (upgrade a subscription, cancel a line to zero quantity, terminate a line with a negative net change, and — if step 1 says yes — a renewal at the same value and an upsell on an existing line) — a scratch-org script, added as a new step to `scripts/scratch-org-bootstrap.sh` per the doc's standing rule of one shared bootstrap script.
3. Run `QuoteDocumentGenerator.generate` against it and manually verify every `classify()` branch (five, or the remapped six from step 1) produces the expected `Transaction_Type__c` and signed measure.
4. Add the confirmed scenario as a permanent fixture in `QuoteDocumentGeneratorTest`, asserting each branch by name (mirrors the existing `grandTotalReconcilesToTheQuoteNetAmount` pattern).
5. Update `docs/quote-document-totals.md` §3 to change "PROVISIONAL, has never been validated" to a dated verification note, recording exactly which branch turned out wrong, what changed, and whichever taxonomy was adopted.
6. **Do not** touch `TRANSACTION_SUMMARY` or any table consuming `classify()` until this step passes — that's the whole point of the gate.

**Acceptance:** a real amendment quote in the org, `TRANSACTION_SUMMARY` generated from it, five branches each hit by at least one line, numbers hand-checked against the quote.

### Phase 2 — Concurrency safety for generation (G1)

**Atomic doc:** [`phases/phase-2-concurrency-lock.md`](phases/phase-2-concurrency-lock.md) — **Status: DONE** — `FOR UPDATE` applied and verified live; caught and fixed a real bug in the process (`ORDER BY` isn't allowed with `FOR UPDATE`)

**Goal:** make double-generation safe before it becomes load-bearing (i.e., before Phase 4 platform-event work ships).

1. Add `FOR UPDATE` to the quote query at the top of `QuoteDocumentGenerator.generateOne` — mirrors [2.md](research/2.md) §12 exactly: `SELECT Id, ... FROM SBQQ__Quote__c WHERE Id IN :quoteIds ORDER BY Id FOR UPDATE`.
2. Add a test that fires two generation calls for the same quote id in quick succession (same transaction, sequential calls is sufficient — Apex tests can't truly race, so this test documents intent and catches a regression in lock scope, not the race itself) and asserts the second call sees the first call's committed row count.
3. No schema change required — this is a one-line query change plus a test.

**Acceptance:** `FOR UPDATE` present in the generator query; new test passing; existing test suite green.

### Phase 3 — Name the atomicity guarantee explicitly (G3)

**Atomic doc:** [`phases/phase-3-atomicity-test.md`](phases/phase-3-atomicity-test.md) — **Status: DONE** — verified live: the atomicity guarantee **holds**. Phase 5's first trigger condition is now permanently resolved (did not fire).

**Goal:** turn an implied guarantee into an asserted one.

1. Add a test: seed a quote with two table definitions, force the second table's build to throw partway through `generateOne` (a test-only override hook, similar to the existing `useDefinitions` test hook), and assert that after the failure, **the previous complete tables for that quote are unchanged** — not partially replaced, not deleted.
2. If the test reveals the guarantee doesn't actually hold today, this becomes the trigger for `Generation_Key__c`/`Is_Current__c` from [1.md](research/1.md) — see Phase 5. Don't build that speculatively; let this test tell you whether you need it.

**Acceptance:** named test exists (`aFailedGenerationLeavesThePreviousCompleteTablesUntouched` or similar) and passes against the current delete-and-reinsert design, or a documented decision to move to generation-key versioning if it doesn't.

### Phase 4 — Test matrix reconciliation (G4)

**Atomic doc:** [`phases/phase-4-test-matrix-reconciliation.md`](phases/phase-4-test-matrix-reconciliation.md) — **Status: DONE** — flagship fix (`Row_Key__c` had no uniqueness enforcement at all) deployed and verified live; all follow-up tests added; org-wide Apex coverage raised to 98%

**Goal:** be able to state "every scenario in research's test matrix has a named test" as a checked fact, not an impression.

1. Walk [2.md](research/2.md) §14 row by row against `QuoteDocumentGeneratorTest.cls` and `QuoteDocumentLifecycleTest.cls`. For each row, record: test name if it exists, or "missing" if it doesn't.
2. File the missing ones as new tests. Expect most of the list to already be covered given the doc's existing verification-assertion coverage (§4 "the four assertions") — this phase is about proving it, and filling the handful that are genuinely absent (likely: group path >255 chars / stable hashing, duplicate platform events — moot until Phase 6, blank dimension fallback to `Not Specified`).
3. Publish the reconciled table as a short appendix to this spec (not a new file, per the single-`.md`-deliverable standard) once done.

**Acceptance:** every row in the appendix has a test name attached; `sf apex run test --class-names QuoteDocumentGeneratorTest --class-names QuoteDocumentLifecycleTest` green.

### Phase 5 — Historical reproducibility (G2) — build only if Phase 3 proves you need it

**Atomic doc:** [`phases/phase-5-generation-versioning.md`](phases/phase-5-generation-versioning.md) — **Status: NOT SCHEDULED** (intentional — gated on Phase 3's result)

**Goal:** don't build this speculatively. [1.md](research/1.md) itself frames this as conditional: "acceptable when the signed PDF in CLM is the only required historical artifact."

1. Trigger condition: either (a) Phase 3's atomicity test fails against the current design, or (b) a real business requirement surfaces to query a past generation's numbers from Salesforce data rather than the signed PDF.
2. If triggered: add `Generation_Key__c` and `Is_Current__c` to `Quote_Document_Table__c` exactly as specified in [1.md](research/1.md) — change the table key from `QuoteId:TableCode` to `QuoteId:GenerationKey:TableCode`, generate a full new set with `Is_Current__c = false`, validate, then flip current/non-current in one final transaction.
3. Extend `QuoteDocumentRetention` to purge non-current generations on the existing retention schedule, leaving the current generation subject to the existing Accepted-quote protection.

**Acceptance:** not scheduled — this phase stays a documented option until its trigger condition fires.

### Phase 6 — Automatic generation via platform event — build only when manual generation becomes the actual friction

**Atomic doc:** [`phases/phase-6-automatic-generation.md`](phases/phase-6-automatic-generation.md) — **Status: NOT SCHEDULED** (intentional — hard-gated on Phase 1 AND Phase 2 both closing)

**Goal:** the doc's own §4 "If you later want fully automatic generation" section already specifies this correctly; this phase is just sequencing it after Phases 1–2 so the concurrency and classification gates are closed first.

1. Prerequisite: Phase 1 (classification proven) and Phase 2 (`FOR UPDATE` in place) must both be done first — automatic generation is exactly the scenario that turns G1 from theoretical into real.
2. Add `Quote_Document_Refresh_Requested__e`, published by `QuoteDocumentStaleness` instead of (or alongside) the current stale-marking.
3. Subscribe with a trigger that enqueues `new QuoteDocumentGenerateJob(quoteId)` — the existing one-argument, skip-unless-stale constructor already provides the debounce; no new debounce logic needed.
4. Configure the subscriber batch size deliberately small (1–5 quotes) per [2.md](research/2.md) §10, measure actual row/CPU volume on a real quote, increase only if justified.
5. Keep the manual "Generate Document Tables" action working alongside the automatic path — don't remove the escape hatch.

**Acceptance:** not scheduled — build when manual generation is confirmed to be the actual operational bottleneck, not before.

### Phase 7 — Bulk backfill ergonomics (G6) — low priority

**Atomic doc:** [`phases/phase-7-bulk-backfill-ergonomics.md`](phases/phase-7-bulk-backfill-ergonomics.md) — **Status: NOT SCHEDULED** (intentional — lowest priority, no evidence of the trigger condition)

1. If backfill volume grows past a few hundred quotes, consider chunking `quote-document-backfill.apex` to auto-requeue itself (schedule a follow-up Queueable when it hits the 50-job cap) instead of requiring manual re-runs.
2. Not urgent; revisit only if backfill becomes a recurring operational task rather than a one-time migration step.

### Phase 8 — Rule-driven table eligibility — new scope, not from the original research

**Atomic doc:** [`phases/phase-8-dynamic-table-eligibility.md`](phases/phase-8-dynamic-table-eligibility.md) — **Status: PLANNED** (blocked only on a short field-discovery step, not on any other phase)

**Goal:** stop generating every active `Quote_Document_Table_Def__mdt` for every quote (current, documented behavior — see §7 above, "Definition count") and instead compute per-quote eligibility from declarative rules, so a Recurring-only table doesn't show up on a One-Time quote, and an Opportunity- or Account-specific addendum table only appears where it applies.

1. New child metadata type, `Quote_Document_Table_Rule__mdt`, mirrors the existing `Quote_Document_Grouping__mdt` pattern: `Dimension__c` + `Value__c` rows attached to a definition, grouped by `Group__c` (AND within a group, OR across groups), zero rows = always eligible.
2. A new eligibility resolver filters `QuoteDocumentTableDefinition.getAll()` down to the eligible subset for a given quote, computed fresh every generation — no new field or stored selection on the Quote itself. Slots in as a filter ahead of `QuoteDocumentGenerator.generateOne`'s existing per-definition loop; the loop itself, the savepoint, and the atomicity guarantee from Phase 2/3 are unchanged.
3. Requires one discovery step before rule data can be authored: confirming which real fields represent Quote Type, Opportunity Type, and Account Type in this org — same shape as Phase 0's tax/subscription-field discovery items, deliberately not assumed.

**Not scheduled speculatively as a stored per-quote override** — the atomic doc records that a Quote-side multi-select (letting a rep manually add/remove tables) was considered and deliberately deferred; add it only if a real request surfaces, per this spec's own standing bias against building ahead of proven need (§5).

---

## 5. Explicit non-goals

Carried forward from [3.md](research/3.md) and [4.md](research/4.md), which both argued against over-building — these stay out even after the phases above:

- No `GroupingDimension`/`MeasureSet`/interface-per-permutation framework. The `switch`-based `QuoteDocumentLine` + CMDT combination already does the job with less code to maintain.
- No generic multi-value/allocation grouping (a line belonging to two groups). [2.md](research/2.md) §6A explicitly rules this out for v1; nothing since has created a need for it.
- No `Map<String, Decimal>` measure store. Explicit properties on `QuoteDocumentLine`/`Measures` stay — the compile-time safety argument in the existing doc §2 (why measures are properties, not a map) still holds.
- No second bootstrap script, no second guide-authoring standard, no CMDT-driven table definitions replaced by Apex or vice versa — the current split is correct per research/4.md's own stated test ("can one generic generator produce every table differing only by config?" — yes, so config stays).

---

## 6. Definition of done for "robust"

This framework is robust, in the sense the research conversations were actually asking about, when:

1. Every measure on a signed document ties back to `SBQQ__NetAmount__c` (or the relevant CPQ total) via an automated assertion that runs on every generation and blocks publication on failure — **already true today**.
2. The one classification path capable of putting a wrong number on a signed document has been validated against real data, not just unit tests — **Phase 1, not yet true**.
3. Concurrent generation requests for the same quote cannot interleave into an inconsistent result — **Phase 2, not yet true**.
4. A failed generation is provably inert — it changes nothing about the last good state — **Phase 3, asserted but not yet proven by a named test**.
5. Every scenario the original design review worried about has a named, passing test someone can point to — **Phase 4, believed true, not yet reconciled**.

Phases 5 and 6 are explicitly optional scale/automation work, gated on real triggers rather than speculative completeness — building them before their trigger condition fires would be the same mistake [3.md](research/3.md) already called out once in this project's history.
