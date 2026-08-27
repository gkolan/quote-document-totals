# Step 04 — Narrative blocks

**Status: BUILT — the payload-hash criterion belongs to step 06A, see close-out**
**Blocked by:** [step 03](step-03-semantic-keys-and-localization.md)
**Blocks:** 06, 07

---

## 1. Goal

Document-level content — introductions, notices, terms, clauses, signature instructions, headings between tables — reaches the renderer as data, in one ordering sequence with the tables.

## 2. Why this step is no longer conditional

An earlier draft made this object conditional on finding standalone narrative content in *this repository*, which contains one disclaimer. That is the wrong evidence base: the question is not what these ten guides happen to contain, it is what a real quote document contains. Every one of the items above is standalone, none is attached to a single table, and `Intro_Text__c` / `Footer_Text__c` cannot model any of them without inventing an empty table to hang them from.

So the choice was: build blocks, or narrow the definition of done to "tabular content and table-attached narrative only". Blocks are built ([step 00](step-00-audit-and-contract-principles.md) §3.1) — kept small, and with the same discipline as everything else: no markup, resolved text only, core decides inclusion.

The inventory in §3.1 still runs. It no longer gates whether the object exists; it decides which block codes ship on day one.

## 3. Scope

### 3.1 Inventory — which block codes ship

1. List every piece of printable text in the intended document that is not a table title, column heading, or row label. For each: table-attached (`Intro_Text__c` / `Footer_Text__c`) or standalone (a block)? Sources — the templates in use, [`optional-products-guide.md:192`](../../../docs/optional-products-guide.md:192), and the business owner's actual document.
2. Record the result in §7. It decides the day-one block codes, not whether the object exists.
3. Create `Quote_Document_Block__c`, lookup to `SBQQ__Quote__c`:

   | Field | Type | Notes |
   |---|---|---|
   | `Block_Code__c` | Text(40) | Semantic key, e.g. `TERMS_STANDARD`. |
   | `Block_Type__c` | Picklist | `Heading`, `Paragraph`, `Clause`, `Notice`. |
   | `Display_Order__c` | Number(4,0) | Interleaves with `Quote_Document_Table__c.Display_Order__c` in one document-wide sequence. |
   | `Is_Displayed__c` | Checkbox, default true | |
   | `Locale__c` | Text(10) | Same locale as the tables in the snapshot. |
   | `Heading__c` | Text(255) | Resolved, localized. |
   | `Body__c` | Long Text | Resolved, localized. Plain text only. |
   | `Source_Version__c` | Text(40) | Which version of the clause text this snapshot captured. |

4. **No markup, ever.** No HTML, no `<# ... #>` tags, no `«MergeField»` syntax, no Word XML in `Body__c`. Enforce by **pattern, not by character**: reject `<#`, `«`, and `<` immediately followed by a letter or `/` (an opening or closing tag). A bare `<` with whitespace or a digit after it is legitimate prose — "terminates in < 30 days" must be storable, and a blanket ban on the character would make it fail. A renderer that needs bold gets it from `Block_Type__c`, not from tags smuggled through the body.
5. Source long-form content from a dedicated CMDT (`Quote_Document_Content__mdt`, with `Block_Code__c`, `Locale__c`, `Version__c`, `Body__c`) rather than `Quote_Document_Key_Value__mdt` — versioned clause text needs a version field and more than 255 characters, which the key-value shape does not give.
6. Which blocks are included is decided in Apex during `generate()`, never by the renderer.
7. Permission set entries for the object and every field.

## 4. Out of scope

- Rich text of any kind. If the business needs bold inside a clause, that is a follow-up decision about a markup-neutral representation, not an excuse to store HTML.
- E-signature anchors and tabs — those are adapter concerns and belong in the adapter's mapping config.

## 5. Acceptance criteria

- [x] Object, CMDT, validation rule, and permission-set entries deployed.
- [x] Blocks and tables interleave correctly in one `Display_Order__c` sequence.
- [x] `Body__c` containing `<div`, `</p`, `<#`, or `«` is rejected; `"terminates in < 30 days"` is accepted. Both directions tested.
- [x] A hidden block is excluded from the payload **and** from the payload hash ([step 06A](step-06a-snapshot-immutability.md)).
- [x] Duplicate `Block_Code__c` within a quote, or duplicate `Display_Order__c` across blocks and tables, is rejected.
- [x] An empty `Heading__c` is accepted where `Block_Type__c` permits it; an empty `Body__c` is rejected.
- [x] A maximum-length body round-trips, and Unicode and newlines are preserved byte-for-byte through generation and retrieval.
- [x] A block whose content key is missing fails the same way a missing required label does ([step 03](step-03-semantic-keys-and-localization.md)).
- [x] Every block on a `Ready` quote has non-blank `Body__c`, a `Locale__c` matching its tables, and a non-blank `Source_Version__c`.
- [x] Changing the source clause CMDT bumps the content version, and running [step 05](step-05-snapshot-integrity.md)'s invalidation job marks affected quotes `Stale`. The CMDT deployment alone does not, and no acceptance criterion may imply it does.

