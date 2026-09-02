# Vendor-Neutral Document Render Contract — spec

**Status of this file:** planning spec, not a build log. It defines a render contract that makes the document product replaceable, audits what still lives outside Salesforce today, proposes the smallest complete data model, and indexes the [steps](steps/) that implement it.

**Read first:** [`docs/quote-document-totals.md`](../../docs/quote-document-totals.md) is still the source of truth for the framework itself. This spec changes *where printable content is resolved*, not how money is calculated.

---

## 1. The contract, in one paragraph

Salesforce produces a complete, immutable, vendor-neutral snapshot. A renderer may only: query the generated records, render in `Display_Order__c` order, bind already-generated values, and apply styling, page breaks, and fonts. A renderer may not: calculate, evaluate business conditions, translate, construct labels or sentences, decide which sections or rows appear, derive totals, read CPQ fields to recover missing data, or hold vendor-specific business rules.

**Definition of done:** a developer adds a new document product by writing a renderer adapter plus mapping/styling config only — no change to Apex business logic, Flow, Custom Metadata content selection, generated records, calculations, or localization.

This contract has **two separate extension directions**. Do not confuse them:

1. A **generation contributor** supplies or changes semantic document content before the snapshot is verified. This is where subscriber Apex or an autolaunched Flow plugs in — through the seam the framework already has ([`QuoteDocumentRowCustomizer`](../../force-app/main/default/classes/QuoteDocumentRowCustomizer.cls)), extended in [step 01A](steps/step-01a-extension-contracts.md), not through a second contribution framework built beside it.
2. A **renderer adapter** reads the verified snapshot after it is `Ready`. It can never contribute business content.

Neither direction requires editing `QuoteDocumentGenerator`, `QuoteDocumentRowBuilder`, or another core class.

**Contributors are trusted, not sandboxed.** Core owns publication, validates contributor *output*, and rolls the attempt back on failure. It cannot prevent a contributor from running its own SOQL, DML, async work, or callouts — Apex offers no such sandbox and neither does Flow. [Step 01A](steps/step-01a-extension-contracts.md) §2 states this in the words the extension guide must repeat. Any claim that the seam prevents those "by construction" is false and must not reappear.

**Three different things get versioned, for three different reasons:**

| Version | Why |
|---|---|
| `DocumentPayload.contractVersion` | Adapters deploy separately and may lag. |
| `QuoteDocumentRowCustomizer.CONTRACT_VERSION` | Subscriber code deploys separately; a compile-time constant plus documented semantic rules, not runtime negotiation. |
| `Row_Customizer_Version__c` / `Row_Customizer_Flow_Version__c` | **Content identity.** Changed contributor logic under an unchanged code or Flow name is invisible to the fingerprint, and `canReuse` would reuse a stale snapshot. See [step 01A](steps/step-01a-extension-contracts.md) §6 — a correctness fix, not bookkeeping, and enforced in CI ([verification protocol](verification-protocol.md)) rather than left to discipline. |

Versions cover changed *logic*. They do nothing when unchanged logic reads changed *data* — an Account field, a custom object, a Flow lookup. Nothing in the framework watches anything outside the quote and its lines, so every contributor declares a `Cache_Policy__c` ([step 01A](steps/step-01a-extension-contracts.md) §6a).

**And hashing is not invalidation.** A hashed dependency only helps when `generate()` runs again; nothing marks a quote `Stale` because an Account field changed. Invalidation handlers are best-effort and sometimes impossible — reverse-mapping an arbitrary custom object to affected quotes may have no answer. So the guarantee rests on a lifecycle rule instead, and every production launch follows it:

```
external change
   → invalidation where a mapping exists (best-effort)
   → launch ALWAYS calls generate-or-reuse   (recomputes the fingerprint — not best-effort)
   → rebuild or reuse
   → returns request Id + fingerprint
   → renderer calls getPayload with exactly those, or fails SNAPSHOT_MOVED
```

Reading a `Ready` snapshot without step 2 is prohibited. Fresh fingerprint computation is the final guard when a trigger, a sweep, or a version bump was missed — see [step 01A](steps/step-01a-extension-contracts.md) §6b and [step 07](steps/step-07-render-service-dto.md).

---

## 2. Audit — printable text and conditional behaviour that is not in the data today

Done against the deployed metadata and the ten table guides. This is the gap list the steps close; each row names its step.

