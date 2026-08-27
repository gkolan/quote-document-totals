# Step 04 — Narrative blocks

**Status: PLANNED**
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

- [ ] Object, CMDT, validation rule, and permission-set entries deployed.
- [ ] Blocks and tables interleave correctly in one `Display_Order__c` sequence.
- [ ] `Body__c` containing `<div`, `</p`, `<#`, or `«` is rejected; `"terminates in < 30 days"` is accepted. Both directions tested.
- [ ] A hidden block is excluded from the payload **and** from the payload hash ([step 06A](step-06a-snapshot-immutability.md)).
- [ ] Duplicate `Block_Code__c` within a quote, or duplicate `Display_Order__c` across blocks and tables, is rejected.
- [ ] An empty `Heading__c` is accepted where `Block_Type__c` permits it; an empty `Body__c` is rejected.
- [ ] A maximum-length body round-trips, and Unicode and newlines are preserved byte-for-byte through generation and retrieval.
- [ ] A block whose content key is missing fails the same way a missing required label does ([step 03](step-03-semantic-keys-and-localization.md)).
- [ ] Every block on a `Ready` quote has non-blank `Body__c`, a `Locale__c` matching its tables, and a non-blank `Source_Version__c`.
- [ ] Changing the source clause CMDT bumps the content version, and running [step 05](step-05-snapshot-integrity.md)'s invalidation job marks affected quotes `Stale`. The CMDT deployment alone does not, and no acceptance criterion may imply it does.

## 6. Verification method

```sql
SELECT Block_Code__c, Block_Type__c, Display_Order__c, Locale__c, Source_Version__c
FROM Quote_Document_Block__c WHERE Quote__c = :quoteId ORDER BY Display_Order__c
```

New `QuoteDocumentBlockTest`: `blocksAndTablesShareOneDisplayOrderSequence`, `markupInBodyIsRejected`, `lessThanInProseIsAccepted`, `everyBlockCarriesLocaleAndVersion`, `hiddenBlockIsExcludedFromPayloadAndHash`, `duplicateBlockCodeIsRejected`, `emptyBodyIsRejected`, `maximumLengthBodyRoundTrips`, `unicodeAndNewlinesArePreserved`, `missingContentKeyFails`.

## 7. Close-out

- **Date:**
- **Inventory result:** *(each item, and whether it is table-attached or standalone)*
- **Day-one block codes:**
- **Next step:** [`step-05-snapshot-integrity.md`](step-05-snapshot-integrity.md)
