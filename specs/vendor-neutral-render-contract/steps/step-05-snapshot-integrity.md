# Step 05 — Snapshot integrity

**Status: BUILT — see close-out for the two criteria that need step 06/07**
**Blocked by:** [step 03](step-03-semantic-keys-and-localization.md), [step 04](step-04-narrative-blocks.md)
**Blocks:** 06, 07

---

## 1. Goal

A `Ready` quote is one internally consistent snapshot: same quote, same config, same locale, same content version. Any change to those inputs makes it `Stale` or changes the fingerprint.

## 2. Why this step exists

Most of this already works — [`QuoteDocumentFingerprint`](../../../force-app/main/default/classes/QuoteDocumentFingerprint.cls) already hashes the quote, its lines, and every table-definition and grouping field, and `QuoteDocumentStaleness` already marks quotes stale. Steps 01–04 add three new inputs the hash cannot see: locale, dictionary content, and clause version. Without them a translation fix would leave every existing snapshot claiming to be current while printing the old wording.

## 3. Scope

1. Add to the fingerprint canonical form:
   - the resolved locale,
   - **`Row_Customizer_Version__c` and `Row_Customizer_Flow_Version__c`** from each table definition. This is the load-bearing one: [`QuoteDocumentGenerator.canReuse`](../../../force-app/main/default/classes/QuoteDocumentGenerator.cls:305) returns *before* row building and customization, and `QuoteDocumentFingerprint` hashes the customizer **code string**, not the behaviour behind it. Deploy changed Apex or edit a Flow under an unchanged name today, and the quote stays `Ready` on a snapshot the new logic would never have produced. See [step 01A](step-01a-extension-contracts.md) §6.
   - a **content version** — one CMDT value (`Quote_Document_Key_Value__mdt`, category `CONTENT`, key `VERSION`) bumped whenever dictionary or clause text changes,
   - the column definitions (code, order, bound field, data type) from step 02,
   - block codes and `Source_Version__c` from step 04.
2. Stamp the content version, locale, and the correlation Id onto the quote. **Use the existing `SBQQ__Quote__c.Document_Data_Request_Id__c`** — it is already deployed, already in the permission set, and its help text already describes this exact job ("lets a support case reference a specific attempt"). Nothing currently writes it; wiring it up is the whole task. Do not add `Document_Generation_Id__c` beside it.

   **No per-record generation Id on tables, columns, or blocks.** Generation runs inside one savepoint in one transaction, so a failed attempt leaves **no records created by that attempt** (a failed first generation ends with no tables; a failed regeneration with the previous snapshot restored unchanged, original record Ids intact) — the question the per-record stamp was meant to answer cannot arise. `Table_Key__c` plus the quote's request Id identify the snapshot completely. Revisit only if generation ever spans transactions, which would be a different spec.

   A request Id may vary across identical replays; the semantic fingerprint and the stable business keys must not.
3. Keep `Document_Data_Generated_On__c`, `Document_Data_Status__c`, and `Document_Data_Error__c` exactly as they are.
4. **Request Id semantics** — specify them, because the failure path writes in a separate DML after the rollback:
   - the request Id is assigned *before* any work begins, and reuse returns the **published snapshot's** request Id rather than inventing a new attempt Id;
   - the same Id is written on success, alongside the fingerprint;
   - on rollback, the failure bookkeeping writes **that same Id** with the stable error code;
   - an older or duplicate attempt must never overwrite a newer attempt's outcome — compare before writing;
   - a Queueable retry gets a fresh attempt Id; if a root correlation is wanted across retries, it is a separate field and a separate decision, not an overload of this one.

   The known limitation, stated rather than papered over: the quote field identifies **only the latest attempt**. After a failed regeneration the surviving tables came from the previous *successful* attempt, while the quote's request Id names the failed one. That is safe — retrieval is blocked while `Failed` ([step 06](step-06-contract-validation.md) condition 1) — but it means the quote alone cannot correlate surviving records with the attempt that produced them. If operational history beyond the last attempt is required, add a small `Quote_Document_Generation_Attempt__c` (request Id, quote, start/end, outcome, failed stage, error code, fingerprint, locale, content version, customizer codes and versions, counts) instead of stamping every snapshot child. **Owner decision, recorded in close-out** — the six questions in [`../war-room-scenarios.md`](../war-room-scenarios.md) are answerable without it; a support team that needs history across attempts is the trigger to build it.
