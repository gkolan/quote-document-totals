# Worked examples — end to end

**Status: BUILT 2026-08-28 — three examples asserted number-for-number, one by mechanism.** This began as a specification written before any of it existed. The tables below are unchanged from what was specified in advance, which is the point of having written them first.

| Example | Test | Asserted |
|---|---|---|
| 1. Payment installments | `QuoteDocumentScheduleTest.anInstallmentScheduleSplitsTheQuoteToTheCent` | **These exact figures** — \$60,000 at 30/40/30 → 18,000 / 24,000 / 18,000 |
| 2. Department allocation | `QuoteDocumentScheduleTest.aDepartmentScheduleDividesQuantitiesWhenToldTo` | **Mechanism only** — the 50/30/20 split and the quantity division, on a \$60,000 quote. The \$120,000 figures below have *not* been asserted |
| 3. Promotional pricing | `QuoteDocumentScheduleTest.aFreePeriodPrintsExactlyZeroAndNeverTheResidual` | **These exact figures**, rescaled to the \$60,000 fixture: free months at exactly 0.00, half-rate and full-rate months, total unchanged |
| 4. One-time versus recurring | `QuoteDocumentExpansionTest.aOneTimeChargeLandsInOnePeriodOnly` and `.spreadingAOneTimeChargeIsAvailableButMustBeChosen` | **These exact figures** — the fee in period 1 only at 5,000.00, and both placements totalling the same |

Two deviations worth recording:

- Examples 1 and 2 were specified as needing subscriber expanders (`SCHEDULE_MILESTONE`, `ALLOCATION_TARGET`). Both are served by the one shipped `SCHEDULE` expander instead — the difference between a milestone and a department turned out to be `Schedule_Divides_Quantity__c` and nothing else. The configuration tables below still name the original expanders; read them as "a schedule whose buckets are milestones / departments".
- `Allocation_Basis__c` values `SCHEDULE` and `WEIGHTED_SOURCE` were never implemented as separate constants. The **weights** carry the shape, so `EVEN` over weighted placements *is* the weighted allocation; a second constant would have been a second name for the same arithmetic. Read `Allocation_Basis__c = EVEN` wherever the tables below say `SCHEDULE` or `WEIGHTED_SOURCE`.

**Companion to:** [step 01](step-01-expansion-contract.md), [step 02](step-02-allocation-primitive.md), [step 03](step-03-non-additive-measures.md)

---

## Why this file exists

Steps 01–03 define capabilities. A capability is not a document. These four cases are the ones [`spec.md`](../spec.md) §3.1 marks *delivered by a planned step* rather than *enabled* — which means this series ships a working table for each, so each needs its configuration and its expected output written down before the code, not inferred from it afterwards.

Every example states: the quote, the configuration, the exact expected rows, and the check that fails if the implementation drifts. Amounts are chosen so the arithmetic can be verified by hand.

---

## 1. Payment installments

**Quote:** one \$60,000 implementation service line. Term irrelevant — this table is not time-based.

**Terms:** 30% at signing, 40% at delivery, 30% at acceptance.

**Configuration**

| Setting | Value |
|---|---|
| `Expander_Code__c` | `SCHEDULE_MILESTONE` (subscriber-supplied; the buckets are the three milestones) |
| `Allocation_Basis__c` | `SCHEDULE` |
| Placement weights | 30, 40, 30 — every line placed in all three buckets |
| `Allocation_Behaviour__c` on `Quantity__c` | `NONE` — a milestone has no quantity |
| Grouping | `EXPANSION` (one level) |
| `Show_Details__c` | false — the milestone *is* the row |

**Expected rows**

| Display order | Row type | Label key / args | `Amount_Net__c` |
|---|---|---|---|
| 10 | Subtotal | `MILESTONE_LABEL` / Signing | 18,000.00 |
| 20 | Subtotal | `MILESTONE_LABEL` / Delivery | 24,000.00 |
| 30 | Subtotal | `MILESTONE_LABEL` / Acceptance | 18,000.00 |
| 40 | Grand Total | `GRAND_TOTAL` | 60,000.00 |

**Checks**

- Grand total equals the quote's `SBQQ__NetAmount__c` exactly.
- Source check ([step 02](step-02-allocation-primitive.md) §3.6): the service line's three shares sum to 60,000.00 at zero tolerance.
- `Quantity__c` is blank on every row, not zero — blank says "not applicable"; zero says "none", and a customer reads them differently.
- **Milestone dates, if present, are labels.** No row's presence or amount depends on a date having passed. This table is the agreed schedule; nothing in it changes when money arrives.

**Ugly case that must be specified, not discovered:** weights that do not sum to 100 (say 30/40/25). They are relative ([step 02](step-02-allocation-primitive.md) §3.1), so the split is 18,947.37 / 25,263.16 / 15,789.47 and still totals 60,000. If an author meant them as percentages, that silently reallocates the quote. So a `SCHEDULE` whose weights sum to neither 1 nor 100 **warns in the generation log and still generates** — failing would break the legitimate relative-weight case, and silence would hide a typo.

---

## 2. Department allocation

**Quote:** one \$120,000 subscription line. Allocation: HQ 50%, West 30%, East 20%.

**Configuration**

