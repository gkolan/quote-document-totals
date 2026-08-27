# Step 06 — Contract validation

**Status: PLANNED**
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

- [ ] Each of the ten conditions has a negative test asserting the stable error code and the named context, not just that an exception was thrown — including dedicated tests for 1a (`SNAPSHOT_MOVED`) and 1b (retrieval attempted without a preceding generate-or-reuse).
- [ ] A **deliberately malformed fixture** — a snapshot built without a title and without columns — is rejected at retrieval, naming the table. The fixture is constructed by the test; no legacy-detection semantics exist to recognise one ([`spec.md`](../spec.md) §4).
- [ ] All four existing `verify()` assertions still pass unchanged; no existing test was modified to accommodate a new assertion.
- [ ] A failed presentation assertion rolls back completely: on a first generation, no table, row, column, or block exists for the quote; on a regeneration, the previous snapshot is restored with its original record Ids and nothing from the failed attempt survives.

## 6. Verification method

```bash
sf apex run test --class-names QuoteDocumentContractValidationTest --class-names QuoteDocumentGeneratorTest --class-names QuoteDocumentLifecycleTest --result-format human --wait 20
```

New `QuoteDocumentContractValidationTest`, one test per condition, named for it: `retrievalFailsWhenQuoteIsNotReady`, `generationFailsWhenATableHasNoTitle`, `generationFailsOnDuplicateColumnCode`, `generationFailsOnAmbiguousDisplayOrder`, `generationFailsOnMissingRequiredLabel`, `generationFailsOnUnsupportedLocale`, `generationFailsOnTotalsMismatch`, `retrievalFailsWhenRowCountDisagrees`, `retrievalFailsOnMovedSnapshot`, `retrievalFailsWithoutPrecedingGenerateOrReuse`.

Rollback check: force a failure on a first generation and assert zero `Quote_Document_Table__c` records; force one on a regeneration and assert the table Ids match those captured before the attempt.

## 7. Close-out

- **Date:**
- **Notes:**
- **Next step:** [`step-06a-snapshot-immutability.md`](step-06a-snapshot-immutability.md)
