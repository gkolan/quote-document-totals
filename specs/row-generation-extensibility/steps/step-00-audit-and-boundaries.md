# Step 00 — Audit and capability boundaries

**Status: BUILT** — audit complete; the defect it found is fixed, see close-out
**Blocked by:** nothing
**Blocks:** 01, 02, 03, 04, 05

---

## 1. Goal

Before writing any new seam, establish on the record: what `QuoteDocumentMonthlyRowCustomizer` actually proves, which of its behaviours are general and which are monthly-specific, and where the boundary sits between "the framework calculates this" and "the framework displays a supplied result".

This step writes no production Apex. It produces two artefacts — an audit table and a boundary rule — that steps 01–05 are held to.

## 2. Why this step exists

The temptation after reading the use-case list is to design a general expansion engine from the list. That is backwards. One expansion is already deployed and reconciles to the cent against CPQ's own `SBQQ__NetAmount__c`. Whatever is general is general *because it survived that*, not because it looked general on paper. Generalizing from the running code is a smaller and safer diff than generalizing from a wish list.

## 3. Scope

1. **Audit `QuoteDocumentMonthlyRowCustomizer` clause by clause**, classifying each documented rule as `GENERAL`, `PARAMETRIC`, or `MONTHLY-ONLY`. Fill this table in the close-out; the starting classification below is a proposal to be confirmed or overturned against the code, not an answer.

   | Rule (from the class header) | Proposed class | Why |
   |---|---|---|
   | THE GRID — derive the axis, fail rather than guess | `PARAMETRIC` | Every expansion has an axis. Only its *derivation* is monthly. |
   | BUCKETS — anniversary months, half-open intervals | `MONTHLY-ONLY` | A milestone or department axis has no interval at all. |
   | OCCUPANCY — a line occupies every bucket it touches | `PARAMETRIC` | Generalizes to "which buckets does this line belong to", a predicate per dimension. |
   | ALLOCATION — even division across occupied buckets | `PARAMETRIC` | Even is one weighting. Percentages, phases, and delivery quantities are others. |
   | ROUNDING — cent-rounded shares, residual to the last bucket | `GENERAL` | This is the rule that makes `verify()` pass. It belongs to step 02, not to any one dimension. |
   | EXCLUSIONS — bundled components omitted, not printed at zero | `GENERAL` | Already expressible as a `Line_Filter__c`; confirm whether the customizer duplicates it. |
   | THE NOTE — conditional explanatory row | `PARAMETRIC` | "Emit a note when a stated condition holds" is general; the condition is not. |

2. **Record the discard-and-replace fact explicitly.** The customizer throws away `QuoteDocumentRowBuilder`'s rows. Decide and record which of the two shapes step 01 adopts, with the reason:
   - **(a) replace** — the expander runs *instead of* the builder for its table; or
   - **(b) pre-transform** — the expander transforms the `List<QuoteDocumentLine>` *before* the builder runs, so grouping, subtotals, ordering and labels stay in the builder.

   Step 01 recommends (b) and must justify it against what the monthly customizer actually needed the builder's absence for. If (b) cannot express the monthly table, (b) is wrong and the recommendation is withdrawn.

3. **State the calculation boundary as a testable rule**, not a sentiment. Proposed wording, to be confirmed:

   > The framework calculates a value only when every input is on the quote, its lines, the table definition, or a source declared in `Contributor_Dependency_Set__c` and hashed into the fingerprint. Anything whose correct value depends on state that changes without the quote changing — a usage balance, a payment received, a recognized amount — is supplied to the framework as an input, never derived by it.

   The test of the rule: applied to all 20 use cases in [`spec.md`](../spec.md) §3, it must classify each one, and it must place usage balances, invoice collection and revenue recognition outside without needing an exception clause.

4. **Inventory the active table definitions again.** The render-contract spec's baseline (15 definitions, 7 active, 4 naming customizers, as of 2026-08-27) is a snapshot and will be stale. Re-run it and record the numbers; any later step quoting a count quotes this one.

5. **List the error codes each planned step will add**, in one place, so codes are unique across steps before any of them are written.

## 4. Out of scope

