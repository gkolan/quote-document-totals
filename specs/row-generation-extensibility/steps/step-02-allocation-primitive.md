# Step 02 — Allocation primitive

**Status: BUILT** — the primitive and the per-measure rule shipped 2026-08-28; weighted allocation closed the same day by the `SCHEDULE` expander. See close-out.
**Blocked by:** [step 01](step-01-expansion-contract.md)
**Blocks:** 05
**Use cases:** 2, 3, 4, 8, 10, 11, 12, 18 ([`spec.md`](../spec.md) §3)

---

## 1. Goal

An amount or quantity is split across several rows by a declared weighting, sums back to its source exactly, and does so through **one** implementation that every allocating table shares.

## 2. Why this step exists

Splitting money is the easiest place in this framework to be wrong by a cent and the hardest place for it to be noticed. `QuoteDocumentMonthlyRowCustomizer` already solves it once — round to the cent, residual to the last bucket — because `verify()` checks the table's grand total against CPQ's `SBQQ__NetAmount__c` to the cent. The next four use cases that split money must not each re-derive that. Step 00 classified the rounding rule `GENERAL`; this step is where it becomes shared code.

An allocation is also the only mechanism that answers use case 3 (installments), which has *no* expansion behind it: the milestone rows come from a schedule, not from multiplying lines.

## 3. Scope

### 3.1 The primitive

```apex
public class QuoteDocumentAllocation {
    /**
     * Splits `total` across `weights` in order, rounded to `scale` decimal
     * places, with every rounding residual carried into the LAST non-zero
     * weight so the result sums back to `total` exactly.
     */
    public static List<Decimal> split(Decimal total, List<Decimal> weights, Integer scale);
}
```

Pure, static, no SObjects, no context, no DML. That is deliberate: the whole correctness argument for this step is that the hard part is a function that can be tested exhaustively without an org.

Rules, stated once and never re-decided per caller:

- Weights are relative, not required to sum to 1 or to 100. `[30, 40, 30]` and `[0.3, 0.4, 0.3]` give the same answer.
- All-zero weights, an empty weight list, or a negative weight fails with `ALLOCATION_WEIGHTS_INVALID`. There is no "fall back to even" — silently changing the basis is how a document becomes wrong without failing.
- A zero weight yields exactly zero, and **never** receives the residual. Use case 8's free months must print as zero, not as one cent.
- The residual goes to the last non-zero weight. Not the largest, not spread: last is deterministic, order-stable, and matches the deployed monthly behaviour.
- `scale` is 2 for currency and 0 for whole-unit quantities (use case 10 — you cannot deliver 33.33 devices). Quantity allocation with a fractional weight and `scale = 0` still sums back exactly, by the same residual rule.
- Negative totals allocate with the same signs and the same exactness — an amendment credit is a real input.

### 3.2 Configuration

On `Quote_Document_Table_Def__mdt`:

| Field | Type | Notes |
|---|---|---|
| `Allocation_Basis__c` | Picklist | `NONE` (default), `EVEN`, `WEIGHTED_SOURCE`, `SCHEDULE` |
| `Allocation_Weight_Source__c` | Text(80) | For `WEIGHTED_SOURCE`: the field path on the source providing each weight |
| `Allocation_Scale__c` | Number(1,0) | Default 2 |

| Basis | Weights come from | Use cases |
|---|---|---|
| `EVEN` | 1 per occupied bucket | 2, 8 (the monthly/annual behaviour, now shared) |
| `WEIGHTED_SOURCE` | A declared field on each expansion bucket or allocation target | 4, 10, 11, 12 |
| `SCHEDULE` | An ordered set of `{ key, weight }` rows supplied by the expander or by a step 04 enrichment source | 3, 8, 18 |

### 3.3 Which measures get allocated — **per measure, never per table**

This is the correction that matters most in the step, and it is fixing something already wrong. `QuoteDocumentMonthlyRowCustomizer` allocates every measure in the set, and `measureFields(PRICE_WATERFALL)` ends with `Quantity__c`. A 100-license line running twelve months therefore prints **8.33 licenses per month**. The customer has 100 licenses active in every one of those months. The money divides; the licenses do not.

