# CPQ Quote Document — DocuSign launch spec

**Status of this file:** planning spec, four increments, none started. It is a *sibling* of [`specs/quote-docusign-totals/spec.md`](../quote-docusign-totals/spec.md), not a replacement — that file owns the hardening roadmap (Phases 0–8) for the generation engine; this file owns the four additive changes that sit around it. Read [`docs/quote-document-totals.md`](../../docs/quote-document-totals.md) first; it remains the single source of truth for the architecture, and nothing here changes it structurally.

**Provenance:** this supersedes an earlier proposal (`quote_document_docusign_framework_spec_v1.md`, external, not in this repo) that framed the same goals as a greenfield rewrite — new grouping model, collapsed row flags, generic detail columns replacing typed ones, 24 new Apex classes, parallel run, retirement of the existing engine. **That framing is withdrawn.** It was written against an imagined blank slate rather than against a deployed engine with 15 active table definitions, four completed phases, 98% org-wide coverage, and live reconciliation against real quote data. Several of its recommendations regressed shipped capability, and one — a generic instruction that Quote Line triggers "call `markStale()`" — would have reintroduced a known correctness bug that produces wrong signed documents.

The four increments below are what survives that review.

---

## 1. Design principle

> Preserve the proven generation engine. Add targeted controls around **request ownership**, **source freshness**, **one-click launching**, and **safe extension registration**.

Every increment is additive to `QuoteDocumentGenerator` and its collaborators. None replaces them. If an increment starts requiring changes to `QuoteDocumentRowBuilder`, `QuoteDocumentLine.countsIn`, or `verify()`, that is the signal it has been mis-scoped — stop and re-derive.

---

## 2. Preserved capability — the do-not-touch list

The withdrawn proposal dropped each of these, mostly without noticing. They are load-bearing and stay exactly as they are. This list exists so a future reader can tell "deliberately kept" from "not yet considered".

| Capability | Where it lives | Why it stays |
|---|---|---|
| All 15 active table definitions | `customMetadata/Quote_Document_Table_Def.*` | Five of them cannot be expressed without the two rows below |
| Child grouping metadata | `Quote_Document_Grouping__mdt` | Custom Metadata has no ordered list; nesting order *is* meaning |
| Same-level composite grouping | `Level__c` equal across parts | `FAMILY_BILLING_COMPOSITE` ships today; two field-path slots cannot express it |
| Computed dimensions (`Dimension__c`) | `QuoteDocumentLine.getGroupingValue` | `BUNDLE` and `TRANSACTION_TYPE` have no field behind them. `BUNDLE_DETAIL`, `BUNDLE_PRODUCT_GRID`, `BUNDLE_SUMMARY`, `TRANSACTION_SUMMARY` all depend on this |
| Section Totals | `Show_Section_Totals__c` | `PRODUCT_FAMILY_SUMMARY` uses it |
| Nine row types | `Row_Type__c` | Including the three reachable only through customizers |
| **Both** inclusion flags | `Include_In_Subtotal__c`, `Include_In_Grand_Total__c` | See §2.1 |
| Typed snapshot fields | `Product_Name__c`, `Product_Family__c`, `Charge_Type__c`, `Transaction_Type__c` | Reports, report type, sorting, filtering, aggregation, existing template bindings |
| Retention | `QuoteDocumentRetention` | Working, tested, protects Accepted quotes. Rows are the expensive object |
| `verify()` and its five assertions | `QuoteDocumentGenerator.verify` | Assertion 4 is the thing standing between this org and a wrong signed number |
| Synchronous generation | `generate(Set<Id>)` | See Increment 3 — v1 stays synchronous |
| Deferred staleness + `suppress()`/`resume()` | `QuoteDocumentStaleness` | See §3. Non-negotiable |
| CMDT type-vs-record deploy ordering | deployment practice | Together they fail with `UNKNOWN_EXCEPTION` |
| Multi-currency compile guard | `UserInfo.isMultiCurrencyOrganization()` | A static `CurrencyIsoCode` reference will not compile in `gkCPQDev` |
| Permission-set-per-field discipline | `CPQ_Document_Totals.permissionset-meta.xml` | Every new field, right block, `editable=false` for formulas |

