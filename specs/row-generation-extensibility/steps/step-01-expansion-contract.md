# Step 01 — Expansion contract

**Status: BUILT** — see close-out
**Blocked by:** [step 00](step-00-audit-and-boundaries.md)
**Blocks:** 02, 04, 05
**Use cases:** 2, 6, 7, 8, 9, 10, 18 ([`spec.md`](../spec.md) §3)

---

## 1. Goal

One quote line can become N document entries along a declared dimension, using declarative configuration plus a small registered class, without discarding `QuoteDocumentRowBuilder` and without any table re-implementing grouping, subtotals, ordering, or labels.

## 2. Why this step exists

The framework can only group. `QuoteDocumentMonthlyRowCustomizer` is the one table that multiplies, and it pays for that by rebuilding the whole row list itself — 500-odd lines that duplicate what the builder already does, per expansion. A second expansion (years, tiers, deliveries) written the same way doubles that duplication and doubles the surface where a subtotal can silently disagree with the builder's.

## 3. Scope

### 3.1 The seam

New interface, alongside `QuoteDocumentRowCustomizer` rather than replacing it:

```apex
public interface QuoteDocumentLineExpander {
    /** The axis: every bucket this table prints, in order, whether or not any line occupies it. */
    List<QuoteDocumentExpansion.Bucket> buckets(QuoteDocumentRowCustomizerContext ctx);

    /** Which buckets this line occupies, and with what relative weight in each. */
    List<QuoteDocumentExpansion.Placement> placements(QuoteDocumentLine line, QuoteDocumentRowCustomizerContext ctx);
}
```

```apex
public class QuoteDocumentExpansion {
    public class Bucket {
        public String key;        // 'MONTH:03' — never printable
        public String labelKey;   // resolved through QuoteDocumentLabels
        public String labelArg1;
        public String labelArg2;
        public Integer order;
    }
    public class Placement {
        public String bucketKey;
        public Decimal weight;    // relative; step 02 normalizes. 1 for an even split.
    }
}
```

**Why `Placement` and not a key list** — [`spec.md`](../spec.md) §5 rule 10. Weight is knowledge only the expander has: a promotional schedule's zero months, a delivery's 200/300/500 split, a phase's percentages. Returning bare keys would force step 02 to re-derive it from a field path that does not exist for half the dimensions, which is how the two halves of one data flow drift apart. The weight travels on the placement that created it.

An expander that wants an even split returns `weight = 1` everywhere; `EVEN` in step 02 is then not a special case, just uniform weights.

`Bucket` carries a semantic key and a sort position, never a printable string ([`spec.md`](../spec.md) §5 rule 2).

**Shape (b), pre-transform, as recommended by step 00.** The expander runs *before* `QuoteDocumentRowBuilder`. The generator asks for the bucket list, asks each line which buckets it occupies, and emits one `QuoteDocumentLine` clone per (line, bucket) pair with the bucket key written to a new transient `expansionKey` field. The builder then groups on `EXPANSION` exactly as it groups on `PRODUCT_FAMILY` today. Everything downstream — subtotals, `Display_Order__c`, `Group_Header` rows, `verify()` — is untouched code.

If step 00 chose shape (a), replace this subsection and say so; do not build both.

### 3.2 Configuration

On `Quote_Document_Table_Def__mdt`:

| Field | Type | Notes |
|---|---|---|
| `Expander_Code__c` | Text(40) | Resolved by a new `QuoteDocumentExpanderRegistry`, same switch-on-code shape as the customizer registry. Blank means no expansion — the current behaviour of every existing table. |
| `Expander_Version__c` | Text(20) | Content identity. Same reason as `Row_Customizer_Version__c`: changed expansion logic under an unchanged code is invisible to the fingerprint. |

The expansion dimension is exposed to grouping as `DIM_EXPANSION = 'EXPANSION'` in `QuoteDocumentTableDefinition`, usable at any level of `Quote_Document_Grouping__mdt`. That is the whole point of shape (b): *year, then product family* and *product family, then year* are both a grouping configuration, not two more classes.

