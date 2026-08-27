# Step 01A — Apex and Flow row-contribution seam

**Status: BUILT — not yet COMPLETE. Every mechanism in this step exists and is tested; the residual gaps are named in §11.**
**Blocked by:** [step 00](step-00-audit-and-contract-principles.md)
**Blocks:** steps 01–09
**Owner decision needed:** none outstanding. Namespace scope was decided in [step 00](step-00-audit-and-contract-principles.md) §7 as **A — same namespace / unlocked source**; §8 and §11 record the consequence. Everything else in this step is locked by [step 00](step-00-audit-and-contract-principles.md) §3.

---

## 1. Goal

A subscriber changes **table-local row content** with either Apex or an autolaunched Flow, through the seam the framework already has, without editing core orchestration — and a change to that subscriber's logic reliably invalidates the snapshot it affects.

## 2. Trust model — state it honestly

> **Contributors are trusted in-transaction extensions.** Core owns publication, validates contributor output, and rolls back the attempt on any failure. Core **cannot** sandbox a contributor from SOQL, DML, async work, or callouts. Apex has no such sandbox, and neither does Flow.

The earlier draft of this step claimed the existing seam prevents DML and publication "by construction". That is wrong, and the correction matters because a spec that overstates its guarantees is how those guarantees stop being checked. Concretely, [`QuoteDocumentRowCustomizerContext`](../../../force-app/main/default/classes/QuoteDocumentRowCustomizerContext.cls) exposes `public SBQQ__Quote__c quote` — a live, mutable SObject. A customizer can update the Quote, insert unrelated records, enqueue a Queueable, or run its own DML. Handing it uninserted rows means only that core owns the *intended* row insert.

What core can actually guarantee, and must therefore test:

| Guarantee | Mechanism | Real? |
|---|---|---|
| Core alone writes the snapshot rows | contributors receive an in-memory list | yes |
| Core's own publication follows verification | `markQuote` runs after `verify()` | yes - but this is the supported lifecycle, not a lock. Trusted Apex can issue its own `update` on the Quote. What core guarantees is that *its* publication is post-verification, and that uncommitted intermediate state is never externally visible |
| Invalid contributor **output** is rejected | §5 output validation plus `verify()` | yes |
| The whole attempt rolls back on failure | one savepoint in the generator | yes, for DML in the same transaction |
| A contributor performs no DML, SOQL, or callouts | — | **no.** Only static analysis on the subscriber's own code can approach this, and it is not a core guarantee |

Shipped examples are tested to behave. Arbitrary subscriber code is trusted, and the extension guide must say so in those words.

## 3. Scope boundary — this seam owns rows, and only rows

A row customizer cannot naturally contribute a table definition, a title, columns, a standalone block, document-level properties, section ordering, or locale selection. Advertising it as a universal document-contribution contract would be false, and would push people to abuse it. The division across this spec and its companion:

| Requirement | Mechanism | Owned by |
|---|---|---|
| Extra source fields | extra-field declaration | [subscribers spec](../../quote-document-subscribers/spec.md) |
| Line classification | line interpreter | subscribers spec |
| Table eligibility | eligibility policy | subscribers spec |
| Which tables, grouping, nesting | `Quote_Document_Table_Def__mdt` + `Quote_Document_Grouping__mdt` | shipped |
| Columns and headings | `Quote_Document_Column_Def__mdt` | [step 02](step-02-column-snapshot-object.md) |
| Titles, subtitles, intro/footer, table visibility | table-definition CMDT | [step 01](step-01-table-presentation-fields.md) |
| Printable strings, per locale | dictionary | [step 03](step-03-semantic-keys-and-localization.md) |
| **Table-local row changes** | **Apex or Flow row customizer** | **this step** |
| Document-level narrative | block mechanism | [step 04](step-04-narrative-blocks.md) |
| Output format | render adapter | [step 08](step-08-two-adapters.md) |

Each owns a materially different lifecycle point, which is why this is still a small number of seams rather than a dozen tiny interfaces.

## 4. Flow parity

One shipped bridge, `QuoteDocumentFlowRowCustomizer`, registered in the existing closed registry under code `FLOW`.