### 2.1 On the two inclusion flags, precisely

The withdrawn proposal collapsed `Include_In_Subtotal__c` and `Include_In_Grand_Total__c` into one `Contributes_To_Total__c`. Do not do this. But state the reason accurately, because a reader who greps `countsIn` will find one boolean feeding both and conclude the second flag is dead:

- **The builder path** (`QuoteDocumentRowBuilder`) currently sets them equal — `QuoteDocumentLine.countsIn` returns a single boolean. [`specs/quote-docusign-totals/spec.md`](../quote-docusign-totals/spec.md) §2 category C records this as a deliberate v1 constraint.
- **The customizer path** already exercises the divergence. A Rounding row is a whole-table adjustment: `Group_Level__c = 0`, counts toward the grand total, never toward a subtotal. That is only expressible with two flags.

So the pair is load-bearing *today* through the customizer path, and the builder path simply has not needed it yet. Collapsing breaks the former and forecloses the latter.

The hidden-row invariant stays conceptual:

> A hidden row must contribute to at least one arithmetic total.

Not "must have one generic contribution flag set". The declarative rule `Hidden_Row_Must_Count` already encodes the former.

### 2.2 On the three generic detail columns

`Detail_Extra_1__c` through `Detail_Extra_3__c` are a **real** identified need and should be added — as part of Increment 3 or separately, they are not gated on anything here. They are **additive**. They exist for template-specific attributes that do not deserve first-class schema fields.

They do not replace the typed fields. A generic Text(255) column cannot be summed, sorted numerically, or reported on, and it couples the template to slot position — "`Detail_Extra_2__c` means Charge Type in this table and Product Family in that one" is a positional-parameter API, which is tolerable for a genuinely open extension slot and intolerable as the primary contract.

**Formatting rule for the generic slots:** deterministic, derived from the Quote's currency and the org locale — **never the requesting user's locale**. Two reps generating the same quote must produce byte-identical text. A user-dependent value on a signed document is a defect, and it would additionally make the Increment 2 fingerprint user-dependent.

---

## 3. Architecture contract — staleness (promoted from commentary)

This section exists because the withdrawn proposal's §23.1 said only "triggers collect Quote IDs and call `markStale(quoteIds)`", which is exactly enough rope for a new developer to reimplement the bug this repo already found and fixed.

Two invariants. Both belong in [`docs/quote-document-totals.md`](../../docs/quote-document-totals.md) §4 as stated architecture and in its §10 rules list — not as narrative commentary, which is where they currently live.

**Invariant S1 — the stale write from a Quote Line trigger must be deferred.**

A synchronous `update` of `SBQQ__Quote__c` from inside a Quote Line trigger does not survive. CPQ's own `QuoteLineAfter` handler reads the quote, calculates, and writes it back later in the same save cascade using the copy it read *before* our write. The `Stale` value is silently overwritten and the quote reads `Ready` with out-of-date tables behind it. This was observed with instrumentation, not assumed. `QuoteDocumentStaleness` defers via `@future applyStaleAsync`, with `canDefer()` guarding the 50-future limit and falling back inline.

`editingALineMarksTheQuoteStale` is the guard test. Do not weaken it.

**Invariant S2 — generator-owned writes to the Quote must suppress staleness.**

```apex
QuoteDocumentStaleness.suppress();
try {
    // generator-owned Quote write
} finally {
    QuoteDocumentStaleness.resume();
}
```

Already implemented in `QuoteDocumentGenerator.markQuote`. Without it, the generator's own `Ready` write fires the Quote trigger, which marks the quote stale as a nested update inside the generator's own DML. The outer write wins so the quote reads `Ready` — but the quote is now in `handledThisTransaction`, so **the next genuine edit is silently skipped.** Same wrong-signed-document failure mode, different route.