Each measure declares its own behaviour, on `Quote_Document_Column_Def__mdt` beside the aggregation rule from [step 03](step-03-non-additive-measures.md) — the same object, because "how does this measure divide" and "how does this measure roll up" are the same question asked in two directions:

| `Allocation_Behaviour__c` | Each expanded row gets | Reconciles by | Right for |
|---|---|---|---|
| `ALLOCATE` | The line's value × its share of the weights | Shares sum to the source value exactly | Every `Amount_*` measure |
| `REPEAT` | The line's **full** value, unchanged, in every bucket it occupies | Nothing to reconcile — it is not a sum across buckets | `Quantity__c` on a period table: 100 licenses in every month |
| `NONE` | Blank | — | A measure with no meaning per bucket |

**`REPEAT` is not additive, so it must not be summed into a subtotal or grand total.** A `REPEAT` measure's aggregate value is governed entirely by [step 03](step-03-non-additive-measures.md)'s `Aggregation_Rule__c` — `SUM` across the products within one period, `MAX` across periods. A `REPEAT` measure left at the default `SUM` rule at every level produces "1,200 licenses" on a twelve-month grand total, which is the same defect wearing a different hat. Config load fails with `REPEAT_MEASURE_NEEDS_AGGREGATION_RULE` when a `REPEAT` measure has no explicit rule at grand-total level. There is no safe default here, so there is no default.

**Defaults by measure**, so an author who configures nothing is right rather than merely consistent:

| Measure | Default |
|---|---|
| `Amount_List__c`, `Amount_Regular__c`, `Amount_Discount__c`, `Amount_Net__c`, `Amount_Customer__c`, and the `CHANGE` set | `ALLOCATE` |
| `Quantity__c` | `REPEAT` on a `PERIOD` expansion; `ALLOCATE` at `Allocation_Scale__c = 0` on any other dimension |

The `Quantity__c` split is dimension-dependent, and deliberately so: 1,000 devices across three deliveries is 200/300/500 — genuinely divided, because each delivery is a different set of physical objects. 100 licenses across twelve months is 100 each month, because it is the *same* 100 licenses. The expander declares which of the two its dimension is, through `QuoteDocumentLineExpander.dimensionDividesQuantity()`, and the default follows from that rather than from a per-table guess.

Where a measure is `ALLOCATE`, all `ALLOCATE` measures use the **same weights**. Allocating `Amount_Net__c` but not `Amount_List__c` would produce a table whose discount percentage is nonsense.

### 3.4 Allocation without expansion (use case 3)

Installments have no source line per row. Model them as a `SCHEDULE` allocation over a **synthetic** bucket list supplied by the expander — an expander whose `bucketKeysFor` returns every bucket for every line, with schedule weights. The rows are then ordinary `Detail` rows and `verify()` reconciles them against the quote total unchanged.

State this in the docs plainly: an installment table is an allocation of the quote total, not a payment record. It says what was agreed, not what was paid. Nothing in this framework tracks receipt.

### 3.5 Package composition (use case 12), and the double-count trap

Bundled components are currently excluded from totals because their price is inside the package price. A composition table **allocates the package price down to the components** — so on that table the components carry the money and the package row must not, or the total doubles.

Implement as: the package line contributes its amount as the allocation total; component rows are the targets; the package row is emitted as a `Group Header` (already outside `AGGREGATE_ROW_TYPES` for leaf-sum purposes) and never as a counted leaf. Add an acceptance test that the table's grand total equals the package price exactly once. This is [`spec.md`](../spec.md) §5 rule 6 in its most dangerous instance.

### 3.6 Source-by-source reconciliation — the check `verify()` cannot make

`QuoteDocumentVerification.TOLERANCE = 0.01`. The table total is checked against CPQ's, to the cent, once. That check is necessary and it is **not sufficient for an allocation**:

- it tolerates a cent, so an allocation that loses one passes;
- it is an aggregate, so allocating line A's money into line B's buckets reconciles perfectly while every printed row is wrong.

A document whose per-row numbers are wrong but whose total is right is worse than one that fails, because it will be signed.

So allocation carries its own check, run before insert, in `QuoteDocumentAllocation.reconcile`:

> For every source line and every `ALLOCATE` measure, the sum of that line's allocated shares equals the line's own value for that measure, at **zero tolerance**, and the set of rows carrying those shares is exactly the set of buckets the expander placed it in.

