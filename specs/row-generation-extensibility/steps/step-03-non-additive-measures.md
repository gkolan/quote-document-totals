# Step 03 — Non-additive measures

**Status: PLANNED**
**Blocked by:** [step 00](step-00-audit-and-boundaries.md) only — independent of 01 and 02
**Blocks:** nothing
**Use cases:** 15, 19 ([`spec.md`](../spec.md) §3)

---

## 1. Goal

A measure can declare how it aggregates — sum, ratio of two other measures, max, or last — so that a subtotal or grand total for a percentage, a blended unit price, a peak quantity, or an ending balance is computed correctly instead of summed.

## 2. Why this step exists

`QuoteDocumentRowBuilder` sums every measure into every aggregate row, because every measure it has today is additive. The moment a table carries an effective discount percentage, the subtotal row prints the sum of the child percentages — a number that can exceed 100 and means nothing. Nobody sees a stack trace. `verify()` does not catch it either: it reconciles amounts, not derived ratios.

This is the only step in the spec that fixes something already wrong rather than adding something missing, which is why it has no dependency on 01 or 02 and can be pulled forward.

## 3. Scope

### 3.1 The rule set

Add `Aggregation_Rule__c` to `Quote_Document_Column_Def__mdt` (the column object from render-contract [step 02](../../vendor-neutral-render-contract/steps/step-02-column-snapshot-object.md), which already declares what each column binds and how it is typed — the correct home, rather than a new object).

| Rule | Aggregate value | Use case |
|---|---|---|
| `SUM` | Default. Sum of contributing leaf rows. Behaviour today, unchanged. | every existing column |
| `RATIO` | `numerator aggregate / denominator aggregate`, each aggregated by its own rule first | effective discount %, blended unit price |
| `MAX` | Greatest leaf value | a per-row ceiling, e.g. the largest single discount |
| `SUM_THEN_MAX` | Sum within each child group, then the greatest of those sums | **peak active licenses** — see §3.2a |
| `LAST` | Value of the last contributing leaf in `Display_Order__c` | ending balance |
| `NONE` | Blank on aggregate rows | a value that has no meaningful roll-up at all |

`RATIO` needs two more fields: `Aggregation_Numerator__c` and `Aggregation_Denominator__c`, each a `Value_Field__c` on the same table. A denominator that aggregates to zero yields **blank**, not zero and not an error — a table with no quantity has no blended price, and that is a legitimate document, not a failure.

### 3.2a Peak licenses needs two rules, not one

`MAX` over detail rows is the wrong answer for "peak active licenses" and gets it wrong in the direction that matters — too low. Two products with 100 and 50 licenses running in the same month are 150 licenses active that month; `MAX` over the leaves returns 100.

The correct rule is **sum within each period, then take the maximum across periods**, which is what `SUM_THEN_MAX` does: the subtotal row for each period is an ordinary `SUM`, and only the grand total takes the maximum of those subtotals. It composes with a `REPEAT` quantity from [step 02](step-02-allocation-primitive.md) §3.3 exactly as it should — 100 in every month, 50 in the months the second product runs, 150 at the peak.

Two conditions this rule needs, and both must be checked rather than assumed:

1. **The child grouping must be the axis being peaked over.** `SUM_THEN_MAX` on a table grouped by product family peaks across families, which is meaningless. Config load fails with `SUM_THEN_MAX_REQUIRES_EXPANSION` unless the outermost grouping level is the expansion dimension.
2. **Summing the quantities has to be meaningful in the first place.** Licenses and gigabytes do not add. The framework cannot know a unit of measure it does not carry, so the rule is not that it detects this — it is that the *guide* for any table using `SUM_THEN_MAX` states the unit and why the sum is valid, and the acceptance criteria below require it. Recording an unenforceable claim as if it were enforced is worse than stating the limit.

### 3.2 Order of computation

Aggregate rows compute bottom-up: leaves, then each subtotal from its own children, then section totals, then grand total. A `RATIO` at every level is computed from *that level's* aggregated numerator and denominator — never by averaging the child ratios. This is the whole point: a 60% discount on \$1,000 and a 10% discount on \$100,000 blend to about 10.5%, not 35%.

A `RATIO` whose numerator or denominator is itself a `RATIO` fails at config load with `AGGREGATION_RULE_CYCLIC`. One level of derivation is enough for every use case listed, and disallowing it removes any need for dependency ordering.

### 3.3 Interaction with `verify()`

`verify()` reconciles leaf contributions against aggregate rows, and a correct `MAX` fails that check. The obvious move is to skip non-`SUM` columns. **Skipping is not enough** — an unverified column is exactly where a wrong number ships quietly, and the whole reason this step exists is that non-additive measures fail silently.

So each rule is *re-verified under its own definition*, in `QuoteDocumentVerification`, by rule read from the column definition rather than by field name:

| Rule | What verification asserts about every aggregate row |
|---|---|
| `SUM` | Unchanged: equals the sum of contributing leaves, within the existing tolerance |
| `RATIO` | Equals `numerator aggregate / denominator aggregate` recomputed from the same row's own values; blank exactly when the denominator is zero |
| `MAX` | Equals the greatest contributing leaf, and is ≥ every one of them |
| `SUM_THEN_MAX` | Equals the greatest child-group aggregate, and each child is a valid `SUM` |
| `LAST` | Equals the contributing leaf with the highest `Display_Order__c` |
| `NONE` | Is null |

Failure is `AGGREGATION_RESULT_UNVERIFIED`, naming the column, the rule, the expected value and the actual. The cost is one extra pass over rows already in memory.

This is the one place in this spec where verification logic changes, and it makes it stricter rather than looser. Cover it with a test asserting that a table mixing `SUM` and `SUM_THEN_MAX` columns still catches a deliberately corrupted `SUM` column, **and** one asserting a corrupted `SUM_THEN_MAX` is caught too.

### 3.4 Minimum commitment and shortfall (use case 15)

Two derived measures on a table whose leaf rows are ordinary: a supplied commitment amount (step 04 enrichment) and a shortfall. The shortfall row is `Informational` — it is a gap, not a charge, and must not enter any total. This distinction is a documentation requirement as much as a code one; the guide must state it in the words the customer will read.

### 3.5 Fingerprint

Add each column's `Aggregation_Rule__c`, numerator, and denominator to the per-column fingerprint contribution. Changing a rule changes the printed numbers without changing any amount, which is precisely the case `canReuse` would otherwise get wrong.

## 4. Out of scope

- Weighted averages beyond the `RATIO` form. A weighted average *is* a ratio of two sums; if a case appears that is not, it gets its own rule then.
- Aggregating across tables. Every rule here is within one table.
- Changing any existing column's rule. Everything currently deployed stays `SUM`, and a test asserts that.

## 5. Acceptance criteria

- [ ] Three CMDT fields deployed and in the permission set.
- [ ] Every existing column defaults to `SUM`; a regenerated quote's fingerprint and row values are unchanged from before the deploy.
- [ ] A `RATIO` discount column on a two-group table shows the correctly blended figure at subtotal and grand-total level, not the sum and not the mean of the children.
- [ ] A `RATIO` with a zero denominator prints blank.
- [ ] A `MAX` column shows the peak leaf value at every aggregate level.
- [ ] **Two products with 100 and 50 licenses active in the same month give a peak of 150, not 100** — `SUM_THEN_MAX`, the point 2 case.
- [ ] `SUM_THEN_MAX` on a table not grouped by an expansion dimension fails with `SUM_THEN_MAX_REQUIRES_EXPANSION`.
- [ ] A corrupted `SUM_THEN_MAX`, `RATIO`, `MAX` and `LAST` value each fail with `AGGREGATION_RESULT_UNVERIFIED` — every rule is verified, none is merely skipped.
- [ ] A `LAST` column shows the final leaf value in `Display_Order__c`, and re-ordering the rows changes it.
- [ ] A `NONE` column is blank on aggregate rows and populated on leaves.
- [ ] A `RATIO` pointing at another `RATIO` fails at config load with `AGGREGATION_RULE_CYCLIC`.
- [ ] `verify()` skips non-`SUM` columns and still fails a corrupted `SUM` column on the same table.
- [ ] A shortfall row is `Informational` and appears in no total.
- [ ] Changing `Aggregation_Rule__c` alone moves the fingerprint.
- [ ] Existing suite passes untouched.

## 6. Verification method

```bash
sf apex run test --class-names QuoteDocumentAggregationTest --class-names QuoteDocumentGeneratorTest --class-names QuoteDocumentFingerprintTest --result-format human --wait 20
```

Worked check on a real quote — one group of \$1,000 at 60% off and one of \$100,000 at 10% off:

```sql
SELECT Row_Type__c, Group_Value__c, Amount_List__c, Amount_Discount__c, Display_Order__c
FROM Quote_Document_Row__c
WHERE Quote_Document_Table__r.Quote__c = :quoteId
ORDER BY Display_Order__c
```

Pass: the grand total's discount percentage column reads ≈10.5%, not 70% and not 35%. Verify by hand from the list and discount amounts in the same result.

New test class `QuoteDocumentAggregationTest`: `existingColumnsStayAdditive`, `ratioBlendsRatherThanSums`, `ratioWithZeroDenominatorIsBlank`, `maxTakesThePeakLeaf`, `lastFollowsDisplayOrder`, `noneIsBlankOnAggregates`, `nestedRatioFailsConfigLoad`, `verifyStillCatchesACorruptedSumColumn`, `shortfallRowEntersNoTotal`, `aggregationRuleMovesTheFingerprint`.

## 7. Close-out

*(To be filled: the exact `verify()` change, and whether any deployed column turned out to be non-additive already — if one is found, that is a live defect and gets its own note.)*

- **Next step:** [`step-04-comparison-and-enrichment.md`](step-04-comparison-and-enrichment.md)