1. New fields on `Quote_Document_Table_Def__mdt`: `Row_Customizer_Flow__c` (Flow API name, namespace-qualified where applicable) and `Row_Customizer_Flow_Version__c` (see §6).
2. The bridge calls `Flow.Interview.createInterview(flowApiName, inputs)` and reads the output collection back.
3. Variables — plain Salesforce types, no Apex-defined types, no JSON:

   | Direction | Variable | Type |
   |---|---|---|
   | in | `rows` | record collection, `Quote_Document_Row__c`, in memory, no Ids |
   | in | `quoteId`, `tableCode`, `locale`, `currencyIsoCode` | Text |
   | out | `rows` | record collection, `Quote_Document_Row__c` |

4. **Prototype before the rest of this step is written.** The design rests on uninserted SObjects surviving a `Flow.Interview` round trip. Prove it in a scratch org against the target API version, across this matrix — a bare round trip is not enough.

   **Result: PROVEN on 2026-08-27**, org `gkCpqDevHub` (`00Dbm00000sk0IrEAI`), API v67.0. Artefacts: [`QuoteDocumentFlowRoundTripProbe`](../../../force-app/main/default/flows/QuoteDocumentFlowRoundTripProbe.flow-meta.xml) (autolaunched — loops every input row through an assignment, mutates one field, appends one Flow-created row) and [`QuoteDocumentFlowRoundTripProbeTest`](../../../force-app/main/default/classes/QuoteDocumentFlowRoundTripProbeTest.cls), **9/9 passing — test run Id `707bm00001BP1fD`**, re-checkable with `sf apex get test -o gkCpqDevHub --test-run-id 707bm00001BP1fD` rather than taken on trust. Uninserted `Quote_Document_Row__c` records survive intact; **the fallback to Apex-defined types is not needed and must not be built.**

   | # | Matrix item | Status | Evidence |
   |---|---|---|---|
   | 1 | existing rows return in the same order, Decimal scale and nulls preserved | ✅ proven | `existingRowsReturnInTheSameOrder`, `decimalScaleAndNullsSurvive`. `1234.5600` returns with its scale intact, and a null `Amount_List__c` returns **null, not zero** — the distinction the framework depends on |
   | 2 | Boolean inclusion flags survive | ✅ proven | `inclusionFlagsSurviveInBothStates` — all three flags, asserted in **both** states, so a surviving `false` is not a lost `true` |
   | 3 | rows created inside the Flow arrive back | ✅ proven | `rowsCreatedInsideTheFlowArriveBack` — every field the Flow set survives, and the row carries no Id |
   | 4 | fields added to `Quote_Document_Row__c` outside core survive | ✅ proven | `fieldsCoreDoesNotPopulateSurvive`. The round trip copies the SObject, so "core field" is not a distinction the mechanism can make: fields the builder never populates survive, therefore a subscriber-added field does |
   | 4b | a mutation made inside the Flow reaches Apex | ✅ proven | `mutationInsideTheFlowReachesApex`. Not in the original matrix and it should have been — a round trip that preserves everything but discards edits is a seam that contributes nothing. **Authoring consequence:** a Flow loop variable is a *copy*, so a contributor Flow must collect edited rows into a second collection and assign that back to `rows`. Editing in place inside the loop silently does nothing. The extension recipe must lead with this |
   | 5 | one output collection, same variable name, is returned | ✅ proven | `getVariableValue('rows')` returns the collection under the same name. **`CONTRIBUTOR_NO_OUTPUT` itself is bridge behaviour, still to build** |
   | 6 | zero returned rows distinguishable from null | ⚠️ half | `emptyInputCollectionRoundTrips` proves an empty collection round trips as non-null and is distinguishable from null. The *validation* that zero rows fails is bridge work |
   | 7 | `CONTRIBUTOR_FLOW_FAULT` | ⛔ bridge | no bridge exists yet, so there is nothing to fault |
   | 8 | `CONTRIBUTOR_FLOW_UNAVAILABLE` | ⛔ bridge | same |
   | 9 | namespaced Flow API names resolve | ➖ N/A | step 00 chose namespace option **A**, and `sfdx-project.json` declares `"namespace": ""`. Revisit only if option B is ever adopted |
   | 10 | largest supported table: CPU and heap against budget | ✅ recorded | 1000 rows in, 1001 back: **685 ms CPU** of a 10,000 ms limit (6.9%) and **328,529 bytes heap** of 6,000,000 (5.5%). Pinned by `largestSupportedTableStaysWithinBudget` at **3 s / 2 MB** — set against the *measured* cost, not against the governor limits. Asserting below the platform ceiling would assert nothing, since Apex throws its own `LimitException` first and the test could never be what failed. This is a viability tripwire on the round trip alone; the real budget, measured across whole generation at the supported maximum, belongs to §9 and [`spec.md`](../spec.md) §8.7 and must be stricter |

   Rows 5–8 are **not** round-trip fidelity questions; they are behaviours of a bridge that does not exist yet. They move to §9's acceptance list rather than blocking this gate, and the question the gate actually guards — *does the mechanism work at all* — is closed.

   If uninserted records do not survive, the fallback is Apex-defined types with `@AuraEnabled` fields (costing a DTO layer and a harder Flow to author); a JSON string is the last resort and then needs a documented schema and negative tests. **Do not build on this assumption unproven.** *(Superseded by the result above — retained so the reasoning behind the gate stays legible.)*

