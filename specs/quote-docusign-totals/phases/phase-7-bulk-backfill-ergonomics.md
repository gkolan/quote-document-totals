# Phase 7 — Bulk backfill ergonomics (gated, low priority, not scheduled)

**Status: NOT SCHEDULED — intentional, low priority**
**Blocked by:** nothing
**Blocks:** nothing
**Owner decision needed:** no

---

## 1. Goal (if triggered)

Remove the need to manually re-run `scripts/apex/quote-document-backfill.apex` until it reports zero remaining, by having it auto-requeue itself when it hits the 50-Queueable-job synchronous-context cap.

## 2. Why this phase is gated rather than built

Gap **G6** in `specs/quote-docusign-totals/spec.md` §3. This is purely an operational-convenience item, not a correctness or safety gap — `generateAsync` already scales correctly per-Quote (`docs/quote-document-totals.md` §6), the cap is a known, documented Salesforce platform limit, and the existing workaround (re-run the script) is a one-line command, not a real burden at current data volume.

## 3. Trigger condition

Backfill volume grows past a few hundred Quotes such that manual re-running becomes a recurring operational task rather than a one-time migration step. No evidence this has happened; not scheduled until it does.

## 4. Scope (if triggered)

Modify `scripts/apex/quote-document-backfill.apex` (or wrap it in a small Batchable/Schedulable) so that when it queues its 50th job in a synchronous context, it schedules a follow-up run rather than exiting and requiring a human to notice and re-invoke it.

## 5. Out of scope

- Changing `generateAsync`'s per-Quote transaction model — that part already scales correctly and is not the bottleneck.
- Any change to the backfill's selection query (quotes with lines and no tables) or its use of the skip-unless-stale one-argument `QuoteDocumentGenerateJob` constructor — both already correct per `docs/quote-document-totals.md` §6.

## 6. Preconditions / dependencies

None.

## 7. Acceptance criteria (if triggered)

- [ ] Running the script once against a backlog larger than 50 Quotes fully completes without manual re-invocation.
- [ ] No duplicate generation occurs across the auto-requeued runs (the existing skip-unless-stale constructor already provides this guarantee; a test should confirm the requeue mechanism doesn't bypass it).

## 8. Verification method (if triggered)

Run against a seeded backlog of 120+ Quotes with no existing tables; confirm all are generated without a second manual invocation, and confirm `SELECT COUNT()` on Quotes with `Document_Data_Status__c` other than `'Ready'` reaches zero.

## 9. Verification status

**Not applicable — not built.**

## 10. Close-out record

- **Date opened:** 2026-08-03
- **Status:** intentionally not scheduled — lowest priority of all eight phases, revisit only if backfill becomes a recurring pain point.
