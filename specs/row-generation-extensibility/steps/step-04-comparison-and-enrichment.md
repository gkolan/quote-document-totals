# Step 04 — Comparison and enrichment sources

**Status: BUILT** — `SOURCE_QUOTE` and `AMENDED_SUBSCRIPTION` ship; `PRIOR_SNAPSHOT` is impossible as specified, see close-out
**Blocked by:** [step 01](step-01-expansion-contract.md)
**Blocks:** 05 (partially — scenario and rebate cases need enrichment)
**Use cases:** 5, 6, 7, 14, 15, 16, 17, 18 ([`spec.md`](../spec.md) §3)

---

## 1. Goal

A table can be built from **two** record sets matched on a stable key, and can read declared data from outside the quote, with staleness handled by the machinery that already exists rather than a second one.

## 2. Why this step exists

Six use cases need something the quote does not contain: the previous subscription position (5), last week's quote version (14), the renewal price (6), the pricing engine's tier breakdown (7), the commitment amount (15), the rebate threshold (16), the customer's part numbers (18). Today a customizer *can* run its own SOQL — the seam is trusted, not sandboxed ([render contract spec §1](../../vendor-neutral-render-contract/spec.md)) — but each one would then invent its own matching, its own missing-record behaviour, and its own answer to "is this snapshot stale". This step supplies one of each.

## 3. Scope

### 3.1 Enrichment: reading declared outside data

**No new object.** The framework already has the answer: a contributor declares its reads in `Contributor_Dependency_Set__c` and sets `Cache_Policy__c`; the fingerprint hashes the declared paths. This step's work on enrichment is therefore small, and mostly consists of *not* building things:

1. Confirm and document that dependency-declared enrichment is the supported path for supplied inputs, with a worked recipe in [`docs/quote-document-extension-recipes.md`](../../../docs/quote-document-extension-recipes.md).
2. Add `CACHE_ALWAYS_REBUILD` guidance for sources whose change cannot be mapped back to affected quotes — a pricing-tier service, an external rebate table. Correctness over reuse; a document that reuses a stale renewal price is worse than a slow one.
3. Add `ENRICHMENT_SOURCE_MISSING` as a coded failure. A missing renewal price must fail generation, never print blank and never fall back to the current price. Use case 6 said it explicitly: an existing quoted amount cannot establish the next renewal price, so guessing one is a fabrication.

### 3.2 Comparison: two record sets

New interface:

```apex
public interface QuoteDocumentComparisonSource {
    List<QuoteDocumentLine> baseline(QuoteDocumentRowCustomizerContext ctx);
    String matchKey(QuoteDocumentLine line);
}
```

The generator pairs `ctx.lines` (current) against `baseline(ctx)` on `matchKey`, producing for each pair a row carrying both sides plus the difference. Configuration on the table definition: `Comparison_Source_Code__c` and `Comparison_Source_Version__c`, registry-resolved like everything else.

Ship two sources:

| Code | Baseline | Use case |
|---|---|---|
| `AMENDED_SUBSCRIPTION` | The subscriptions the amendment quote amends | 5 |
| `PRIOR_SNAPSHOT` | The rows of a named earlier `Quote_Document_Table__c` for the same quote | 14 |

`PRIOR_SNAPSHOT` is the cheaper of the two and depends on nothing new: the snapshots are already immutable and already retained. It also proves the design without CPQ amendment semantics in the way, so build it first.

### 3.3 Matching, and what happens when it is ambiguous

The single hardest part of this step, and the one that must not be decided implicitly.

- The match key is the source's own choice. Product Id is the obvious default and is wrong often enough to matter — two lines of the same product at different terms are two positions, not one.
- **Ambiguity fails.** Two current lines matching one baseline line, or vice versa, fails with `COMPARISON_MATCH_AMBIGUOUS` naming the key and the record count. Silently picking one produces a difference column that is confidently wrong, and a customer reading a change document trusts that column completely.
- Unmatched on either side is **not** an error — it is the answer. A current line with no baseline is `Added`; a baseline with no current is `Removed`. Both get a row.
- Matched with no change still gets a row by default, with a zero difference. Suppressing unchanged rows is a `Line_Filter__c` decision, not a matching decision.

### 3.4 Row shape

Comparison rows carry both sides. Rather than doubling every measure field on `Quote_Document_Row__c`:

- current-side measures use the existing fields;
- baseline-side and difference measures reuse the `CHANGE` measure set fields already on the object (`Amount_Net_Change__c`, `Amount_Final__c` and siblings), whose semantics are already "before, after, difference".

Confirm this mapping against the deployed `CHANGE` measure set in step 00's audit before writing code. If it does not fit, add the minimum new fields and say which and why — but check first, because seven fields for this shape already exist.

`Row_Type__c` gains **no** new values. Added, removed and changed are distinguished by `Transaction_Type__c`, which is already on the row and already means this.

### 3.5 Relationship to the existing transaction summary