## 5. Output validation — what is already checked, and what this step adds

"`verify()` runs afterward" is only meaningful per invariant. [`QuoteDocumentVerification`](../../../force-app/main/default/classes/QuoteDocumentVerification.cls) covers some of these today and not others:

| Contributor can return | Covered today | This step |
|---|---|---|
| Duplicate `Row_Key__c` | ✅ `assertUniqueRowKeys` | pin with a test |
| No Grand Total | ✅ `findGrandTotal` throws | pin with a test |
| Unbalanced subtotals or grand total | ✅ assertions 1–4 | pin with a test |
| **Two Grand Total rows** | ❌ `findGrandTotal` returns the first match | add `CONTRIBUTOR_MULTIPLE_GRAND_TOTALS` |
| **Duplicate or null `Display_Order__c`** | ❌ | add — [step 06](step-06-contract-validation.md) condition 4 |
| **Grand Total not last, Detail after it** | ❌ | add `ROW_ORDER_INVALID` |
| **A row belonging to another table** | ❌ | add `CONTRIBUTOR_FOREIGN_TABLE` |
| **Measure fields outside the table's measure set** | ❌ | add `ROW_MEASURE_MISMATCH` |
| **Hidden row that counts toward nothing** | ✅ `Hidden_Row_Must_Count` validation rule | pin with a test |
| **A returned row carrying an Id** | ❌ | add `CONTRIBUTOR_RETURNED_PERSISTED_ROW` |

That last code is deliberately named for what it observes. A populated Id proves the row is persisted — it does **not** prove this contributor inserted it, and the reverse is worse: a Flow can insert rows and return different uninserted ones, update the Quote, or call an Apex action that does DML, all invisibly. Calling it `CONTRIBUTOR_DML_ATTEMPT` would claim a detection the check cannot make. See §2.

## 6. Contributor identity in the fingerprint — the correctness fix

[`QuoteDocumentGenerator.canReuse`](../../../force-app/main/default/classes/QuoteDocumentGenerator.cls:305) **returns before row building and customization** when the fingerprint matches. `QuoteDocumentFingerprint` hashes `rowCustomizerCode` — the *string*, not the behaviour behind it. So today:

> Deploy a changed `QuoteDocumentIndustryRowCustomizer`, or edit an autolaunched Flow, leaving the code and API name unchanged → the fingerprint is identical → the quote stays `Ready` → regeneration silently reuses a snapshot the new logic would not have produced.

That is a wrong-document defect, not a hygiene issue, and it is why removing every notion of contributor version was unsafe. The minimum fix is a **content-identity token**, not version negotiation:

| Field | On |
|---|---|
| `Row_Customizer_Version__c` | `Quote_Document_Table_Def__mdt` |
| `Row_Customizer_Flow_Version__c` | `Quote_Document_Table_Def__mdt` |

Both participate in `QuoteDocumentFingerprint.canonicalize`. Deploying changed contributor logic **must** bump the corresponding value and run the [step 05](step-05-snapshot-integrity.md) invalidation job. Nothing in the platform can detect the Apex or Flow body changing, so this is an operational discipline core enforces only by making the token part of identity — document it in the extension recipe and in the release checklist.

### 6a. Contributor *inputs* — the other half of the same hole

