# Step 00 — Audit sign-off and contract principles

**Status: COMPLETE**
**Blocked by:** nothing
**Blocks:** every later step
**Owner decision needed:** only if overriding the defaults below

---

## 1. Goal

Freeze what the renderer is allowed to do, confirm the audit in [`spec.md`](../spec.md) §2 is complete, and get the data model approved before any field is deployed. No code in this step.

## 2. Why this step exists

The expensive failure mode here is building `Column_1_Label__c` through `Column_20_Label__c`, or a `Quote_Document_Block__c` nobody has content for, and carrying them forever. Deciding the model against real table shapes costs an hour; unwinding a wrong one costs a release.

## 3. Scope

1. Owner reviews the [`spec.md`](../spec.md) §2 audit table and either accepts it or names what is missing. Anything added must name a file and line, not a suspicion.
2. **These are locked, not open questions.** They were choices while the design was unsettled; the design is settled, and leaving them open only delays the build. An owner overrides one by recording the use case and the consequence in §7 — nobody needs to *confirm* them to proceed:

   | Locked | Value |
   |---|---|
   | Locale source | **Per quote**, from an explicit configured field path. The contract carries locale even if the first rollout authors one language. |
   | Required-label fallback | **Fail.** Optional text may use a configured chain. Silent blanking is prohibited. |
   | Column model | **`Quote_Document_Column__c` child object.** |
   | Generation persona | **B1** — system-context source reads, gated at the entry point by a `Generate_Quote_Document` custom permission ([`spec.md`](../spec.md) §10). Deliberately separates permission-to-generate from permission-to-read-every-source-field, so it ships **subject to security review**, which is a review, not a decision to reopen. |
   | Dependency declaration | **Mandatory from day one.** `Cache_Policy__c` is required; there is no phase where undeclared reads are tolerated. |
   | Narrative blocks | **Built** ([step 04](step-04-narrative-blocks.md)) — see §3.1 below. |

3. **The one genuine owner decision: namespace scope.**

   | Option | Consequence |
   |---|---|
   | **A — same namespace / unlocked source** *(default)* | `public` is sufficient. The subscriber factory is optional convenience. |
   | **B — cross-namespace managed package** | A permanent `global` Apex API that cannot be narrowed later, requiring a transitive type inventory ([step 01A](step-01a-extension-contracts.md) §8). |

   Enable B only if packaged distribution is a confirmed product requirement. Speculative enablement is the expensive mistake here, because it cannot be undone.

   The attempt-history object ([step 05](step-05-snapshot-integrity.md)) stays deferred — operational convenience, not a correctness prerequisite.

### 3.1 Why narrative blocks are no longer conditional

A real document contains an introduction, notices, terms, clauses, signature instructions, and headings between tables. `Intro_Text__c` and `Footer_Text__c` are attached to a table and cannot model any of that. So either blocks are built, or the definition of done is narrowed to:

> A complete vendor-neutral payload for **tabular quote content and table-attached narrative**.

Claiming to represent the whole document while standalone content sits outside the contract is the version that fails on contact with the first real template. Blocks are built — kept small, per step 04.

4. Record the renderer permissions, prohibitions, and the seven hard constraints in [`spec.md`](../spec.md) §8 as the acceptance bar every later step is measured against — including the honest limit in §1: contributors are trusted, not sandboxed.
5. Run the table-definition inventory mechanically. Current baseline: 15 definitions, seven active, four with customizer codes.
6. Classify every `Conditional Test` hit as **visibility/business logic**, **styling**, or **documentation example**. Do not use a raw hit count as a requirement.

## 4. Out of scope

- Any metadata or Apex change.
- Touching DocuSign templates.
- Deciding renderer *choice* — this spec makes the choice replaceable, it does not make it.

## 5. Acceptance criteria

- [x] Audit table accepted, or amended with file:line evidence for each addition.
- [x] Namespace scope decided and recorded in §7. Any override of a §3 locked default recorded with its use case and consequence.
- [x] Data model in [`spec.md`](../spec.md) §3 approved or edited.
- [x] Confirmed that no step in this series changes a measure, a filter, a grouping, or `verify()`.

