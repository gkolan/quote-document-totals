# Phase 5 — Generation versioning and historical reproducibility (gated, not scheduled)

**Status: NOT SCHEDULED — this is intentional, not a stalled phase**
**Blocked by:** its own trigger condition, defined below, not by any other phase's completion
**Blocks:** nothing
**Owner decision needed:** yes, but only if/when the trigger condition fires

---

## 1. Goal (if triggered)

Let Salesforce data itself answer "what did this table look like before the last regeneration," by adding generation-key versioning (`Generation_Key__c`, `Is_Current__c`) so old generations are retained rather than deleted-and-replaced, instead of relying on the signed PDF as the only durable record.

## 2. Why this phase is gated rather than built

Gap **G2** in `specs/quote-docusign-totals/spec.md` §3. `research/1.md`'s own framing is explicit: this is *"acceptable when the signed PDF in CLM is the only required historical artifact"* — i.e., not a default requirement, a conditional one. Building it speculatively would be the exact mistake `research/3.md` and `research/4.md` both warned against elsewhere in this project (over-abstracting before there's a proven need). `QuoteDocumentRetention` already protects Accepted quotes from automatic purge, which covers most of the practical "don't lose the numbers behind a signed deal" concern without any new schema.

## 3. Trigger condition — either of these fires this phase

1. **`phase-3-atomicity-test.md` fails.** ~~If that phase's test proves a failed generation *can* leave the Quote in a mixed/inconsistent state under the current delete-and-reinsert design, that's a correctness problem versioning would fix, and this phase stops being optional.~~ **Resolved, 2026-08-03: this condition did not fire.** `phase-3-atomicity-test.md`'s test ran live against a real org and passed — the existing savepoint design already guarantees atomicity. This trigger is permanently closed unless the generation logic changes in a way that could reopen it (e.g., removing the single-savepoint-per-Quote structure).
2. **A real business requirement surfaces** to query a past generation's numbers from Salesforce data directly (not the signed PDF) — e.g., an audit request, a dispute over what a document said before an edit, or a reporting need that can't be satisfied by a PDF.

Condition 1 is now closed (see above). This phase remains unscheduled, gated on condition 2 only, until a real business need surfaces.

## 4. Scope (if triggered)

1. Add `Generation_Key__c` and `Is_Current__c` to `Quote_Document_Table__c`.
2. Change the table key from `QuoteId:TableCode` to `QuoteId:GenerationKey:TableCode`.
3. Change the generation sequence: build a full new set of tables/rows with `Is_Current__c = false`, validate everything, then flip current/non-current for the whole Quote in one final transaction — exactly as specified in `research/1.md`'s "Recommended publication model."
4. Extend `QuoteDocumentRetention` to purge non-current generations on the existing retention schedule, leaving the current generation subject to the existing Accepted-quote protection.
5. Update every SOQL query in `QuoteDocumentGenerator`, the reports, and any DocuSign Data Source mapping that currently assumes one table per `TableCode` per Quote, to filter on `Is_Current__c = true`.

## 5. Out of scope

- Building any part of this speculatively before the trigger condition fires. If someone is tempted to start this "since it seems useful," re-read `research/3.md`: *"The previous design was drifting into framework-building before you had proven you needed a framework."*
- Retaining every historical generation forever — retention policy (§4.4) still applies; this is about *querying* recent history, not permanent archival.

## 6. Preconditions / dependencies

`phase-3-atomicity-test.md` must resolve first (either outcome) so it's known whether condition 1 has fired.

## 7. Acceptance criteria (if triggered)

- [ ] `Table_Key__c` uniqueness holds under the new three-part key.
- [ ] Exactly one generation per Quote is ever `Is_Current__c = true` at a time — enforced in the same final transaction that flips the flag, per `research/1.md`'s publication model.
- [ ] Every existing report and DocuSign Data Source mapping is updated to filter on `Is_Current__c = true` — a regression here would silently show stale or duplicate data in a live document.
- [ ] Retention purges non-current generations without touching the current one or violating the existing Accepted-quote protection.

## 8. Verification method (if triggered)

Standard deploy + Apex test run, plus a manual check that a DocuSign Preview Data run against a Quote with more than one historical generation shows only the current one.

## 9. Verification status

**Not applicable — not built.** This document exists so the decision and its trigger condition are on record, not lost in a "Deferred" list nobody revisits.

## 10. Close-out record

- **Date opened:** 2026-08-03
- **Status:** intentionally not scheduled. Re-evaluate once `phase-3-atomicity-test.md` closes.
