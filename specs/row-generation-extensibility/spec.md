# Row generation extensibility — spec

**Status of this file:** planning spec and index. Nothing here is built except what §2 lists as already deployed. It does not re-describe the architecture — [`docs/quote-document-totals.md`](../../docs/quote-document-totals.md) is the source of truth for that, and [`specs/vendor-neutral-render-contract/spec.md`](../vendor-neutral-render-contract/spec.md) owns everything downstream of the snapshot. This spec owns only the stage **before** the snapshot: how the rows get produced.

---

## 1. The gap, in one paragraph

Every declarative table shape in this framework **groups**: one `SBQQ__QuoteLine__c` becomes exactly one `Detail` row, in exactly one bucket, carrying its own amounts. `Quote_Document_Grouping__mdt` cannot express anything else. But a large class of real quote documents needs one source line to become *several* calculated rows — one per month, per milestone, per department, per delivery, per pricing tier — with money split among them; or needs rows derived from *comparing* two sources; or needs a measure that is not a sum. Those documents are not "another grouping configuration"; they need calculation the framework does not have.

**The design position:** keep grouping, ordering, verification, snapshotting and rendering exactly as they are, and make the stage that *produces the rows* extensible along five axes.

| Capability | What it does | Step |
|---|---|---|
| **Expand** | One source line becomes N rows along a declared dimension | [01](steps/step-01-expansion-contract.md) |
| **Allocate** | Money or quantity split among rows, reconciling to the source to the cent | [02](steps/step-02-allocation-primitive.md) |
| **Aggregate non-additively** | A measure that must be a ratio, a max, or a last value rather than a sum | [03](steps/step-03-non-additive-measures.md) |
| **Compare / enrich** | Rows derived from two record sets, or from data outside the quote | [04](steps/step-04-comparison-and-enrichment.md) |
| **Partition** | Independently totalled tables or separate documents from one quote | [05](steps/step-05-partitioning.md) |

Nothing here adds a second contribution framework. Every capability lands on the seam the framework already has — `QuoteDocumentRowCustomizer`, extended in [step 01A of the render contract](../vendor-neutral-render-contract/steps/step-01a-extension-contracts.md) — or on the declarative config that feeds it.

---

## 2. What already exists — do not rebuild it

Verified against deployed code on 2026-08-28.

| Already there | Where | Consequence for this spec |
|---|---|---|
| **A working expansion**: one line → one row per month, even allocation of money, cent-exact residual, unconditional `Note` row | [`QuoteDocumentMonthlyRowCustomizer`](../../force-app/main/default/classes/QuoteDocumentMonthlyRowCustomizer.cls) | Expansion is *proven*, not *general*. It discards `QuoteDocumentRowBuilder`'s rows entirely and rebuilds them. Step 01 generalizes that shape; it does not invent it. |
| Reconciliation that catches a lost penny | [`QuoteDocumentVerification`](../../force-app/main/default/classes/QuoteDocumentVerification.cls) — leaf rows are everything outside `AGGREGATE_ROW_TYPES` carrying `Include_In_Grand_Total__c` | Every capability here is checked by machinery that already exists. An allocation that does not reconcile fails generation. This is the biggest single reason not to build a parallel pipeline. |
| Row types that exist only through the seam: `Informational`, `Discount`, `Rounding`, `Note` | `Row_Type__c` picklist | New capabilities need **no** new row types except where a step says so and justifies it. |
| Contributor content-identity versioning, `Cache_Policy__c`, `Contributor_Dependency_Set__c` | [`QuoteDocumentFingerprint`](../../force-app/main/default/classes/QuoteDocumentFingerprint.cls) §116–147 | Enrichment from outside the quote (step 04) already has its staleness answer. Do not invent a second one. |
| Code→class registry, no `Type.forName` | [`QuoteDocumentRowCustomizerRegistry`](../../force-app/main/default/classes/QuoteDocumentRowCustomizerRegistry.cls) | Everything new registers here. A rename becomes a compile error, not a runtime failure. |
| Columns, labels, locale, narrative blocks | render contract steps 02–04 | No printable string is constructed in any class this spec adds. Semantic key plus args, always. |

---

## 3. Use-case traceability

Every use case raised in the analysis, mapped to the capability that carries it. A use case is absent from this table only if it is already just a grouping configuration.