| # | What | Where it lives today | Should live | Step |
|---|---|---|---|---|
| 1 | **Table title** | `Table_Name__c` on the CMDT, never copied to the record. The record's `Name` is `"Q-00063 - Family and Billing Summary"` — an identifier, not a printable title. Guides tell the author to type the heading into Word. | `Quote_Document_Table__c.Display_Title__c` | [01](steps/step-01-table-presentation-fields.md) |
| 2 | **Column headings** | Typed into the `.docx` per each guide's §9. Not in the data at all. | `Quote_Document_Column__c` child rows | [02](steps/step-02-column-snapshot-object.md) |
| 3 | **Which columns a table shows, and in what order** | The template author's choice of `<Value Select="..."/>` tags. `measureFields()` returns 6–7 measures; guides print 3–4, a different subset per table. | `Quote_Document_Column__c` child rows | [02](steps/step-02-column-snapshot-object.md) |
| 4 | **Row visibility** | The guides contain renderer conditionals based on `Row_Type`, plus styling conditionals. The exact count is intentionally not frozen because prose examples and executable tags are mixed; Step 00 classifies every hit. | `Is_Displayed__c`, honoured by every adapter; `Row_Type` remains styling-only | [06](steps/step-06-contract-validation.md) |
| 5 | **Whether a whole section appears** | [`optional-products-guide.md:194`](../../docs/optional-products-guide.md:194) — a `count(...) > 0` XPath hides the section when the quote has no optional lines. | `Quote_Document_Table__c.Is_Displayed__c` | [01](steps/step-01-table-presentation-fields.md) |
| 6 | **Narrative text (disclaimer)** | [`optional-products-guide.md:192`](../../docs/optional-products-guide.md:192) — "print a clear disclaimer above this table (plain Word text, not a tag)". The only copy of that sentence is in a Word file. | `Intro_Text__c`, or `Quote_Document_Block__c` if it is not table-attached | [04](steps/step-04-narrative-blocks.md) |
| 7 | **English sentence construction inside Apex** | [`QuoteDocumentRowBuilder.cls:228`](../../force-app/main/default/classes/QuoteDocumentRowBuilder.cls:228) builds `g.value + ' Subtotal'`; line 283 builds `Total … Charges`; line 298 emits `Total`; line 328 falls back to `'(unnamed)'`. `QuoteDocumentTableDefinition` also defaults the composite separator. Not a template problem — this is generation logic that must be centralized. | Semantic key plus dictionary | [03](steps/step-03-semantic-keys-and-localization.md) |
| 8 | **Locale** | Nowhere. No object carries one. | `Locale__c` on table and block, and inside the fingerprint | [03](steps/step-03-semantic-keys-and-localization.md), [05](steps/step-05-snapshot-integrity.md) |
| 9 | **`Group_Dimensions__c`** | Holds API names (`SBQQ__Product__r.Family > CHARGE_TYPE`). Diagnostic, never printable — must be explicitly excluded from the render contract. | unchanged, documented as non-printable | [09](steps/step-09-docs-and-closeout.md) |

**Inventory baseline on 2026-08-27:** 15 table definitions exist, seven are active, and four definitions name row customizers. Any step that reports “ten tables” is stale and must re-run the inventory.

**Already compliant, do not rebuild:** all arithmetic and reconciliation (`verify()`), grouping and nesting, row ordering (`Display_Order__c`), persisted row labels (`Display_Label__c`), snapshot status and fingerprint (`Document_Data_Status__c`, `Document_Data_Fingerprint__c`, and `QuoteDocumentFingerprint`, which already hashes table-definition and grouping inputs), and the `Quote_Document_Key_Value__mdt` dictionary primitive. Existing compliance does not mean the API is simple enough to extend; Step 01A supplies the supported boundary.

---

## 3. Smallest complete data model

The day-one model. Existing fields are renamed or removed where the clean shape is better — see §4.