The framework has a `CHANGE` table with a provisional change classification. This step does **not** replace it and must not silently diverge from it. The close-out states, for a quote where both tables are generated, whether their totals agree and — if they do not — which is authoritative and why. Two change tables disagreeing on the same quote is worse than either one alone.

### 3.6 Fingerprint

`comparisonSourceCode`, `comparisonSourceVersion`, and the baseline's own identity — for `PRIOR_SNAPSHOT`, the baseline table's `Document_Payload_Hash__c`; for `AMENDED_SUBSCRIPTION`, the declared dependency paths under the existing mechanism. A comparison against a changed baseline is a different document and must not be reused.

### 3.7 Tier expansion and part-number mapping

These are the two use cases deferred from [step 01](step-01-expansion-contract.md) §3.3, and they land here because their bucket list comes from an enrichment source, not from the quote:

- **Tiers (7):** the expander's buckets are the pricing engine's returned tier breakdown. **Consume it; never recompute it.** A document that re-derives tier boundaries will eventually disagree with the price the customer is quoted, and the document will be the one that is wrong. If the breakdown is not available for a line, fail with `ENRICHMENT_SOURCE_MISSING` rather than reconstructing it.
- **Part numbers (18):** the expander's buckets are the mapped customer codes, with the line's amount allocated across them by [step 02](step-02-allocation-primitive.md)'s `WEIGHTED_SOURCE` basis.

## 4. Out of scope

- A general "second quote" comparison across different quote records. `PRIOR_SNAPSHOT` compares versions of one quote; cross-quote comparison needs a record-access answer this step does not have.
- Three-way comparison.
- Owning renewal pricing, tier pricing, or rebate rules. All three are supplied inputs ([`spec.md`](../spec.md) §3).

## 5. Acceptance criteria

- [ ] Interface, registry, and both CMDT fields deployed and in the permission set.
- [ ] `PRIOR_SNAPSHOT`: a quote regenerated after a quantity change produces rows showing before, after, and difference, and the difference column sums to the change in the quote's net amount.
- [ ] A product added since the baseline appears once with `Transaction_Type__c` = Added and no baseline amounts.
- [ ] A product removed appears once as Removed, with baseline amounts and no current amounts.
- [ ] An unchanged product appears with a zero difference by default.
- [ ] Two current lines matching one baseline line fails with `COMPARISON_MATCH_AMBIGUOUS` naming the key.
- [ ] `AMENDED_SUBSCRIPTION`: use case 5's example — 100 → 150 licenses plus a removed support package — produces exactly the documented three-row shape.
- [ ] A missing enrichment source fails with `ENRICHMENT_SOURCE_MISSING`; no code path prints a blank or substitutes the current price.
- [ ] A tier expansion consumes a supplied breakdown and its rows sum to the line's quoted amount; a test asserts the framework performs no tier arithmetic of its own.
- [ ] Changing the baseline snapshot moves the fingerprint even when the quote has not changed.
- [ ] The `CHANGE` table and a `PRIOR_SNAPSHOT` table generated on the same quote have their agreement — or documented disagreement — recorded.
- [ ] Existing suite passes untouched.

## 6. Verification method

```bash
sf apex run test --class-names QuoteDocumentComparisonTest --class-names QuoteDocumentGeneratorTest --class-names QuoteDocumentFingerprintTest --result-format human --wait 20
```

```sql
SELECT Product_Name__c, Transaction_Type__c, Quantity__c,
       Amount_Net__c, Amount_Net_Change__c, Amount_Final__c
FROM Quote_Document_Row__c
WHERE Quote_Document_Table__r.Quote__c = :quoteId
  AND Quote_Document_Table__r.Table_Code__c = 'REVISION_COMPARISON'
ORDER BY Display_Order__c
```

Pass: every product appears exactly once; added rows have no baseline amount; removed rows have no current amount; the difference column sums to the quote-level change.

New test class `QuoteDocumentComparisonTest`: `priorSnapshotProducesBeforeAfterDifference`, `addedProductHasNoBaseline`, `removedProductHasNoCurrent`, `unchangedProductShowsZeroDifference`, `ambiguousMatchFails`, `amendedSubscriptionMatchesTheWorkedExample`, `missingEnrichmentSourceFails`, `tierBreakdownIsConsumedNotRecomputed`, `baselineChangeMovesTheFingerprint`.

## 7. Close-out

- **Date:** 2026-08-28
- **Status: PARTIAL.** The comparison engine and one source shipped. `PRIOR_SNAPSHOT` turned out to be **impossible as specified**, and `AMENDED_SUBSCRIPTION` is untestable in this org. Both are recorded below rather than half-built.

### `PRIOR_SNAPSHOT` cannot work today — a planning error found in build