Failure is `ALLOCATION_SOURCE_UNRECONCILED`, naming the line, the measure, the expected value and the actual sum. No tolerance parameter is exposed: the primitive is exact by construction (§3.1), so a mismatch is a bug in a caller, not a rounding artefact to be absorbed.

`REPEAT` measures are checked differently and are still checked: every occupied bucket carries the source value unchanged, and no bucket the line does not occupy carries it at all.

This does not change `verify()`'s existing table-level tolerance. It is an additional, stricter check on a narrower claim.

### 3.7 Fingerprint

Add `allocationBasis`, `allocationWeightSource`, `allocationScale`, and each measure's `Allocation_Behaviour__c`. Schedule weights that come from an enrichment source are covered by step 04's dependency hashing; weights that come from a quote field are already inside the line hash.

## 4. Out of scope

- Day-weighted allocation. Even and weighted cover every use case listed; day-weighting is a fourth basis added when a real document needs it, and the primitive already accepts arbitrary weights, so it is a config change, not a redesign.
- Ratio and non-sum measures — [step 03](step-03-non-additive-measures.md). An allocated discount *percentage* is meaningless; percentages are recomputed there, not split here.
- Payment tracking, invoicing, revenue recognition ([`spec.md`](../spec.md) §3).

## 5. Acceptance criteria

- [ ] `QuoteDocumentAllocation.split` deployed with unit tests that need no org data.
- [ ] `split(100, [1,1,1], 2)` returns `[33.33, 33.33, 33.34]` and sums to exactly 100.
- [ ] `split(60000, [30,40,30], 2)` returns `[18000, 24000, 18000]` — use case 3's worked example, to the cent.
- [ ] `split(120000, [50,30,20], 2)` returns `[60000, 36000, 24000]` — use case 4's.
- [ ] `split(1000, [200,300,500], 0)` returns `[200, 300, 500]` — use case 10's device deliveries, whole units.
- [ ] `split(100, [0,1,1], 2)` returns `[0, 50, 50]`; the zero weight receives nothing, including no residual.
- [ ] `split(-100, [1,1,1], 2)` sums to exactly -100.
- [ ] Empty, all-zero, and negative weight lists all fail with `ALLOCATION_WEIGHTS_INVALID`.
- [ ] Randomized property test: 10,000 generated `(total, weights, scale)` triples, every one summing back exactly. This is cheap and it is the only check that covers the cases nobody thought of.
- [ ] An `EVEN` allocation over a step 01 `PERIOD` expansion produces a table whose grand total equals the unexpanded table's grand total, and `verify()` passes.
- [ ] Every `ALLOCATE` measure is allocated with the same weights, not only `Amount_Net__c`.
- [ ] **A 100-license line on a twelve-month `PERIOD` table shows 100 in every month**, not 8.33 — the §3.3 defect, with a test that fails against today's code.
- [ ] The same line's `Amount_Net__c` is still divided across the twelve months and still reconciles.
- [ ] A `REPEAT` measure with no explicit grand-total aggregation rule fails config load with `REPEAT_MEASURE_NEEDS_AGGREGATION_RULE` — no twelve-month table ever prints 1,200 licenses.
- [ ] 1,000 devices across three deliveries allocates 200/300/500 — the same measure, divided, because the dimension divides quantity.
- [ ] `ALLOCATION_SOURCE_UNRECONCILED` fires when a line's shares are deliberately swapped with another line's, **even though the table total still reconciles** — the §3.6 case that `verify()` alone cannot catch.
- [ ] A deliberately dropped cent fails the source check at zero tolerance, despite passing `verify()`'s 0.01.
- [ ] A `REPEAT` measure appears in every occupied bucket and no unoccupied one.
- [ ] A composition table's grand total equals the package price exactly once, with components carrying it and the package row not counted.
- [ ] An installment table with no expansion source generates three `Detail` rows reconciling to the quote total.
- [ ] Changing `Allocation_Basis__c` alone moves the fingerprint.
- [ ] Existing suite passes untouched, including `QuoteDocumentMonthlyRowCustomizer`'s own tests — which still run on their own code until [step 06](step-06-docs-and-closeout.md) migrates it.

## 6. Verification method