**Consequence for this spec:** every new Quote write introduced by Increments 1–3 (request ownership, `Generating`, `Ready`, `Failed`) goes through `markQuote` or an equivalent that wraps in `suppress()`/`resume()`. No increment may add a bare `update SBQQ__Quote__c`.

---

## 4. Increment 1 — request ownership

**Goal:** distinguish "the current request is writing" from "an abandoned or superseded request is writing". Extends Phase 2's `FOR UPDATE` (DONE); does not replace it.

### 4.1 Schema

Ordered. The picklist value must land and deploy *before* any Apex writes it.

1. **`Document_Data_Status__c` — add `Generating`.** The value set is `<restricted>true</restricted>` and currently holds only `Not Generated` · `Stale` · `Ready` · `Failed`. Apex writing an absent value into a restricted set fails at runtime with `INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST` — it does not degrade gracefully.
2. **`Document_Data_Request_Id__c`** — Text(64). Correlation ID for the current or latest preparation request.
3. **`Document_Data_Started_At__c`** — Date/Time. Detects abandoned `Generating`.

Both new fields go into `CPQ_Document_Totals.permissionset-meta.xml`. The picklist value does not.

**Not added:** `Document_Data_Job_Id__c`. It is meaningful only for the asynchronous path, which v1 does not build (§6.4).

### 4.2 Ownership algorithm

There is no conditional-update DML in Apex. The re-query / lock / compare / write sequence **is** the concurrency control — this is the one place the race actually bites, and it must be written out rather than described as "conceptually a `WHERE` clause".

```
1. Query the Quote FOR UPDATE.
   (Note: ORDER BY is not permitted with FOR UPDATE — Phase 2 found this the hard way.
    Lock acquisition is in Id order automatically.)
2. Inspect Document_Data_Status__c, Document_Data_Request_Id__c, Document_Data_Started_At__c.
3. If status is Generating and Started_At is within the abandonment window,
   another live request owns this Quote — return that request's ID. Do not start work.
4. Otherwise assign a new request ID, set status Generating, stamp Started_At.
   (Through markQuote — invariant S2.)
5. On every later completion or failure path:
   a. Re-query the Quote FOR UPDATE.
   b. Compare the stored request ID against this request's ID.
   c. Write only if it still matches.
6. An older request must never overwrite a newer one.
```

**Step 5 is forward-looking infrastructure, not something v1's `prepare()` calls itself.** In synchronous v1, `generate()` runs inside the same transaction `acquireOwnership`'s `FOR UPDATE` already spans, so there is no second writer for step 5 to guard against yet — the lock alone is sufficient for the happy path. Implement `completeIfOwned` (or equivalent) as a directly-tested, named seam that Increment 2/3's asynchronous or multi-step completion paths will call, rather than wiring it into `prepare()` just to have a caller. Revisit whether it's still the right shape once an increment actually needs it.

The abandonment window is a constant for now — a CMDT field for it is Increment 3's `Quote_Document_Launch_Config__mdt` if one is wanted, not new metadata on its own.

### 4.3 Interaction with existing entry points

`generate(Set<Id>)`, `generateAsync(Set<Id>)`, and `generateFromFlow` all currently write status through `markQuote` without any ownership concept. Ownership is acquired by the **new preparation facade** (Increment 3), not retrofitted into `generate` — the backfill script and the admin quick action deliberately generate unconditionally and must keep doing so. Decide this explicitly rather than letting it happen: **`generate` stays ownership-free; the facade acquires ownership and then calls it.**

### 4.4 Acceptance

- `Generating` deployed and writable; a test asserts the restricted-picklist write succeeds.
- Two sequential preparation calls in one test: the second observes the first's request ID rather than starting new work.
- A simulated stale `Generating` older than the window is superseded with a new request ID.
- A write attempt carrying a superseded request ID is rejected and leaves the newer state intact.
- Existing suite green.

---

## 5. Increment 2 — fingerprint validation and reuse