| Setting | Value |
|---|---|
| `Expander_Code__c` | `ALLOCATION_TARGET` (subscriber-supplied; buckets are the departments, weights from the allocation records) |
| `Allocation_Basis__c` | `WEIGHTED_SOURCE` |
| `Allocation_Weight_Source__c` | the allocation record's percentage field |
| `Quantity__c` behaviour | `ALLOCATE`, scale 0 — a department's share of seats is a real count of seats |
| Grouping | `EXPANSION > PRODUCT_FAMILY` |
| `Cross_Partition_Total__c` | n/a here — this is one table. Use [step 05](step-05-partitioning.md) with `SUM` only when each department needs its own document. |

**Expected rows** (one product, so one detail per department)

| Display order | Row type | Group | `Amount_Net__c` |
|---|---|---|---|
| 10 | Group Header | HQ | — |
| 20 | Detail | HQ | 60,000.00 |
| 30 | Subtotal | HQ | 60,000.00 |
| 40 | Group Header | West | — |
| 50 | Detail | West | 36,000.00 |
| 60 | Subtotal | West | 36,000.00 |
| 70 | Group Header | East | — |
| 80 | Detail | East | 24,000.00 |
| 90 | Subtotal | East | 24,000.00 |
| 100 | Grand Total | | 120,000.00 |

**Checks**

- Source check: the line's three shares sum to 120,000.00 exactly.
- A line with **no** allocation records fails with `ALLOCATION_WEIGHTS_INVALID` rather than landing in a default department. An unallocated cost is a data error, and inventing a home for it is how one department gets billed for another's software.
- Allocations summing to 90% still produce a grand total of 120,000 — weights are relative. The guide must say so, because "the percentages must add to 100" is what every reader will assume.

---

## 3. Promotional pricing

**Quote:** one 12-month subscription, \$1,200 net. Months 1–2 free, months 3–6 at half rate, months 7–12 at full rate.

**The rule that must be stated:** the *quote* already prices this — \$1,200 is what the customer pays. This table explains the shape of the schedule; it must not re-derive the price. If the schedule's weights disagree with the quoted total, the **total wins** and the weights are the thing that is wrong.

**Configuration**

| Setting | Value |
|---|---|
| `Expander_Code__c` | `PERIOD`, `Period_Months__c = 1` |
| `Allocation_Basis__c` | `SCHEDULE` |
| Placement weights | months 1–2: `0`; months 3–6: `1`; months 7–12: `2` — relative, giving 0/0/x4/x8 |
| `Quantity__c` behaviour | `REPEAT` — the licenses are active in the free months too |
| `Quantity__c` grand-total rule | `SUM_THEN_MAX` ([step 03](step-03-non-additive-measures.md)) |

Weight total = (4 × 1) + (6 × 2) = 16. Half-rate month = 1,200 / 16 = 75.00. Full-rate month = 150.00.

**Expected rows** (subtotals only)

| Month | `Amount_Net__c` | `Quantity__c` |
|---|---|---|
| 1 | 0.00 | 10 |
| 2 | 0.00 | 10 |
| 3–6 | 75.00 each | 10 |
| 7–12 | 150.00 each | 10 |
| Grand Total | 1,200.00 | 10 |

**Checks**

- A free month is exactly `0.00` and is **printed**, not omitted. A missing month reads as a gap in service.
- The zero months never receive the rounding residual ([step 02](step-02-allocation-primitive.md) §3.1) — a free month showing \$0.01 is the defect this rule exists to prevent.
- Grand total quantity is 10, not 120.
- The `MONTHLY_ALLOCATION_NOTE` narrative, or a promotional equivalent, is present: a customer seeing \$0.00 must be told it is a promotional period and not an error.

---

## 4. One-time versus recurring

**Quote:** 12-month term. A \$12,000 subscription and a \$5,000 one-time implementation fee.

**The rule** ([step 01](step-01-expansion-contract.md) §3.3a): a one-time charge occupies **one** period, not all of them. `Period_One_Time_Placement__c = FIRST_PERIOD`.

**Expected rows** (subtotals)

| Month | `Amount_Net__c` | Composition |
|---|---|---|
| 1 | 6,000.00 | 1,000 subscription + 5,000 one-time |
| 2–12 | 1,000.00 each | subscription only |
| Grand Total | 17,000.00 | |

**Checks**

- The implementation fee appears in exactly one month's detail rows, and in no other month.
- Grand total = 17,000.00 = the quote's net amount.
- Switching to `SPREAD` produces 1,416.67 in each month (with the residual in month 12) and a grand total still of 17,000.00 — the same money, a different and **explicitly chosen** shape.
- With no explicit setting, the behaviour is `FIRST_PERIOD`. A guide for any table using `SPREAD` must state why the charge genuinely spreads, because the default assumption — a one-time fee is incurred once — is the safer one.

---

## Cross-cutting checks for all four

- [ ] Every expected-row table above exists as a test asserting amounts to the cent, in the step that ships it.
- [ ] Every table has a guide meeting [`docs/documentation-standards.md`](../../../docs/documentation-standards.md).
- [ ] No example relies on a default that is not written down here.
- [ ] Each example's grand total is independently reconcilable against the quote by hand, from the numbers printed in the document alone.
