# Step 07 — `QuoteDocumentRenderService` and DTOs

**Status: PLANNED**
**Blocked by:** [step 06](step-06-contract-validation.md)
**Blocks:** 08

---

## 1. Goal

One entry point — `QuoteDocumentRenderService.getPayload(quoteId, expectedRequestId, expectedFingerprint)` — returns the whole document as typed, already-resolved data, bound to exactly the snapshot the caller's generate-or-reuse published, with no vendor vocabulary anywhere in it.

## 2. Why this step exists

Adapters querying the objects directly would each re-derive ordering, visibility filtering, and the table–column–row join, and would drift apart. One projection, shared by every adapter, is the thing that makes "swap the renderer" a small job.

## 3. Scope

1. New `QuoteDocumentRenderService` with:

```apex
DocumentPayload  getPayload(Id quoteId, String expectedRequestId, String expectedFingerprint)
```

   **This is the only signature.** Both expectations are required, always, and come from the generate-or-reuse call that preceded the render ([step 01A](step-01a-extension-contracts.md) §6b). A mismatch fails with `SNAPSHOT_MOVED`, naming both values.

   No quote-Id-only overload exists — not for tests, not for inspection. The service cannot tell a "production" call from an "ad hoc" one, so an overload that skips the expectations is simply the bypass the rest of the contract prohibits, and its existence would make [step 06](step-06-contract-validation.md) condition 1b unenforceable. Tests obtain the values the way every caller does, from generate-or-reuse.

   Administrators who need to inspect a snapshot get a separate, explicitly named diagnostic — `describeSnapshot(Id quoteId)`, returning status, request Id, fingerprint, locale, and record counts. It **cannot return a `DocumentPayload`**, so it can never be quietly promoted into a render path.
2. DTO shape — plain Apex classes with public fields, no getters, no behaviour:

```
DocumentPayload
  contractVersion, requestId, quoteId, quoteNumber, locale, currencyIsoCode
  generatedOn, fingerprint, contentVersion, status
  List<Section> sections            // tables and blocks, one Display_Order__c sequence
Section
  sectionType ('Table' | 'Block'), code, displayOrder
  title, subtitle, introText, footerText
  List<Column> columns              // Table only
  List<Row> rows                    // Table only
  heading, body, blockType          // Block only
Column
  code, label, displayOrder, dataType
Row
  key, rowType, groupLevel, displayOrder, label
  Map<String, Object> values        // keyed by Column.code, typed Decimal/String/Date
```

3. **Rules the DTO obeys:**
   - Reads persisted records only. No arithmetic, no string building, no translation, no defaulting a blank field. If something is missing, step 06 already failed the snapshot.
   - Applies `Is_Displayed__c` as a filter and `Display_Order__c` as the sort — the two things every adapter would otherwise reimplement.
   - Raw typed values: `Decimal` for money, not `"$1,234.00"`. Formatting is the renderer's job, and `locale` plus `currencyIsoCode` give it what it needs.
   - `values` is keyed by `Column.code`, so an adapter never has to know that `COL_NET` means `Amount_Net__c`.
   - No field named for a vendor, no markup, no `docusign`/`conga`/`word`/`pdf`/`html` anywhere in the class.
4. Bulk-safe service core:

```apex
List<DocumentPayload> getPayloads(List<PayloadRequest> requests)

PayloadRequest:  quoteId, expectedRequestId, expectedFingerprint
```

   The single-quote method delegates to this one. **No `Set<Id>` entry point exists** — a bulk method without expectations is the same bypass as the removed overload, wearing a different signature. Every quote in the batch carries its own expectations, and one mismatch fails that request with `SNAPSHOT_MOVED` without silently degrading the rest of the batch (the result reports per-request outcome; a partial batch never looks like a whole one). One query per object, no SOQL in a loop, regardless of quote or table count.