**Goal:** close the correctness hole for source changes that fire no Quote or Quote Line trigger — principally `Product2` fields used in a grouping `Field_Path__c` or a detail column. [`specs/quote-docusign-totals/spec.md`](../quote-docusign-totals/spec.md) does not cover this; trigger-based staleness cannot.

### 5.1 What reuse actually saves

State this plainly so nobody sizes it as a free fast path. The reuse check still performs:

- definition loading (CMDT)
- required-path collection
- schema path validation
- the dynamic Quote Line query
- canonicalization
- digest calculation

It saves: row construction, reconciliation, the delete, both inserts, and the stamp/update. That is the expensive half, and worth having — but it is **not** query-free.

### 5.2 Canonical input

Correctness-critical and under-specified in the withdrawn proposal. Any nondeterminism here makes the fingerprint never match, which regenerates every time — silently, with no failure to notice.

Ordered contents:

```
Plan identity (launch config code)
Ordered table definitions      — every field that changes output, see below
Ordered grouping definitions   — Level__c, Sequence__c, Dimension__c, Field_Path__c
Ordered required field paths
Quote-level values             — including CurrencyIsoCode, guarded (§5.4)
Ordered Quote Line IDs
Typed field values per line
```

"Every field that changes output" on a table definition means: `Table_Code__c`, `Line_Filter__c`, `Measure_Set__c`, `Show_Details__c`, `Show_Section_Totals__c`, `Max_Groups__c`, `Composite_Separator__c`, `Display_Order__c`, `Is_Active__c`, `Sort_Groups_By__c`, `Amount_Basis__c`, **and the row customizer code** (see §5.5).

Value encodings — unambiguous, locale-free:

```
NULL                          distinct from empty string
STRING:<length>:<value>       length prefix defeats delimiter collision
DECIMAL:<normalized plain>    plain notation, no scientific, fixed scale
DATE:YYYY-MM-DD
DATETIME:<UTC>                canonicalized to UTC, never user timezone
BOOLEAN:0|1
ID:<18-character>             always 18, never 15
```

Sort Quote Lines by Id and field paths lexically. Never rely on map iteration order — the same rule `QuoteDocumentRowBuilder` already follows.

Digest: SHA-256 via `Crypto.generateDigest`, hex-encoded, stored in a new `Document_Data_Fingerprint__c` Text(64) on the Quote. Permission set, as ever.

### 5.3 Reuse decision

Reuse only when **all** hold:

- status is `Ready`
- stored fingerprint equals freshly computed fingerprint
- **every expected `Table_Code__c` exists for this quote**
- **every one of those tables has a Grand Total row**

The last two are not belt-and-braces. `Quote_Document_Table__c` OWD is currently Public Read/Write ([`docs/quote-document-totals.md`](../../docs/quote-document-totals.md) §2.1), so anyone holding `CPQ_Document_Totals` can delete rows out from under a `Ready` quote. Fingerprint matches; snapshot is incomplete; document prints short.

Otherwise regenerate.

### 5.4 Multi-currency

`CurrencyIsoCode` is a quote-level value that changes output and must be in the canonical input — but it exists only when multi-currency is enabled, and naming it statically will not compile in `gkCPQDev`. Same guard as `copyCurrency`:

```apex
if (UserInfo.isMultiCurrencyOrganization()) { ... }
```

Do not "tidy" this into a direct reference. One codebase, deployable to both.

### 5.5 Ordering note — expect one global regeneration

Increment 4 changes `Row_Customizer_Class__c` into a controlled customizer code. Since the customizer is part of the effective definition and therefore part of the fingerprint, **whichever of Increments 2 and 4 lands second causes one global fingerprint miss and a one-time regeneration of every quote.** This is harmless and expected. Write it in the release note or it gets filed as a bug.

### 5.6 On `planVersion`

The withdrawn proposal made a hand-maintained `planVersion` string a correctness control — "must change whenever a change can alter generated output". That is a manual cache-invalidation key, and it will be forgotten.

The fingerprint already includes the effective definitions, so a definition change busts it automatically. Keep a version label only for its genuinely useful purpose — **template compatibility**, e.g. "plan version 3 requires DocuSign template version 7" — and never as a second correctness requirement.

