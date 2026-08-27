# Step 09 — Documentation and closeout

**Status: PLANNED**
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

- [ ] No architecture doc presents DocuSign as the system's rendering model.
- [ ] Every guide's §9 is labelled as an adapter.
- [ ] No filtering conditional remains in any guide; every surviving conditional is annotated as styling.
- [ ] No guide instructs the author to type a table title or column heading into Word.
- [ ] Standards file requires columns and semantic keys in new guides.
- [ ] `CLAUDE.md` reading list updated.
- [ ] Series-level: the definition of done in [`spec.md`](../spec.md) §1 is demonstrably true, evidenced by the step 08 commit SHA.

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

- **Date:**
- **Series outcome:**
- **Deferred items:**