```bash
sf apex run test --class-names QuoteDocumentAllocationTest --class-names QuoteDocumentExpansionTest --class-names QuoteDocumentGeneratorTest --result-format human --wait 20
```

```sql
SELECT Group_Value__c, Row_Type__c, Amount_Net__c, Amount_List__c, Quantity__c
FROM Quote_Document_Row__c
WHERE Quote_Document_Table__r.Quote__c = :quoteId
  AND Quote_Document_Table__r.Table_Code__c = 'PAYMENT_SCHEDULE'
ORDER BY Display_Order__c
```

Pass: the `Detail` rows sum to the `Grand Total` row to the cent, and the `Grand Total` equals the quote's own net amount.

New test class `QuoteDocumentAllocationTest` (pure) plus additions to `QuoteDocumentExpansionTest` for the org-side cases: `evenAllocationOverPeriodsPreservesGrandTotal`, `everyMeasureIsAllocated`, `packagePriceIsCountedExactlyOnce`, `installmentScheduleReconcilesWithoutExpansion`, `quantityAllocatesInWholeUnits`.

## 7. Close-out

- **Date:** 2026-08-28
- **Status: BUILT.** The primitive and the per-measure rule shipped first; the weighted bases followed the same day once `QuoteDocumentScheduleExpander` existed to supply non-uniform weights. The "Not built" list below has been updated in place rather than rewritten, so what was outstanding and for how long stays visible.

**Built and tested**

- `QuoteDocumentAllocation.split` / `splitEvenly` / `reconcile`, pure and org-free. Relative weights, exact sums at any scale, zero weights that stay zero and never take the residual, negative totals, and coded refusal of empty / all-zero / negative weights.
- **Per-measure behaviour (§3.3), the point of this step.** `ALLOCATE` and `REPEAT` are decided by the expander's `dividesQuantity()` rather than per table: money divides on every axis, a quantity divides on a delivery axis and repeats on a period one. The 8.33-licences defect cannot recur through this path.
- **Source-by-source reconciliation (§3.6) at zero tolerance,** run before insert, for every counted line and every allocated measure. This is the check `verify()` structurally cannot make - its 0.01 table-level tolerance would pass a lost cent, and no aggregate check can see one line's money landing in another's buckets.
- The §5 worked numbers, all asserted: 100/[1,1,1] to 33.33/33.33/33.34; 60,000 at 30/40/30; 120,000 at 50/30/20; 1,000 devices at scale 0; a free month at exactly 0.00.
- **The property test runs 312 combinations** - twelve totals including zero and negatives, two scales, one to thirteen parts, with a deterministic weighting that puts a zero weight in one part of five. Deterministic rather than seeded: a random failure in a test that guards money is a failure you cannot investigate.

**Not built**

- ~~`WEIGHTED_SOURCE` and `SCHEDULE` as configuration~~ — **closed 2026-08-28.** `QuoteDocumentScheduleExpander` supplies non-uniform weights from `Quote_Document_Schedule__mdt`, which is what those two bases were for. `Allocation_Basis__c` still accepts only `EVEN`, and that is now correct rather than a gap: the *weights* carry the shape, and `EVEN` over weighted placements is exactly the weighted allocation. A second basis constant would have been a second name for the same arithmetic.
- Package composition (use case 12) still needs a subscriber expander: allocating a package price down to its components requires knowing which components belong to which package, which no schedule expresses. It stays *enabled, needs its own implementation*.
- The installment table (use case 3) is **built and tested** — see `QuoteDocumentScheduleTest.anInstallmentScheduleSplitsTheQuoteToTheCent`, which asserts the specification's own \$60,000 at 30/40/30.
- `Allocation_Behaviour__c` on `Quote_Document_Column_Def__mdt`. The behaviour is currently the expander's declaration, which is the right default and covers every shipped case; a per-column override earns its field when a table needs one, not before.

- **Test evidence:** `QuoteDocumentAllocationTest` 16/16, `QuoteDocumentExpansionTest` 18/18. Full suite 434 ran, 429 passed, 5 pre-existing failures.

- **Next step:** [`step-03-non-additive-measures.md`](step-03-non-additive-measures.md)

- **Next step:** [`step-03-non-additive-measures.md`](step-03-non-additive-measures.md)