### 5.7 Acceptance

- Identical inputs produce an identical digest across two transactions and two different running users.
- A `Product2.Family` change with no Quote or Quote Line DML changes the fingerprint and forces regeneration.
- A deactivated table definition changes the fingerprint.
- Manually deleting one table from a `Ready` quote forces regeneration despite a matching fingerprint.
- Null and empty string produce different digests.
- Decimal scale and DateTime timezone variations do not.

---

## 6. Increment 3 — one-click DocuSign launch

**Goal:** the actual user-facing value. Today a rep presses **Generate Document Tables**, waits, then hunts for a separate DocuSign action.

```
Generate Agreement
        ↓
Validate or regenerate document data (synchronous)
        ↓
Apex transaction returns — data is committed
        ↓
Start managed DocuSign Flow action
```

The Apex call and the Flow start are separate transactions. That separation is what guarantees the generated rows are committed before the managed action reads them, and it is deliberate.

### 6.1 Metadata

New `Quote_Document_Launch_Config__mdt`:

| Field | Purpose |
|---|---|
| Developer Name | Stable launch key |
| `Launch_Code__c` | Template-facing code |
| `Docusign_Template_Id__c` | Per-environment template ID |
| `Generation_Mode__c` | Generate-only / generate-and-send |
| `Is_Active__c` | Enables the action |
| `Label__c` | User-facing action label |
| `Abandoned_Generation_Minutes__c` | Increment 1's window |
| `Max_Sync_Rows__c` | §6.4 threshold |

The template ID is configuration, not a secret — but it must never be hardcoded in Apex, LWC JavaScript, or a Flow formula.

### 6.2 LWC behaviour

1. Disable duplicate clicks immediately on click.
2. Call the preparation facade.
3. Reuse current data when the fingerprint matches.
4. Regenerate when it does not.
5. Start the DocuSign Flow **only** after successful Apex completion.
6. On failure, surface the existing `Document_Data_Error__c` — no stack trace, no dynamic SOQL, no record values, plus the request ID as a support reference.
7. Keep the existing manual generation action available to admins and support only.

A DocuSign-side failure is not a preparation failure. If the snapshot is still current, retrying must not rebuild it.

### 6.3 The manual action is a layout change, not a repo change

The **Generate Document Tables** quick action is deployed but added to a managed-package layout by hand, and that layout is not source-controlled here ([`docs/quote-document-totals.md`](../../docs/quote-document-totals.md) §6). Restricting it to admins/support is an org-side layout edit plus permission-set surgery, tracked as a deployment step. Do not expect it to fall out of a `sf project deploy`.

### 6.4 v1 is synchronous — and the threshold needs measuring, not assuming

No Queueable, no Finalizer, no polling, no `SUPERSEDED` state, no modal-resume machinery. Above the threshold, fail clearly:

> This Quote is too large for interactive document preparation. Contact support with request ID `X`.

**The threshold cannot be inherited from the existing doc.** [`docs/quote-document-totals.md`](../../docs/quote-document-totals.md) §7 estimates "a 500-line quote with 6 tables ≈ 2–3k rows". There are now **15 active definitions**, and every active definition generates for every quote. Scaled linearly that is 5–7k rows on a large quote — plausibly already outside a comfortable synchronous envelope, and close to the 10k DML ceiling before any headroom for triggers and package automation.

Two consequences:

1. Measure the real envelope on a production-shaped quote before setting `Max_Sync_Rows__c`. Record CPU, heap, SOQL rows, DML rows.
2. **Phase 8 of the sibling spec — rule-driven table eligibility — stops being backlog and becomes the lever that keeps v1 synchronous.** Cutting 15 definitions down to the handful actually applicable to a given quote is a far better answer than building the async machinery we just deferred. Sequence that decision alongside this increment.

If a real quote then exceeds the measured envelope and eligibility rules cannot bring it back under, *that* is the trigger to build the asynchronous path — not before.

