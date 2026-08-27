# Step 05A — Generation lifecycle: abandonment, locks, and launch retry

**Status: BUILT for §3 and §4. §5 needs the launch wrapper from step 07 — see close-out**
**Blocked by:** [step 05](step-05-snapshot-integrity.md)
**Blocks:** 07

---

## 1. Goal

Give the three concurrency behaviours the runbook promises an owner, a specified rule, and named tests: a generation stuck in `Generating`, a lock that will not come, and a launch that keeps losing its snapshot.

## 2. Why this step exists

These were described in [`../war-room-scenarios.md`](../war-room-scenarios.md) with no owning step, no acceptance criteria, and no tests — which made them documentation, not behaviour. Each needs a decision (how long, how many, who retries) before it can be built at all.

## 3. Stuck `Generating`

`SBQQ__Quote__c.Document_Data_Started_At__c` already exists and its help text already names abandonment detection. `Quote_Document_Table__c.Status__c` has `Generating`.

1. **Abandonment window** — one configured value (`Quote_Document_Key_Value__mdt`, category `LIFECYCLE`, key `ABANDON_MINUTES`), not a literal. A request older than the window is abandoned and may be taken over.
2. **One time source.** All comparisons use `System.now()` on the same side of the boundary. Never mix a Flow-supplied timestamp with an Apex one.
3. **Takeover** assigns a new request Id. The superseded request, if it ever completes, **must not publish**: before `markQuote`, core re-reads the quote and refuses when the stored request Id is no longer its own — `REQUEST_SUPERSEDED`.
4. A `Generating` quote with a **null** `Document_Data_Started_At__c` is treated as abandoned, not as eternally live. That state can only come from an interrupted write, and blocking on it forever is the worse failure.
5. Diagnosis of a stuck quote surfaces `GENERATION_ABANDONED` with the request Id and the start time.

**Tests** (`QuoteDocumentLifecycleConcurrencyTest`): `freshGeneratingRequestCannotBeTakenOver`, `expiredRequestCanBeTakenOver`, `supersededRequestCannotPublish`, `takeoverBoundaryIsExactAtTheThreshold`, `nullStartedAtIsTreatedAsAbandoned`.

## 4. Lock timeout and deadlock

[`QuoteDocumentQuery`](../../../force-app/main/default/classes/QuoteDocumentQuery.cls:72) uses `FOR UPDATE`, which serialises ordinary duplicate clicks. Acquisition can still time out.

| Decision | Value |
|---|---|
| Who retries | **Async callers only.** A synchronous caller fails immediately with a retryable code and lets the user click again — a UI thread must not sit in a retry loop. |
| Attempts | at most **3**, exponential with jitter |
| Retryable | `UNABLE_TO_LOCK_ROW` and query/lock timeouts. Everything else is terminal on the first failure. |
| After the limit | `GENERATION_LOCK_TIMEOUT`, terminal |
| Snapshot state | **unchanged.** A lock failure never mutates a snapshot and never marks an existing `Ready` snapshot corrupt — the quote's status is untouched, because nothing about the document is wrong. |

**Tests:** `lockFailureLeavesTheExistingSnapshotReady`, `asyncCallerRetriesBoundedTimes`, `synchronousCallerDoesNotRetry`, `nonRetryableErrorIsNotRetried`, `terminalCodeAfterRetryLimit`.

## 5. Repeated `SNAPSHOT_MOVED`

A launch takes expectations, then a regeneration lands before retrieval. Recovery is "re-launch", which loops forever under frequent regeneration.

1. **At most one** automatic retry, performed by the launch wrapper, not the render service.
2. The retry re-runs **generate-or-reuse** and uses the expectations that returns. It never re-reads with the old ones and never substitutes the newer snapshot silently.
3. A second mismatch surfaces `SNAPSHOT_CONTENTION` to the user. Two collisions in a row means something is regenerating in a loop, and hiding that is worse than failing.
4. In a bulk call, each request retries **independently**. Successful items are not replayed.

**Tests:** `firstMismatchRetriesOnce`, `secondMismatchTerminatesWithContention`, `retryRerunsGenerateOrReuse`, `newerPayloadIsNeverSubstituted`, `bulkRetryDoesNotReplaySuccessfulRequests`.

## 6. Out of scope