### 3.3 Expanders that ship

Ship exactly **one**.

| Code | Dimension | Buckets | Covers |
|---|---|---|---|
| `PERIOD` | An anniversary period axis of configurable length (`Period_Months__c`: 1 = monthly, 12 = annual) | Derived from the quote term exactly as `QuoteDocumentMonthlyRowCustomizer.resolveGrid` derives it today; fail with `EXPANSION_AXIS_UNRESOLVED` rather than guess | 2, 6, 8, 9 |

`DELIVERY` is **removed from this step.** Its bucket list is a set of delivery events that exist nowhere on the quote, so it depends on [step 04](step-04-comparison-and-enrichment.md)'s enrichment path and cannot ship in a step that precedes it. Shipping it here would have meant either a hard-coded source or an expander that fails on every real org. Use case 10 is therefore *enabled, needs its own implementation* ([`spec.md`](../spec.md) §3.1) — the seam is proven by `PERIOD`, and the event source is the subscriber's.

Tier expansion (7) and part-number mapping (18) are out for the same reason, and are described in step 04 §3.7.

### 3.3a `PERIOD` occupancy — the rules, stated exhaustively

Vague occupancy is where a period table goes wrong silently. Every case below is a shipped rule with a test, not a default:

| Line | Occupies | Why |
|---|---|---|
| Subscription window inside the term | Every period the window touches, whole or partial | One day of overlap means the product was running that period |
| Blank start **and** blank end | Every period | Matches CPQ's own meaning for a blank `SBQQ__EffectiveStartDate__c` |
| Blank start, dated end | First period through the end's period | |
| Dated start, blank end | The start's period through the last | |
| End before start | Fails, `EXPANSION_WINDOW_INVALID` | |
| Entirely outside the term | Fails, `EXPANSION_LINE_OUTSIDE_AXIS` | Dropping it silently leaves the printed periods short of the quote total |
| **One-time charge** (`Charge_Type__c` = One-Time, or `SBQQ__SubscriptionPricing__c` blank) | **Exactly one period — the one containing its effective date**, defaulting to the first period when it has no date of its own | Use case 9. A blank window on a one-time charge does **not** mean the whole term: hardware and setup are incurred once. Spreading a setup fee across twelve months prints a recurring charge that does not exist. |

The one-time rule is a `Period_One_Time_Placement__c` picklist on the definition — `FIRST_PERIOD` (default), `EFFECTIVE_DATE`, `SPREAD` — because a prepaid annual support fee genuinely does spread, and only the author knows which. `SPREAD` is the old behaviour and must be chosen explicitly, never inherited by silence.

### 3.4 Ordering and identity

- Bucket order drives `Display_Order__c` through the builder's existing group ordering. Add `SORT_EXPANSION_ORDER` to `Sort_Groups_By__c` so an expansion axis sorts by its own order rather than alphabetically — an axis sorted alphabetically prints month 10 before month 2.
- `Row_Key__c` uniqueness is already enforced. An expanded detail row's key must include the bucket key, or two periods of the same line collide. Test this explicitly; it is the first thing a naive implementation gets wrong.

### 3.5 Amounts

**This step does not divide money.** An expanded line carries its source line's amounts unchanged, which means an expanded table's grand total is wrong by a factor of N until [step 02](step-02-allocation-primitive.md) lands. That is deliberate and it is *safe*, because `verify()` fails the generation rather than shipping the wrong number.

To keep the step independently shippable, a definition with an `Expander_Code__c` and no allocation basis fails config load with `EXPANSION_WITHOUT_ALLOCATION` unless it sets `Suppress_Amounts__c` — a label-only expansion (a coverage calendar, a delivery list with quantities in step 02) that carries no money at all.

### 3.6 Fingerprint

Add to `QuoteDocumentFingerprint.encode`, beside the existing customizer tokens: `expanderCode`, `expanderVersion`, `periodMonths`, `suppressAmounts`, and the resolved bucket count. Bucket count matters because a term change moves the axis without moving any configuration field.