§3.2 said to build `PRIOR_SNAPSHOT` first because it "depends on nothing new". That was wrong. [`QuoteDocumentGenerator`](../../../force-app/main/default/classes/QuoteDocumentGenerator.cls) deletes **every** `Quote_Document_Table__c` for the quote before rebuilding, so by the time a comparison could read the previous snapshot it no longer exists. Comparing snapshots requires generation versioning — planned in [`specs/quote-docusign-totals/phases/phase-5-generation-versioning.md`](../../quote-docusign-totals/phases/phase-5-generation-versioning.md) and not built.

**`SOURCE_QUOTE` ships instead**, and answers the same use case (14) better: CPQ already records `SBQQ__Source__c` on a revision, so "what changed since the version we sent last week" needs no retention mechanism at all. It compares *quotes* rather than snapshots, which §4 had listed as out of scope on record-access grounds; the access answer is that the baseline is read `with sharing` and an unreadable source fails with `ENRICHMENT_SOURCE_MISSING` rather than printing an empty baseline. §4 is superseded on this point.

### Built

- `QuoteDocumentComparisonSource`, `QuoteDocumentComparison` (the engine), `QuoteDocumentSourceQuoteComparison`, `QuoteDocumentComparisonRegistry`, three CMDT fields, and the generator hook.
- **Four outcomes, each with its own test:** changed carries before/after/difference; added has no baseline; removed appears once with no current amount and a negative change; unchanged still gets a row with a zero difference, because a customer scanning for what moved is entitled to see what did not.
- **`Amount_Baseline__c` was needed.** §3.4 hoped the `CHANGE` set would carry the shape unchanged. It carries the difference (`Amount_Net_Change__c`) and the result (`Amount_Final__c`) but **not the starting point**, and recovering it as "after minus difference" is a subtraction no renderer may perform. One field, on the row and the table, added to the `CHANGE` measure set so subtotals come for free.
- **Two picklist values** on `Transaction_Type__c`: `Amended` and `Unchanged`. These are comparison outcomes, not CPQ amendment semantics — whether a position moved between two quotes is a different question from how CPQ classified the line, and the help text now says so.
- **Ambiguity fails**, as §3.3 requires: two lines sharing a match key on either side is `COMPARISON_MATCH_AMBIGUOUS`, naming both products. The default key is product + charge type + subscription window, because the same product on two terms is two positions.
- **The baseline lookup rides the existing dependency-path mechanism** rather than a new one — which means the *value* of `SBQQ__Source__c` is hashed, so re-pointing a revision at a different source quote moves the fingerprint. Nothing else would have noticed.
- **Comparison and expansion together are refused.** What one line's third period looked like on a baseline that may not contain that line has no agreed answer, and a money table is not the place to invent one.
- **A read-only quote query** was added: a baseline is read, never written, so locking it `FOR UPDATE` would block two quotes generating against the same source for no reason.

### Not built

- `PRIOR_SNAPSHOT` — blocked, above.
- ~~`AMENDED_SUBSCRIPTION`~~ — **built 2026-08-29** as `QuoteDocumentAmendmentComparison`. The earlier "no org here has the data" was **wrong**: `SBQQ__Subscription__c` exists and carries product, quantity, net price, charge type, dates and `SBQQ__RenewalPrice__c`. It stays **PROVISIONAL** — tested against constructed subscriptions, not a real CPQ amendment — and its class header says so.
- ~~§3.7's tier expansion and part-number mapping~~ — **both built 2026-08-29.** Tiers read CPQ's own `SBQQ__QuoteLineConsumptionSchedule__c` / `SBQQ__QuoteLineConsumptionRate__c` and are *consumed, never recomputed*; part numbers come from a new `Quote_Document_Product_Alias__mdt`.

**A bug in shipped code, found by building these.** `QuoteDocumentLine.fromSubscription` first set `quoteLineId` from the subscription. That reached `Quote_Line__c` on the row and the platform rejected it at insert — a quote-line lookup cannot hold a subscription Id. Fixed by separating `rowIdentity` (what makes a row key unique within its group) from `quoteLineId` (a real quote line, or nothing). Ordinary lines set both to the same value, so every existing row key is byte-identical.

**The tier design decision worth keeping.** Tier rows explain an amount; they do not recalculate it. The bands and rates are used as *weights* and the line's own quoted total is what gets divided — so the breakdown foots to what the customer pays even where CPQ applied a discount or override this expander knows nothing about. A breakdown that footed to a recomputed price would be a second opinion about the deal.
- The `CHANGE`-table agreement finding (§3.5): not established, because no quote in this org exercises both tables meaningfully.

### Use-case status after this step

Use case 14 (revision comparison) is **built and tested**. Use case 5 (amendment before/after) remains *enabled, needs its own implementation* — the engine is there and the matching is there; only the amendment-specific baseline is missing.

- **Test evidence:** `QuoteDocumentComparisonTest` 15/15. Full suite 464 ran, 459 passed, 5 failed — the five pre-existing org-only failures, unchanged.

- **Next step:** [`step-05-partitioning.md`](step-05-partitioning.md)

- **Next step:** [`step-05-partitioning.md`](step-05-partitioning.md)