```
SBQQ__Quote__c
├── snapshot identity              Document_Data_Request_Id__c (EXISTS, currently unwritten
│                                  — wire it up, do not add a second correlation field),
│                                  Document_Data_Fingerprint__c (EXISTS — source identity),
│                                  + Document_Payload_Hash__c (persisted-output integrity),
│                                  + Document_Content_Version__c, resolved locale
├── Quote_Document_Table__c        (+ Display_Title__c, Display_Subtitle__c,
│   │                                Intro_Text__c, Footer_Text__c,
│   │                                Locale__c, Is_Displayed__c)
│   ├── Quote_Document_Column__c   NEW — Column_Code__c, Display_Label__c, Display_Label_Key__c,
│   │                                    Display_Order__c, Value_Field__c,
│   │                                    Data_Type__c, Is_Displayed__c
│   └── Quote_Document_Row__c      (+ Display_Label_Key__c, Label_Arg_1__c, Label_Arg_2__c)

Quote_Document_Table_Def__mdt      (+ Display_Title__c, Display_Subtitle__c, Intro_Text__c,
                                     Footer_Text__c and their *_Key__c counterparts,
                                     Row_Customizer_Version__c,
                                     Row_Customizer_Flow__c, Row_Customizer_Flow_Version__c,
                                     Cache_Policy__c,
                                     Contributor_Dependency_Set__c)
└── Quote_Document_Block__c        NEW — Block_Code__c, Block_Type__c,
                                   Display_Order__c, Is_Displayed__c, Locale__c,
                                   Heading__c, Body__c, Source_Version__c
```

**`Quote_Document_Column__c` over `Column_1_Label__c … Column_N`.** Checked against the real shapes: `PRICE_WATERFALL` exposes six measures, `CHANGE` seven, and the guides print *a different subset in a different order per table* — three columns for `PRODUCT_FAMILY_SUMMARY`, four for `CHARGE_TYPE_SUMMARY`. Fixed slots would need roughly eight label fields, plus eight more to record which measure each slot binds, on every table, mostly null — and would still not carry a data type. A child object is fewer fields and answers "which columns, in what order, bound to what, formatted how" in one query.

**One correlation Id, on the Quote only.** `SBQQ__Quote__c.Document_Data_Request_Id__c` already exists and its help text already describes exactly this job — telling one attempt from another for support. It is currently written by nothing; wire it up rather than adding a second field with the same meaning. It is deliberately **not** stamped onto tables, columns, or blocks: generation runs inside one savepoint, so **a failed attempt leaves no records created by that attempt** — on a failed regeneration the previous committed snapshot is restored unchanged, with its original record Ids. That is the single invariant, stated the same way everywhere in this spec set. "Did records from the failed attempt survive" is therefore a question the transaction boundary already answers. Add per-record stamping only if generation ever spans transactions — which it does not, and which would need its own spec.

**`Quote_Document_Block__c` is foundational, not speculative.** Introductions, notices, terms, clauses, signature instructions, and headings between tables are all standalone; `Intro_Text__c` / `Footer_Text__c` are table-attached and cannot model them without inventing an empty table. A contract that claims to carry the whole document while standalone content sits outside it fails on the first real template. The [step 04](steps/step-04-narrative-blocks.md) inventory now decides which block codes ship, not whether the object exists.

---

## 4. Day-one deployment — no backward compatibility

**There is no installed legacy system.** Nothing depends on the current snapshot shape except templates this spec is replacing, so the earlier "additive only, nothing renamed" framing was a self-imposed constraint that made the target model less clear. It is removed. Deploy the complete contract, regenerate, and delete what the clean model does not need.

| Decision | Day-one position |
|---|---|
| Field shape | Rename or remove where the clean model is better. Additive-only is not a requirement. |
| Required-ness | Required in metadata wherever the platform allows it, not merely "required by the contract". A field the contract needs before `Complete` should be a required field. |
| Table definitions | Every **active** definition must carry its presentation configuration — title, columns, cache policy. No defaults standing in for unconfigured records. |
| Title fallback | **Removed.** `Display_Title__c` is not defaulted from `Table_Name__c`; an active definition without a title fails config load. |
| Pre-contract snapshots | No detection, no repair path, no "legacy" branch in retrieval. Regenerate. |
| Existing renderer mappings | Not preserved. The CLM Data Source and template are rebuilt against the new contract, or that renderer is non-conforming (§4.1). |
| Rollback tests | **Kept** — they test transactional correctness, not legacy support. |
| Fingerprint | Adding locale, content version, and contributor tokens changes every hash once. Release runs [step 05](steps/step-05-snapshot-integrity.md)'s invalidation job; Custom Metadata deployment does not mark quotes stale on its own. |
| Permission set | Every new field and object needs an entry in `CPQ_Document_Totals.permissionset-meta.xml`, or generation fails. |
| Reports | `Quote_Document_Tables_and_Rows.reportType-meta.xml` lists fields explicitly; a new printable field is invisible in reports until added there. |

