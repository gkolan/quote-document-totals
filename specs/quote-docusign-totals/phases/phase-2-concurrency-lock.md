# Phase 2 — Lock the Quote row during generation

**Status: DONE — deployed and verified live on 2026-08-03, after fixing a real bug the first live test run caught.**
**Blocked by:** nothing
**Blocks:** nothing directly, but is a hard prerequisite before Phase 6 (automatic generation) is ever built — see `phase-6-automatic-generation.md` §5
**Owner decision needed:** no

---

## 1. Goal

Make it structurally impossible for two near-simultaneous generation requests against the same Quote to interleave into an inconsistent result, by acquiring a row lock on the Quote for the duration of `generateOne`.

## 2. Why this phase exists

Gap **G1** in `specs/quote-docusign-totals/spec.md` §3, sourced from `research/2.md` §12: *"Two events for the same Quote can still arrive close together... `FOR UPDATE` is specifically intended to prevent race conditions between transactions updating the same records."* Today this is low-probability (generation is a manual, single-user button click), but it is exactly the gap that becomes load-bearing the day automatic generation (Phase 6) ships — a platform-event subscriber can legitimately fire more than once for the same Quote in quick succession.

## 3. Scope

Add `FOR UPDATE` to the single query at the top of `QuoteDocumentGenerator.generateOne`'s call chain (`queryQuotes`), and add regression coverage proving the change doesn't break normal (single-transaction, sequential) generation.

## 4. Out of scope

- A true two-transaction concurrency test. Apex unit tests run in one transaction; a genuine race between two independent transactions cannot be constructed inside `QuoteDocumentGeneratorTest` — that would need an integration test against a real org (two parallel CLI/API calls), which is a manual verification step, not something committed to the test suite. See §9.
- Locking anything other than the Quote row. `Quote_Document_Table__c`/`Quote_Document_Row__c` are deleted and reinserted fresh every generation, not read-then-updated across transactions, so they don't need their own lock — the Quote row lock is sufficient to serialize the whole operation, since nothing else touches these child records outside `generateOne`.

## 5. Preconditions / dependencies

None.

## 6. Step-by-step tasks

1. Add `ORDER BY Id FOR UPDATE` to the SOQL in `QuoteDocumentGenerator.queryQuotes`, after the existing `WITH USER_MODE` clause (correct SOQL clause order: `WHERE … WITH … ORDER BY … FOR UPDATE`). — **Done.**
2. Document, in an inline comment at the query, exactly what the lock protects against and why `ORDER BY Id` matters (consistent lock-acquisition order across calls prevents a deadlock between two transactions each locking a different subset of the same Quotes in opposite order). — **Done.**
3. Add a named regression test confirming `FOR UPDATE` combined with `WITH USER_MODE` and the child subquery is valid SOQL that still generates correctly, and that calling `generate()` twice in one transaction (which now acquires and releases the lock twice) still replaces rather than accumulates. — **Done** (`generateSucceedsWithTheQuoteRowLocked`).
4. Note in this document, honestly, that step 3 cannot prove the lock actually prevents a cross-transaction race — only that it doesn't break anything. Real proof requires org access. — **Done, this section.**

## 7. Files touched

- `force-app/main/default/classes/QuoteDocumentGenerator.cls` — `queryQuotes`, one clause added, one comment added
- `force-app/main/default/classes/QuoteDocumentGeneratorTest.cls` — one new test, `generateSucceedsWithTheQuoteRowLocked`

## 8. Acceptance criteria

- [x] `FOR UPDATE` present in `queryQuotes`.
- [x] A named test exists proving generation still succeeds with the lock in place — **verified passing live**, 2026-08-03 (`generateSucceedsWithTheQuoteRowLocked`).
- [x] The query compiles and deploys against a real org — **verified**, after a correction (see below).
- [ ] **Still not verified:** a genuine two-transaction race is actually serialized rather than merely believed to be, per §4's stated limitation — needs the manual two-terminal check in §9, not attempted this pass.

### A real bug the live test run caught

The first version of this fix used `ORDER BY Id FOR UPDATE`, directly mirroring `research/2.md`'s own recommended syntax. Deploying and running the test suite against it failed **23 of 38 tests** with `System.QueryException: Explicit ORDER BY not allowed when locking rows (Id order is implied)` — Salesforce SOQL rejects an explicit `ORDER BY` combined with `FOR UPDATE`, because row-lock order is Id order automatically. Removed the explicit `ORDER BY Id`; the deadlock-avoidance property it was there for is preserved automatically, since that's exactly what "Id order is implied" means. Redeployed and reran: 38/38, then 51/51 once later phases' tests were added. This is exactly the class of error that can't be caught by reading the code or by research alone — it needed a real compiler and a real query planner, which is why this phase couldn't have been marked "verified" without live org access.

## 9. Verification method

```bash
sf project deploy start --target-org <alias> --source-dir force-app
sf apex run test --target-org <alias> --class-names QuoteDocumentGeneratorTest --result-format human --synchronous
```

For the concurrency claim specifically (manual, not part of the automated suite): from two separate terminal sessions authenticated to the same org, fire two `sf apex run` calls invoking `QuoteDocumentGenerator.generate` for the same Quote Id within roughly the same second, and confirm from debug logs that the second call's SOQL blocks until the first transaction commits (a `UNABLE_TO_LOCK_ROW` error would indicate the lock is active but the caller didn't wait — expected if using `Database.query` without retry logic; a clean sequential completion of both indicates the lock worked as intended).

## 10. Verification status (honest)

**Deployed and passing against a real org.** `sf project deploy start` succeeded; `sf apex run test` reported 51/51 passing (38 in the first run before later phases' tests were added, all subsequently re-confirmed together). The one thing still open is the manual two-terminal concurrent-access check described in §9 — not attempted this pass, since it requires deliberately timing two overlapping CLI calls and isn't part of the automated suite by design (per §4's own stated limitation).

## 11. Close-out record

- **Date:** 2026-08-03
- **What shipped:** `FOR UPDATE` lock added to `queryQuotes` (without an explicit `ORDER BY`, corrected after a live test failure); one new regression test, passing.
- **What's still open:** the manual cross-transaction race check in §9. Does not block close-out — the mechanism (`FOR UPDATE`) is deployed, compiles, and doesn't regress anything; only the "does it actually serialize two real transactions" claim remains unverified by direct observation, as scoped from the start.
- **Next phase:** `phase-3-atomicity-test.md`.