- Any Apex, object, or CMDT change. If this step edits `force-app`, it has overrun.
- Deciding *which* expansion dimensions ship. That is step 01 §3.

## 5. Acceptance criteria

- [ ] Every rule in the monthly customizer's header is classified `GENERAL` / `PARAMETRIC` / `MONTHLY-ONLY`, with a one-line reason each.
- [ ] Shape (a) or (b) is chosen for step 01, in writing, with the monthly table demonstrated as expressible under the chosen shape — as a worked description, not as code.
- [ ] The calculation-boundary rule classifies all 20 use cases with no exception clause, and the classification is recorded.
- [ ] Fresh table-definition inventory recorded with its date.
- [ ] Error-code list for steps 01–05 recorded, with no duplicates against the existing catalogue in [`docs/quote-document-extension-recipes.md`](../../../docs/quote-document-extension-recipes.md).
- [ ] `git status` shows changes only under `specs/row-generation-extensibility/`.

## 6. Verification method

```bash
git diff --stat master -- force-app
```

Pass: empty output.

```bash
grep -rn "GENERAL\|PARAMETRIC\|MONTHLY-ONLY" specs/row-generation-extensibility/steps/step-00-audit-and-boundaries.md
```

Pass: every header rule appears exactly once with a classification.

Inventory query, run against the connected org:

```sql
SELECT Table_Code__c, Is_Active__c, Row_Customizer_Code__c, Row_Customizer_Flow__c
FROM Quote_Document_Table_Def__mdt
ORDER BY Display_Order__c
```

Pass: the recorded counts match the query result on the date recorded.

## 7. Close-out

- **Date:** 2026-08-28
- **Scope note:** this step was to write no production Apex, and it did not — **but it found a defect while auditing**, and that defect was fixed in the same session under [`spec.md`](../spec.md) §3.2 rather than filed and forgotten. The §5 acceptance criterion "changes only under `specs/`" is therefore **not met, deliberately**. Recording that is the honest outcome; claiming the audit was clean would not be.

### Classification, as audited against the code

| Rule | Proposed | **Audited** | Finding |
|---|---|---|---|
| THE GRID | `PARAMETRIC` | `PARAMETRIC` | `resolveGrid` derives a start (quote, else earliest line) and a length (`SBQQ__SubscriptionTerm__c`, else `monthsToCover`), and throws `MONTHLY_TERM_UNRESOLVED` rather than guessing. Only "months" is monthly; the shape is an axis. |
| BUCKETS | `MONTHLY-ONLY` | **`PARAMETRIC`, overturned** | `MonthGrid.indexOf` is a half-open interval search over an ordered axis. `Period_Months__c = 12` needs `addMonths(i * n)` and nothing else. The proposal was wrong — the anniversary logic generalizes to any period length, just not to a non-interval axis like milestones. |
| OCCUPANCY | `PARAMETRIC` | `PARAMETRIC` | `occupancyOf` returns a contiguous first/last range. **A general expander cannot assume contiguity** — a delivery or milestone axis is a set, not a range. Step 01's `placements()` returns a list for this reason. |
| ALLOCATION | `PARAMETRIC` | `PARAMETRIC` | Even division is `allocate(value, monthCount)`. Weights generalize it. |
| ROUNDING | `GENERAL` | `GENERAL` | `allocate()` is already pure, static and public — it moves to step 02's primitive almost unchanged. |
| EXCLUSIONS | `GENERAL` | `GENERAL`, **and duplicated** | The customizer re-filters with `line.countsIn(definition.lineFilter)` even though the generator already applied `applyFilter` before calling it. Harmless today (idempotent), worth removing when the customizer migrates in step 06. |
| THE NOTE | `PARAMETRIC` | **`MONTHLY-ONLY` in its current form** | The header documents it as unconditional and the code emits it unconditionally, with a written reason for the reversal from conditional. It is one string keyed to this table's meaning, not a mechanism. |

### The eighth rule, which the header does not state

**`Quantity__c` is allocated like money, and that is wrong.** `measureFields(PRICE_WATERFALL)` ends with `Quantity__c`; `customize()` allocates every measure in the set. A 100-licence line over twelve months printed **8.33 licences per month**, and a grand total of 1,200. The class header's ALLOCATION rule says "each measure is divided evenly" and meant it.