### 3.7 Guard rails

- `MAX_EXPANSION_BUCKETS = 120`, mirroring the monthly customizer's `MAX_MONTHS`. Exceeding it fails with `EXPANSION_TOO_MANY_BUCKETS` naming the count, rather than producing a 4,000-row document.
- Expanded row count is `lines × buckets`. Add an explicit governor-limit test at the documented ceiling: 200 lines × 60 buckets. If DML rows or CPU are exceeded, the ceiling in the docs is the measured one, not the aspirational one.
- Permission set: no new fields on `Quote_Document_Row__c`, so nothing to add there; the two CMDT fields still need their entries.

## 4. Out of scope

- Dividing amounts across buckets — [step 02](step-02-allocation-primitive.md).
- Side-by-side period *columns* (year 1 / year 2 / year 3 across a row). That is a column-set-per-bucket problem in the render contract, not an expansion problem. Rows-per-period is the shape this step delivers, and it answers use case 2's "annual subtotals and total contract value".
- Migrating `QuoteDocumentMonthlyRowCustomizer` to the new seam — [step 06](step-06-docs-and-closeout.md), after allocation exists, since the monthly table needs both halves.

## 5. Acceptance criteria

- [ ] Interface, `QuoteDocumentExpansion.Bucket`, and `QuoteDocumentExpanderRegistry` deployed; unknown code throws naming the code.
- [ ] Both CMDT fields deployed and in the permission set.
- [ ] A definition with no `Expander_Code__c` generates byte-identically to today — asserted by fingerprint equality on an existing table before and after deploy.
- [ ] A `PERIOD` table with `Period_Months__c = 12` on a 36-month quote emits three buckets, and a line running months 7–20 appears in exactly buckets 1 and 2.
- [ ] Every row of §3.3a's occupancy table has a test, including both failure codes.
- [ ] A one-time charge with `FIRST_PERIOD` occupies exactly one bucket; the same charge with `SPREAD` occupies all of them; the difference is visible in the generated rows.
- [ ] A line with a blank subscription window occupies every bucket.
- [ ] `placements()` returns a weight per bucket, and an expander returning an empty placement list for a counted line fails rather than dropping the line.
- [ ] A quote with neither a term nor derivable line dates fails with `EXPANSION_AXIS_UNRESOLVED`.
- [ ] `Row_Key__c` differs per bucket for the same source line; the duplicate-key check does not fire.
- [ ] Grouping `EXPANSION > PRODUCT_FAMILY` and `PRODUCT_FAMILY > EXPANSION` both generate, with the same rows in a different nesting — the proof that shape (b) bought composability.
- [ ] `SORT_EXPANSION_ORDER` puts bucket 10 after bucket 2.
- [ ] An expansion without allocation and without `Suppress_Amounts__c` fails with `EXPANSION_WITHOUT_ALLOCATION` at config load, not at `verify()`.
- [ ] 121 buckets fails with `EXPANSION_TOO_MANY_BUCKETS`.
- [ ] 200 lines × 60 buckets generates within limits, and the measured heap/CPU/DML figures are recorded in the close-out.
- [ ] Changing `Expander_Version__c` alone moves the fingerprint; changing the quote term alone moves it too.
- [ ] Existing suite passes untouched.

## 6. Verification method

```bash
sf project deploy start --source-dir force-app
sf apex run test --class-names QuoteDocumentExpansionTest --class-names QuoteDocumentGeneratorTest --class-names QuoteDocumentFingerprintTest --result-format human --wait 20
```

```sql
SELECT Group_Dimension__c, Group_Value__c, Row_Type__c, Display_Order__c,
       Product_Name__c, Row_Key__c
FROM Quote_Document_Row__c
WHERE Quote_Document_Table__r.Quote__c = :quoteId
  AND Quote_Document_Table__r.Table_Code__c = 'ANNUAL_SCHEDULE'
ORDER BY Display_Order__c
```

Pass: buckets appear in axis order, each product appears once per bucket it occupies, and no `Row_Key__c` repeats.