### 6.5 DocuSign org prerequisites — validate before finalizing the LWC

None of these are assumptions this spec is entitled to make. Confirm in the target org first:

- which DocuSign product and package version is installed
- that the managed Flow action exists under the installed version
- its actual input variable API names and namespace
- whether it runs correctly inside `lightning-flow`
- whether the user can proceed inline or requires a managed-package navigation step

The last one changes the UX materially. If navigation is required, keep the same modal and present one prominent **Continue to DocuSign** button — do not return the rep to the Quote to find a second unrelated action.

Note also that this repo has already been bitten once by an assumption about DocuSign CLM vs. Gen syntax ([`docs/quote-line-type-bundle-reporting-guide.md`](../../docs/quote-line-type-bundle-reporting-guide.md) §13). Check, don't recall.

### 6.6 Acceptance

- One action from the Quote prepares and launches.
- A current snapshot launches without rebuilding.
- A stale or missing snapshot rebuilds automatically, then launches.
- DocuSign is never invoked after a preparation failure.
- A DocuSign failure with a current snapshot retries without rebuilding.
- Double-click creates one request.
- A quote above the threshold fails with the actionable message and a request ID.
- No template ID appears in Apex, JS, or a Flow formula.

---

## 7. Increment 4 — explicit customizer registry

**Goal:** remove `Type.forName()` on a metadata-supplied class name while preserving the shipped plug-in capability.

### 7.1 What exists today

`QuoteDocumentGenerator.applyRowCustomizer` reads `Row_Customizer_Class__c` off the definition and calls `Type.forName`. Four records use it:

| Record | Class |
|---|---|
| `DISCOUNT_EXAMPLE` | `QuoteDocumentDiscountRowCustomizer` |
| `INDUSTRY_ALLEGIANCE` | `QuoteDocumentIndustryRowCustomizer` |
| `ROUNDING_EXAMPLE` | `QuoteDocumentRoundingRowCustomizer` |
| `ROW_CUSTOMIZER_EXAMPLE` | `QuoteDocumentEstimatedTaxRowCustomizer` |

### 7.2 Replacement

Metadata holds a controlled **code**; Apex owns the mapping.

```apex
public class QuoteDocumentRowCustomizerRegistry {
    public static QuoteDocumentRowCustomizer resolve(String customizerCode) {
        switch on customizerCode {
            when 'DISCOUNT_EXAMPLE'      { return new QuoteDocumentDiscountRowCustomizer(); }
            when 'INDUSTRY_ALLEGIANCE'   { return new QuoteDocumentIndustryRowCustomizer(); }
            when 'ROUNDING_EXAMPLE'      { return new QuoteDocumentRoundingRowCustomizer(); }
            when 'ESTIMATED_TAX'         { return new QuoteDocumentEstimatedTaxRowCustomizer(); }
            when else {
                throw new QuoteDocumentException(
                    'Unknown row customizer code: ' + customizerCode
                );
            }
        }
    }
}
```

Buys: no `Type.forName`, no arbitrary class-name configuration, compile-time breakage on rename, straightforward security review, a test that resolves every supported code, and closure of a standing PMD finding.

**`Dimension__c` is explicitly not affected by this change.** A controlled enum interpreted by trusted Apex is not dynamic class loading and never was. There is no security or maintainability argument for removing it, and four shipped tables depend on it.

### 7.3 Migration

Four CMDT records. Add `Row_Customizer_Code__c`, populate, cut over, then remove `Row_Customizer_Class__c` in a later deploy. Remember that a Custom Metadata deploy writes only the fields present in the file — to blank the old field you must deploy `<value xsi:nil="true"/>` explicitly; deleting the `<values>` block leaves whatever the org already had.

### 7.4 Acceptance

**Split across the two deploys named in §7.3 — do not read this as one checklist for a single PR.**

