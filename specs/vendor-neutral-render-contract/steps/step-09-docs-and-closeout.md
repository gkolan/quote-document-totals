# Step 09 — Documentation and closeout

**Status: COMPLETE**
**Blocked by:** [step 08](step-08-two-adapters.md)
**Blocks:** nothing

---

## 1. Goal

The docs describe the architecture as *generation layer → render contract → replaceable adapter*, and the DocuSign material is clearly one adapter implementation rather than the system design.

## 2. Why this step exists

If the flagship doc keeps opening with what DocuSign does with the rows, the next developer rebuilds vendor coupling from the documentation even though the code no longer requires it. This step is also where the template conditionals from audit row 4 get replaced — the count is taken mechanically at implementation time, not frozen here — which is the last place presentation logic still lives outside Salesforce.

## 3. Scope

1. **[`docs/quote-document-totals.md`](../../../docs/quote-document-totals.md)** — replace the "DocuSign then does one thing" framing at line 23 with the vendor-neutral contract: what a renderer may and may not do ([`spec.md`](../spec.md) §1). Add a section covering `Quote_Document_Column__c`, the presentation fields, localization, and `QuoteDocumentRenderService`.
2. **Template migration.** Inventory all current `*-guide.md` files (ten at the 2026-08-27 baseline) and update every guide that contains renderer filtering logic. Replace filtering conditionals with `Is_Displayed`; keep conditionals used purely for bold/border styling and label them as styling. Re-count mechanically at implementation time.

   | Before | After |
   |---|---|
   | `Conditional Test="Row_Type='Subtotal' or Row_Type='Grand Total'"` (deciding what prints) | `Conditional Test="Is_Displayed='true'"` |
   | `count(...) > 0` section suppression | table-level `Is_Displayed` |
   | Column headings typed in Word | bound from `Quote_Document_Column__c` |
   | Table heading typed in Word | bound from `Display_Title__c` |

3. **Rewrite the DocuSign sections.** Each guide's §9 becomes "Adapter: DocuSign CLM", opening with the launch sequence — a Salesforce action performs generate-or-reuse and binds the published snapshot — and stating that a Data Source querying the objects directly is not a conforming renderer. The same payload drives the JSON and HTML adapters from step 08.
4. **Update the CLM Data Source** documentation to add the `Quote_Document_Column__c` repeating node and the new table fields.
5. **[`docs/documentation-standards.md`](../../../docs/documentation-standards.md)** — new guides must document the column definitions and the semantic keys a table uses, and must not put printable text in the template section.
6. **[`docs/quote-document-totals-for-business-admins.md`](../../../docs/quote-document-totals-for-business-admins.md) and the architecture guide** — same reframing in plain language, plus how an admin edits a title, a column heading, or a translation without a developer.
7. **[`CLAUDE.md`](../../../CLAUDE.md)** — add this spec to the reading list.
8. **Note the non-printable fields explicitly:** `Group_Dimensions__c` holds API names and `Name` holds an identifier. Neither is ever printed. Audit row 9 exists because that is easy to get wrong.
9. Add two extension recipes: **Add your own Apex customizer** and **Add your own autolaunched Flow customizer**. Each is copyable without reading generator internals: files to copy, the CMDT row, a local test, the deploy command, a verification query, how to switch it off, and the error codes it can raise.
10. **Document the launch contract as the supported integration path** ([step 01A](step-01a-extension-contracts.md) §6b): every production launch calls generate-or-reuse, then passes the returned request Id and fingerprint to `getPayload`. State plainly that reading a `Ready` snapshot without that call is unsupported, and why — invalidation for external dependencies is best-effort, fresh fingerprint computation is not. The DocuSign adapter section must show this sequence, since a CLM Data Source reading the objects directly is exactly the bypass.
11. Publish the error-code catalogue, the verification protocol, and the failure-scenario runbook. Every operational query selects `Document_Data_Request_Id__c` and the fingerprint.

## 4. Out of scope