A version token identifies the contributor's **logic**. It says nothing about the **data that logic read**. Nothing in the framework watches anything outside the quote and its lines: [`QuoteDocumentStaleness`](../../../force-app/main/default/classes/QuoteDocumentStaleness.cls) is driven by the two triggers on `SBQQ__Quote__c` and `SBQQ__QuoteLine__c` and a fixed field set, and the fingerprint canonicalizes only the quote, its lines, and configuration. So:

```
Flow reads Account.Customer_Tier__c   →  tier changes on the Account
                                      →  no trigger, no fingerprint change
                                      →  canReuse() = true
                                      →  the document still shows the old tier
```

Version tokens do not close this, because the logic never changed. Every contributor must therefore declare one of two things, and a contributor that declares neither fails configuration validation with `CONTRIBUTOR_DEPENDENCY_UNDECLARED`:

`Cache_Policy__c` is a **picklist, not a checkbox** — a checkbox cannot distinguish "not configured" from an intentional false, and this is a value nobody may leave ambiguous:

| `Cache_Policy__c` | Meaning |
|---|---|
| `STANDARD` | The contributor reads only the normalized quote and lines. Nothing extra to hash. |
| `DECLARED_DEPENDENCIES` | `Contributor_Dependency_Set__c` names schema-validated field paths, or a dependency pack from the [subscribers spec](../../quote-document-subscribers/spec.md). Declared values are read into the canonical form and hashed. |
| `ALWAYS_REBUILD` | The contributor reads data it cannot enumerate. Reuse is skipped and customization reruns whenever generation is requested. |

Blank fails config load with `CONTRIBUTOR_DEPENDENCY_UNDECLARED`, as does `DECLARED_DEPENDENCIES` with an empty dependency set. Reading undeclared external data under `STANDARD` is prohibited — it is exactly the combination that produces a confidently wrong document. Core cannot detect the read; this is a declaration, and the extension guide must say so.

**Two things `ALWAYS_REBUILD` does not mean.** It does not mean the quote becomes `Stale` when external data changes — nothing observes that change. It means *rebuild whenever generation is requested*, which only helps because of the launch contract in §6b. And because [`canReuse`](../../../force-app/main/default/classes/QuoteDocumentGenerator.cls:305) is evaluated **per quote, not per table** — `generate` returns from the whole quote on a match — one `ALWAYS_REBUILD` contributor on any applicable table skips reuse for the **entire quote**. An earlier draft said "defeats reuse for that table"; that is not implementable against the current generator and would have been discovered in code.

**Hashing is not invalidation.** A dependency pack that only supplies canonical values leaves this hole open:

```
Account.Customer_Tier__c changes  →  no trigger fires on the Quote
                                  →  the Quote stays Ready
                                  →  nobody invokes generate()
                                  →  the renderer prints the old tier
```

So each pack declaring `DECLARED_DEPENDENCIES` must supply **both** halves, and say which:

| Half | What |
|---|---|
| Canonical values | what to hash — the field paths above |
| Invalidation mapping | how to get from a changed external record back to affected quote Ids — a trigger handler, a scheduled or event-driven sweep, or an explicit `LaunchRefreshOnly` declaration meaning "no mapping exists; the launch contract is the only guard" |

`LaunchRefreshOnly` is an acceptable answer. An unstated answer is not: the pack fails config load with `DEPENDENCY_INVALIDATION_UNDECLARED`. Reverse mapping from an arbitrary custom object to quote Ids is genuinely hard, which is why declaring its absence is permitted — but it must be declared, so the risk is visible rather than assumed away.

Declared paths reuse the existing validator, so a renamed or deleted field fails at config load rather than dropping out of the hash silently. A path whose *type* changes moves the canonical form, and the fingerprint with it.

### 6b. The launch contract — the guard that does not depend on anyone remembering

Invalidation is best-effort: a trigger may not exist, a sweep may lag, a pack may be `LaunchRefreshOnly`. Fresh fingerprint computation is not best-effort — it happens on every `generate()` call, before `canReuse` decides anything. So make it the last line of defence by forbidding the one sequence that bypasses it:

```
Every production document launch:
    1. call generate-or-reuse for the quote          (recomputes the fingerprint)
    2. take the request Id and fingerprint it returns
    3. call getPayload with exactly those            (step 07)

Never: read a Ready snapshot without step 1.
```