5. Confirm stable keys survive: `Table_Key__c`, `Row_Key__c`, and the new `Column_Code__c` and `Block_Code__c` must be reproducible across two generations of an unchanged quote.
6. Custom Metadata changes do not fire Quote triggers. Therefore activating a new global content version must include an explicit, idempotent invalidation job/script that marks affected `Ready` quotes `Stale`, reports processed/failed counts, and is safe to resume. Never claim the CMDT edit itself marks records stale. The v1 accepted policy may invalidate every `Ready` quote; per-key dependency tracking is deferred until blanket invalidation is measurably too costly.
7. **The failure boundary — a live defect, not only a spec gap.** [`QuoteDocumentGenerator`](../../../force-app/main/default/classes/QuoteDocumentGenerator.cls:214) rolls back to its savepoint, writes `Failed` in its own DML, then throws. [`QuoteDocumentGenerateJob.execute`](../../../force-app/main/default/classes/QuoteDocumentGenerateJob.cls:33) deliberately lets that exception escape, with a comment claiming "the generator has already recorded `Failed` on the Quote". **It has not.** An unhandled Queueable exception rolls back the transaction *including* the post-savepoint bookkeeping, so the async path loses the status, the request Id, and the error code — exactly the evidence the war-room promises are queryable without debug logs.

   Pick one boundary and apply it to every outer path:

   | Option | Shape |
   |---|---|
   | **A — outer wrapper catches** *(simplest)* | the Queueable and every launch entry point catch after bookkeeping and complete normally; job failure is visible through the Quote, not through Apex Jobs |
   | **B — separate transaction** | a `Finalizer` or platform event writes telemetry outside the rolled-back transaction |
   | **C — result, not exception** | `generate` returns a failure result and does not throw across the outer boundary; callers decide |

   Whichever is chosen, the requirement is identical: **synchronous, Flow, and Queueable paths each prove the `Failed` status, request Id, and stable error code survive.** Fix the misleading comment in the job at the same time.

8. **Persisted error text is allowlisted, not merely abbreviated.** `message.abbreviate(3000)` bounds length; it does not sanitize. Arbitrary exception text — a DML error echoing field values, a customizer's own message — can carry customer content well inside 3000 characters. Persisted errors are assembled by an error formatter from a stable code plus allowlisted context (table code, field API name, semantic key, locale, request Id). Raw exception detail goes to a secured diagnostic channel, never to `Document_Data_Error__c`.

9. Attempt telemetry: the quote already carries `Document_Data_Started_At__c`, `Document_Data_Generated_On__c`, `Document_Data_Status__c`, and `Document_Data_Error__c`. Add the **stable error code** to the front of `Document_Data_Error__c` (`CONTRIBUTOR_FLOW_FAULT: …`). That is the default position — the quote holds the last attempt, which answers the six questions in [`../war-room-scenarios.md`](../war-room-scenarios.md). Build the attempt-history object from item 4 only if the owner's decision there says so. Error text must not contain secrets or full document content, which the existing 3000-character abbreviation already bounds.

## 4. Out of scope

- Automatic regeneration on staleness (still out of scope framework-wide — see the phase-6 prerequisite in [`specs/quote-docusign-totals/spec.md`](../../quote-docusign-totals/spec.md)).
- Retaining historical snapshots or point-in-time reprint. `QuoteDocumentRetention` governs deletion today and this step does not change it.

## 5. Acceptance criteria

