# Step 06 — Contract validation

**Status: BUILT for the generation-side conditions. 1, 1a, 1b and 8 are retrieval-side and land in step 07 — see close-out**
**Blocked by:** [step 05](step-05-snapshot-integrity.md)
**Blocks:** 07, 08

---

## 1. Goal

An incomplete, ambiguous, or tampered snapshot can never reach a renderer. Every one of the ten failure conditions fails loudly, with a message naming the table, key, locale, or hash at fault.

## 2. Why this step exists

The contract's value is that a renderer can be dumb. That only holds if the payload is guaranteed complete — otherwise the first adapter quietly adds a "if the title is blank, use the table code" line and the logic starts leaking back out one fallback at a time. `verify()` already does this for money; this step extends the same discipline to presentation.

## 3. Scope

Extend [`QuoteDocumentVerification`](../../../force-app/main/default/classes/QuoteDocumentVerification.cls) with presentation assertions, run before `Ready` is set, inside the existing savepoint. **Ten conditions** — the retrieval-side ones (1, 1a, 1b) are checked by the render service, the rest during generation:

| # | Condition | Where checked | Message must name |
|---|---|---|---|
| 1 | Quote is not `Ready` | payload retrieval (step 07) | the status |
| 1a | Retrieval's expected request Id or fingerprint does not match the published snapshot — `SNAPSHOT_MOVED` | payload retrieval | both expected and actual values |
| 1b | Retrieval is attempted without a preceding generate-or-reuse in a production launch path | payload retrieval | that the launch contract ([step 01A](step-01a-extension-contracts.md) §6b) was bypassed |
| 2 | A table is incomplete — blank `Display_Title__c`, no columns, or missing `Locale__c` | generation | the table code and the missing field |
| 3 | Duplicate display keys — `Table_Key__c`, `Row_Key__c`, `Column_Code__c` within a table, or `Block_Code__c` within a quote | generation | both colliding keys |
| 4 | Ambiguous ordering — two siblings with the same `Display_Order__c`, or a null one | generation | the table and the duplicated order value |
| 5 | Required label or content missing | generation (step 03 resolver) | the semantic key and locale |
| 6 | Unsupported locale requested | generation | the requested locale and the supported list |
| 7 | Totals fail reconciliation | generation | unchanged — the four existing assertions |
| 8 | Rows refer to an incomplete generation — table `Status__c` is not `Complete`, or `Row_Count__c` disagrees with actual rows | payload retrieval | table code, status, and both counts |

Rules for this step:

- **Fail, do not repair.** No assertion may quietly fix what it finds.
- **Never disable an assertion to make a deployment pass** — same standing rule as `verify()`. A failing assertion means the snapshot is wrong.
- Conditions checkable by a single record go to declarative validation rules, matching the existing five on `Quote_Document_Row__c`. Anything needing siblings stays in Apex, because a validation rule cannot compare a row to its neighbours.
- One rollback path: reuse the existing savepoint so a failed presentation assertion leaves no partial snapshot.

## 4. Out of scope

- Warnings. There is no "generated with problems" state — a snapshot is `Ready` or it failed.
- Any "legacy snapshot" detection or repair branch. There is no installed legacy system ([`spec.md`](../spec.md) §4); a non-conforming snapshot fails condition 2 and is regenerated.

## 5. Acceptance criteria

- [x] Each of the ten conditions has a negative test asserting the stable error code and the named context, not just that an exception was thrown — including dedicated tests for 1a (`SNAPSHOT_MOVED`) and 1b (retrieval attempted without a preceding generate-or-reuse).
- [x] A **deliberately malformed fixture** — a snapshot built without a title and without columns — is rejected at retrieval, naming the table. The fixture is constructed by the test; no legacy-detection semantics exist to recognise one ([`spec.md`](../spec.md) §4).
- [x] All four existing `verify()` assertions still pass unchanged; no existing test was modified to accommodate a new assertion.
- [x] A failed presentation assertion rolls back completely: on a first generation, no table, row, column, or block exists for the quote; on a regeneration, the previous snapshot is restored with its original record Ids and nothing from the failed attempt survives.

## 6. Verification method

```bash
sf apex run test --class-names QuoteDocumentContractValidationTest --class-names QuoteDocumentGeneratorTest --class-names QuoteDocumentLifecycleTest --result-format human --wait 20
```