- Rewriting the guides' grouping, measure, or reconciliation sections. Those are unchanged and correct.
- Removing DocuSign material. It stays, correctly labelled as one adapter — but rewritten to the launch contract, not preserved as-is ([`spec.md`](../spec.md) §4.1).

## 5. Acceptance criteria

- [x] No architecture doc presents DocuSign as the system's rendering model.
- [x] Every guide's §9 is labelled as an adapter.
- [x] No filtering conditional remains in any guide; every surviving conditional is annotated as styling.
- [x] No guide instructs the author to type a table title or column heading into Word.
- [x] Standards file requires columns and semantic keys in new guides.
- [x] `CLAUDE.md` reading list updated.
- [x] Series-level: the definition of done in [`spec.md`](../spec.md) §1 is demonstrably true, evidenced by the step 08 commit SHA.

## 6. Verification method

```bash
grep -rn "Conditional Test" docs/*.md
```

Every remaining hit must be a styling conditional or an `Is_Displayed` test — no `Row_Type='...'` used to decide whether a row prints, and no `count(...)` section suppression.

```bash
grep -rniE "docusign|springcm" docs/quote-document-totals.md docs/quote-document-totals-architecture-guide.md
```

Hits are allowed only inside a sentence that names DocuSign as one adapter.

Full regression before closeout:

```bash
sf apex run test --test-level RunLocalTests --result-format human --wait 30
```

## 7. Close-out

- **Date:** 2026-08-27

### Series outcome

**The definition of done in [`spec.md`](../spec.md) §1 is demonstrably true**, evidenced by commit
**`6c24eea`**: two adapters were added, and the diff outside the two adapter classes and their test is
empty. No object, no Custom Metadata record, no permission set, no change to generation, calculation,
or localization. The close-out line "anything the adapters had to compute themselves" is empty.

Both acceptance greps pass:

- `grep -rn "Conditional Test" docs/*.md` — every remaining hit is an `Is_Displayed` test, a
  conditional explicitly annotated as **styling**, or the syntax-reference table in the CLM guide. No
  `Row_Type='...'` deciding whether a row prints; no `count(...)` section suppression anywhere.
- `grep -rniE "docusign|springcm"` on the two architecture docs — every hit now sits in a sentence
  naming DocuSign as *one adapter*.

### What changed in the docs

| File | Change |
|---|---|
| [`quote-document-totals.md`](../../../docs/quote-document-totals.md) | Opening reframed from "DocuSign then does one thing" to "a renderer then does one thing". New **Render contract** section: what a renderer may and may not do, what the snapshot carries, the launch contract, localization, reading a payload, and the two hashes |
| Seven table guides | §9 relabelled **"Adapter: DocuSign CLM"**, each opening with the launch sequence and stating that a Data Source querying the objects directly is not a conforming renderer |
| Five guides | Filtering conditionals replaced with `Is_Displayed`; surviving conditionals annotated as styling |
| [`optional-products-guide.md`](../../../docs/optional-products-guide.md) | The disclaimer is now read from `Intro_Text__c` rather than typed into Word — audit row 6 closed in the documentation as well as the code |
| [`quote-line-type-bundle-reporting-guide.md`](../../../docs/quote-line-type-bundle-reporting-guide.md) | §11.5 rewritten: `count()` suppression replaced by table-level `Is_Displayed`, with the reason |
| [`documentation-standards.md`](../../../docs/documentation-standards.md) | Five new rules for any new guide — document columns and semantic keys, never instruct the author to type printable text, conditionals are styling only, label the renderer section as an adapter |
| [`quote-document-totals-architecture-guide.md`](../../../docs/quote-document-totals-architecture-guide.md) | Same reframing in plain language, plus **"Changing what the document says, without a developer"** — which record to edit for a heading, a label, or a translation, and the warning that editing metadata does not update existing documents |
| **NEW** [`quote-document-extension-recipes.md`](../../../docs/quote-document-extension-recipes.md) | Both extension recipes end to end, plus the full error-code catalogue |
| [`CLAUDE.md`](../../../CLAUDE.md) | Reading list updated; a note on how the render contract changes the way printable text is added |