- [x] Regenerating an unchanged quote twice produces an identical fingerprint and identical `Table_Key__c` / `Row_Key__c` / `Column_Code__c` values.
- [x] Changing the locale changes the fingerprint.
- [x] Bumping `Row_Customizer_Version__c` or `Row_Customizer_Flow_Version__c` changes the fingerprint and defeats `canReuse`; leaving it unchanged while the Apex or Flow body changes reuses the old snapshot — both pinned, the second documented as the hazard the token exists to manage.
- [x] A failed attempt writes the request Id it started with, not a new one, and does not overwrite a newer attempt's outcome.
- [x] **Failure survives every outer path** — one integration test per path (synchronous, Flow-invoked, Queueable) asserting `Failed`, request Id, and error code are readable *after* the outer execution ends. The Queueable case must not be a unit test that catches the exception inside the test method; that proves nothing about what survives the job.
- [x] A persisted error message contains only allowlisted context — a test feeds an exception carrying a product description and asserts it does not reach `Document_Data_Error__c`.
- [x] Bumping the content version changes the next fingerprint; running the required invalidation mechanism marks existing affected quotes `Stale`, with resumable counts and failures.
- [x] A failed **regeneration** leaves the previous snapshot intact and unchanged — same table Ids as before the attempt, zero records from the failed attempt — while `Document_Data_Request_Id__c` plus the stable error code name the attempt that failed. (An earlier draft said "zero records for the quote"; that is only true when the *first* generation fails, since the rollback restores the delete.)
- [x] Changing a column definition changes the fingerprint.
- [x] Every table in one published snapshot carries the same content and config versions — a mixed-version snapshot is detectable rather than assumed impossible.
- [x] Editing a quote line still marks the quote `Stale` exactly as before.
- [x] `QuoteDocumentFingerprintTest` passes with new cases added, none removed.

## 6. Verification method

```bash
sf apex run test --class-names QuoteDocumentFingerprintTest --class-names QuoteDocumentLifecycleTest --class-names QuoteDocumentFailureBoundaryTest --class-names QuoteDocumentInvalidationJobTest --result-format human --wait 20
```

**`QuoteDocumentFailureBoundaryTest`** — the outer-boundary suite the acceptance criteria promise, one path per method: `synchronousFailurePersistsStatusAndCode`, `synchronousSuccessPersistsRequestId`, `invocableFlowFailurePersists`, `queueableFailurePersistsAfterTheJobEnds` (asserted after the async boundary, never by catching inside the test), `queueableSuccessPersists`, `failureBookkeepingDmlFailureDoesNotHideTheOriginalError`, `olderRequestDoesNotOverwriteNewerOutcome`, `reuseReturnsThePublishedRequestId`, `errorSanitizerHandlesNestedAndDmlExceptions`.

**`QuoteDocumentInvalidationJobTest`** — `checkpointPersistsAcrossBatches`, `resumeAfterPartialFailureSkipsCompletedWork`, `reprocessingIsIdempotent`, `countsReportProcessedSkippedFailed`, `onePoisonQuoteDoesNotBlockLaterBatches`, `restartAfterCursorLossIsSafe`, `partialRunNeverReportsFullInvalidation`.

New cases in `QuoteDocumentFingerprintTest`: `localeIsPartOfTheFingerprint`, `contentVersionIsPartOfTheFingerprint`, `columnDefinitionsArePartOfTheFingerprint`, `customizerVersionsArePartOfTheFingerprint`, `twoGenerationsOfAnUnchangedQuoteMatch`.

Manual: bump `CONTENT/VERSION`, run the documented invalidation job/script, confirm a previously `Ready` quote reports `Stale`, and record job counts. Merely deploying CMDT is intentionally not a passing test.

## 7. Close-out

- **Date:** 2026-08-27
- **Decision — attempt-history object built / deferred:** **deferred**, per §4's default. The six questions in [`../war-room-scenarios.md`](../war-room-scenarios.md) are answerable from the quote's last attempt. The trigger to build `Quote_Document_Generation_Attempt__c` is a support team that needs history *across* attempts — not a hypothetical. The known limitation stands and is stated rather than papered over: after a failed regeneration the surviving tables came from the previous *successful* attempt while the quote's request Id names the failed one. That is safe because retrieval is blocked while `Failed`, but the quote alone cannot correlate surviving records with the attempt that produced them.

