# Phase 8 — Rule-driven table eligibility (stop generating every definition for every quote)

**Status: PLANNED — ready to build, blocked only on the field-discovery step in Task 1**
**Blocked by:** nothing structurally; needs one discovery conversation before rule data can be authored (see §6)
**Blocks:** nothing directly. Not a prerequisite for Phases 1–7.
**Owner decision needed:** yes — which Quote/Opportunity/Account fields represent the first real dimensions (Quote Type, Opportunity Type, Account Type), before any `Quote_Document_Table_Rule__mdt` record can be written correctly

---

## 1. Goal

Today, `QuoteDocumentGenerator.generateOne` builds one `Quote_Document_Table__c` for **every** active `Quote_Document_Table_Def__mdt`, for **every** quote — documented as current, intended behavior in `docs/quote-document-totals.md` §7 ("Every definition is generated for every quote | Deactivate unused ones with `Is_Active__c`"). `Is_Active__c` is the only lever, and it's global: turning a table off removes it for every quote everywhere, not just the ones it doesn't apply to.

This phase adds **per-quote eligibility**: a table definition can declare, in metadata, which quotes it applies to — by Quote Type, Opportunity Type, Account Type, or any future dimension — and the generator builds only the definitions that match a given quote. A definition with no rules attached still applies to every quote (this is how the "common" tables stay common, with no special-case flag).

## 2. Why this phase exists

Not a gap from the original research (`research/1.md`–`5.md`) — this is new scope from a direct design conversation. As the definition count grows past the original six (Phase 0 already added an 11th, Discount Summary, and flagged Subscription/Tax tables as likely future additions), "every definition, every quote" stops being harmless. A Recurring-only quote generating a `TRANSACTION_SUMMARY` table that's meaningless for it, or an Enterprise-only addendum table showing up on every SMB quote, is exactly the kind of irrelevant/noisy output this framework has otherwise been careful to avoid (§2's whole A/B/C boundary is about not silently doing the wrong thing).

## 3. Design decided in conversation, and what was deliberately rejected

Worth recording explicitly, since the design changed twice before landing here:

- **Rejected: a multi-select picklist field on the Quote**, defaulted at creation and edited by the rep before each Generate click. Rejected for two reasons: (a) picklist values are static and drift out of sync with `Table_Code__c` values in CMDT — a new table definition needs someone to remember to also add a picklist value; (b) it's *stored* state that can go stale relative to the Quote/Opportunity/Account it's derived from, the opposite of this framework's own founding rule that generated data is a disposable projection, never repaired (`docs/quote-document-totals.md` §1).
- **Rejected: criteria fields directly on `Quote_Document_Table_Def__mdt`** (e.g. `Quote_Type_Criteria__c`, `Opportunity_Type_Criteria__c` as sibling multi-select fields). This only expresses AND-across-a-fixed-field-list and can't express "(Recurring AND Upsell) OR (Enterprise, any quote type)" — real combinations across dimensions — without turning the field list itself into an ad hoc boolean-logic surface.
- **Adopted: eligibility as computed, not stored**, evaluated fresh on every generation from the Quote/Opportunity/Account's actual current state — no selection object anywhere. Uses the same child-metadata-with-`Dimension__c`-and-`Value__c` shape the codebase already uses for `Quote_Document_Grouping__mdt`, so a developer who already understands groupings recognizes this pattern immediately.
- **Adopted: disjunctive-normal-form (OR of ANDs)** as the combination logic — rules with the same `Group__c` number are AND'd, distinct groups are OR'd, zero rules means the definition is unconstrained (always eligible). This is deliberately the simplest model that covers every case discussed (single-dimension gate, multi-dimension AND, alternate-path OR) without building a general boolean-expression parser.
- **Adopted: the resolver never touches the row-building code.** Eligibility answers "which definitions apply," nothing about grouping, filtering, or measures. `QuoteDocumentGenerator`'s existing per-definition build loop doesn't change — it just iterates over a filtered list instead of `QuoteDocumentTableDefinition.getAll()` unfiltered.

## 4. Scope

