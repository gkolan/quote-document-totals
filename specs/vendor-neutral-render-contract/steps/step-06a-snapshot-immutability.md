# Step 06A — Snapshot immutability and access control

**Status: PLANNED**
**Blocked by:** [step 06](step-06-contract-validation.md)
**Blocks:** 07, 08

---

## 1. Goal

"Immutable snapshot" becomes true. A published snapshot cannot be edited by ordinary permissions, and a snapshot that was edited anyway cannot render.

## 2. Why this step exists

Two gaps make the word "immutable" false today.

**Sharing.** `Quote_Document_Table__c` ships `<sharingModel>ReadWrite</sharingModel>` and `Quote_Document_Row__c` is `ControlledByParent`. Anyone holding `CPQ_Document_Totals` can edit a persisted row. The generator's own [`canReuse`](../../../force-app/main/default/classes/QuoteDocumentGenerator.cls:305) already acknowledges this — its last two checks exist precisely because "anyone holding `CPQ_Document_Totals` can delete rows out from under a `Ready` quote".

**Identity covers inputs, not output.** `Document_Data_Fingerprint__c` hashes the *source and configuration*. The expected request Id and fingerprint at retrieval ([step 07](step-07-render-service-dto.md)) detect **regeneration**, not **tampering**. None of these change the source fingerprint:

- editing `Display_Label__c` or narrative text
- editing an amount
- changing `Display_Order__c` or `Is_Displayed__c`
- changing a column binding
- deleting one Detail row and inserting a replacement

Some are caught by `Row_Count__c`; most are not. The document renders, modified, with every expectation matching.

## 3. Scope

### 3.1 Two hashes, two jobs

| Field | On | Covers | Computed |
|---|---|---|---|
| `Document_Data_Fingerprint__c` *(exists)* | Quote | source + configuration identity — decides rebuild vs reuse | before generation |
| `Document_Payload_Hash__c` *(new)* | Quote | the exact persisted semantic output | **after** insert and after `verify()`, over the same canonical form [step 08](step-08-two-adapters.md) §3a defines for adapter equivalence |

`getPayload` recomputes the payload hash from what it just queried and compares. Mismatch fails `PAYLOAD_INTEGRITY_MISMATCH`, naming the quote, the expected hash, and the actual one. Regenerate from authoritative inputs — never "repair" the records, because nothing knows which version was correct.

Reusing step 08's canonicalizer is deliberate: one definition of "the semantic document", used by the integrity check and by the adapter equivalence test. Two canonicalizers would drift, and the drift would be invisible.

### 3.2 Lock the objects down

1. `Quote_Document_Table__c` → `<sharingModel>Private</sharingModel>`. `Quote_Document_Row__c`, `Quote_Document_Column__c`, and `Quote_Document_Block__c` stay `ControlledByParent`.
2. Split `CPQ_Document_Totals` by persona, since one permission set currently serves generation, rendering, and human inspection:

   | Persona | Snapshot objects |
   |---|---|
   | Generation (B1 system context) | create, read, edit, delete |
   | Renderer / integration | **no direct object access at all** — payload only, through the service |
   | Business user / support | read via a separate diagnostic permission, never edit or delete |

3. Generation runs in the documented system context ([`spec.md`](../spec.md) §10, model B1), so restricting the objects does not break it.
4. `QuoteDocumentRetention`'s cross-quote deletes run in the same context — check them explicitly when the sharing model changes, because a delete that silently stops deleting is worse than one that fails.

Without this, "direct access is unsupported" is an honour-system rule that the first integration under deadline will break.

## 4. Out of scope

- Field-level audit history. The payload hash answers *whether* the snapshot changed; *who* changed it is a Salesforce audit-trail question and belongs to whoever asks for it.
- Encrypting snapshot content.

## 5. Acceptance criteria

- [ ] `Document_Payload_Hash__c` written after `verify()`, in the same transaction as publication.
- [ ] Tampering is caught for each mutation class: **amount, label, display order, visibility, column binding, block body, and delete-plus-reinsert** — one test each, all failing `PAYLOAD_INTEGRITY_MISMATCH` with expected and actual hashes named.
- [ ] Regenerating an unchanged quote produces the same payload hash.
- [ ] A renderer persona **cannot query or mutate** the snapshot objects directly, and **can** obtain a payload through the service. Both halves tested with `System.runAs`.
- [ ] A business-user persona can read via the diagnostic permission and cannot edit or delete.
- [ ] **Four distinct B1 misconfiguration codes**, one named test each: `LAUNCH_PERMISSION_MISSING` (user lacks `Generate_Quote_Document`), `SERVICE_SOURCE_ACCESS_MISSING` (system context cannot read a declared source field), `RENDER_SERVICE_ACCESS_MISSING` (persona can launch but cannot invoke the payload service), `RENDERER_HAS_DIRECT_CRUD` (a persona holding object CRUD it must not have — asserted as a permission-set shape check, so a future edit that grants it fails the build).
- [ ] Retention still deletes correctly under `Private` sharing.
- [ ] The payload hash and the source fingerprint are separately asserted — a test that changes only persisted output moves the payload hash and leaves the source fingerprint alone.

## 6. Verification method

```bash
sf project deploy start --source-dir force-app
sf apex run test --class-names QuoteDocumentIntegrityTest --class-names QuoteDocumentAccessControlTest --class-names QuoteDocumentRetentionTest --result-format human --wait 20
```

`QuoteDocumentIntegrityTest`: one method per mutation class in §5, plus `regeneratingAnUnchangedQuoteReproducesThePayloadHash` and `sourceFingerprintDoesNotMoveWhenOnlyOutputIsEdited`.

`QuoteDocumentAccessControlTest`: `rendererPersonaCannotQuerySnapshotObjects`, `rendererPersonaCannotUpdateOrDeleteRows`, `rendererPersonaCanRetrieveAPayload`, `supportPersonaIsReadOnly`, `launchPermissionMissingFails`, `serviceSourceAccessMissingFails`, `renderServiceAccessMissingFails`, `noPersonaHoldsDirectSnapshotCrud`.

## 7. Close-out

- **Date:**
- **Sharing model deployed:**
- **Personas split in the permission set:**
- **Next step:** [`step-07-render-service-dto.md`](step-07-render-service-dto.md)
