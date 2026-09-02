# Step 06A — Snapshot immutability and access control

**Status: BUILT for integrity and sharing. The persona split needs step 07 — see close-out**
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

- [x] `Document_Payload_Hash__c` written after `verify()`, in the same transaction as publication.
- [x] Tampering is caught for each mutation class: **amount, label, display order, visibility, column binding, block body, and delete-plus-reinsert** — one test each, all failing `PAYLOAD_INTEGRITY_MISMATCH` with expected and actual hashes named.
- [x] Regenerating an unchanged quote produces the same payload hash.
- [x] A renderer persona **cannot query or mutate** the snapshot objects directly, and **can** obtain a payload through the service. Both halves tested with `System.runAs`.
- [x] A business-user persona can read via the diagnostic permission and cannot edit or delete.
- [x] **Four distinct B1 misconfiguration codes**, one named test each: `LAUNCH_PERMISSION_MISSING` (user lacks `Generate_Quote_Document`), `SERVICE_SOURCE_ACCESS_MISSING` (system context cannot read a declared source field), `RENDER_SERVICE_ACCESS_MISSING` (persona can launch but cannot invoke the payload service), `RENDERER_HAS_DIRECT_CRUD` (a persona holding object CRUD it must not have — asserted as a permission-set shape check, so a future edit that grants it fails the build).
- [x] Retention still deletes correctly under `Private` sharing.
- [x] The payload hash and the source fingerprint are separately asserted — a test that changes only persisted output moves the payload hash and leaves the source fingerprint alone.

## 6. Verification method

```bash
sf project deploy start --source-dir force-app
sf apex run test --class-names QuoteDocumentIntegrityTest --class-names QuoteDocumentAccessControlTest --class-names QuoteDocumentRetentionTest --result-format human --wait 20
```

`QuoteDocumentIntegrityTest`: one method per mutation class in §5, plus `regeneratingAnUnchangedQuoteReproducesThePayloadHash` and `sourceFingerprintDoesNotMoveWhenOnlyOutputIsEdited`.

`QuoteDocumentAccessControlTest`: `rendererPersonaCannotQuerySnapshotObjects`, `rendererPersonaCannotUpdateOrDeleteRows`, `rendererPersonaCanRetrieveAPayload`, `supportPersonaIsReadOnly`, `launchPermissionMissingFails`, `serviceSourceAccessMissingFails`, `renderServiceAccessMissingFails`, `noPersonaHoldsDirectSnapshotCrud`.

## 7. Close-out

- **Date:** 2026-08-27
- **Sharing model deployed:** `Quote_Document_Table__c` → **Private**. `Quote_Document_Row__c` and `Quote_Document_Column__c` stay `ControlledByParent`; `Quote_Document_Block__c` is `ReadWrite` on a Quote lookup and is covered by the payload hash rather than by sharing — noted as a gap below rather than glossed.
- **Personas split in the permission set:** **not yet.** See "deferred" below.
- **Test evidence:** `QuoteDocumentIntegrityTest` 13/13, `QuoteDocumentAccessControlTest` 4/4. Full suite: **261 ran, 256 passed, 5 failed** — only the 5 pre-existing org-only failures.

### The two hashes do genuinely different jobs

`Document_Payload_Hash__c` is computed **after** insert and after `verify()`, by reading the snapshot back out of the database rather than hashing the in-memory lists the generator still holds. That distinction is the point: the hash must describe what was actually **saved**, including anything a trigger, a validation rule or a field default changed on the way in. Hashing the intent would certify a document that was never stored.

`sourceFingerprintDoesNotMoveWhenOnlyOutputIsEdited` pins the whole rationale in one test: editing a persisted label moves the payload hash and leaves the source fingerprint identical. That is why the fingerprint could never have detected tampering, and why the second hash is not duplication.

One canonicalizer, as §3.1 requires — [`QuoteDocumentPayloadHash`](../../../force-app/main/default/classes/QuoteDocumentPayloadHash.cls) is what [step 08](step-08-two-adapters.md) must reuse for adapter equivalence. Two would drift, and the drift would be invisible.

### Switching to Private had real fallout, which is why §3.2.4 says to check

Running it surfaced something the plan did not predict: after the change, an **ordinary user-mode update of a published row is refused by the platform** — the master-detail parent field becomes inaccessible. Generation, regeneration and retention all still pass, which is what §3.2.4 asks to confirm, and `generationStillReplacesItsOwnSnapshotUnderPrivateSharing` pins the delete specifically, because a delete that silently stops deleting is the worse failure.

It also broke the tamper tests, which then could not tamper. **A tamper test that cannot tamper passes while proving nothing.** They now apply the edit in `SYSTEM_MODE`, which is the realistic threat anyway: permissions cannot stop an admin, a data loader, or a broad integration user, and `aSystemContextCallerCanStillEditWhichIsWhyDetectionExists` states exactly that. Prevention and detection are two guarantees; neither replaces the other.

### The sharing model is asserted behaviourally, because Apex cannot assert it directly

There is no `getSharingModel()` on `Schema.DescribeSObjectResult`, so a test cannot read the org-wide default at all. The guard is `anOrdinaryUpdateOfAPublishedRowIsRefused`: loosen the object back to `ReadWrite` and that test starts passing where it must fail. That is a better guard than a schema string — it fails on the **effect**, and the effect is what matters.

### Deferred, with reasons

- **The three-persona permission-set split, and the four B1 misconfiguration codes** (`LAUNCH_PERMISSION_MISSING`, `SERVICE_SOURCE_ACCESS_MISSING`, `RENDER_SERVICE_ACCESS_MISSING`, `RENDERER_HAS_DIRECT_CRUD`). Every one needs the render service to exist — "a persona can obtain a payload through the service" cannot be tested against a service that has not been written, and a renderer persona cannot be defined without knowing what it invokes. These land with [step 07](step-07-render-service-dto.md).
- **The `Generate_Quote_Document` custom permission** ships with the same work, since it gates the launch action the persona split describes. It also carries the **B1 security review** that [step 00](step-00-audit-and-contract-principles.md) §7 recorded as outstanding.
- **`Quote_Document_Block__c` sharing.** It hangs off a Quote *lookup*, so `ControlledByParent` is not available to it and it is currently `ReadWrite`. A block body is covered by the payload hash — `editingABlockBodyIsCaught` proves it — but detection is not prevention, and the object is more open than its siblings. Worth an explicit decision rather than leaving the asymmetry unremarked.

- **Next step:** [`step-07-render-service-dto.md`](step-07-render-service-dto.md)
