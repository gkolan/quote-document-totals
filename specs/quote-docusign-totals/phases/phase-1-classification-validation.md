# Phase 1 — Validate transaction classification against real amendment data, and settle the revenue-taxonomy question

**Status: BLOCKED — narrowed 2026-08-06. The code change is *not* applied; `classify()` still has its original five branches (an earlier version of this line claimed otherwise and was wrong — §10 was correct).**
**Blocked by:** originally two things. Reassessed 2026-08-06:
- ~~(a) a Salesforce org/CLI connection~~ — **resolved.** `sf` is installed and authenticated; `gkCpqDevHub` (Developer Edition) is connected, and the full suite runs against it (78 passing).
- (b) a real amendment/renewal quote — **still true.** The org holds 62 quotes, all `SBQQ__Type__c = 'Quote'`, and exactly one line with `SBQQ__Existing__c = true`. No amendment or renewal quote exists.

**What the resolved half changes:** §10's reasoning for not applying the remap was "no way to run or verify it." That no longer holds — a check-only deploy with `RunLocalTests` now verifies any change to `classify()` before it touches the org. What remains blocked is *validation against real amendment data*, which is a different and weaker claim than the original status implied.

**One acceptance criterion may be unreachable by test data alone.** `QuoteDocumentGeneratorTest` records that the Termination branch (existing line, negative Net Total) cannot be reached by any hand-built fixture: `SBQQ__NetTotal__c` is a managed-package formula field that cannot be assigned, and CPQ will not store a negative Net Total from a negative Net Price on a plain quote. Under the §4 remap this branch merges into Churn, so the remap would *remove* a branch that is currently untestable here — an argument for it independent of taxonomy vocabulary. Worth weighing in §3's decision.
**Blocks:** nothing else in this spec — no other phase depends on Phase 1 finishing, but no table using `CHANGE` measures (`TRANSACTION_SUMMARY`) should be trusted on a real amendment quote until this closes
**Owner decision needed:** yes — see §3. Made the call below (adopt the standard taxonomy) so work could proceed; flagged clearly so it's easy to override.

---

## 1. Goal

Turn `QuoteDocumentLine.classify()` from "provisional, never validated against real data" into either (a) confirmed correct against a real amendment quote, or (b) fixed and then confirmed — before any document built from `TRANSACTION_SUMMARY` is trusted on an amendment/renewal deal. Settle, at the same time, whether the five current branches should be remapped onto the industry-standard six-category ARR taxonomy (New, Expansion, Renewal, Contraction, Churn, Resurrected).

## 2. Why this phase exists

This is gap **G5** in `specs/quote-docusign-totals/spec.md` §3 — the single highest-consequence open item in the whole framework, because a wrong classification puts a wrong number on a signed, legally binding document. `docs/quote-document-totals.md` §3 already states this plainly: *"It has never been validated against real data, because `gkCPQDev` contains no amendment or renewal quotes."* The revenue-taxonomy question was raised directly in conversation and is folded in here rather than scheduled separately, because it touches the exact same method and the exact same test fixtures — deciding it later would mean re-opening `classify()` a second time for one decision that could have been made once.

## 3. The decision that had to be made to keep moving

**Question:** should `Transaction_Type__c` speak the current five categories (*Net New, Cancellation, Replacement Removed, Replacement Added, Termination*) or be remapped onto the standard six-category SaaS ARR taxonomy (*New, Expansion, Renewal, Contraction, Churn, Resurrected*)?

**This is a real business decision** — finance/RevOps teams often have a specific, already-reported-on taxonomy they expect a document to match, and guessing wrong means relabeling later after someone's built a report against the wrong category names.

**Call made to keep this phase moving:** adopt the standard six-category taxonomy, because (a) it's the industry-standard vocabulary a finance stakeholder is likely to already use, (b) the current five categories are visibly incomplete against it — there's no `Renewal` bucket at all, and a renewed subscription (`SBQQ__RenewedSubscription__c` populated) currently gets folded into Replacement Added/Removed instead of being labeled Renewal, and (c) `classify()` was already going to be touched and re-tested in this phase regardless, so the marginal cost of remapping now is near zero compared to doing it as a second pass later.

