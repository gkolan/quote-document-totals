# Step 05A — Generation lifecycle: abandonment, locks, and launch retry

**Status: PLANNED**
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

- [ ] Abandonment window is configuration, not a literal, and is documented in the runbook.
- [ ] Every test named in §3, §4, and §5 exists and asserts a stable error code plus context.
- [ ] A lock failure changes no snapshot record and no quote status.
- [ ] `REQUEST_SUPERSEDED` is impossible to bypass: publication re-reads the stored request Id, so a late worker cannot win.

## 8. Verification method

```bash
sf apex run test --class-names QuoteDocumentLifecycleConcurrencyTest --class-names QuoteDocumentLifecycleTest --result-format human --wait 20
```

Lock contention is exercised with a second transaction holding the row, not by mocking the exception — a mocked `UNABLE_TO_LOCK_ROW` proves the handler, not the behaviour.

## 9. Close-out

- **Date:**
- **Abandonment window chosen:**
- **Retry limit chosen:**
- **Next step:** [`step-06-contract-validation.md`](step-06-contract-validation.md)