1. **New CMDT: `Quote_Document_Table_Rule__mdt`.**

   | Field | Type | Notes |
   |---|---|---|
   | `Table_Def__c` | Metadata Relationship → `Quote_Document_Table_Def__mdt` | which definition this rule gates |
   | `Group__c` | Number | rules sharing a `Group__c` value are AND'd; distinct `Group__c` values are OR'd |
   | `Dimension__c` | Picklist | `QUOTE_TYPE`, `OPPORTUNITY_TYPE`, `ACCOUNT_TYPE` at launch — open for more values later, same open-endedness as `Quote_Document_Grouping__mdt.Dimension__c` |
   | `Value__c` | Text | the value that dimension must equal for this rule to match |

   A definition with **zero** child rule records is unconstrained — matches every quote. This needs no boolean flag; it falls out of "AND over an empty set of groups is vacuously... actually the correct statement is OR over zero groups is false" — so the evaluator's base case must be explicit: **no rule rows → eligible**, stated as code, not inferred from empty-list-is-falsy default logic (get this backwards and every unconstrained table silently stops generating for everyone).

2. **New class: `QuoteDocumentTableEligibility`** (name to be confirmed against existing `QuoteDocument*` naming conventions at build time).

   - Input: the normalized dimension values for one quote (see Task 3) and the full list of active `Quote_Document_Table_Def__mdt` with their `Quote_Document_Table_Rule__mdt` children.
   - Output: the subset of definitions eligible for this quote.
   - Evaluation, per definition: group its rules by `Group__c`; the definition is eligible if any group's rules **all** match (AND within group), or if it has no rules at all. An unrecognized `Dimension__c` value throws — same fail-loud convention as `QuoteDocumentLine.getGroupingValue`/`matchesFilter` (spec.md §2, "The part that makes this actually safe rather than just documented"). No silent pass-through.