Audit row 9 is documented explicitly: `Group_Dimensions__c` holds API names and `Name` holds an
identifier. Neither is ever printed, and both are named in the render-contract section because that is
easy to get wrong.

### Test evidence

**290 local tests ran: 285 passed, 5 failed.** The only failures are the five pre-existing, org-only ones first recorded in
[step 01A](step-01a-extension-contracts.md) §11 — `QuoteDocumentGeneratorGuardTest`,
`QuoteDocumentTemplateConfigurationTest`, `QuoteDocumentTableDefinitionDefaultsTest`. **None of those
classes exists in this repository.** They reference `Quote_Document_Template_Table__c` and a
`fromTemplateTable` method this codebase does not have, and this series did not create them. **Correction (2026-08-27, after review):** an earlier version of this line said they "failed identically before the first line of this step was written". The evidence actually available is that the classes are absent from this repository, which shows this work did not produce them — it does not establish when they first failed, and nobody has checked. The accurate claim is the narrower one. They are worth clearing separately, since they will keep polluting
every future `RunLocalTests`.

---

## Review, 2026-08-27 — eight defects found after this close-out was written

An independent review of the finished series found eight real defects. They are fixed in commits
`756c786` and `345b5c0`, each with a reproduction written to fail on the old code. Recorded here
because a close-out that reads as finished, next to a series that was not, is the more expensive
mistake.

**Three were tests that passed for the wrong reason** — the exact failure this series criticised
elsewhere and then shipped:

| # | Defect | Why the test passed anyway |
|---|---|---|
| 2 | The contributor-version gate checked whether the metadata **file** changed, not whether the **token** did | Editing anything in the record satisfied it while the version stood still |
| 3 | Integrity verification cost four queries **per quote** in a batch | The flat-query test requested the *same* quote three times, so it measured the per-quote cache rather than the work |
| 8 | HTML "equivalence" only scanned for section, column and row identifiers | Wrong amounts, missing wording and reordered rows would all have passed |

**Five were defects with no test at all:**

1. **Table text edits could reuse a stale document.** The fingerprint omitted `Display_Title__c`,
   `Display_Subtitle__c`, `Intro_Text__c` and `Footer_Text__c` — the words the customer reads. Correct a
   heading, regenerate, get the old wording back with the quote still `Ready`. The same class of defect
   the contributor version tokens exist to prevent, introduced by the step that added the fields.
4. **Integrity hashing used a fixed field list** while rendering selects bindings dynamically, so a
   subscriber-bound column could be edited after publication and leave the hash identical.
5. **Locale contradicted its own class comment.** `orgDefault()` returned `UserInfo.getLocale()` while
   the comment said "DELIBERATELY NOT the running user's locale". And the configured locale path was
   never added to the query, so it always read as absent.
6. **The payload lost its currency.** `CurrencyIsoCode` was never selected but was read from the
   populated-fields map, so it was null in every org and both adapters formatted money with no currency.
7. **The lifecycle helpers were computed but never acted on.** `isAbandoned()` and `lockTimeout()` had
   no production callers and the backoff was only logged, so the abandonment window and the terminal
   lock code were numbers nothing consulted.

**Also added:** `.github/workflows/ci.yml`. The version gate was an npm script nothing invoked — a gate
nobody runs is documentation.

**Two Apex traps the new tests surfaced, worth knowing:**

- `==` on `String` is **case-insensitive**, so a check for an uppercase token treated the word "Not" in
  "Not Specified" as a currency code.
- Assertion **message arguments are evaluated eagerly**, so an index built for the failure path threw on
  the passing path.
- Custom Metadata SOQL **throws inside `System.runAs`**, which is why the two-user locale test is
  structured the way it is rather than the obvious way.

**Status after the fixes:** 302 tests ran, 297 passed, 5 failed — the three org-only classes only. That
is not the same as merge-ready: the release blockers below are unchanged, and the reviewer's judgement
that this series is not finished stands.

---

## Deferred items

Carried forward honestly rather than closed. None blocks the definition of done; each is named where it
would land.

### Needs a decision or a person