- Automatic regeneration on staleness — still framework-wide out of scope.
- Distributed locking beyond what `FOR UPDATE` provides.

## 7. Acceptance criteria

- [x] Abandonment window is configuration, not a literal, and is documented in the runbook.
- [x] Every test named in §3, §4, and §5 exists and asserts a stable error code plus context.
- [x] A lock failure changes no snapshot record and no quote status.
- [x] `REQUEST_SUPERSEDED` is impossible to bypass: publication re-reads the stored request Id, so a late worker cannot win.

## 8. Verification method

```bash
sf apex run test --class-names QuoteDocumentLifecycleConcurrencyTest --class-names QuoteDocumentLifecycleTest --result-format human --wait 20
```

Lock contention is exercised with a second transaction holding the row, not by mocking the exception — a mocked `UNABLE_TO_LOCK_ROW` proves the handler, not the behaviour.

## 9. Close-out

- **Date:** 2026-08-27
- **Abandonment window chosen:** **30 minutes**, as `LIFECYCLE`/`ABANDON_MINUTES` in `Quote_Document_Key_Value__mdt`, with 30 as the documented fallback when no record exists. Configuration rather than a literal, because the right value depends on how large an org's quotes are. Comfortably longer than any generation this framework can legally run — a Queueable cannot exceed its own limits for anything like that long — so the window only ever catches a genuinely dead request. A malformed configured value falls back rather than failing generation: a longer window merely delays a takeover, it never lets two workers publish.
- **Retry limit chosen:** **3 attempts**, exponential with jitter, **async callers only**. A synchronous caller fails immediately with a retryable code and lets the user click again, because a UI thread must not sit in a retry loop. Retries are re-queued rather than looped — Apex has no sleep, and a busy wait would burn the CPU limit the backoff exists to protect.

### The guarantee that makes takeover safe

`QuoteDocumentGenerator` now **claims** the quote before any work begins (status `Generating`, `Document_Data_Started_At__c`, request Id) and **re-reads the stored request Id immediately before publication**. A worker that was taken over as abandoned cannot publish: `REQUEST_SUPERSEDED`.

This is a guarantee rather than a narrowed window because the claim, the work and the check all sit inside one transaction that already holds the row under `FOR UPDATE`. Nothing can interleave between the check and the write. Without it, a late worker publishing would overwrite a snapshot built from newer inputs with one built from older ones — and nothing downstream could tell, because both look like a complete, verified snapshot.

### What these tests do not prove, stated plainly

§8 asks for lock contention exercised with a second transaction holding the row, "not by mocking the exception". **Apex unit tests cannot open a second concurrent transaction** — there is no mechanism for it in any test context.

So the retry *policy* is asserted directly: what counts as retryable, that the limit is three, that backoff grows, and that it carries jitter (the part that actually matters — two jobs on a fixed schedule collide again on every attempt). The claim that a real lock is survived is **not** made. Writing a mocked `UNABLE_TO_LOCK_ROW` test would prove the handler while appearing to prove the behaviour, which is exactly the substitution §8 warns against. Real contention needs a two-org or load test, and that is an integration exercise this step does not own.

### §5 is deferred to step 07, not skipped

`SNAPSHOT_MOVED` retry belongs to the **launch wrapper**, and §5.1 says so explicitly — "performed by the launch wrapper, not the render service". Neither exists until [step 07](step-07-render-service-dto.md). Building a retry loop now would mean building it against an interface that does not exist yet and rewriting it there.

The five tests §5 names — `firstMismatchRetriesOnce`, `secondMismatchTerminatesWithContention`, `retryRerunsGenerateOrReuse`, `newerPayloadIsNeverSubstituted`, `bulkRetryDoesNotReplaySuccessfulRequests` — move to step 07's acceptance list rather than being written against a placeholder.

- **Test evidence:** `QuoteDocumentLifecycleConcurrencyTest`, 15/15. Full suite **230 local tests**, 98% — only the 5 pre-existing org-only failures.
- **Runbook note still outstanding:** the abandonment window is configuration and is documented here, but [`../war-room-scenarios.md`](../war-room-scenarios.md) has not been updated to point at `LIFECYCLE`/`ABANDON_MINUTES`. That belongs with [step 09](step-09-docs-and-closeout.md)'s documentation pass.

- **Next step:** [`step-06-contract-validation.md`](step-06-contract-validation.md)