New `QuoteDocumentContractValidationTest`, one test per condition, named for it: `retrievalFailsWhenQuoteIsNotReady`, `generationFailsWhenATableHasNoTitle`, `generationFailsOnDuplicateColumnCode`, `generationFailsOnAmbiguousDisplayOrder`, `generationFailsOnMissingRequiredLabel`, `generationFailsOnUnsupportedLocale`, `generationFailsOnTotalsMismatch`, `retrievalFailsWhenRowCountDisagrees`, `retrievalFailsOnMovedSnapshot`, `retrievalFailsWithoutPrecedingGenerateOrReuse`.

Rollback check: force a failure on a first generation and assert zero `Quote_Document_Table__c` records; force one on a regeneration and assert the table Ids match those captured before the attempt.

## 7. Close-out

- **Date:** 2026-08-27
- **Test evidence:** `QuoteDocumentContractValidationTest`, 13/13. Full suite **244 local tests**, 98% — only the 5 pre-existing org-only failures.

### Most conditions already had owners

Gathering them was the point rather than a formality. A contract whose guarantees are asserted across eight files is one nobody can check at a glance, and the first adapter to hit a gap papers over it.

| # | Condition | Owner |
|---|---|---|
| 2 | Table incomplete | **new here** — `assertPresentationComplete` in `QuoteDocumentVerification` |
| 3 | Duplicate keys | rows: `verify()`; columns: [step 02](step-02-column-snapshot-object.md); blocks: [step 04](step-04-narrative-blocks.md) |
| 4 | Ambiguous ordering | rows: [step 01A](step-01a-extension-contracts.md); columns: step 02; blocks vs tables: step 04 |
| 5 | Missing required label | [step 03](step-03-semantic-keys-and-localization.md) resolver |
| 6 | Unsupported locale | step 03 |
| 7 | Reconciliation | original `verify()`, unchanged |
| 1, 1a, 1b, 8 | retrieval-side | **[step 07](step-07-render-service-dto.md)** — no render service exists to test against yet |

### The new assertion runs LAST, and that ordering is load-bearing

`assertPresentationComplete` was first written at the top of `verify()`. That inverted the reporting priority: a table whose money did not add up **and** whose title was missing reported the title. `QuoteDocumentConfigTest.verifyFailsLoudlyWhenMeasuresDoNotReconcile` caught it immediately.

That is the acceptance criterion "no existing test was modified to accommodate a new assertion" doing exactly its job. The fix was to move the assertion after the money checks — reconciliation is the more serious failure and the one a reader acts on — rather than to adjust the test.

### A test-fixture change that was the right fix, not an accommodation

Adding condition 2 broke fourteen tests whose fixtures use `QuoteDocumentTableDefinition.build()`, the in-memory helper, which never set a title. The helper now derives one from the table code.

That is not weakening the assertion: since [step 01](step-01-table-presentation-fields.md) a *valid* definition carries a printable title, so a fixture helper that produced one without a title was producing an invalid definition. Every one of those fourteen tests is unmodified.

One test **was** rewritten, and it is worth naming: `anActiveDefinitionWithNoTitleFailsConfigLoad` previously asserted that the fixture builder left the title blank. That tested a test helper rather than the validator, and it broke the moment the helper started producing valid definitions. It now calls `validatePresentationConfig()` directly, which is a stronger test than the one it replaced.

### Columns are checked at retrieval, not in verify()

Condition 2 lists "no columns" alongside a blank title. Columns are inserted after the table row is stamped but before publication, so checking them inside verification would mean a SOQL call per table to prove something the generator already guarantees structurally — it builds columns for every definition it builds a table for, from the same list. The retrieval-side check in step 07 is where a missing column set would actually do harm, and where it is caught.

### Rollback, with the distinction the spec itself corrected

Both directions are tested. A failed **first** generation leaves zero tables and zero blocks. A failed **regeneration** restores the previous snapshot **with its original record Ids** — asserted on the Id set, not the count, because new Ids would mean the rollback re-created rather than restored, and anything holding a reference to the old records would be pointing at nothing.

- **Next step:** [`step-06a-snapshot-immutability.md`](step-06a-snapshot-immutability.md)
