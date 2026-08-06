# Phase 3 — Prove a failed generation leaves the previous complete state untouched

**Status: DONE — the guarantee is CONFIRMED. Verified live on 2026-08-03: the test passes. Atomicity holds under the current delete-and-reinsert design; Phase 5's versioning work is not triggered by this result.**
**Blocked by:** nothing
**Blocks:** `phase-5-generation-versioning.md` — its trigger condition is explicitly "this phase's test fails against the current design"
**Owner decision needed:** no

---

## 1. Goal

Turn an implied guarantee (the existing savepoint pattern *should* mean a failed generation leaves prior tables untouched) into a proven one, with a named test — before deciding whether the versioning work in Phase 5 is actually necessary.

## 2. Why this phase exists

Gap **G3** in `specs/quote-docusign-totals/spec.md` §3, sourced from `research/1.md`'s "Quote-level consistency" concern: with multiple tables, a partial failure could in principle leave CLM reading a mix of generations. Reading `QuoteDocumentGenerator.generateOne` directly (`force-app/main/default/classes/QuoteDocumentGenerator.cls` lines 130–205) shows the design already appears correct: one `Savepoint` is taken before the `delete [SELECT Id FROM Quote_Document_Table__c ...]`, and every subsequent step (insert tables, insert rows, stamp measures, `verify()`, mark the Quote `Ready`) happens inside the same `try` block. Any exception — including `verify()` throwing on a reconciliation mismatch — is caught and triggers `Database.rollback(sp)`, which undoes the delete along with everything after it. **This means the concern G3 describes may already be fully resolved by the existing structure, and this phase might be "write the proof," not "fix a bug."** That distinction matters enough to warrant its own phase rather than being asserted without a test.

## 3. Scope

One named test that: seeds a Quote with a successful first generation (real, complete tables/rows persisted), then forces a second generation attempt to fail partway through, then asserts the Quote's tables/rows are **identical** to the first generation's — not merely "still marked Complete," but byte-for-byte the same records (same `Row_Count__c`, same measure values, same `Generated_On__c` timestamp — proving nothing was touched, not just that nothing looks wrong).

## 4. Out of scope

- Any production code change. This phase is verification-only unless the test reveals the guarantee doesn't actually hold, in which case the fix becomes an unplanned addition to this same phase (see §8, last bullet) rather than silently rolling into Phase 5.
- Testing a failure during the *first ever* generation for a Quote (no prior state to preserve) — that path already has coverage via the existing `Status__c = 'Failed'` assertions referenced in `docs/quote-document-totals.md` §4.

## 5. Preconditions / dependencies

None.

## 6. Step-by-step tasks

1. ~~In `QuoteDocumentGeneratorTest`, generate successfully once...~~ — **Done.**
2. ~~Force a second generation attempt on the same Quote to fail partway through...~~ — **Done**, using `QuoteDocumentTableDefinition.build()` + `useDefinitions()` to inject a single definition with `maxGroups = 1` against a dimension (`SBQQ__Product__r.Name`) guaranteed to produce more than one group from the test fixture's five distinct products — `QuoteDocumentRowBuilder.build` throws inside `generateOne`'s per-definition loop, after `delete` has already executed and before any reinsert.
3. ~~Call `QuoteDocumentGenerator.generate` again and assert it throws...~~ — **Done.**
4. ~~Re-query and assert every captured value is unchanged...~~ — **Done**, and strengthened beyond the original plan: the test asserts the **same record Ids** before and after, not just equivalent values — proving the rollback restored the exact prior rows rather than the test happening to reconstruct matching numbers by coincidence.
5. Assert `Document_Data_Status__c = 'Failed'` with `Document_Data_Error__c` populated — **not added in this pass**; the test as written proves the data-untouched claim, which was this phase's specific goal, but doesn't yet also assert the failure-surfacing side. Low-risk, cheap follow-up if reopened.
6. If the test fails when actually run (the guarantee doesn't hold), escalate to `phase-5-generation-versioning.md` — **still the plan; unknown until run.**

Test name: `aFailedRegenerationLeavesThePreviousCompleteTablesUntouched`, in `QuoteDocumentGeneratorTest.cls`.

## 7. Files touched (planned)

- `force-app/main/default/classes/QuoteDocumentGeneratorTest.cls` — one new test, proposed name `aFailedRegenerationLeavesThePreviousCompleteTablesUntouched`

## 8. Acceptance criteria

- [x] Named test exists and, when run: **outcome (a) — it passes.** Every captured field (`Id`, `Row_Count__c`, `Amount_Net__c`, `Generated_On__c`) on every prior table matched exactly after the forced failure, proving the savepoint restores the exact prior records, not merely equivalent-looking new ones. This phase closes with **atomicity confirmed, no further work needed.**
- [x] Outcome recorded honestly in this document's close-out (§11).

## 9. Verification method

```bash
sf apex run test --target-org <alias> --class-names QuoteDocumentGeneratorTest --result-format human --synchronous
```

## 10. Verification status (honest)

**Verified live**, 2026-08-03, against `act.gkolan@gmail.com`. `sf apex run test --class-names QuoteDocumentGeneratorTest` reported `aFailedRegenerationLeavesThePreviousCompleteTablesUntouched` as `Pass`, alongside 50 other passing tests, 0 failures. The question this phase exists to answer is now answered, not just hypothesized: **the existing savepoint-per-Quote design in `generateOne` already provides full atomicity.** A failure partway through generation — after the delete, before any reinsert — leaves the prior complete tables and rows exactly as they were, same record Ids included.

## 11. Close-out record

- **Date:** 2026-08-03
- **What shipped:** `aFailedRegenerationLeavesThePreviousCompleteTablesUntouched` in `QuoteDocumentGeneratorTest.cls` — passing.
- **Result:** Atomicity confirmed. `phase-5-generation-versioning.md`'s first trigger condition ("this test fails") did not fire — that phase remains gated on its second condition only (a real business need to query historical generations from Salesforce data, not the signed PDF).
- **Optional follow-up, not blocking:** the `Failed`/`Document_Data_Error__c` surfacing assertion from step 5 above was not added — the core claim this phase exists to prove is already proven.
- **Next phase:** `phase-4-test-matrix-reconciliation.md` (independent of this one).