| # | Use case | Capabilities | Step |
|---|---|---|---|
| 1 | Monthly subscription breakdown | Expand + Allocate | **built** (§2) |
| 2 | Multi-year pricing / phased rollout | Expand (period) + Allocate | 01, 02 |
| 3 | Payment installments and milestones | Allocate (rule-driven, no line-derived source) | 02 |
| 4 | Cost allocation across locations / departments | Allocate (one line → many groups) | 02 |
| 5 | Before-and-after amendment comparison | Compare | 04 |
| 6 | Renewal / co-term schedules | Expand (period) + Enrich (renewal price source) | 01, 04 |
| 7 | Usage-tier explanation | Expand (tier) + Enrich (pricing engine result) | 01, 04 |
| 8 | Free periods and promotional pricing | Expand (period) + Allocate (schedule containing zeros) | 01, 02 |
| 9 | Prepaid vs recurring charges in one schedule | Expand (period) with a per-charge scheduling rule | 01 |
| 10 | Delivery schedules | Expand (event) + Allocate (quantity, not amount) | 01, 02 |
| 11 | Project phase breakdown | Allocate (phase weights) | 02 |
| 12 | Package composition allocation | Allocate (parent price → components) | 02 |
| 13 | Alternative proposals (Basic / Recommended / Premium) | Partition | 05 |
| 14 | Quote revision comparison | Compare (two snapshots) | 04 |
| 15 | Minimum commitment and shortfall | Enrich + non-additive measure | 03, 04 |
| 16 | Rebate / incentive illustration | Enrich + Partition (guaranteed vs contingent) | 04, 05 |
| 17 | Estimated consumption scenarios | Partition (scenarios) + Enrich | 04, 05 |
| 18 | Customer part-number mapping | Expand (mapping) + Allocate | 01, 02, 04 |
| 19 | Effective discount %, blended unit price, peak licenses, ending balance | Non-additive aggregation | 03 |
| 20 | Separate purchasing entities, one document each | Allocate + Partition (document-level) | 02, 05 §3.4 |

### 3.1 Coverage states — what "supported" actually means

A capability existing is not a use case working. Every use case carries one of four states, and the words are not interchangeable:

| State | Means |
|---|---|
| **Built and tested** | Deployed, with a named test asserting the documented output. |
| **Delivered by a planned step** | A step in this series ships it end to end, including its own configuration and test. |
| **Enabled, needs its own implementation** | The extension point exists; a subscriber still writes a class and authors metadata. This series does **not** deliver a working table. |
| **Deferred** | Not planned. |