This requires one API change: `QuoteDocumentGenerator.generate(Set<Id>)` returns `void` today. Add a result — request Id, fingerprint, status, and whether the snapshot was rebuilt or reused, per quote — without changing the existing `@InvocableMethod` signature that Flow already calls. The Flow-facing launch action returns the same values so a declarative launch can pass them on.

The residual risk after this is bounded and worth stating: a change made to external data *between* step 1 and step 3, which the expected-fingerprint check in step 07 turns into a loud failure rather than a wrong document.

Separately, expose a compile-time API version so a separately deployed subscriber can assert what it built against:

```apex
public interface QuoteDocumentRowCustomizer {
    Integer CONTRACT_VERSION = 1;   // or exposed from the context
    List<Quote_Document_Row__c> customize(QuoteDocumentRowCustomizerContext context);
}
```

Semantic rules, documented once: adding an optional context field is compatible; removing or renaming one is breaking; changing row-inclusion semantics is breaking; adding a verifier is potentially breaking and must be release-noted.

## 7. Execution order is public contract

One Apex code and one Flow per table definition, **Apex first, then Flow**. The consequences are the contract, not incidental:

- the Flow sees rows the Apex customizer produced;
- the Apex customizer never sees Flow-produced rows;
- localization and verification see both;
- **last writer wins on the same field of the same row** — the Flow can undo the Apex customizer's change, deliberately.

Named here, tested in §9. A table needing three behaviours composes them inside its own class or Flow.

## 8. Apex from a subscriber package — decide the namespace scope first

The closed registry ([`QuoteDocumentRowCustomizerRegistry`](../../../force-app/main/default/classes/QuoteDocumentRowCustomizerRegistry.cls)) is a recorded decision, restated in [`specs/quote-document-subscribers/spec.md`](../../quote-document-subscribers/spec.md) §2.2, which rejects free-text `Type.forName`. Per-provider reflection reverses it and is not adopted. The upgrade-safety complaint has a narrower answer — **one delegation point**: core switch → one subscriber factory named by one CMDT value → `SUBSCRIBER_CODE_UNKNOWN`.

But that is only reachable if the API is callable from where the subscriber lives, and today it is not. `QuoteDocumentRowCustomizer` is `public`, as are `QuoteDocumentRowCustomizerContext`, `QuoteDocumentLine`, and `QuoteDocumentTableDefinition`. **Owner decision, recorded in §11:**

| Option | Cost |
|---|---|
| **A — same namespace only** (unlocked package or org source) | zero. The factory is a small convenience; `public` is sufficient. Recommended unless a packaged subscriber is a stated requirement. |
| **B — cross-namespace managed package** | inventory every type transitively reachable from the interface, promote the minimum surface to `global`, and accept it as a permanently versioned API that cannot be narrowed later. Substantial and irreversible. |

Do not build the factory under option B without completing that inventory in this step. Under option A, §11 may also defer the factory entirely.

## 9. Acceptance criteria

