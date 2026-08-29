# Step 06 — Docs, migration, and close-out

**Status: PLANNED**
**Blocked by:** every step that was actually built
**Blocks:** nothing

---

## 1. Goal

The capabilities are documented where the next person will look, `QuoteDocumentMonthlyRowCustomizer` is migrated onto the shared seam or explicitly kept as it is with a reason, and the series states honestly what was built and what was dropped.

## 2. Why this step exists

Five new extension points that only exist in spec files are five new ways for the next author to reinvent them. And the monthly customizer is the test of whether the seam is real: if the one expansion that already works cannot be expressed through the generalization built for it, the generalization is wrong and this step is where that gets admitted rather than buried.

## 3. Scope

### 3.1 Migrate the monthly customizer, or justify not doing it

Rewrite `MONTHLY_SUBSCRIPTION` as a `PERIOD` expander (`Period_Months__c = 1`) plus an `EVEN` allocation, and delete the row-building code the builder now does.

The bar is exact: **the migrated table must produce a byte-identical snapshot** — same rows, same order, same labels, same amounts, same payload hash — on the same quotes its current tests cover. Anything less is a behaviour change shipped under the word "refactor".

If it cannot, do not force it. Record which rule resisted (the conditional `Note`, the anniversary bucketing, the exclusion handling), keep the customizer, and correct the generalization claim in [`spec.md`](../spec.md) §2. A seam that covers four of five expansions and says so is more useful than one that claims five.

### 3.2 Documentation

| Document | Addition |
|---|---|
| [`docs/quote-document-totals.md`](../../../docs/quote-document-totals.md) | A section on the row-production stage: the five capabilities, and where each sits in the pipeline diagram. |
| [`docs/quote-document-extension-recipes.md`](../../../docs/quote-document-extension-recipes.md) | One copyable recipe per built capability, plus every new error code in the catalogue. |
| [`docs/quote-document-totals-architecture-guide.md`](../../../docs/quote-document-totals-architecture-guide.md) | Plain-language explanation for an admin: what expansion and allocation mean, and the one thing they must get right — that money split across rows still adds up to what the customer pays. |
| A guide per shipped table, to [`docs/documentation-standards.md`](../../../docs/documentation-standards.md) | Applied automatically, as that standard requires. |

Three sentences that must appear verbatim somewhere in the admin-facing docs, because each is a place this framework will otherwise be misread:

- An installment table states the agreed schedule. It does not track payments, and nothing in it changes when money arrives.
- A consumption scenario is an estimate. Its assumptions are printed with it and are part of the document, not a footnote that can be dropped.
- A shortfall against a minimum commitment is a gap, not a charge. It is never added to any total.

### 3.3 Series close-out

In [`spec.md`](../spec.md) §6, mark each step BUILT / PARTIAL / DROPPED with a one-line reason. A dropped step needs no apology — [`spec.md`](../spec.md) §4 says explicitly to stop after any step that turns out to be enough — but it does need to be marked, so the next reader does not assume it exists.

Re-walk the 19-row traceability table in §3 and mark each use case Covered / Partially covered / Not built. A use case listed against a built step but never actually exercised by a test is **not** covered, and saying so is the entire point of this section.

## 4. Out of scope

- New capability. If something is missing, it is a new step, not an addendum here.
- Rewriting the render contract docs. Nothing in this spec changes what a renderer sees; if it did, that was a defect in the step that caused it.

## 5. Acceptance criteria

- [ ] The monthly table is migrated with a byte-identical payload hash on its existing test quotes, or the resisting rule is named and `spec.md` §2 is corrected.
- [ ] Every built capability has a working, copyable recipe that a developer can follow without reading generator internals.
- [ ] Every new error code is in the catalogue.
- [ ] The three verbatim sentences appear in the admin guide.
- [ ] Every shipped table has a guide meeting `docs/documentation-standards.md`.
- [ ] `spec.md` §6 marks every step, and §3 marks every use case, with test evidence named for each Covered claim.
- [ ] Full suite green; measured coverage recorded, not estimated.

## 6. Verification method

```bash
sf apex run test --result-format human --code-coverage --wait 30
```

Payload-identity check for the migration, run before and after on the same quote:

```sql
SELECT Document_Payload_Hash__c, Document_Data_Fingerprint__c
FROM SBQQ__Quote__c WHERE Id = :quoteId
```

Pass: the payload hash is unchanged across the migration. A changed fingerprint is expected — the configuration changed — but a changed payload hash means the rows changed, and §3.1's bar is not met.

Documentation check:

```bash
grep -rn "does not track payments\|assumptions are printed\|gap, not a charge" docs/
```

Pass: all three found.

## 7. Close-out

*(To be filled: migration outcome, final status of every step and use case, coverage figures, and anything the series learned that contradicts its own §1 framing.)*