| # | Use case | State | Evidence / owner |
|---|---|---|---|
| 1 | Monthly subscription breakdown | Built and tested — **with one defect**, §3.2 | `QuoteDocumentMonthlyRowCustomizerTest`, 17 tests |
| 2 | Multi-year / phased rollout | Delivered by a planned step | 01 (`PERIOD`, `Period_Months__c = 12`) + 02 (`EVEN`) |
| 3 | Payment installments and milestones | Delivered by a planned step | 02 §3.4 + [worked example](steps/worked-examples.md#1-payment-installments) |
| 4 | Department / location cost allocation | Delivered by a planned step | 02 (`WEIGHTED_SOURCE`) + [worked example](steps/worked-examples.md#2-department-allocation) |
| 5 | Amendment before/after | Delivered by a planned step | 04 (`AMENDED_SUBSCRIPTION`) |
| 6 | Renewal / co-term schedules | **Enabled, needs its own implementation** | 01 gives the axis; the renewal *price* is a supplied input with no shipped source |
| 7 | Usage-tier explanation | **Enabled, needs its own implementation** | 04 §3.7 defines the consumption rule; no tier source ships |
| 8 | Free periods / promotional pricing | Delivered by a planned step | 01 + 02 (`SCHEDULE`) + [worked example](steps/worked-examples.md#3-promotional-pricing) |
| 9 | Prepaid vs recurring in one schedule | Delivered by a planned step | 01 §3.3a occupancy rule + [worked example](steps/worked-examples.md#4-one-time-versus-recurring) |
| 10 | Delivery schedules | **Enabled, needs its own implementation** | Moved out of 01 — the event list is an enrichment source (04). The seam covers it; no expander ships. |
| 11 | Project phase breakdown | **Enabled, needs its own implementation** | 02's `WEIGHTED_SOURCE` covers the split; phase source is the subscriber's |
| 12 | Package composition | Delivered by a planned step | 02 §3.5 |
| 13 | Alternative proposals | Delivered by a planned step | 05 (`SCENARIO`) |
| 14 | Quote revision comparison | Delivered by a planned step | 04 (`PRIOR_SNAPSHOT`) |
| 15 | Minimum commitment / shortfall | **Enabled, needs its own implementation** | 03 gives the measure; the commitment value is a supplied input |
| 16 | Rebate / incentive illustration | **Enabled, needs its own implementation** | 04 + 05 give the mechanisms; the rebate rule is the subscriber's |
| 17 | Consumption scenarios | **Enabled, needs its own implementation** | 05 partitions and requires assumptions; the scenario inputs are supplied |
| 18 | Customer part-number mapping | **Enabled, needs its own implementation** | Mapping data is the subscriber's |
| 19 | Non-additive measures | Delivered by a planned step | 03 |
| 20 | Separate purchasing entities | Delivered by a planned step, if 05 §3.4 is built | 05 §3.4 is explicitly optional — see its close-out |

Eight of twenty are "enabled, needs its own implementation". That is the honest number and it must not drift upward in a close-out without a test to back the change.

### 3.2 Known defect, found while writing this spec

`QuoteDocumentMonthlyRowCustomizer` allocates **`Quantity__c` evenly across months**, because `Quantity__c` is in `measureFields(PRICE_WATERFALL)` and the customizer allocates every measure in the set. A 100-license line running twelve months prints **8.33 licenses in each month**. No test covers it. Licenses are not consumed by the month — the customer has 100 active in every month — so the number is wrong in a document a customer reads.

This is the concrete case behind [step 02](steps/step-02-allocation-primitive.md) §3.3: **allocation behaviour is per measure, not per table.** Fixed as the first build task of this series, ahead of the rest of step 02, because it is a defect in code that already exists rather than a feature that does not.

**Permanently out of scope:** live usage balances, invoice collection state, revenue recognition. The framework may *display* a supplied result for any of them — that is step 04's enrichment path — but must never own the calculation. Owning them changes what this product is.

---

## 4. Order, and why

Build **01 → 02 → 03 → 04 → 05**, and stop after any step that turns out to be enough.

- 01 and 02 carry 11 of the 19 use cases and sit the shortest distance from code already running in production.
- 03 is small and independent, but it is a *correctness* fix: a table that sums percentages is wrong today, silently. Pull it forward if such a table is authored before 02 lands.
- 04 is the largest, because "two record sets" raises questions 01–03 do not: what is the second source, how are records matched, what happens when the match is ambiguous.
- 05 is last because partitioning into separate *documents* touches the lifecycle — request Id, fingerprint, retention — and only earns that cost once several partitioned tables exist.

---

## 5. Rules every step inherits

Stated once here rather than repeated five times.

1. **Verification is never bypassed.** Rows from any capability pass through the same `verify()`. If a capability cannot reconcile, the capability is wrong, not the check.
2. **No English in Apex.** Labels are `Label_Key__c` plus `Label_Arg_1__c` / `Label_Arg_2__c`, resolved through `QuoteDocumentLabels`. No fallback string, ever.
3. **Every new configuration input enters the fingerprint.** A changed expansion dimension, allocation basis, or aggregation rule must move `Document_Data_Fingerprint__c`, or `canReuse` serves a stale snapshot. Each step names its fingerprint additions.
4. **Every new object and field lands in `CPQ_Document_Totals.permissionset-meta.xml` in the same commit.** This has bitten the project before.
5. **Failure is loud and coded.** Every new failure mode gets an error code in the catalogue in [`docs/quote-document-extension-recipes.md`](../../docs/quote-document-extension-recipes.md) — never a silent zero, a guess, or a dropped row.
6. **Money never appears twice.** A capability that puts one line's amount into more than one row must either make exactly one of them counted (`Include_In_Grand_Total__c`) or split the amount. There is no third option.
7. **Each step ships its own test class and is verifiable standalone.** A step is done when its acceptance list is checked *and* the pre-existing suite still passes untouched.
8. **A matching grand total is not proof of a correct allocation.** `QuoteDocumentVerification` reconciles table totals with `TOLERANCE = 0.01` — a cent of slack, and only at the aggregate. Two source lines allocated to each other's buckets reconcile perfectly and are completely wrong. Every allocating capability therefore carries a **source-by-source** check: for each source line, the sum of its allocated shares equals its own measure value **exactly, at zero tolerance**. See [step 02](steps/step-02-allocation-primitive.md) §3.7. Existing table-level tolerance is unchanged; the new check is additional and stricter, not a replacement.
9. **Non-additive measures are validated, not skipped.** [Step 03](steps/step-03-non-additive-measures.md) excuses a `RATIO`/`MAX`/`LAST` column from *sum* reconciliation, and must then check it against its own rule. An unchecked column is how a wrong number ships quietly.
10. **An interface carries everything its consumer needs, or it is the wrong interface.** Expansion and allocation are separate capabilities but one data flow: the expander decides which buckets a line occupies *and* with what relative weight, because nothing downstream can recover that. [Step 01](steps/step-01-expansion-contract.md) §3.1 defines the whole contract once, and step 02 consumes it rather than redefining it.

---

## 6. Steps

| Step | Title | Status |
|---|---|---|
| 00 | [Audit and capability boundaries](steps/step-00-audit-and-boundaries.md) | **BUILT** 2026-08-28 |
| 01 | [Expansion contract](steps/step-01-expansion-contract.md) | **BUILT** 2026-08-28 |
| 02 | [Allocation primitive](steps/step-02-allocation-primitive.md) | **PARTIAL** 2026-08-28 — primitive and per-measure rule shipped; `WEIGHTED_SOURCE` / `SCHEDULE` need a subscriber expander |
| 03 | [Non-additive measures](steps/step-03-non-additive-measures.md) | Planned |
| 04 | [Comparison and enrichment sources](steps/step-04-comparison-and-enrichment.md) | Planned |
| 05 | [Partitioning](steps/step-05-partitioning.md) | Planned |
| 06 | [Docs and close-out](steps/step-06-docs-and-closeout.md) | Planned |
| — | [Worked examples](steps/worked-examples.md) — end-to-end config and expected rows for the four cases that are configuration, not code | Planned |