**This is easy to override.** If the real answer turns out to be "keep the current five, finance doesn't use ARR-standard terms," the fix is confined to `QuoteDocumentLine.classify()`, `QuoteDocumentTableDefinition`'s picklist-equivalent values, and the tests added in this phase — nothing elsewhere in the framework references transaction-type category names directly.

## 4. Scope

1. Remap `classify()`'s branches onto: **New** (net-new business, no `SBQQ__Existing__c`, no replacement pair), **Expansion** (a replacement pair where the added side is larger — an upgrade), **Renewal** (`SBQQ__RenewedSubscription__c` populated, value roughly unchanged), **Contraction** (a replacement pair where the added side is smaller — a downgrade, or an existing line reduced but not to zero), **Churn** (existing line reduced to zero — replaces both the old `Cancellation` and `Termination` labels, which were two names for variants of the same underlying event), **Resurrected** (out of scope for v1 — nothing in the current CPQ field set distinguishes "this new line is a customer who previously churned" from ordinary New business; flagged as a known limitation, not silently ignored).
2. Preserve the existing sign and value-source logic exactly (prior-quantity-at-current-price for the leaving side of a replacement or a churn) — only the category labels and the New/Expansion/Contraction split are new; the arithmetic that was already correct stays correct.
3. Build one real amendment quote scenario (upgrade, downgrade, renewal-at-same-value, cancellation-to-zero) and hand-verify every branch.
4. Add named test coverage for each branch, replacing/extending the existing three classification tests.
5. Update `docs/quote-document-totals.md` §3 with a dated verification note (or a record of what was found wrong).

## 5. Preconditions / dependencies

None from other phases. Genuinely dependent on org/CLI access to execute and hand-verify — not available in this working environment.

## 6. Step-by-step tasks