- [ ] A sample **Flow** contributor changes a label and adds a row, with no change to core Apex.
- [ ] A sample **Apex** contributor does the same via at most one CMDT row.
- [ ] Both exercised by one fixture, producing semantically identical rows.
- [ ] Every code in §5 has a test asserting the code and the offending row, table, or Flow — never merely "an exception was thrown".
- [ ] `CONTRIBUTOR_NO_OUTPUT`, `CONTRIBUTOR_FLOW_FAULT`, and `CONTRIBUTOR_FLOW_UNAVAILABLE` each tested.
- [ ] **Fingerprint:** bumping `Row_Customizer_Version__c` or `Row_Customizer_Flow_Version__c` changes the fingerprint and defeats `canReuse`; leaving it unchanged reuses — both pinned, the second as the documented hazard.
- [ ] Ordering contract in §7 tested: a Flow overwriting an Apex customizer's field wins.
- [ ] **Dependencies (§6a):** a blank `Cache_Policy__c`, or `DECLARED_DEPENDENCIES` with an empty dependency set, fails with `CONTRIBUTOR_DEPENDENCY_UNDECLARED`.
- [ ] A `DECLARED_DEPENDENCIES` pack with no invalidation mapping and no `LaunchRefreshOnly` declaration fails with `DEPENDENCY_INVALIDATION_UNDECLARED`.
- [ ] One `ALWAYS_REBUILD` contributor on any applicable table skips reuse for the **whole quote** — asserted by generating twice with no change and proving customization ran both times.
- [ ] `generate` returns the request Id and fingerprint per quote, and reports rebuilt vs reused.
- [ ] Changing a value at a declared dependency path changes the fingerprint and marks the quote `Stale`.
- [ ] A quote with an `ALWAYS_REBUILD` contributor on any applicable table never takes the `canReuse` path, proven by asserting customization ran on a second identical generation.
- [ ] A declared dependency path that no longer resolves fails at config load, naming the path.
- [ ] **`DEPENDENCY_UNREADABLE`**, one test per cause: removed field, missing permission for the generation persona, deleted related record, malformed pack configuration. Each fails **before** the reuse decision, and an unreadable value is never canonicalized as null.
- [ ] A contributor cannot publish `Ready` or skip `verify()` — tested. A contributor performing its own DML is **not** tested as prevented, because it is not.
- [ ] **Cache and launch edge cases**, one test each:
      `LaunchRefreshOnly` — changing the external value marks nothing `Stale`, yet the next launch rebuilds because the fresh fingerprint moved;
      `ALWAYS_REBUILD` on one table forces a rebuild for a quote that also has ordinary tables;
      reuse returns the **published** snapshot's request Id, never a newly invented one;
      an empty active-table set;
      a contributor configured with a blank version token fails config load;
      a Flow returning a different collection instance with identical contents is treated as unchanged;
      a Flow that removes every ordinary row but returns a valid Grand Total;
      a Flow that alters a stable `Row_Key__c` (`CONTRIBUTOR_DUPLICATE_ROW_KEY` or an unstable-key failure, never a silent rekey).
- [ ] **The CI version gate has its own executable suite** — see §10. A gate with no tests is a gate nobody can trust.
- [ ] Clearing either CMDT value removes the contribution with no code change.
- [ ] Existing customizer suites pass unmodified.

## 10. Verification

```bash
sf apex run test --class-names QuoteDocumentFlowCustomizerTest --class-names QuoteDocumentRowCustomizerRegistryTest --class-names QuoteDocumentFingerprintTest --class-names QuoteDocumentDiscountRowCustomizerTest --class-names QuoteDocumentIndustryRowCustomizerTest --result-format human --wait 20
```

**CI gate suite** (owned here, because the tokens are defined here). A script plus its own tests, run in CI and locally:

```bash
node scripts/ci/check-contributor-versions.js --base origin/master
npm test -- check-contributor-versions
```

Cases the suite must cover, each expected to **fail the build** rather than warn: zero mappings parsed; merge base unavailable; subscriber mapping file missing; a class or Flow renamed so the mapping no longer resolves; a malformed or reformatted registry; multiline `when` branches; commented-out branches; and the emergency-deployment path, which is allowed to skip CI only by recording a manual invalidation run.

Zero-core-diff proof, per [`spec.md`](../spec.md) §9: the Flow sample adds a `.flow-meta.xml`, CMDT rows, and permission-set entries — all expected. It must not change core Apex, and must not modify an existing core CMDT record.

## 11. Close-out

- **Date:** §4 gate closed 2026-08-27; bridge, declarations, output validation, launch contract and CI gate built the same day.
- **Flow round-trip prototype result:** **PROVEN** — full matrix in §4. Uninserted `Quote_Document_Row__c` records survive `Flow.Interview` intact. Apex-defined types and the JSON fallback are **ruled out**; do not reintroduce them.
- **One design consequence the prototype found that the matrix did not ask for:** a Flow loop variable is a **copy**. A contributor Flow must collect rows into a second collection and assign it back to `rows`; editing the loop variable in place changes nothing and fails *silently*. It leads the sample Flow, the `Row_Customizer_Flow__c` help text, the `CONTRIBUTOR_NO_OUTPUT` message, and the bridge class comment — four places, deliberately, because it is the one mistake that produces a successful-looking run and an unchanged document.
- **Decision — namespace scope:** **A**, from [step 00](step-00-audit-and-contract-principles.md) §7. `public` throughout; nothing promoted to `global`.
- **Decision — subscriber factory:** **deferred**, as §8 permits under option A. The closed registry resolves every shipped code; build the factory when a real subscriber needs it.
- **`global` surface inventory (option B only):** not applicable.
- **Flow sample:** [`QuoteDocumentSampleFlowContributor`](../../../force-app/main/default/flows/QuoteDocumentSampleFlowContributor.flow-meta.xml), with [`Quote_Document_Table_Def.FLOW_CONTRIBUTOR_EXAMPLE`](../../../force-app/main/default/customMetadata/Quote_Document_Table_Def.FLOW_CONTRIBUTOR_EXAMPLE.md-meta.xml) (inactive, matching the other shipped examples).