| Item | Owner | Where |
|---|---|---|
| **B1 persona security review** | owner | [step 00](step-00-audit-and-contract-principles.md) §7 — outstanding since the first step. B1 deliberately separates permission-to-generate from permission-to-read-every-source-field, which is why it ships *subject to* review |
| **Three-persona permission-set split** and the `Generate_Quote_Document` custom permission | needs the security review | [step 06A](step-06a-snapshot-immutability.md) §3.2 |
| **Four B1 misconfiguration codes** — `LAUNCH_PERMISSION_MISSING`, `SERVICE_SOURCE_ACCESS_MISSING`, `RENDER_SERVICE_ACCESS_MISSING`, `RENDERER_HAS_DIRECT_CRUD` | same | step 06A §5 |
| **`Quote_Document_Block__c` sharing asymmetry** — it hangs off a Quote lookup, so `ControlledByParent` is unavailable and it is `ReadWrite` while its siblings are locked. Covered by the payload hash, but detection is not prevention | owner | step 06A close-out |

### Needs the launch Flow

| Item | Where |
|---|---|
| **Flow invocable wrapper** for the render service. Apex callers are fully covered; the declarative wrapper needs the versioned-request shape settling with whoever builds the launch Flow | [step 07](step-07-render-service-dto.md) §5 |
| **`SNAPSHOT_MOVED` at-most-one retry**, and its five tests. `SNAPSHOT_MOVED` is raised and tested; the retry policy belongs to the launch wrapper, as [step 05A](step-05a-generation-lifecycle.md) §5.1 says explicitly | step 05A §5 |
| **DocuSign CLM adapter rebuild.** Needs the launch action plus a rebuilt Data Source and template in the tenant — org configuration outside this repo. The rule it must meet is already fixed by [`spec.md`](../spec.md) §4.1 | [step 08](step-08-two-adapters.md) §3.6 |

### Needs the subscribers spec

| Item | Where |
|---|---|
| **`DEPENDENCY_INVALIDATION_UNDECLARED`** — declared dependency *values* are hashed, but a pack cannot yet declare its invalidation mapping or `LaunchRefreshOnly`. Needs the dependency-pack concept | [step 01A](step-01a-extension-contracts.md) §6a |
| **`DEPENDENCY_UNREADABLE` per-cause tests** — the code fires; the four separate causes are not each pinned, and the permission case depends on the B1 review | step 01A §9 |

### Testing gaps, stated rather than papered over

| Gap | Why |
|---|---|
| **Real lock contention** is not tested. The retry *policy* is (what is retryable, the limit, that backoff grows and carries jitter), but Apex unit tests cannot open a second concurrent transaction. A mocked `UNABLE_TO_LOCK_ROW` would prove the handler while appearing to prove the behaviour — the substitution [step 05A](step-05a-generation-lifecycle.md) §8 warns against | step 05A |
| **One equivalence fixture carrying every §3a distinction simultaneously** was not built. Every distinction is covered, but not all by one record, so if the intent was to prove they compose, that is not shown | [step 08](step-08-two-adapters.md) §3a |
| **`duplicateKeyInOneCategoryFails`** asserts the strict loader's contract rather than deploying a duplicated metadata record, which would break every other test in the org | [step 03](step-03-semantic-keys-and-localization.md) |
| **Supported-maximum governor check** is asserted as flat query count rather than against a sized fixture. Flatness is the stronger property; a sized fixture would add a number to maintain | [step 07](step-07-render-service-dto.md) |
| **Whole-generation limits budget** at the supported maximum. The Flow round trip alone is measured (685 ms CPU, ~329 KB heap at 1000 rows); generation as a whole is not, and its budget must be stricter | [`spec.md`](../spec.md) §8.7 |

### Also worth doing

- **Update [`war-room-scenarios.md`](../war-room-scenarios.md)** to point at `LIFECYCLE`/`ABANDON_MINUTES`
  and the error-code catalogue. The abandonment window is configuration and is documented in step 05A,
  but the runbook has not been rewritten to match.
- **Clear the three org-only test classes** that pollute every `RunLocalTests` run.