1. ~~Confirm the taxonomy question with finance/RevOps~~ — decision made per §3 above; revisit if the org's stakeholders say otherwise.
2. Update `QuoteDocumentLine.classify()`: rename/remap the five branches to the six above, add the Expansion-vs-Contraction sign comparison on replacement pairs, merge Cancellation+Termination into Churn.
3. Update `QuoteDocumentRowBuilder.Measures` and `QuoteDocumentGenerator.measureFields()` field lists if the measure field API names change (recommend keeping `Amount_Cancellation__c`/`Amount_Termination__c` API names as-is even if the display category changes, to avoid a field rename after `docs/quote-document-totals.md` §7's own warning: *"Never rename or delete a field a DocuSign template references... additive changes only"* — add new measure fields for Expansion/Contraction/Renewal rather than renaming existing ones, if a template may already exist against the current names).
4. Build a scratch-org script creating one amendment scenario per category, added to `scripts/scratch-org-bootstrap.sh`.
5. Run `QuoteDocumentGenerator.generate` against it; hand-verify every row.
6. Add/extend tests in `QuoteDocumentGeneratorTest.cls` — one assertion per category, named by category.
7. Update `docs/quote-document-totals.md` §3.
8. Do not let `TRANSACTION_SUMMARY` (or any future table using `CHANGE` measures) be presented as trustworthy for a real amendment quote until step 5 passes.

## 7. Files touched (planned; not yet executed pending org access)

- `force-app/main/default/classes/QuoteDocumentLine.cls` — `classify()`
- `force-app/main/default/classes/QuoteDocumentRowBuilder.cls` — `Measures` (only if new fields are added, per §6.3)
- `force-app/main/default/classes/QuoteDocumentGeneratorTest.cls` — new/updated tests
- `force-app/main/default/objects/Quote_Document_Row__c/fields/Transaction_Type__c.field-meta.xml` — picklist values, if changed
- `scripts/apex/*` — new amendment-scenario script
- `docs/quote-document-totals.md` §3

## 7a. Progress — 2026-08-06

Step §6.4's scenario is built, as an Apex fixture rather than org data (test data rolls back, so it costs nothing to keep and mutates no shared org): `handBuiltAmendmentProducesEveryReachableClassification` in `QuoteDocumentGeneratorTest`. It drives an amendment quote of its own through an injected CHANGE definition grouped by transaction type.

| Branch | Covered | Value asserted |
|---|---|---|
| Net New | yes | present as its own subtotal |
| Cancellation | yes | −500 — prior quantity at current price, not the line's own zero total |
| Replacement Removed | yes | −200 — prior quantity at current price |
| Replacement Added | yes | present, positive |
| Termination | **no — unreachable** | no fixture can produce it (see the note in the header) |

Also added: `aRenewalCurrentlyHasNoBranchOfItsOwn`, asserting that a line with `SBQQ__RenewedSubscription__c` populated currently classifies as **Replacement Added**. That is recorded as current behaviour, not endorsed — it is the concrete gap §3's six-category taxonomy would close, and is the clearest evidence available for that decision.

**This does not satisfy §8.** These are the branches `classify()` is *written* to produce, so agreement proves the arithmetic is self-consistent, not that the rules match what CPQ emits on a genuine amendment. §8 still requires a real amendment quote. What the fixture buys is that the scenario data now exists under either taxonomy, so the remap becomes a one-pass change with reconciliation already asserted.

Verified: `RunLocalTests` against `gkCpqDevHub` — 80 passing, 0 failing.

## 8. Acceptance criteria

- [ ] Every category (New, Expansion, Renewal, Contraction, Churn) is hit by at least one line in a real (or realistically hand-built) amendment quote and produces the expected `Transaction_Type__c` and signed measure.
- [ ] Existing sign/value-source correctness (prior-quantity-at-current-price) is preserved — no regression on the two `docs/quote-document-totals.md` §3 traps already documented (a cancelled line's own Net Total is zero; CPQ won't store a negative Net Total from a negative Net Price).
- [ ] Named tests exist for each category, not just the three current ones (`transactionSummaryClassifiesNewBusinessAsNetNew`, `cancellationIsValuedFromPriorQuantityAndStoredNegative`, `replacementPairIsClassifiedBySign`).
- [ ] `docs/quote-document-totals.md` §3 updated from "PROVISIONAL, never validated" to a dated, honest verification note.
- [ ] Resurrected is explicitly documented as unsupported in v1, with the reason (no field distinguishes a returning churned customer from new business), not silently dropped.

## 9. Verification method

```bash
sf apex run --target-org <alias> --file scripts/apex/<new-amendment-scenario-script>.apex
sf apex run test --target-org <alias> --class-names QuoteDocumentGeneratorTest --result-format human --synchronous
```
Hand-check each classified row against the scenario script's own expected values before trusting the test suite alone — this is the one place in the framework where a passing test and a correct document are not automatically the same claim, precisely because the test data itself has never been checked against a real amendment.

## 10. Verification status (honest)

**Not started at the code level. Reassessed 2026-08-06 — the original reason no longer applies, but a new one does.**

The original reason was "no way to run or verify it." Org access now exists, so that reason is void. `classify()` is still unchanged, and the taxonomy *decision* in §3 remains made-but-unconfirmed.

**The remaining reason not to apply it is the decision itself, not the tooling.** §3 adopted the six-category ARR taxonomy explicitly "to keep moving," flagged as needing finance/RevOps confirmation. Applying it now would mean:

- new measure fields for Expansion / Contraction / Renewal across two objects, the permission set, and the report type (§6.3 forbids renaming the existing `Amount_Cancellation__c` / `Amount_Termination__c`, so this is additive schema, not a relabel);
- picklist changes to `Transaction_Type__c`;
- a category vocabulary printed on signed documents.

That is a large, schema-touching change built on an unconfirmed business decision — cheap to write, expensive to reverse once a report or template is built against the new field names. The gate is now a stakeholder answer, not org access.

**Recommended sequencing:** get the §3 taxonomy confirmed or overridden first, then implement and validate in one pass. Building the amendment fixture before that answer is safe and useful — the scenario data is needed under either taxonomy — but `classify()` itself should not be remapped until the vocabulary is settled.

The four tables consuming `CHANGE` measures are all `Is_Active__c = false` as of 2026-08-06, so nothing publishes provisional classification while this stays open.

## 11. Close-out record

- **Date opened:** 2026-08-03
- **Decision recorded:** adopt standard six-category ARR taxonomy (§3), pending override from finance/RevOps.
- **Implementation status:** not applied — see §10.
- **Next phase:** independent of this one; `phase-2-concurrency-lock.md` and `phase-3-atomicity-test.md` do not depend on Phase 1 and can close first.
