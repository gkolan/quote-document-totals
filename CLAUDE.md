# CLAUDE.md — working notes for this repo

This file orients an agent (or a new developer) working in `cpqRules`. It doesn't restate the architecture — read these first, in order:

1. [`docs/quote-document-totals.md`](docs/quote-document-totals.md) — the single source of truth for the CPQ Quote Document framework (object model, generation pipeline, staleness, retention, config).
2. [`docs/quote-document-totals-architecture-guide.md`](docs/quote-document-totals-architecture-guide.md) — the same framework explained for a Salesforce admin with no coding background: plain-language walkthrough of every object, custom metadata type, Apex class, and how to configure or extend it. Point a junior admin here first; point a developer at #1 first.
3. [`docs/annual-schedule-guide.md`](docs/annual-schedule-guide.md) — the worked example of a table that expands one line into several rows, and the first guide written for a definition that is deliberately still inactive.
4. [`docs/documentation-standards.md`](docs/documentation-standards.md) — the required standard for any new `Quote_Document_Table_Def__mdt` guide. Apply it automatically; don't ask.
5. [`specs/vendor-neutral-render-contract/spec.md`](specs/vendor-neutral-render-contract/spec.md) — the render contract that makes the document product replaceable. Read this before touching anything that produces printable text: titles, column headings, row labels, narrative blocks, or locale. Its steps are under [`specs/vendor-neutral-render-contract/steps/`](specs/vendor-neutral-render-contract/steps/), each with a close-out recording what was built and what was deliberately deferred.
6. [`docs/quote-document-extension-recipes.md`](docs/quote-document-extension-recipes.md) — copyable recipes for an Apex or Flow row customizer, plus the full error-code catalogue. Start here rather than reading generator internals.
7. [`specs/row-generation-extensibility/spec.md`](specs/row-generation-extensibility/spec.md) — how one quote line becomes several document rows: expansion, allocation, non-additive measures, comparison and partitioning. Read this before adding a table that multiplies, divides, compares or splits — most of those are configuration now, and the recipes in #6 are the entry point.
8. [`specs/quote-docusign-totals/spec.md`](specs/quote-docusign-totals/spec.md) — the hardening roadmap, phased and atomic under [`specs/quote-docusign-totals/phases/`](specs/quote-docusign-totals/phases/). Check phase status before assuming something is done vs. planned.


## The render contract changes how you add printable text

Since `specs/vendor-neutral-render-contract`, **no printable string is constructed in Apex or typed into
a template.** Titles come from the table definition, column headings and row labels resolve from a
locale dictionary through `QuoteDocumentLabels`, and narrative comes from `Quote_Document_Content__mdt`.

Two consequences worth knowing before you write code:

- `QuoteDocumentRowBuilder.defaultRow()` **fails** on a blank label rather than substituting
  `'(unnamed)'`. Resolve `GROUP_UNNAMED` from the dictionary at the call site.
- A renderer never queries the snapshot objects. It calls
  `QuoteDocumentRenderService.getPayload(quoteId, expectedRequestId, expectedFingerprint)`, with both
  expectations from a preceding `generate()`. There is no overload that omits them, and a test asserts
  none is ever added.

## Environment note: `sf` and Java are on PATH, but not always in a fresh shell

This machine has the Salesforce CLI (`C:\Program Files\sf\bin`) and a JDK (`C:\Program Files\Eclipse Adoptium\jdk-25.0.4.7-hotspot\bin`) installed system-wide, and `sf` is already authenticated to a dev org. Both were installed after some shells were opened, so a shell that predates the install has a stale cached `PATH` and reports `sf`/`java` as not found even though they're really there. If that happens, don't conclude there's no org access — add both paths to the session and retry:

```powershell
$env:Path += ";C:\Program Files\sf\bin;C:\Program Files\Eclipse Adoptium\jdk-25.0.4.7-hotspot\bin"
sf org list
```

## The scratch org is `quotedoctotals` - never destroy it

The permutation work in `specs/quote-document-test-data` runs against one
long-lived scratch org, aliased **`quotedoctotals`** (also `qdtdScratch`),
created from the `sfdo-gk-dev-ed` Dev Hub and expiring 2026-09-26. Rebuilding it
costs a CPQ package install plus a full deploy, and the Dev Hub allows only
3 active scratch orgs, so a rebuild can require deleting someone else's org.

**Never run `cci org remove` against it.** For a scratch org that command deletes
the org itself, not just CumulusCI's keychain entry - one was destroyed that way
on 2026-08-27, taking CPQ, the deploy and all generated data with it. The same
applies to `sf org delete scratch` and to deleting `ActiveScratchOrg` rows on the
Dev Hub.

