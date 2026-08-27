# Quote Document Feature Guides — authoring standard

**Purpose:** this file is the reusable template behind [`docs/quote-line-type-bundle-reporting-guide.md`](quote-line-type-bundle-reporting-guide.md). It exists so that any future "how do I get X shown on the quote document / reported on / put in the DocuSign template" request produces a guide at the same level of rigor, without the requester having to re-specify format, depth, or click-by-click detail every time.

**Trigger:** apply this standard automatically whenever someone asks for a guide, config walkthrough, or setup doc covering any `Quote_Document_Table_Def__mdt` view — new or existing — in this repo. Don't ask whether to follow it; follow it, then flag deviations if a case genuinely doesn't fit.

---

## 1. The eleven required sections, in order

Every guide produced under this standard has these sections, in this order. Renumber to fit the specific guide, but don't drop one — if a section has nothing to say for this particular view (e.g. "no code change needed"), say that explicitly rather than omitting the section.

| § | Section | Must contain |
|---|---|---|
| 0 | **Title + status banner** | One sentence stating this is the single source of truth and is self-contained. A **Status** line stating exactly what's applied-in-source vs. deployed-to-an-org vs. verified-by-running — never blur these three. |
| 1 | **What you're building** | A table: view name, shape (in plain English — "one row per X, columns for Y"), table code. This is the elevator pitch a reader scans before committing to the rest. |
| 2 | **Architecture primer** | The data model, restated in full — object hierarchy, the `Row_Type__c` reference table, the two measure families, how grouping works. Copy this from an existing guide rather than re-deriving it; keep it word-for-word consistent across guides so a reader who's seen one guide recognizes the next instantly. |
| 3 | **Classification/business-logic caveats** | Any provisional or unverified logic this view depends on (e.g. `classify()`'s five branches), stated plainly, with the specific risk if skipped. If none apply to this view, say so in one line — don't delete the section. |
| 4+ | **One subsection per view/table**, each with: what it prints (ASCII table), exact `Quote_Document_Table_Def__mdt` config as a **Field \| Value** table sourced from the real deployed record (or the new one you're proposing), the grouping record(s), and a **deployable XML file** for each — real, complete, ready to `sf project deploy start`, never pseudo-code. | |
| — | **Code changes**, if any | Only if config alone can't do it. Apply the fix directly to the real files, with a test — but **do not narrate the diff in the guide**. The guide is for a junior admin who should never need to read Apex; state the resulting behavior in one line inside the relevant view's section (e.g. "lines with no bundle print under a labeled 'Uncategorized' bucket — already handled, nothing to configure"), and put the reasoning where a developer will actually look for it: inline code comments in the changed file. If the change adds a genuine per-table config option (a new CMDT field), document *that* like any other config field — a row in the config table — not as a code walkthrough. |
| — | **Worked example** | One concrete numeric scenario walked through every view in the guide, with a **script** (`scripts/apex/*.apex`) that builds it as real records — hand-built, safe to re-run, scoped to its own table codes so it never clobbers another example's data. |
| — | **Deployment checklist** | Numbered, in the order a junior dev would actually run them: deploy → assign permset → generate/build → verify with a SOQL query → move on to reports/template. State plainly what's already done in source vs. what the reader still has to do. |
| — | **Salesforce reports** | **Build the actual report(s) as deployable metadata** (`force-app/main/default/reports/CPQ_Document_Totals/*.report-meta.xml`, following the existing reports' conventions) — one per view, filtered to that view's `Table_Code__c`. Tell the reader which named report to open (**Reports → CPQ Document Totals → \<name\>**), not how to build one. Keep the filter/group/column spec as a table underneath, for anyone auditing the report definition, but the primary instruction is "go here," not "build this." State explicitly if multiple views can't share one report (they usually can't — say why, don't let the reader assume). **Also:** Quote-scoped preview links — when [`specs/quote-document-report-links`](../specs/quote-document-report-links/spec.md) is implemented, each view needs a `Quote_Document_Report_Link__mdt` row and an unlocked Quote filter as `fv0` per that series' contract; until then, note the report name and that one-click Quote preview is planned. |
| — | **DocuSign CLM (or Gen) template** | Full click-by-click: Data Source/mapping setup (with the exact field→XML-node table), Composer usage (where tags come from, which one you hand-type), the actual tag block per view, styling, publishing, connecting to a Salesforce button, and how to verify before trusting it. Assume the reader has never opened the tool. Confirm which product (CLM vs. Gen) before picking a syntax — don't guess silently; if you got it wrong once already in this conversation, say so, matching the correction pattern from the flagship guide's §13 opening. |
| — | **Scratch-org reproduction** | Point at (or extend) the shared bootstrap script (§6 below) so this view is included in the one-command replay. Don't invent a second bootstrap script per guide. |
| — | **Review & score** | Self-review against §5's rubric below, itemized, with a final score. Required on every guide — see §5. |

---

## 2. Non-negotiable authoring rules

These came from direct corrections in the conversation that produced the flagship guide. Treat them as binding, not stylistic preferences.

1. **Self-contained. No cross-document dependency.** A reader must never need to open a second file to follow this one. Repeat the architecture primer in full every time, verbatim. *(Corrected explicitly: "I am not referring to another document. I need this document to be the single source of truth.")*
2. **Ground every claim in the actual repo, not in general Salesforce/CPQ knowledge.** Read the real Apex/metadata before writing a field name, a default value, or a behavior claim. If you find the requester's own assumption is wrong (like the alphabetical-vs-sequence group ordering), say so plainly, show the code that proves it, and correct course — don't silently agree and write around it.
3. **If something isn't achievable through configuration, don't just flag the gap — write the fix, and keep it out of the guide.** Apply the real change to the real files, with a test. *("make sure the code can handle it" — a gap flagged but not closed does not satisfy this.)* But the guide itself should read as if the framework always handled it: a junior admin/developer using this guide should never need to understand *how* the fix works internally, only that it does. Put the "why" in the code (inline comments, docblocks), not in a "Required code change" narrative with diffs — a config guide is not a PR description. *(Corrected explicitly: "the framework should take care of all of that right? ... the junior developer/admin does not need to know ... remove all these things from the docs.. just apex." An earlier draft of the flagship guide got this backwards — full diffs and a "Required code change" walkthrough for two Apex fixes — and had to be stripped back to one line each, with the Apex left exactly as applied but the narrative removed. Don't repeat that.)*
4. **Every metadata/code snippet is a complete, deployable file**, not an excerpt or pseudocode. A reader should be able to save the block verbatim and deploy it. This applies to reports too: build the actual `.report-meta.xml` in `force-app/main/default/reports/CPQ_Document_Totals/` for every view, and point the reader at it by name — don't describe a report and leave building it as an exercise for the reader. *(Corrected explicitly: "Are the reports created for each of the examples? ... please add them to each of the example document asking users to go to a particular report to view the data.")*
5. **Every worked example ships as a script**, not just numbers in the doc. Hand-built (not generator output) unless the scenario is one the generator can actually produce from real data today. Safe to re-run: scope deletion to only what the script owns.
6. **One `.md` file per guide.** Never split a guide across files, and never produce anything other than Markdown for this kind of deliverable, per this project's standing preference.
7. **State verification status honestly, every time.** "Written and internally consistent" is not the same claim as "deployed" or "ran successfully in an org." If you have no CLI/org access in your environment, say exactly that — don't imply you clicked something you didn't.
8. **DocuSign instructions are click-by-click, assuming zero familiarity with the tool.** Name the actual menu path, what gets auto-generated vs. hand-typed, and how to verify before trusting output. Confirm CLM vs. Gen from evidence (a real tag sample, a stated product name) — never pick one silently and hope.
9. **A scratch-org bootstrap script is shared, not per-guide.** Extend the one script (`scripts/scratch-org-bootstrap.sh`) to include every new example's build step, so there is always exactly one command that reproduces everything.

---

## 3. Style conventions

- Headings: `##` for top-level numbered sections, `###` for subsections within one view.
- Every config recipe is a **Field \| Value** two-column table, immediately followed by the raw deployable XML — table for scanning, XML for copy-paste.
- ASCII-art tables (fixed-width text in a fenced code block) for "what it prints" — not a Markdown table — because printed-document layout (indentation, subtotal rows) doesn't survive Markdown table rendering.
- Numbers in worked examples must foot correctly across every view in the guide (all grand totals agree) — this is itself part of the review score (§5).
- No filler transitions ("Now let's look at..."). Each section opens with the content, not a preamble.
- Link every other file mentioned (`force-app/...`, `scripts/...`) as an inline code path so it's unambiguous which repo file is meant.

---

## 4. Reusable boilerplate blocks

Copy these verbatim into every new guide's corresponding section — don't redrive them from scratch, and don't let them drift out of sync between guides. If one needs to change, update it here first, then propagate.

### 4.1 Architecture primer (§2 of every guide)
Source: `docs/quote-line-type-bundle-reporting-guide.md` §2, in full — the object hierarchy diagram, the `Quote_Document_Row__c` field reference table, the two-measure-family explanation, and the grouping-mechanism paragraph.

### 4.2 DocuSign CLM Data Source setup (part of the DocuSign section of every guide)
Source: `docs/quote-line-type-bundle-reporting-guide.md` §11.2 — steps 1–3 (Admin Console → Data Sources → root object → repeating child nodes) are identical for every guide. Only the field-mapping table (step 6) changes per view — list only the fields that specific guide's tags actually use.

### 4.3 Composer usage steps
Source: §11.3 of the same guide — identical across every guide (how repeating regions/conditionals get inserted, what's auto-generated vs. hand-typed).

### 4.4 Publishing + connecting to Salesforce
Source: §11.8 of the same guide — identical across every guide.

**Section numbers drift.** The flagship guide has been renumbered at least once already (removing a "Required code change" section per rule 3 shifted everything after it down by two). Before citing a section number from the flagship guide anywhere — here or in a new guide — verify it against the file's actual current headings rather than trusting a number written down earlier in this standard.

---

## 5. Review rubric — every guide must score ≥ 9.8 / 10 before it's considered done

Ten criteria, one point each, scored 1.0 / 0.5 / 0. A guide below 9.8 gets fixed before being presented as finished — don't present a low score as acceptable and stop.

| # | Criterion | 1.0 | 0.5 | 0 |
|---|---|---|---|---|
| 1 | Self-contained | Zero cross-doc dependencies | Minor cross-reference to a sibling script only | Assumes another doc was read |
| 2 | Grounded in real code | Every field/object name verified against actual repo source | One or two claims not directly verified | Guessed at Salesforce/CPQ conventions generically |
| 3 | Config vs. code correctly separated | Every "needs code" case is applied directly to the real files (with a test) and mentioned in the guide in one line, no diff/walkthrough exposed to the reader; genuine new config fields are documented as config, not as code | A diff or Apex excerpt is still shown in the guide, even briefly | A gap flagged without a fix, or a full diff/code-review-style section left in a reader-facing guide |
| 4 | Deployable artifacts | Every snippet is a complete, real file | Snippet complete but formatting/whitespace needs cleanup | Pseudocode or partial file |
| 5 | Worked example + script | Numbers foot exactly across every view; script exists, safe to re-run, scoped deletion | Numbers foot; script exists but deletion scope too broad or too narrow | No script, or numbers don't reconcile |
| 6 | Deployment checklist | Ordered, actionable, states what's already done vs. pending | Ordered but missing a status distinction | Missing or out of order |
| 7 | Reporting section | Points at a real, deployed report by name for every view; explains what can't be combined and why | Spec/table given but the report itself wasn't actually built as metadata | Vague ("build a report showing...") |
| 8 | DocuSign section | True click-by-click, correct product (CLM/Gen) confirmed from evidence, tags are real and complete | Click-by-click but assumes one menu label without noting it may vary | Generic tag examples with no setup walkthrough |
| 9 | Honest verification status | States plainly what was/wasn't actually run, in an explicit Status line | Mentions limitations but not up front | Implies deployment/testing that didn't happen |
| 10 | Scratch-org reproduction | Points at the one shared bootstrap script, extended to cover this guide | Gives standalone steps that duplicate the bootstrap script | No reproduction path given |

**Scoring a guide:** list all ten, mark each, sum, present as `X.X / 10` at the end of the guide itself (§"Review & Score"), not just in a separate audit. If any single criterion scores 0, the guide is not done — fix it before delivering.

---

## 6. The shared scratch-org bootstrap script

`scripts/scratch-org-bootstrap.sh` is the **one** script that reproduces the entire repo, base demo data, and every worked example, for every guide, in one run. Every new guide's worked-example script gets one new line added to this bootstrap script (in its own numbered step) — never create a second bootstrap script.

---

## 7. Template skeleton (copy this to start a new guide)

```markdown
# <View Name> — configuration and DocuSign guide

**Single source of truth, self-contained.**

**Status:** <applied-in-source? deployed? verified?>

## 1. What you're building
## 2. Architecture primer               (§4.1 boilerplate, verbatim)
## 3. Classification/business-logic caveats   (or: "None apply to this view.")
## 4. <View>                             (config table + XML + sample output, repeat per view)
## 5. Code changes                       (or: "None needed — configuration only.")
## 6. Worked example + script
## 7. Deployment checklist
## 8. Salesforce reports
## 9. DocuSign CLM template              (§4.2–4.4 boilerplate + view-specific tags)
## 10. Scratch-org reproduction          (point at scripts/scratch-org-bootstrap.sh)
## 11. Review & score
```

---

## 8. Applying this standard right now

This standard was extracted retroactively from `docs/quote-line-type-bundle-reporting-guide.md`, which already scores against this rubric (see that guide's own §"Review & Score" once added). The six remaining shipped table definitions — `PRODUCT_FAMILY_SUMMARY`, `CHARGE_TYPE_SUMMARY`, `BUNDLE_DETAIL`, `GROUP_FAMILY_DETAIL`, `OPTIONAL_PRODUCTS`, `FAMILY_BILLING_COMPOSITE` — each get their own guide under this same standard:

- `docs/product-family-summary-guide.md`
- `docs/charge-type-summary-guide.md`
- `docs/bundle-detail-guide.md`
- `docs/group-family-detail-guide.md`
- `docs/optional-products-guide.md`
- `docs/family-billing-composite-guide.md`

All six are config-only (no code changes needed — the CMDT framework already supports every one of them), so each guide's §5 will read "None needed" with an explanation of why, which is itself information a reader needs (not a shortcut taken).


## Required since the render contract

Three rules every new `Quote_Document_Table_Def__mdt` guide must follow. They exist because the
framework moved presentation out of templates and into the snapshot, and a guide written the old way
quietly teaches the next author to put it back.

### 1. Document the columns, not the tags

State which `Quote_Document_Column_Def__mdt` records the table has: code, order, bound field, data type.
That table **is** the column layout. A guide that instead lists which `<Value Select="..."/>` tags to
drag into Word is describing one renderer's implementation of the layout, which is exactly the coupling
the contract removes.

### 2. Document the semantic keys

List the label keys the table's rows resolve — `GRAND_TOTAL`, `SUBTOTAL`, `SECTION_TOTAL`, and any the
table adds. A reader translating the document needs the keys; the English wording is a lookup, not the
contract.

### 3. Never instruct the author to type printable text into a template

No table title, no column heading, no disclaimer, no notice. Every one of those is data now:

| Printable text | Where it lives |
|---|---|
| Table heading | `Display_Title__c` on the table definition |
| Subtitle, intro, footer | `Display_Subtitle__c`, `Intro_Text__c`, `Footer_Text__c` |
| Column heading | the label dictionary, keyed by column code |
| Row label | the label dictionary, keyed by semantic key |
| Notice, terms, signature instructions | `Quote_Document_Content__mdt` |

The test is simple: **if the sentence exists only inside a `.docx`, no review, no translation and no
test can reach it.** That was true of the optional-products disclaimer for the whole life of this
project, and nobody noticed until the audit went looking.

### 4. Conditionals are styling only

A guide may show a conditional that decides how a row **looks**. It may not show one that decides
whether a row **prints** — that is `Is_Displayed`, decided during generation so every renderer reaches
the same answer. Annotate every surviving conditional as styling, so the distinction survives the next
edit.

### 5. Label the renderer section as an adapter

The DocuSign section is "Adapter: DocuSign CLM", and it opens with the launch sequence: a Salesforce
action performs generate-or-reuse and binds the published snapshot by request Id and fingerprint. A Data
Source pointed straight at the objects is not a conforming renderer and must not be documented as one.