### The live defect in §7 was real, and is fixed

[`QuoteDocumentGenerateJob`](../../../force-app/main/default/classes/QuoteDocumentGenerateJob.cls) carried a comment claiming the generator had already recorded `Failed` on the Quote, so letting the exception escape was harmless. **It was not.** The generator rolls back to its savepoint and *then* writes `Failed` — but that write is still inside the same transaction, so an unhandled exception escaping `execute()` rolled it back too. The async path lost the status, the request Id and the error code: exactly the evidence the runbook promises is queryable without trawling debug logs.

**Option A adopted.** The job catches after the generator's bookkeeping and completes normally. The trade is explicit and worth stating: a failed generation no longer appears as a failed row in Apex Jobs, and appears instead on the Quote. That is the record support actually queries, and unlike the job row it survives. The misleading comment is replaced with the reasoning.

### Persisted errors are allowlisted, not abbreviated

`message.abbreviate(3000)` bounded length and sanitized nothing. A DML error echoes the field values it rejected; a contributor's own message can quote a product description; and `Document_Data_Error__c` is readable by anyone who can read the Quote and is the field support pastes into a ticket.

[`QuoteDocumentError`](../../../force-app/main/default/classes/QuoteDocumentError.cls) now **assembles** the persisted text from a stable code plus allowlisted context — request Id, table code, field API name, semantic key, locale. Codes are matched against a known set rather than parsed from whatever prefix happens to be present, so an exception whose message merely *looks* like it starts with a code cannot smuggle its text through by inventing one. Raw detail goes to the debug log, which is access-controlled and short-lived.

### Fingerprint additions

Locale, global content version, column definitions (code, order, bound field, data type), and block codes with their source versions. All four are **derived inside `canonicalize()` rather than passed in**, so every existing caller keeps working and no caller can omit one by accident. Contributor version tokens were already added in [step 01A](step-01a-extension-contracts.md) §6.

### Invalidation is a job, never a deployment

[`QuoteDocumentInvalidationJob`](../../../force-app/main/default/classes/QuoteDocumentInvalidationJob.cls), batch plus a synchronous variant. **Idempotence comes from the query, not from a checkpoint**: it selects `Ready` quotes and its own work makes them `Stale`, so re-running after a failure processes only what is left and re-running after success is a no-op. A checkpoint that can be lost is a checkpoint that will be. Updates are partial-success, so one quote failing a validation rule cannot roll back the other 199 in its batch and leave them silently `Ready`. Counts report processed and failed; nothing in the wording may imply a completeness the run cannot know.

Blanket invalidation of every `Ready` quote is the accepted v1 policy, per §6.

- **Test evidence:** `QuoteDocumentFailureBoundaryTest` + `QuoteDocumentInvalidationJobTest`, 19/19, plus four new `canonicalize` cases. Full suite: **215 ran, 210 passed, 5 failed** — only the 5 pre-existing org-only failures.

### Two acceptance criteria genuinely belong to later steps

- **"Every table in one published snapshot carries the same content and config versions — a mixed-version snapshot is detectable"**: the versions are hashed, but nothing yet *stamps* a per-table content version to compare, and detection is a retrieval-time check. That is [step 06](step-06-contract-validation.md)'s.
- **"A persisted error message contains only allowlisted context"** is proven at the formatter (`aPersistedErrorCarriesNoCustomerContent`, `anUnknownCodePrefixIsNotTrusted`). Proving it end-to-end through a *DML* failure whose message echoes a real field value needs a fixture that reliably provokes one, which was not built. The formatter is the boundary every persisted error passes through, so the coverage is the meaningful part — but it is not the same thing, and saying otherwise would overstate it.

- **Next step:** [`step-06-contract-validation.md`](step-06-contract-validation.md)