### 4.1 No renderer reads the objects directly

The launch contract (§1) and "the CLM template keeps working unchanged" cannot both be true: a Data Source pointed at `Quote_Document_Table__c` never calls generate-or-reuse and never passes an expected fingerprint. The architecture wins.

> **Direct document-product access to the Quote Document objects is unsupported.** Every renderer — DocuSign CLM included — launches through a Salesforce-controlled action that performs generate-or-reuse and binds the resulting snapshot by request Id and fingerprint. A renderer that cannot be launched that way is not a conforming renderer.

For CLM this means the generate action is invoked from Salesforce, not from the CLM side, and the template consumes what that action bound. If the tenant cannot support that, the honest outcome is that CLM stops being the renderer — not that the contract acquires an exception. There is no "best-effort adapter" tier.

---

## 5. Steps

Each step is independently verifiable. A step's verification must pass before the next one starts.

| Step | Title | Gate | Status |
|---|---|---|---|
| [00](steps/step-00-audit-and-contract-principles.md) | Audit sign-off and contract principles | Owner approves the §2 audit and the §3 model | **Complete** |
| [01A](steps/step-01a-extension-contracts.md) | Apex and Flow extension seam | A Flow contributor changes rows with zero core diff | **Built** — §6a invalidation declaration outstanding |
| [01](steps/step-01-table-presentation-fields.md) | Table presentation fields | A `Ready` quote's tables carry printable titles and visibility | **Complete** |
| [02](steps/step-02-column-snapshot-object.md) | Column snapshot object | Every generated table has ordered, labelled, typed columns | **Built** — DTO-side items landed in 07 |
| [03](steps/step-03-semantic-keys-and-localization.md) | Semantic keys and central localization | No English literal is constructed outside the dictionary | **Complete** |
| [04](steps/step-04-narrative-blocks.md) | Narrative blocks | Standalone document content prints, ordered with the tables | **Built** |
| [05](steps/step-05-snapshot-integrity.md) | Snapshot integrity | Locale and content version change the fingerprint | **Built** |
| [05A](steps/step-05a-generation-lifecycle.md) | Generation lifecycle | Abandonment, lock retry, and launch retry are specified and tested | **Built** — §5 retry needs the launch wrapper |
| [06](steps/step-06-contract-validation.md) | Contract validation | Ten named failure conditions each fail loudly | **Built** |
| [06A](steps/step-06a-snapshot-immutability.md) | Snapshot immutability and access control | A tampered snapshot cannot render; a renderer persona cannot touch the objects | **Built** — persona split needs the B1 security review |
| [07](steps/step-07-render-service-dto.md) | `QuoteDocumentRenderService` and DTOs | Payload is complete and vendor-free | **Built** — Flow wrapper outstanding |
| [08](steps/step-08-two-adapters.md) | Two adapters (JSON, HTML) | A second adapter is added with a zero-line core diff | **Complete** — proven by `6c24eea` |
| [09](steps/step-09-docs-and-closeout.md) | Documentation and closeout | Architecture docs are vendor-neutral | **Complete** |

**Series status as of 2026-08-27: BUILT, NOT MERGE-READY.** An independent review after the first close-out found eight real defects, including three tests that passed for the wrong reason. All eight are fixed (`756c786`, `345b5c0`) with reproductions that failed on the old code, and they are listed in [step 09](steps/step-09-docs-and-closeout.md). The definition of done in §1 holds structurally — Commit `6c24eea` added two
renderers with an empty diff outside the adapter classes and their test — no object, no Custom Metadata
record, no permission set, no change to generation, calculation, or localization. 290 local tests ran, 285 passing and 5 failing;
the five failures are pre-existing org-only classes that do not exist in this repository.

"Built" rather than "Complete" means every mechanism the step specifies exists and is tested, with named
residual items in that step's close-out. [Step 09](steps/step-09-docs-and-closeout.md) carries the
consolidated deferred list — chiefly the B1 persona security review, the Flow launch wrapper and the
retry that lives in it, and the DocuSign CLM adapter rebuild, which is tenant configuration outside this
repository.

Every implementation step must use the shared [verification protocol](verification-protocol.md). Release cannot close until every [failure scenario](war-room-scenarios.md) has evidence **of the class that row declares** — an automated test, a green CI gate, a recorded drill, or an accepted residual risk. A scenario with no owning step is not covered, whatever the runbook says.