Migration deploy (§7.3 step 1, this increment):
- `Row_Customizer_Code__c` added; every active customizer-bearing record carries the matching code alongside its existing `Row_Customizer_Class__c`.
- The generator prefers the code path whenever a code is present, falling back to `Type.forName` only when it is blank — precedence stated explicitly in code and in the PR description.
- Every code in the registry resolves in a test; an unknown code throws.
- All four records generate identically to before (compare row-for-row).
- `Type.forName` **is still present** in the file at this point — it must be, since it is the fallback for any definition not yet migrated. PMD will still flag it. That is expected, not a failed acceptance criterion.

Removal deploy (§7.3, later, separate PR):
- Confirm every active definition has a populated code (query CMDT, don't assume).
- Delete `Row_Customizer_Class__c`, the fallback method, and its field-permission entry.
- **Only now** does "no `Type.forName` remains in the generation path" become a true acceptance criterion, and only now should the PMD finding be expected to clear.

---

## 8. Out of scope

Named so nobody assumes they are covered:

- **Asynchronous preparation** — Queueable, Finalizer, polling, `SUPERSEDED`. Deferred until a real quote exceeds the measured synchronous envelope (§6.4).
- **Master-detail conversion of `Quote_Document_Table__c` → `SBQQ__Quote__c`** — worth doing, standalone. It needs its own verification for data conversion, sharing behaviour, cascade delete, reports, DocuSign relationship paths, tests, permission set, deploy order, and rollback. Two extra constraints the earlier proposal missed: `SBQQ__Quote__c` is a managed-package object, so the conversion must survive CPQ package upgrades; and the `DocumentTables` relationship name must be preserved *exactly*, or the report type, both reports, and every template path break simultaneously. Do not ride this inside Increment 2 or 3.
- **Replacing the grouping model, collapsing the row flags, or replacing typed fields with generic slots** — withdrawn, see §2.
- **Bulk or scheduled generate-and-send** — the interactive action creates at most one generation per successful launch. Any future batch design needs its own throttling against DocuSign's documented generation window, which must be re-confirmed against current DocuSign documentation rather than recalled.
- **Anything in the sibling spec's Phases 1, 5, 6, 7** — those remain owned by [`specs/quote-docusign-totals/spec.md`](../quote-docusign-totals/spec.md) and gated on their own triggers. Phase 8 is the exception; §6.4 pulls it forward.

---

## 9. Sequence

| Order | Increment | Depends on | Blocking prerequisite |
|---|---|---|---|
| 1 | Request ownership | Phase 2 (DONE) | none |
| 2 | Fingerprint and reuse | Increment 1 | none |
| 3 | Customizer registry | none | none — can run parallel |
| 4 | One-click launch | Increments 1, 2 | §6.5 org validation; §6.4 threshold measurement |

Increments 1–3 are self-contained and verifiable against the existing test suite. Increment 4 is the only one with an external dependency, which is why it goes last despite being the visible payoff.

Each increment lands green: `sf apex run test --class-names QuoteDocumentGeneratorTest --class-names QuoteDocumentLifecycleTest`, org-wide coverage not below its current 98%.

---

## 10. Doc changes this spec obliges

Not optional — the staleness one is the whole reason §3 exists.

1. [`docs/quote-document-totals.md`](../../docs/quote-document-totals.md) §4 — promote invariants S1 and S2 from narrative commentary to stated architecture contract.
2. Same file, §10 — add a rule: *"Staleness marking from a Quote Line trigger must stay deferred, and generator-owned Quote writes must stay wrapped in `suppress()`/`resume()`. Both prevent a quote reading `Ready` over stale tables."*
3. Same file, §2 — record the two-flag rationale from §2.1 above, so `countsIn` returning one boolean does not read as evidence the second flag is dead.
4. Same file, §7 — update the row-volume estimate from 6 definitions to 15 once §6.4's measurement lands.
5. [`docs/quote-document-totals-architecture-guide.md`](../../docs/quote-document-totals-architecture-guide.md) — mirror 1–3 in admin-facing language.
6. Any new `Quote_Document_Table_Def__mdt` guide follows [`docs/documentation-standards.md`](../../docs/documentation-standards.md) automatically.