## 6. Verification method

Editorial review plus mechanical checks that the audit is not stale:

```bash
rg -n "Conditional Test" docs --glob "*.md"
rg -n "Row_Customizer_Code__c|Is_Active__c" force-app/main/default/customMetadata --glob "Quote_Document_Table_Def.*.md-meta.xml"
```

Record the classified conditional inventory and parsed metadata counts in close-out. No fixed grep count is a pass condition.

## 7. Close-out

- **Date:** 2026-08-27
- **Decision — namespace scope (A / B):** **A — same namespace / unlocked source.** `public` Apex is sufficient; no `global` API is created and the subscriber factory stays optional convenience. Packaged cross-namespace distribution is not a confirmed product requirement, and B is the one choice that cannot be narrowed later.
- **Overrides to locked defaults, if any:** none. Locale source (per quote), required-label fallback (fail), column model (`Quote_Document_Column__c`), generation persona (B1), dependency declaration (mandatory), narrative blocks (built) all stand as written.
- **Security review booked for B1 persona:** outstanding. B1 ships subject to it; it gates release, not the start of the build. Raise before [step 06A](step-06a-snapshot-immutability.md) closes.
- **Definition inventory:** 15 `Quote_Document_Table_Def__mdt` records; **7 active** — `BUNDLE_DETAIL`, `CHARGE_TYPE_SUMMARY`, `DISCOUNT_SUMMARY`, `FAMILY_BILLING_COMPOSITE`, `GROUP_FAMILY_DETAIL`, `OPTIONAL_PRODUCTS`, `PRODUCT_FAMILY_SUMMARY`; **8 inactive** — `BUNDLE_PRODUCT_GRID`, `BUNDLE_SUMMARY`, `DISCOUNT_EXAMPLE`, `INDUSTRY_ALLEGIANCE`, `PRODUCT_SUMMARY`, `ROUNDING_EXAMPLE`, `ROW_CUSTOMIZER_EXAMPLE`, `TRANSACTION_SUMMARY`. **4 name a row customizer**, all inactive: `DISCOUNT_EXAMPLE`, `INDUSTRY_ALLEGIANCE`, `ROUNDING_EXAMPLE`, `ROW_CUSTOMIZER_EXAMPLE` (code `ESTIMATED_TAX`). Matches the [`spec.md`](../spec.md) §2 baseline; no amendment needed.
- **Conditional inventory artifact:** 15 `Conditional Test` hits in `docs/`, classified — no count is a pass condition, the classification is.

  | Class | Count | Hits |
  |---|---|---|
  | **Visibility / business logic** | 5 | `discount-summary-guide.md:212`, `:215`; `family-billing-composite-guide.md:180`; `product-family-summary-guide.md:200`; `optional-products-guide.md:194` (section-level `count(...) > 0`) |
  | **Styling** | 3 | `charge-type-summary-guide.md:174`; `product-family-summary-guide.md:206`; `quote-line-type-bundle-reporting-guide.md:552` |
  | **Documentation example** | 7 | `quote-line-type-bundle-reporting-guide.md:458`, `:467`, `:519`, `:535`, `:544`, `:564`, `:571` — a syntax reference guide, not a deployed template |

  The 5 visibility hits are exactly what `Is_Displayed__c` on row and table absorbs ([step 06](step-06-contract-validation.md), [step 01](step-01-table-presentation-fields.md)). The 3 styling hits stay in the renderer, keyed on `Row_Type` — which remains styling-only.
- **Audit table:** accepted as written. No additions; nothing found in the metadata or the guides that §2 does not already name with a file and line.
- **Data model:** [`spec.md`](../spec.md) §3 approved unedited.
- **Confirmed:** no step in this series changes a measure, a filter, a grouping, or `verify()`.
- **Org used for verification:** `gkCpqDevHub` (`00Dbm00000sk0IrEAI`), connected; 86 `Quote_Document_Table__c` records readable.
- **Next step:** [`step-01a-extension-contracts.md`](step-01a-extension-contracts.md)