### What was built

| § | Delivered | Where |
|---|---|---|
| 4 | Flow bridge + three probe Flows | [`QuoteDocumentFlowRowCustomizer`](../../../force-app/main/default/classes/QuoteDocumentFlowRowCustomizer.cls) |
| 5 | Six previously-unowned output invariants | [`QuoteDocumentContributorOutput`](../../../force-app/main/default/classes/QuoteDocumentContributorOutput.cls) |
| 6 | `Row_Customizer_Version__c`, `Row_Customizer_Flow_Version__c` in the fingerprint | `QuoteDocumentFingerprint` |
| 6a | `Cache_Policy__c` (restricted picklist), `Contributor_Dependency_Set__c`, value hashing, `DEPENDENCY_UNREADABLE` | `QuoteDocumentTableDefinition`, `QuoteDocumentQuery` |
| 6b | `generate()` returns request Id + fingerprint + reused; `Document_Data_Request_Id__c` wired up | `QuoteDocumentGenerator` |
| 7 | Apex-then-Flow order, last writer wins | `QuoteDocumentGenerator.applyRowCustomizer` |
| 10 | CI version gate + 15-test suite | [`scripts/ci/check-contributor-versions.js`](../../../scripts/ci/check-contributor-versions.js) |

### One acceptance criterion was changed, not met as written

`ROW_ORDER_INVALID` is narrower than §5 implies, and the reasoning is recorded in the class and pinned by tests both ways. Two stricter readings were implemented and both were **wrong**: "nothing after the Grand Total", then "nothing *counted* after the Grand Total". Each failed three shipped, documented, tested customizers — Discount and Rounding append counted adjustment rows below the total, EstimatedTax an uncounted one. That is the framework's own convention: `context.newRow()` appends, and `verify()` reconciles on the inclusion flags, never on order. Only a **Detail** row below the total is wrong, which is what §5 says literally. A global invariant that contradicts the framework's append convention would simply have been switched off by whoever hit it next.

### Still open before this step can be marked COMPLETE

- **`DEPENDENCY_INVALIDATION_UNDECLARED`** — the invalidation-mapping half of §6a. Declared dependency *values* are hashed; a pack still cannot declare its invalidation mapping or `LaunchRefreshOnly`, so that code has no owner yet. Needs the dependency-pack concept from the [subscribers spec](../../quote-document-subscribers/spec.md), which is why it did not land here.
- **`DEPENDENCY_UNREADABLE` per-cause tests** — the code exists and fires on a removed or malformed path. The four separate causes §9 asks for (removed field, missing permission for the generation persona, deleted related record, malformed pack) are not each pinned. The permission case in particular depends on the B1 persona security review.
- **Some §9 cache and launch edge cases** — `LaunchRefreshOnly`; a Flow returning a different collection instance with identical contents; a Flow that removes every ordinary row but returns a valid Grand Total; a Flow that alters a stable `Row_Key__c`; an empty active-table set.
- **The supported-maximum limits budget** (§8.7 of [`spec.md`](../spec.md)). The round trip alone is measured (685 ms CPU, ~329 KB heap at 1000 rows, budgeted at 3 s / 2 MB). Whole generation at the supported maximum is not, and its budget must be stricter than the round trip's.
- **Locale** is `null` on the context until [step 03](step-03-semantic-keys-and-localization.md) resolves it per quote. The bridge passes it through already.

### Test evidence

138 local tests pass. Five failures remain and are **not** from this work: `QuoteDocumentGeneratorGuardTest`, `QuoteDocumentTemplateConfigurationTest` and `QuoteDocumentTableDefinitionDefaultsTest` do not exist in this repository — they are org-side leftovers from other work, referencing `Quote_Document_Template_Table__c` and a `fromTemplateTable` method this codebase does not have. They failed identically before the first line of this step was written. Worth clearing separately, since they will keep polluting every future `RunLocalTests`.

- **Next step:** [`step-01-table-presentation-fields.md`](step-01-table-presentation-fields.md)