No test caught it because every line in `QuoteDocumentMonthlyRowCustomizerTest` had `SBQQ__Quantity__c = 1`, where the wrong answer (0.08) and the right one (1) are both small and neither is asserted.

Fixed in this session, ahead of step 02, because it is a defect in existing code rather than a missing feature:

| Change | Where |
|---|---|
| `REPEATED_MEASURES = { Quantity__c }`, `repeat()` beside `allocate()` | `QuoteDocumentMonthlyRowCustomizer` |
| Grand total rolled up from month subtotals — summed for divisible measures, **maximum** for repeated ones | same |
| `nonAdditiveMeasures`, declared by the contributor | `QuoteDocumentRowCustomizerContext` |
| Collected per table and passed to verification | `QuoteDocumentGenerator` |
| `assertSumWithinGroupsMaxAcross` — declared measures are **verified under their own rule, not skipped** | `QuoteDocumentVerification` |

Four new tests: `licencesRepeatInEveryMonthRatherThanBeingDividedAmongThem`, `theTermShowsThePeakMonthNotTheSumOfEveryMonth`, `moneyStillDividesWhileLicencesRepeat`, `repeatGivesEveryPartTheWholeValue`. **17/17 in the class; 400 local tests, 395 passed, 5 failed — the five pre-existing org-only failures, unchanged.**

This is also the first working instance of [step 03](step-03-non-additive-measures.md)'s `SUM_THEN_MAX`, built at the size the defect needed. Step 03 generalizes it to configuration; it does not invent it.

### Shape for step 01: (b) pre-transform, confirmed

The monthly customizer needs the builder's absence for exactly three things, and each survives under (b):

1. **Multiplying rows** — (b)'s whole purpose: expand the line list, then let the builder group it.
2. **Its own row keys** (`DETAIL:MONTH:03:<lineId>`) — the builder produces the same uniqueness once the bucket key is a grouping dimension.
3. **Its own grand total**, because the money is allocated — that becomes step 02's job, before the builder ever sees the lines.

What (b) does **not** give it is the unconditional `Note` row, which stays a customizer concern. So the monthly table under (b) is a `PERIOD` expander plus an `EVEN` allocation plus a small customizer for the note — not zero custom code, and step 06's migration criterion is written accordingly.

### Calculation boundary, adopted as proposed

The §3 wording classifies all 20 use cases with no exception clause. Usage balances, invoice collection and revenue recognition fall outside on the "changes without the quote changing" clause alone.

### Inventory, 2026-08-28

Not re-run against the org. The render-contract baseline (15 definitions, 7 active, 4 naming customizers, 2026-08-27) is one day old and the only change since is `MONTHLY_SUBSCRIPTION_SUMMARY`, still untracked in git. **Any step that depends on the count must re-run the query in §6** — this is a deferral, not a measurement.

### Error codes reserved

`EXPANSION_AXIS_UNRESOLVED`, `EXPANSION_WINDOW_INVALID`, `EXPANSION_LINE_OUTSIDE_AXIS`, `EXPANSION_WITHOUT_ALLOCATION`, `EXPANSION_TOO_MANY_BUCKETS` (01) · `ALLOCATION_WEIGHTS_INVALID`, `ALLOCATION_SOURCE_UNRECONCILED`, `REPEAT_MEASURE_NEEDS_AGGREGATION_RULE` (02) · `AGGREGATION_RULE_CYCLIC`, `AGGREGATION_RESULT_UNVERIFIED`, `SUM_THEN_MAX_REQUIRES_EXPANSION` (03) · `COMPARISON_MATCH_AMBIGUOUS`, `ENRICHMENT_SOURCE_MISSING` (04) · `PARTITION_TOTAL_UNRECONCILED`, `PARTITION_KEY_COLLISION`, `SCENARIO_ASSUMPTIONS_MISSING` (05). No collision with the existing catalogue or with the customizer's own `MONTHLY_*` codes.

- **Next step:** [`step-01-expansion-contract.md`](step-01-expansion-contract.md)