4a. **The row query is dynamic.** Its SELECT list is the union of the base row fields and every `Value_Field__c` configured on the columns of the tables being retrieved, schema-validated before it is concatenated — the same discipline `QuoteDocumentQuery.validateFieldPath` already applies to grouping paths, and the reason that dynamic SOQL is defensible here. A static field list would make [step 02](step-02-column-snapshot-object.md)'s subscriber-field binding valid metadata that never produces a value. A configured field missing from the query result fails with `COLUMN_VALUE_NOT_QUERIED`; it must never surface as a null cell.
5. Provide thin consumer entry points only where required: Apex calls the service directly; Flow uses one documented invocable wrapper that accepts versioned requests and returns results/errors without exposing internal SObjects. The wrapper contains no query or transformation logic.
6. Retrieval revalidates Quote status, the expected request Id and fingerprint, **the recomputed payload hash** ([step 06A](step-06a-snapshot-immutability.md) — `PAYLOAD_INTEGRITY_MISMATCH` if the persisted output was edited after publication), table `Complete` status, counts, and contract major version. It never recalculates a commercial value, and there is no repair path for a non-conforming snapshot — it fails, and the answer is to regenerate.

## 4. Out of scope

- Caching. Generation is already the expensive half; measure before optimising the read.
- A `RendererAdapter` interface. Two adapters, two classes, no hierarchy (see [`spec.md`](../spec.md) §6).
- Any REST surface.

## 5. Acceptance criteria

- [ ] `getPayload` with matching expectations on a `Ready` quote returns every displayed table and block in one correct `displayOrder` sequence.
- [ ] No overload exists that omits the expectations — asserted against the class's method list, including the bulk path, so neither bypass can be reintroduced without failing a test.
- [ ] A tampered snapshot fails `PAYLOAD_INTEGRITY_MISMATCH` before any payload is returned.
- [ ] **Bulk isolation matrix**, one test each: empty request list; null request; duplicate quote Ids with different expectations; a batch mixing `Ready`, `Failed`, `Stale`, moved, and tampered quotes; a dynamic field valid for one table and absent for another; output ordering stable regardless of input ordering; the configured maximum batch size; a payload-hash failure isolated to its own request; **no successful result omitted because another request failed**.
- [ ] Query count stays flat as the number of **quotes** grows, not only as tables grow.
- [ ] `describeSnapshot` returns diagnostics and cannot return a `DocumentPayload`.
- [ ] Hidden tables, hidden rows, and hidden columns are absent from the payload.
- [ ] Every `Row.values` key matches a `Column.code` on its own section; no key without a column, no column without a key.
- [ ] Money arrives as `Decimal`, dates as `Date` — no pre-formatted strings.
- [ ] Grep test passes: no vendor token in the DTO or service source.
- [ ] A column bound to a field outside the base row field set is present and populated in the payload — the dynamic SELECT actually included it.
- [ ] A configured column whose field is missing from the query result fails with `COLUMN_VALUE_NOT_QUERIED` rather than yielding a null cell.
- [ ] Calling on a non-`Ready` quote throws with the status named (step 06 condition 1).
- [ ] Governor check at the **configured supported maximum** — a fixture parameter, not a number frozen in prose. The current inventory is 15 definitions with seven active, so any hard-coded "10-table quote" is already wrong. Queries stay flat as table count grows.

## 6. Verification method

```bash
sf apex run test --class-names QuoteDocumentRenderServiceTest --result-format human --wait 20
grep -rniE "docusign|conga|springcm|\.docx|word|merge ?field|<#" force-app/main/default/classes/QuoteDocumentRenderService*.cls
```

The grep must return nothing. Same check runs as an Apex assertion so it cannot be forgotten in CI.

New `QuoteDocumentRenderServiceTest`: `payloadOrdersSectionsAndRowsCorrectly`, `hiddenRecordsAreExcluded`, `valuesAreKeyedByColumnCode`, `amountsAreTypedNotFormatted`, `payloadContainsNoVendorTokens`, `nonReadyQuoteThrows`, `payloadQueryCountIsFlat`, `dynamicSelectIncludesEveryConfiguredColumnField`, `unqueriedColumnFieldFails`, `noOverloadOmitsExpectations` (reflection over the class's method list), `describeSnapshotCannotReturnAPayload`, `tamperedSnapshotFailsIntegrity`, and the bulk matrix above as `bulk*` methods.

## 7. Close-out

- **Date:**
- **Notes:**
- **Next step:** [`step-08-two-adapters.md`](step-08-two-adapters.md)