Data loading does not go through CumulusCI at all. Snowfakery generates JSON
locally, `scripts/qdtd/build-load-apex.py` turns it into anonymous Apex, and
`sf apex run` loads it - no access token is ever handed to a second tool, which
is what prompted the destructive `cci org remove` in the first place.

## sf-skills

Installed from [`forcedotcom/sf-skills`](https://github.com/forcedotcom/sf-skills) via:

```bash
npx skills add forcedotcom/sf-skills
```

112 skills, symlinked into `.claude/skills/` (and `.agents/skills/` for other tools). Re-run the same command to pick up upstream updates — it's idempotent. The library is described upstream as evolving rapidly; skills may be renamed or restructured between runs, so re-check `.claude/skills/` if a skill referenced here stops resolving.

### Skills genuinely relevant to this project

This repo is a Salesforce CPQ project: custom objects, Custom Metadata-driven configuration, Apex triggers/classes, permission sets, report types, and a DocuSign CLM integration — no LWC-heavy UI, no Experience Cloud, no Commerce, no OmniStudio, no Data Cloud. The table below reflects that; skills outside this project's actual footprint are named explicitly as not applicable, not silently omitted, per the instruction to understand where each skill can or can't help.

| Skill | Use it for, in this repo |
|---|---|
| `dx-code-analyzer-run` | Static analysis on every `QuoteDocument*` class before a PR — PMD (Apex best practices, CRUD/FLS, security), CPD (duplication), SFGE (data-flow security). Needs Java (see PATH note above) for PMD/CPD/SFGE; without it only the `regex` engine runs. Already run once this session — see `code-analyzer-results-*.json` in the repo root and the findings noted below. |
| `dx-code-analyzer-configure` | If a future scan reports an engine startup error (missing Java, plugin not installed) — delegates setup, don't self-diagnose. |
| `dx-code-analyzer-custom-rule-create` | If this project ever wants to enforce a repo-specific rule (e.g., "every `Quote_Document_Table_Def__mdt` guide file must exist for every active table definition") as a lint rule instead of a manual checklist item. Not used yet. |
| `platform-apex-generate` | Scaffolding a new `QuoteDocument*` class or trigger in the established style. |
| `platform-apex-test-generate` / `platform-apex-test-run` | Generating/running Apex test coverage — this is exactly the workflow used to close the coverage gaps in `phases/phase-4-test-matrix-reconciliation.md` and reach the 98% org-wide target. |
| `platform-apex-logs-debug` | Debugging a failed `QuoteDocumentGenerator.generate()` call or a `Document_Data_Error__c` message in a real org. |
| `platform-custom-object-generate` | Any future object in this family (e.g., if `phase-5-generation-versioning.md` or a Contract-spanning sibling framework ever gets built). |
| `platform-custom-field-generate` | Adding a new measure or snapshot field to `Quote_Document_Row__c` / `Quote_Document_Table__c` — remember the accompanying step this project always needs: add the field to `CPQ_Document_Totals.permissionset-meta.xml` too (documented in `docs/quote-document-totals.md` §7, "Field-level security will bite you"). |
| `platform-custom-report-type-generate` | Extending `Quote_Document_Tables_and_Rows.reportType-meta.xml` when a new measure needs to be exposed as a report column — this is the exact fix applied this session for `Amount_Regular__c`/`Amount_Customer__c` (custom report types require every field explicitly listed; having it on the object isn't enough). |
| `platform-report-generate` | Building the per-table-view reports under `force-app/main/default/reports/CPQ_Document_Totals/`, one per `Table_Code__c`, per `docs/documentation-standards.md`'s reporting-section requirement. |
| `platform-permission-set-generate` | Keeping `CPQ_Document_Totals.permissionset-meta.xml` in sync with new fields/objects. |
| `platform-validation-rule-generate` | The five declarative rules on `Quote_Document_Row__c` (`Aggregate_Excluded_From_Totals`, etc.) — extend this way, not in Apex, for anything a single record can validate on its own. |
| `platform-metadata-deploy` / `platform-metadata-retrieve` | The `sf project deploy start` / retrieve loop this session ran repeatedly by hand. |
| `platform-soql-query` | Ad-hoc verification queries against `Quote_Document_Table__c` / `Quote_Document_Row__c` in a connected org — the same queries embedded in each phase doc's "Verification method" section. |
| `platform-docs-get` | Looking up current Salesforce/CPQ platform documentation rather than relying on training-data knowledge that may be stale — relevant given this project has already been bitten once by an assumption about DocuSign CLM vs. Gen syntax (see `docs/quote-line-type-bundle-reporting-guide.md` §13). |
| `platform-data-manage` | Bulk data operations against the org — e.g., the backfill script's job (`scripts/apex/quote-document-backfill.apex`), or seeding scratch-org demo data. |
| `platform-sandbox-configure` | Provisioning the scratch org used by `scripts/scratch-org-bootstrap.sh`. |
| `dx-org-manage` / `dx-org-switch` / `dx-org-permission-set-assign` | Managing and switching between the dev org and any scratch orgs, and assigning `CPQ_Document_Totals` — the exact step in every phase doc's deployment checklist. |
| `dx-devops-test-suite-run` / `dx-devops-test-failures-analyze` | Running `QuoteDocumentGeneratorTest` + `QuoteDocumentLifecycleTest` in CI and triaging a failure — same job as `sf apex run test` used manually this session. |
| `external-diagram-mermaid-generate` | Rendering the object-hierarchy / pipeline diagrams that currently live as ASCII art in `docs/quote-document-totals.md` — optional, not required, since the ASCII form is deliberate (renders in any Markdown viewer without a Mermaid plugin). |
| `integration-eventing-cdc-configure` / `integration-eventing-subscription-configure` | Directly relevant if `phase-6-automatic-generation.md` is ever triggered (platform-event-driven generation) — not needed before that phase's hard prerequisites (Phases 1 and 2) close. |

### Not applicable to this project (confirmed, not omitted)

`agentforce-*`, `commerce-*`, `data360-*`, `design-systems-slds*`, `experience-*`, `mobile-*`, `omnistudio-*`, `service-digital-engagement-*`, `sales-agentforce-*` — none of these apply. This repo has no Agentforce bot, no B2B/B2C Commerce storefront, no Data Cloud, no Experience Cloud site, no mobile app, no OmniStudio, and no digital engagement channel configuration. If the project's scope ever expands into one of these areas, revisit this table rather than assuming the skill isn't installed — it already is.

### Findings from the first `dx-code-analyzer-run` pass

Run against every `QuoteDocument*` class and both triggers (PMD + CPD + regex; SFGE and ApexGuru not run — SFGE needs an explicit `--workspace` flag and 10–20 minutes, ApexGuru needs deeper org auth setup, neither was justified for a first pass). 188 violations, 0 Critical, 12 High, 50 Moderate, 126 Low.

Reviewed, not blindly fixed — each needs a judgment call this session didn't have the scope to make safely:

- **`ApexCRUDViolation` (×10, High)** — DML/query calls PMD can't statically prove are permission-checked. Most of this codebase's actual CRUD enforcement comes from the `CPQ_Document_Totals` permission set and `WITH USER_MODE` on specific queries (documented in `docs/quote-document-totals.md` §2.1 and §5.1) — PMD can't see the permission-set model, so several of these are plausibly accepted risk rather than real gaps. Needs a deliberate review pass, not an automated fix, since blindly wrapping every DML in `Security.stripInaccessible` could silently change delete/regeneration behavior this framework depends on (e.g., `QuoteDocumentRetention`'s cross-quote deletes).
- **`ApexSOQLInjection` (×1, High, `QuoteDocumentGenerator.cls`)** — the dynamic SOQL in `queryQuotes()`. The interpolated field list comes from `QuoteDocumentTableDefinition.allFieldPaths()`, which is schema-validated field-by-field in `validateFieldPath` *before* it's concatenated into the query string — so this is very likely a false positive PMD can't see past (it can't trace that the string was validated upstream). Worth a comment at the call site rather than a structural change, so the next PMD run — or the next developer — doesn't have to re-derive this.
- **`ApexUnitTestClassShouldHaveRunAs` (×49, Moderate)** — neither test class wraps its assertions in `System.runAs()`. Deliberately not fixed here: this codebase's tests are written to run as the deploying/admin user, matching how generation is actually triggered (a quick action, not typically a restricted-permission user), and retrofitting `runAs` across 51 tests without checking whether `CPQ_Document_Totals`-only permissions still pass is exactly the kind of change that needs its own verification pass, not a global find-and-replace.
- **`ApexDoc` (×71, Low) / `FieldDeclarationsShouldBeAtStart` (×19, Low)** — style-only, and this project has an explicit standing preference for minimal comments (only where the *why* isn't obvious) documented throughout `docs/quote-document-totals.md`'s own commentary. Not fixed — would fight the codebase's established style, not improve it.
- **`EmptyCatchBlock` (×1, High, `QuoteDocumentGeneratorTest.cls`)** — genuinely fixed. A catch block added this session had only comments, no statement; added a sanity assertion on the caught exception's message.

Full results: `code-analyzer-results-20260803-005843-2.json` (repo root). Query it with `node .agents/skills/dx-code-analyzer-run/scripts/query-results.js <file> [options]` rather than reading the JSON directly — see that skill's `SKILL.md` for the full option set.