---

## 6. Scope discipline

This is a decoupling exercise, not a feature. Three things it deliberately does **not** do:

1. **No second calculation engine.** The persisted records stay authoritative; the DTO is a projection over them. If a value *can* be computed in the DTO, it belongs on the record instead.
2. **No speculative hierarchies in either direction.** The render DTO is the stable boundary for renderers; two demonstration adapters need no inheritance. On the contribution side, the seam that already exists is extended rather than duplicated — [step 01A](steps/step-01a-extension-contracts.md) adds a Flow bridge, label keys, and one subscriber factory hook, and adds no second contributor interface.
3. **No speculative fields.** `Secondary_Display_Text__c` and `Footnote_Text__c` are built only when a step's inventory finds a real requirement. A null column on every row is a cost paid forever for a document nobody asked for. `Quote_Document_Block__c` is **not** in this category — see [step 00](steps/step-00-audit-and-contract-principles.md) §3.1: a document contract without standalone content is not a document contract.

---

## 7. Where the flexibility actually comes from

"As flexible as possible" is not the same as "as configurable as possible" — a provider-discovery subsystem adds knobs while making the common case harder. These are the levers that let an org change the document without forking core, cheapest first. A design change is worth making only if it moves something up this list.

| Lever | What it lets someone change | Cost to use |
|---|---|---|
| Table definition CMDT | which tables, filters, measure family, sort, caps | one record |
| Grouping CMDT (`Level__c` × `Sequence__c`) | nesting or composite, any depth, any field path | one record per dimension |
| Column definition CMDT (step 02) | which columns, order, heading, data type | one record per column |
| **Any field on `Quote_Document_Row__c` as a column source** | a column bound to a field *the subscriber added in their own org* — additive, upgrade-safe, no core change | a custom field plus a CMDT row |
| Label dictionary (step 03) | every printable string, per locale | one CMDT row per key |
| Presentation fields (step 01) | titles, subtitles, intro and footer text, table visibility | one CMDT row |
| **Autolaunched Flow contributor** (step 01A §3) | arbitrary row logic, no Apex at all | one Flow plus one CMDT value |
| Apex customizer | anything the above cannot express | one class, one registry or factory entry |
| Renderer adapter (step 08) | the output format itself | one class, zero core diff |

The two additions that matter most for flexibility are the Flow contributor and letting a column bind a subscriber-added field. Together they mean an org can add a column carrying its own data, populate it declaratively, label it in its own language, and print it in any renderer — without a line of core Apex.

## 8. Hard build constraints

Release gates. Trimmed to what a test or a grep can actually enforce; anything already guaranteed by the existing savepoint, registry, or `verify()` is a property to pin with a test, not a constraint to restate.

1. **Core is closed for extension work.** Adding a table, column set, locale, Flow contributor, or renderer must not change generator, builder, verification, query, fingerprint, or DTO classes. Proven by the core-diff check defined in §9.
2. **Publication is core's, as a lifecycle rule.** `Ready` is set by core, after `verify()`, in the same transaction. This is the supported lifecycle, not a technical sandbox property — trusted Apex can issue its own update. Contributors are *asked* not to do snapshot DML or callouts and are not technically prevented from either (§1); what is enforced is that their **output** is validated and the attempt rolls back on failure.
3. **Deterministic replay.** Same input, config, locale, content version, **and contributor version tokens** produce the same semantic snapshot and fingerprint. Timestamps, record Ids, and the request Id are excluded from semantic equality. Replay is only deterministic under one generation persona — see §10.
4. **No hidden fallback.** A missing key, field, code, or locale fails with a stable error code and names what was missing. Never blank, never silently substitute.
5. **Flow and Apex parity.** Both go through the same seam, mutate the same in-memory row list, and are held to the same tests.
6. **Vendor vocabulary stops at the adapter.** CI greps core contracts and persisted printable data for vendor tokens and markup.
7. **Limits are measured at the supported maximum,** not observed after release: one test generates the largest supported quote and asserts query, DML, CPU, and heap stay within a recorded budget.

**Deliberately cut, so they are not re-added by reflex:**

