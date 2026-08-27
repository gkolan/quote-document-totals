# Vendor-neutral render contract — failure scenarios

Each row places the same requirement on the design: the failure is identifiable from persisted data, without debug logs, and names a stable error code. **How each row is verified differs**, and pretending otherwise is how a runbook drifts from the build:

| Class | Verified by | Rows |
|---|---|---|
| **T — automated test** | Apex tests in the owning step | most rows; the step that owns each is linked in-line |
| **G — CI gate** | the version-token gate suite ([verification protocol](verification-protocol.md)) | contributor version not bumped; gate's own failure modes |
| **D — operational drill** | a rehearsal with evidence recorded in the release close-out, not `sf apex run test` | renderer outage; config rollback |
| **R — residual risk** | documented, accepted, and re-stated in the extension guide — **not** verifiable for arbitrary subscriber code | contributor performs its own DML or callout |

A row's class is marked in its Recovery column. Nothing here is an executable release test unless it is class **T** and a step names the test.

## Six questions the persisted model must answer

If any of these needs a debug log, operational identity is incomplete and [step 05](steps/step-05-snapshot-integrity.md) cannot close.

1. Which snapshot is currently published for this quote, and when?
2. Which attempt produced it? (`Document_Data_Request_Id__c`)
3. If it failed, at what and why? (stable error code in `Document_Data_Error__c`)
4. Did anything from the failed attempt survive? This is a **proven invariant, not a queryable fact** — the savepoint guarantees it and the rollback tests demonstrate it. Without per-attempt stamps on child records, no query answers it directly, and the runbook must not imply one does.
5. Which locale, content version, and fingerprint were used?
6. Can the same payload be replayed to a renderer without regenerating? (Only by passing that snapshot's own request Id and fingerprint — an unqualified read is not a supported path.)

## Scenarios

| Scenario | Required behaviour | Recovery |
|---|---|---|
| Apex contributor throws | Whole attempt rolls back — the *previous* snapshot is restored intact, with its original record Ids; quote is `Failed`, so retrieval refuses and the restored snapshot is never presented as current | fix or clear `Row_Customizer_Code__c`, regenerate |
| Flow contributor faults | `CONTRIBUTOR_FLOW_FAULT` naming the Flow API name and table code; no partial records | clear `Row_Customizer_Flow__c`, regenerate |
| Flow returns null, or no output collection | `CONTRIBUTOR_NO_OUTPUT` — never read as "unchanged", which would hide a misconfigured Flow | fix the Flow's output variable, regenerate |
| Flow is inactive, renamed, or missing | `CONTRIBUTOR_FLOW_UNAVAILABLE` at startup, naming the API name | restore or repoint the CMDT value |
| **[G]** Contributor logic changed, version token not bumped | Nothing detects it. `canReuse` reuses the old snapshot and the quote stays `Ready` — a wrong document, produced silently | bump `Row_Customizer_Version__c` / `Row_Customizer_Flow_Version__c` and run invalidation. This is why the token exists; it is release discipline, not a runtime guarantee |
| Contributor returns two Grand Totals, or a Detail after the Grand Total | `CONTRIBUTOR_MULTIPLE_GRAND_TOTALS` / `ROW_ORDER_INVALID` — neither is caught by `verify()` today; [step 01A](steps/step-01a-extension-contracts.md) §5 adds them | fix the contributor, regenerate |
| **[R]** Contributor performs its own DML or a callout | **Not prevented.** Contributors are trusted ([spec.md](spec.md) §1). Same-transaction DML rolls back with the attempt; committed async work does not | **R.** Verifiable only as: static analysis on shipped and sample contributors, a trust-model documentation check, and a test proving same-transaction DML rolls back when generation subsequently fails. Not a behavioural test for arbitrary subscriber code |
| Flow returns rows carrying Ids | `CONTRIBUTOR_RETURNED_PERSISTED_ROW` — output validation only. It does **not** prove this Flow inserted them, and a Flow that inserts rows then returns different uninserted ones passes this check | fix the Flow, regenerate |
| Contributor duplicates a row key | `CONTRIBUTOR_DUPLICATE_ROW_KEY` naming both rows | fix the contributor, regenerate |
| **External dependency changed, no invalidation mapping exists** | Nothing marks the quote `Stale`. The launch contract is the only guard: generate-or-reuse recomputes the fingerprint, sees the changed declared value, and rebuilds | none needed if the launch contract is followed; a renderer reading a `Ready` snapshot directly is the defect |
| **Renderer called without a preceding generate-or-reuse** | Prohibited path. Retrieval without matching expectations fails `SNAPSHOT_MOVED`; a launch integration that skips step 1 is a release blocker, not a warning | fix the launch integration |
| **Snapshot regenerated between launch and render** | `SNAPSHOT_MOVED`, naming expected and actual request Id and fingerprint | re-launch; never render the newer snapshot under the older expectation |
| Missing required translation | fails during localization naming the key and locale; never blanks | add the dictionary row, bump content version, invalidate, regenerate |
| Content version activated | existing snapshots are marked `Stale` **only** by the explicit invalidation job — deploying CMDT does not do it | run the job, record processed/failed counts |
| Column binds an unknown or unreadable field | fails at config load, naming the field | correct the CMDT row, regenerate |
| Column binds a measure outside the table's measure set | `COLUMN_MEASURE_MISMATCH` | correct the CMDT row, regenerate |
| Totals fail reconciliation | the four existing `verify()` assertions block `Ready` | fix source, config, or contributor — never bypass the verifier |
| FLS or DML failure midway | savepoint rollback leaves nothing from this attempt — a first generation ends with no tables, a regeneration with the previous ones restored; error names the field where the platform supplies it | fix the permission set, regenerate |
| Duplicate click or retry | `FOR UPDATE` on the quote query plus the request Id keep two attempts from interleaving; one wins | show the winning request Id and fingerprint |
| Renderer asked for a `Stale`, `Failed`, or structurally incomplete snapshot | retrieval refuses, naming the status or the missing element. Verified against a deliberately malformed fixture — there is no pre-contract snapshot to detect ([`spec.md`](spec.md) §4) | regenerate — never let the adapter fall back to reading CPQ |
| **[D]** Renderer outage | the verified snapshot is untouched; retry the adapter only | **D.** Testable in Apex: an adapter that throws leaves the snapshot unchanged, the same expectations succeed on retry, and no regeneration happens. An actual vendor outage is a drill, not a unit test |
| **[D]** Config rollback | previous CMDT package redeployable; affected quotes stay non-`Ready` until regenerated | **D.** A deployment rehearsal in a non-production org, recorded in the close-out. `RunLocalTests` cannot prove a package redeploys |
| Largest supported quote | fails before publishing rather than hitting a governor mid-write; the limits test records the budget | reduce contributor output, or raise the reviewed ceiling |
| **Persisted snapshot tampered with** ([step 06A](steps/step-06a-snapshot-immutability.md)) | `PAYLOAD_INTEGRITY_MISMATCH` naming the quote, expected and actual payload hash. Rendering refuses. Tested across amount, label, order, visibility, column-binding, block-body, and delete-plus-reinsert mutations ([step 06A](steps/step-06a-snapshot-immutability.md)) | regenerate from authoritative inputs — never repair the records, nothing knows which version was right |
| **Queueable fails after failure bookkeeping** ([step 05](steps/step-05-snapshot-integrity.md) §3 item 7) | `Failed`, request Id, error code, and the restored previous snapshot are all readable *after the job ends*. Today they are not: the escaping exception rolls back the bookkeeping ([step 05](steps/step-05-snapshot-integrity.md) item 7) | integration test per outer path, not a unit test that catches inside the test method |
| **Generation stuck in `Generating`** ([step 05A](steps/step-05a-generation-lifecycle.md) §3) | Worker termination, transaction timeout, a job that never starts, or an abandoned request. `Document_Data_Started_At__c` already exists for this. Define the safe takeover window; a superseded request that finishes late must not publish — `GENERATION_ABANDONED` / `REQUEST_SUPERSEDED` | take over after the window; the late attempt loses |
| **Lock timeout or deadlock** ([step 05A](steps/step-05a-generation-lifecycle.md) §4) | `FOR UPDATE` serialises ordinary duplicate clicks, but acquisition can still time out. No snapshot mutation; bounded retry with jitter for async callers; a stable terminal code after the limit. **Never mark a good existing snapshot corrupt because a lock failed** | retry, then surface the terminal code |
| **Declared dependency source unavailable** ([step 01A](steps/step-01a-extension-contracts.md) §6a) | Removed field, missing permission, deleted related record, invalid pack config, or selectivity limits. Fail *before* reuse, naming the pack and path, code `DEPENDENCY_UNREADABLE`. An unreadable dependency is never treated as null — that silently changes the hash and reuses the wrong snapshot | fix the pack or permission, regenerate |
| **Invalidation job partially fails** ([step 05](steps/step-05-snapshot-integrity.md) §3 item 6) | Checkpoint/cursor, plus processed / stale-marked / skipped / failed counts and per-quote error evidence. Rerun is safe. **Never report "all snapshots invalidated" when only part of the job ran** | rerun from the cursor; reconcile counts |
| **Content or config activated during a launch** ([step 05](steps/step-05-snapshot-integrity.md)) | Narrowed to what a test can actually prove, since Apex cannot deploy Custom Metadata concurrently mid-transaction: **(a)** the snapshot records the exact content and config versions used; **(b)** every table in one snapshot carries the same versions, so a mixed-version snapshot is detectable; **(c)** activation landing between generation and retrieval is caught by the expected fingerprint and payload hash. Transaction-level metadata isolation is an accepted platform property, stated and not claimed as tested | regenerate if the expectation no longer matches |
| **Repeated `SNAPSHOT_MOVED`** ([step 05A](steps/step-05a-generation-lifecycle.md) §5) | At most **one** bounded automatic retry, then a user-visible concurrency error. Never silently render the newest snapshot under older launch expectations | investigate what is regenerating in a loop |
| **Service or permission misconfiguration (B1)** ([step 06A](steps/step-06a-snapshot-immutability.md) §5) | Four distinct codes: requesting user holds the launch permission but the service lacks source access; user lacks launch permission; renderer can launch but cannot invoke the payload service; renderer has accidental direct object CRUD (which [step 06A](steps/step-06a-snapshot-immutability.md) forbids) | each with its own recovery |
| **[G]** The version-token CI gate itself fails ([step 01A](steps/step-01a-extension-contracts.md) §10) | Parser finds zero mappings, merge base unavailable, subscriber mapping file missing, a rename breaks the mapping, or an emergency deploy skips CI. **A gate failure blocks the release** — it never degrades to a warning, because a gate that warns is a gate that is ignored | fix the gate before deploying; an emergency path that skips it requires the invalidation job to be run manually and recorded |
| Sensitive data in an error message | `Document_Data_Error__c` is assembled by an allowlisting formatter — stable code plus permitted context. Abbreviation is not sanitization: raw exception text can carry customer content well inside 3000 characters | one test feeds an exception containing a product description and asserts it does not reach the field |

## Coverage index — every row has an owner

Rows not carrying an inline link above are owned as follows. A row with no owner is not covered, whatever this file says about it.

| Rows | Owning step |
|---|---|
| Contributor throws / Flow faults / null output / Flow unavailable / bad row shape / row keys / returned Ids | [01A](steps/step-01a-extension-contracts.md) §4–§5 |
| External dependency changed; renderer called without generate-or-reuse; snapshot moved mid-launch | [01A](steps/step-01a-extension-contracts.md) §6a–§6b, [07](steps/step-07-render-service-dto.md) |
| Missing translation; content version activated; sensitive data in an error | [03](steps/step-03-semantic-keys-and-localization.md), [05](steps/step-05-snapshot-integrity.md) |
| Column binding failures | [02](steps/step-02-column-snapshot-object.md) |
| Totals reconciliation; FLS/DML failure midway; incomplete snapshot at retrieval | [06](steps/step-06-contract-validation.md) |
| Duplicate click or retry | [05A](steps/step-05a-generation-lifecycle.md) §4 |
| Largest supported quote | [07](steps/step-07-render-service-dto.md) |
| Renderer outage (testable half) | [08](steps/step-08-two-adapters.md) |

## Scope note

Every row above maps to a failure the design can actually produce. Nothing here requires an attempt-history object, per-record generation stamps, or provider version negotiation — those were dropped from the design ([`spec.md`](spec.md) §8), and scenarios that only exist to exercise them were dropped with them.