3. **Dimension resolution.** A small `when`-block, structurally identical to `QuoteDocumentLine.getGroupingValue` (`docs/quote-document-totals.md` §5.1's Dimensions table) but resolved once per quote instead of once per line:

   ```
   QUOTE_TYPE        → [field TBD — confirm in Task 1]
   OPPORTUNITY_TYPE  → [field TBD — confirm in Task 1]
   ACCOUNT_TYPE      → [field TBD — confirm in Task 1]
   ```

   `AccountIndustry__c` on `SBQQ__Quote__c` is the existing precedent for this exact pattern — a formula field on the Quote denormalizing an Account attribute so it's queryable in the same `queryQuotes` SOQL without a relationship traversal per line (`QuoteDocumentLine.cls`, `industry = quote.AccountIndustry__c`). New dimensions should follow the same shape unless there's a reason not to: a formula field on `SBQQ__Quote__c` denormalizing the Opportunity/Account attribute, added to the `queryQuotes` SELECT list.

4. **Wire into `QuoteDocumentGenerator.generateOne`.** Currently:

   ```apex
   for (QuoteDocumentTableDefinition definition : QuoteDocumentTableDefinition.getAll()) { ... }
   ```

   appears twice — once building tables/rows (line ~141), once stamping/verifying them (line ~175). Both loops need to iterate over the **eligible** subset, computed once at the top of `generateOne` right after `normalize(quote)`, so both loops see the same list and stay in sync. This stays inside the existing single-savepoint, single-transaction structure from Phase 2/3 — eligibility is a filter applied before the loop starts, not a second transaction phase. (The earlier conversation floated a two-phase "insert shells with `Status__c='Generating'`, then requery" design for independent testability; deliberately **not** adopted here — it would split one savepoint-protected transaction into two, reopening exactly the atomicity question Phase 3 just closed. Keep it one transaction; revisit only if Phase 6's async/platform-event work later needs per-table parallelism.)

5. **Documentation.** Extend `docs/documentation-standards.md`'s required guide sections to include "Applies to," listing a definition's eligibility rules in plain language, so a table's scope is readable without opening CMDT records. Update `docs/quote-document-totals.md` §9's index with a new row: "Make a table apply only to certain quotes" → add `Quote_Document_Table_Rule__mdt` records, no Apex.

6. **Tests**, added to `QuoteDocumentGeneratorTest`:
   - A definition with zero rules is eligible for an arbitrary quote (the common-table case).
   - A definition with one rule group of two ANDed rules is eligible only when both match, not when just one does.
   - A definition with two rule groups (OR) is eligible when either group fully matches.
   - An unrecognized `Dimension__c` value throws, mirroring the existing grouping/filter tests.
   - End-to-end: two quotes with different `QUOTE_TYPE` values generate different `Table_Code__c` sets; a zero-rule definition appears in both.

## 5. Out of scope

- **No manual per-quote override.** If a rep needs to add or remove a table on a specific quote against what the rules compute, that's a real but separate feature — an additive exception list, not a redesign of the eligibility engine. Don't build it speculatively; per this framework's own established pattern (see `phase-5-generation-versioning.md` §5, `phase-6-automatic-generation.md`), wait for a real request.
- **No UI for authoring rules** beyond the standard Custom Metadata Types setup page. A guided rule-builder screen is a possible future convenience, not part of this phase.
- **No dimension requiring data outside the Quote's own record graph** (an external system call, an async lookup). Same restriction `resolvePath` already has for grouping field paths (spec.md §2, Category C) — this reuses that limitation rather than lifting it.
- **No change to which quote-level fields are valid *grouping* dimensions.** The "a Quote-level field yields exactly one group" trap (`docs/quote-document-totals.md` §5.2) is unrelated to and unaffected by this phase — eligibility deliberately wants exactly one value per quote; that's a feature here, not the limitation it is for grouping.

## 6. Preconditions / dependencies

**Task 1 must happen before any `Quote_Document_Table_Rule__mdt` record is authored:** confirm which real fields back `QUOTE_TYPE`, `OPPORTUNITY_TYPE`, and `ACCOUNT_TYPE` in this org — e.g., does "Quote Type" mean `SBQQ__Quote__c`'s own type/subscription-mix field, or something derived from line-level charge types; does "Opportunity Type" mean the standard `Opportunity.Type` picklist; does "Account Type" mean `Account.Type` or a segmentation field. This is a discovery step, not a technical blocker — same shape as Phase 0's tax-field and subscription-field discovery items, and shouldn't be assumed or guessed at build time.

No dependency on Phases 1–7 completing first. Can be built independently, though it's worth sequencing after Phase 4 (test matrix reconciliation) closes, so this phase's new tests land against a codebase whose existing test coverage is already reconciled rather than adding to an unverified baseline.

## 7. Acceptance criteria

- [ ] `Quote_Document_Table_Rule__mdt` deployed, correctly related to `Quote_Document_Table_Def__mdt`.
- [ ] `QuoteDocumentTableEligibility` (or equivalent) implemented and unit tested: AND-within-group, OR-across-groups, zero-rules-is-eligible, unrecognized dimension throws.
- [ ] `QuoteDocumentGenerator.generateOne` builds only eligible definitions for a given quote — verified against at least two differently-typed quotes producing different `Table_Code__c` sets, plus one zero-rule (common) table appearing in both.
- [ ] Existing behavior for today's 11 definitions is unchanged after this ships **until** rule records are added — i.e., zero rules on every existing definition means every existing definition keeps generating for every quote, exactly as today. This phase must not silently narrow current output the moment it deploys.
- [ ] `docs/documentation-standards.md` and `docs/quote-document-totals.md` §9 updated per Task 5.
- [ ] Full existing test suite (`QuoteDocumentGeneratorTest`, `QuoteDocumentLifecycleTest`) still green.

## 8. Verification method

```bash
sf project deploy start --target-org <alias> --source-dir force-app
sf apex run test --target-org <alias> --class-names QuoteDocumentGeneratorTest --class-names QuoteDocumentLifecycleTest --result-format human --synchronous
```

Manual: create two sandbox quotes differing in the confirmed `QUOTE_TYPE` dimension, add rule records gating one existing definition to each type plus leaving at least one definition unconstrained, run `QuoteDocumentGenerator.generate` against both, and confirm via SOQL (`SELECT Table_Code__c FROM Quote_Document_Table__c WHERE Quote__c = :quoteId`) that each quote's table set differs exactly as the rules specify, with the unconstrained table present on both.

## 9. Verification status

**Not built.** This document is the plan; nothing in this phase has been implemented or deployed yet.

## 10. Close-out record

- **Date opened:** 2026-08-04
- **Status:** planned, not started. Next action is Task 1 (field discovery), not code.