| Cut | Why |
|---|---|
| "One owner per stage — acquire, normalize, contribute, assemble, localize, persist, verify, publish" | The generator was split into its three real responsibilities two commits ago, and every class is under 500 lines. Splitting into eight because a spec enumerated eight nouns adds indirection to a structure that is already legible. Localization is a new stage; the rest already have owners. |
| Per-request `contractVersion` on the contributor contract | Kept as a compile-time constant instead (§1). Subscriber code does not upgrade atomically with core, so *some* version marker is warranted — but a constant plus documented semantic rules covers it without a negotiation protocol on every invocation. |
| "No maps as undocumented schemas" | Only one map survives the design — `Row.values`, keyed by `Column.code` and validated against the column definitions. The rule has nothing left to prohibit. |
| Provider manifests, capabilities, row ceilings, ownership arbitration, failure policies | All presuppose several simultaneous contributors per table. Step 01A permits at most two, in a fixed order. Unreachable machinery is worse than absent machinery: it has to be read, tested, and upgraded forever. |

**Partly reinstated after review — contributor versions.** An earlier pass cut them along with the manifest subsystem. That was wrong: `canReuse` returns before customization, so changed contributor logic under an unchanged code string leaves the fingerprint identical and reuses a stale snapshot. Two CMDT version fields are back, as content identity inside the fingerprint. The manifest, capability, and ceiling machinery around them stays cut. See [step 01A](steps/step-01a-extension-contracts.md) §6.


---

## 9. What "zero core diff" actually proves

The check is a dependency-direction gate, not a path filter. `git show --stat -- .../classes` alone is foolable: business logic can be moved into a Flow, a CMDT record, or a formula field and still couple a subscriber to core internals.

| Adding this | Core Apex change | Existing core CMDT record change | New subscriber-owned metadata |
|---|---|---|---|
| A renderer adapter | ✗ forbidden | ✗ forbidden | ✓ expected |
| A Flow contributor | ✗ forbidden | ✗ forbidden | ✓ expected — the Flow, CMDT rows, permission-set entries |
| A new table or column set | ✗ forbidden | ✗ forbidden | ✓ expected — CMDT rows, and a custom field on `Quote_Document_Row__c` if the column needs one |
| An Apex contributor | ✗ forbidden | one CMDT row naming the subscriber factory | ✓ expected |

So the gate is: **(a)** no diff in the core class list named in §8.1; **(b)** no modification to an existing shipped CMDT record — new records are fine; **(c)** the reviewer states which direction the new code depends on. Additive subscriber metadata is the expected shape of an extension, not a failure of it, and a step whose proof shows an empty diff *everywhere* has probably not been exercised.

---

## 10. Generation persona — one open product decision

`QuoteDocumentQuery` runs the quote/line query `WITH USER_MODE`; the table delete and the row inserts do not, and the framework must not be described as user-mode throughout. That leaves a question this spec cannot dodge, because an immutable snapshot whose content depends on *who clicked generate* is not deterministic: two sales users with different field-level security on a column's bound field would produce different documents, or one would fail.

"Runs as a service user" is not something Apex can simply switch to. A Queueable keeps the submitting user's identity, and `WITH USER_MODE` is precisely a statement that the running user's permissions apply. So option B has to name its mechanism or it is a preference, not a requirement:

| Model | Mechanism | Consequence |
|---|---|---|
| **A — requesting user** | keep `WITH USER_MODE` on source reads | FLS is part of the document contract. Every column binding must be readable by every user allowed to generate, the permission set becomes a hard release artifact, and deterministic replay holds only within one permission profile. |
| **B1 — system context, gated at the entry point** *(recommended)* | drop `WITH USER_MODE` on source reads, run generation in system mode, and gate the action on a `Generate_Quote_Document` custom permission | Identical output whoever generates. Deliberately separates *permission to generate* from *permission to read every contributing source field* — which is why it needs a security review, not just a design decision. |
| **B2 — a genuinely separate execution identity** | dispatch through an integration/service user via a mechanism that actually changes identity | Heaviest. Only justified if reads must be attributable to a service principal for audit. |

Recommended shape if B1 is chosen:

```
Authorization:  the requesting user holds the Generate_Quote_Document custom permission.
Execution:      core source reads and snapshot writes run in documented system context,
                so identical source data produces identical output.
Renderer access: enforced separately, through object/field permissions on the snapshot
                objects or through the render service.
```

[Step 00](steps/step-00-audit-and-contract-principles.md) records the choice. Until it is made, "any readable field is a valid column source" ([step 02](steps/step-02-column-snapshot-object.md)) has two different meanings, and step 05's replay determinism claim is unproven.
