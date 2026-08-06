# Phase 6 — Automatic generation via platform event (gated, not scheduled)

**Status: NOT SCHEDULED — intentional**
**Blocked by:** `phase-1-classification-validation.md` AND `phase-2-concurrency-lock.md` must both be closed first (hard prerequisite, not a soft preference — see §3)
**Blocks:** nothing
**Owner decision needed:** yes, but only if/when the trigger condition fires

---

## 1. Goal (if triggered)

Replace the current on-demand ("press the button") generation flow with automatic regeneration triggered by a platform event, so a Quote's document tables are refreshed without a user action, while keeping the manual path available as a fallback.

## 2. Why this phase is gated rather than built

`docs/quote-document-totals.md` §4 already explains why on-demand generation was chosen deliberately: *"CPQ writes a quote several times during one calculation. Generating on every save would rebuild three to five times per user action and discard most of it... A blocked document beats a wrong one."* Nothing about that reasoning has changed. This phase exists because the pieces for automatic generation are already in place (staleness marking via `QuoteDocumentStaleness`, the skip-unless-stale `QuoteDocumentGenerateJob` one-argument constructor) — not because manual generation has become an actual problem yet.

## 3. Trigger condition, and the hard prerequisite

**Trigger:** manual generation is confirmed to be the actual operational bottleneck — reps forgetting to click "Generate," or a measured volume of quotes reaching DocuSign in a `Stale` state because nobody regenerated. Not scheduled until someone can point at that evidence.

**Hard prerequisite, not optional sequencing:** `phase-1-classification-validation.md` and `phase-2-concurrency-lock.md` must both close before this phase starts, for a specific reason — automatic generation is exactly the scenario that turns the Phase 2 concurrency gap from theoretical into real (a platform-event subscriber can legitimately fire more than once for the same Quote in quick succession), and it's also the point at which an unvalidated `TRANSACTION_SUMMARY` classification would start reaching real amendment quotes without a human in the loop double-checking the number before it's used. Building this first would mean shipping automation on top of two known, open risks.

## 4. Scope (if triggered)

1. Add `Quote_Document_Refresh_Requested__e` (`Quote_Id__c` Text(18), `Reason__c` Text(80)), published by `QuoteDocumentStaleness` alongside (not necessarily instead of) the current stale-marking.
2. Subscribe with a trigger that enqueues `new QuoteDocumentGenerateJob(quoteId)` — the existing one-argument, skip-unless-stale constructor already provides the debounce described in `docs/quote-document-totals.md` §4 ("If you later want fully automatic generation"); no new debounce logic needed.
3. Configure the platform-event subscriber batch size deliberately small (1–5 Quotes) per `research/2.md` §10, measure real row/CPU volume on a representative Quote, increase only if justified by measurement.
4. Keep the manual "Generate Document Tables" quick action working exactly as it does today — this is additive, not a replacement, per `research/3.md`'s general caution against removing an escape hatch when adding automation.

## 5. Out of scope

- Removing or hiding the manual generation path.
- Any change to when staleness itself is marked — that logic (`QuoteDocumentImpactDetector`-equivalent judgment of "does this change matter") already exists and is out of scope for this phase.
- Building this before its hard prerequisite phases close, under any circumstance, including "it's just the event and trigger, the risky part is elsewhere" — the point of the prerequisite is that automation changes *how often* the risky parts get exercised, not just whether new risky code is added.

## 6. Preconditions / dependencies

`phase-1-classification-validation.md` — closed. `phase-2-concurrency-lock.md` — closed. Both, not either.

## 7. Acceptance criteria (if triggered)

- [ ] Manual generation continues to work unchanged.
- [ ] Duplicate/closely-spaced platform events for the same Quote are harmless (proven by test, not assumed) — the skip-unless-stale constructor is the mechanism; a test should exercise two events arriving before the first job runs.
- [ ] Subscriber batch size is deliberately set (not left at the 2,000-event platform default) and justified by a measured row/CPU figure on a real Quote, per `research/2.md` §10's explicit warning against accepting the default blindly.
- [ ] A regression test confirms automatic generation doesn't fire for a save that doesn't actually affect document data (mirroring the existing staleness-trigger discipline already documented in `docs/quote-document-totals.md` §4).

## 8. Verification method (if triggered)

Deploy, assign any new permission-set grants for the platform event object, then trigger a real Quote Line edit and confirm (a) the platform event publishes, (b) the subscriber regenerates within an acceptable delay, (c) firing the same edit twice in quick succession produces one generation, not two.

## 9. Verification status

**Not applicable — not built.**

## 10. Close-out record

- **Date opened:** 2026-08-03
- **Status:** intentionally not scheduled. Re-evaluate only once both prerequisite phases are closed and there's real evidence of the trigger condition.