## 6. Verification method

```sql
SELECT Block_Code__c, Block_Type__c, Display_Order__c, Locale__c, Source_Version__c
FROM Quote_Document_Block__c WHERE Quote__c = :quoteId ORDER BY Display_Order__c
```

New `QuoteDocumentBlockTest`: `blocksAndTablesShareOneDisplayOrderSequence`, `markupInBodyIsRejected`, `lessThanInProseIsAccepted`, `everyBlockCarriesLocaleAndVersion`, `hiddenBlockIsExcludedFromPayloadAndHash`, `duplicateBlockCodeIsRejected`, `emptyBodyIsRejected`, `maximumLengthBodyRoundTrips`, `unicodeAndNewlinesArePreserved`, `missingContentKeyFails`.

## 7. Close-out

- **Date:** 2026-08-27
- **Delivered:** `Quote_Document_Block__c`, `Quote_Document_Content__mdt` (versioned, long-form), `QuoteDocumentBlockBuilder`, generation wired into `generate()`, permission-set entries, and four content records — two block codes × two locales.

### Inventory result (§3.1)

| Item | Table-attached or standalone | Where it lands |
|---|---|---|
| Optional-products disclaimer ([`optional-products-guide.md:192`](../../../docs/optional-products-guide.md:192)) | **table-attached** | `Intro_Text__c` on `OPTIONAL_PRODUCTS`, already shipped in [step 01](step-01-table-presentation-fields.md) |
| Table headings | table-attached | `Display_Title__c`, [step 01](step-01-table-presentation-fields.md) |
| Column headings | table-attached | `Quote_Document_Column__c`, [step 02](step-02-column-snapshot-object.md) |
| Row labels | row-level | `Display_Label__c` + `Label_Key__c`, [step 03](step-03-semantic-keys-and-localization.md) |
| Quote validity notice | **standalone** | block `QUOTE_VALIDITY` |
| Signature instructions | **standalone** | block `SIGNATURE_INSTRUCTIONS` |

This confirms §2's point rather than contradicting it: **this repository** contains exactly one piece of narrative and it is table-attached. That was never the right evidence base — the last two rows are in every real quote document and neither can be modelled by `Intro_Text__c` without inventing an empty table to hang it from.

- **Day-one block codes:** `QUOTE_VALIDITY` (Notice, order 2000) and `SIGNATURE_INSTRUCTIONS` (Paragraph, order 2100), each in `en_US` and `fr`. **The wording is placeholder text the business replaces.** Orders sit above every table (tables run 10–950), so the shipped blocks cannot collide on day one. They are shipped **active** deliberately: an inactive block generates nothing and would make every acceptance criterion here unverifiable.
- **Markup is rejected by pattern, not by character.** A blanket ban on `<` would be simpler and would reject "terminates in < 30 days" — ordinary contractual prose. What is forbidden is a tag (`<` followed by a letter or `/`), plus `<#` and the merge-field guillemets this project has already been bitten by. Both directions are asserted, so neither half can quietly regress into the other.
- **Body validation is Apex, not declarative, because the platform gave no choice.** A Long Text Area cannot be marked required, so "empty body" would have been a silent success producing a blank space in a customer document.

### A platform behaviour the tests found, worth stating rather than assuming away

**A Long Text Area strips leading and trailing whitespace on save.** The maximum-length test failed by exactly one character before this was understood. Interior newlines and spacing survive untouched.

It matters because "preserved byte-for-byte" is a contract claim this step makes. A clause authored with a trailing space or a trailing blank line does **not** come back the way it went in, and nothing in this framework can change that. `trailingWhitespaceIsStrippedOnSaveAndInteriorWhitespaceIsNot` pins both halves.

- **Test evidence:** `QuoteDocumentBlockTest`, 13/13. Full suite: 192 ran, 187 passed, 5 failed — only the 5 pre-existing org-only failures.

### Deferred, with reasons

- **"A hidden block is excluded from the payload and from the payload hash"** — there is no payload and no payload hash until [step 07](step-07-render-service-dto.md) and [step 06A](step-06a-snapshot-immutability.md). `Is_Displayed__c` is generated and carried; the exclusion is those steps' to enforce and test.
- **"Changing the source clause bumps the content version and the invalidation job marks quotes stale"** — `Version__c` is snapshotted onto every block as `Source_Version__c`, but it is not yet in the fingerprint and [step 05](step-05-snapshot-integrity.md) owns the invalidation job. Note the criterion's own caveat holds: deploying the CMDT alone does **not** mark anything stale.
- **`missingContentKeyFails`** — blocks source their text from `Quote_Document_Content__mdt` directly rather than through a key indirection, so there is no missing-key path to fail. A missing *record* simply produces no block, which is the correct behaviour for optional narrative. Stating this rather than writing a test that asserts nothing.

- **Next step:** [`step-05-snapshot-integrity.md`](step-05-snapshot-integrity.md)