New test class `QuoteDocumentExpansionTest`: `noExpanderIsUnchangedBehaviour`, `annualAxisDerivesFromQuoteTerm`, `lineOccupiesEveryBucketItsWindowTouches`, `blankWindowMeansWholeTerm`, `unresolvableAxisFails`, `rowKeyIncludesBucket`, `expansionNestsEitherWayRoundWithGrouping`, `bucketOrderBeatsAlphabetical`, `expansionWithoutAllocationFailsAtConfigLoad`, `bucketCeilingIsEnforced`, `expanderVersionMovesTheFingerprint`, `twoHundredLinesBySixtyBucketsStaysInLimits`.

## 7. Close-out

- **Date:** 2026-08-28
- **Status: BUILT.**
- **Delivered:** `QuoteDocumentLineExpander` (interface), `QuoteDocumentExpansion` (Request/Bucket/Placement/Result and the expand-and-allocate engine), `QuoteDocumentPeriodExpander`, `QuoteDocumentExpanderRegistry`, seven `Quote_Document_Table_Def__mdt` fields, `DIM_EXPANSION`, `SORT_EXPANSION_ORDER`, fingerprint tokens, an inactive `ANNUAL_SCHEDULE` definition, and `YEAR_LABEL` / `PERIOD_LABEL` dictionary entries in en_US and fr.
- **Shape (b) held.** The expander returns lines, the builder groups them, and no grouping, subtotal, ordering or verification code was rewritten. `EXPANSION > PRODUCT_FAMILY` and the reverse are both a metadata change, as promised.
- **`DELIVERY` was dropped from this step,** as §3.3 says: its bucket list is not on the quote. Use case 10 stays *enabled, needs its own implementation*.
- **One thing the plan did not foresee — the grand total.** Expansion alone was not enough for a repeated measure. `QuoteDocumentRowBuilder.emitGrandTotal` sums every line, so a licence count repeated across three periods totalled 351 instead of the peak 151, and verification (correctly) rejected it. Fixed with `withNonAdditiveMeasures()` and `peakAcrossTopLevelGroups()`: subtotals stay sums, the grand total takes the largest group. This is step 03's `SUM_THEN_MAX` arriving early because expansion could not ship without it.
- **A restriction added, not planned:** an expanded table may not also show section totals. A section total cuts across every bucket at once, and on an expanded table that second cut has no agreed meaning - the repeated quantity would be summed across periods again. Refused at config load rather than guessed at.
- **Group keys come from the bucket LABEL,** as they do for every other dimension - a year bucket keys as `EXPANSION:YEAR_1`. The internal `PERIOD:001` key never reaches a row. This was a test expectation that had to be corrected, not the code.
- **Measured, 2026-08-28:** 60 lines x 36 monthly buckets = **2,174 rows**, costing **2,187 DML rows of 10,000**, **3,321 ms CPU of 10,000**, and **178 KB heap of 6 MB**. CPU is the binding limit at roughly 1.5 ms a row, which puts the real single-transaction ceiling near **6,000 rows** — not the DML cap, and nowhere near heap. The step's original "200 lines x 60 buckets" is 12,000 rows and is past the platform's own DML limit, so it is not a ceiling this framework can offer; anything that large belongs in `generateAsync`, one quote per transaction. Asserted by `generationStaysInLimitsAtTheDocumentedCeiling`.
- **A second expander shipped after the close-out:** `QuoteDocumentScheduleExpander` (`SCHEDULE`), whose buckets and weights are authored in `Quote_Document_Schedule__mdt` rather than derived from the quote. It is what makes installments, department splits, project phases and promotional pricing configuration rather than code.
- **Test evidence:** `QuoteDocumentExpansionTest` 18/18, `QuoteDocumentAllocationTest` 16/16. Full suite 434 ran, 429 passed, 5 failed - the five pre-existing org-only failures, unchanged.

- **Next step:** [`step-02-allocation-primitive.md`](step-02-allocation-primitive.md)

- **Next step:** [`step-02-allocation-primitive.md`](step-02-allocation-primitive.md)
