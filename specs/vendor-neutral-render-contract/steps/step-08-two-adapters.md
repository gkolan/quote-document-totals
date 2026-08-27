# Step 08 — Two adapters (JSON, HTML)

**Status: PLANNED**
**Blocked by:** [step 07](step-07-render-service-dto.md)
**Blocks:** 09

---

## 1. Goal

Prove the claim. Two renderers consume the same payload and produce the same document, and adding the second one changes nothing in the generation layer.

## 2. Why this step exists

Every decoupling spec sounds finished at step 07 and is discovered to be unfinished the first time someone writes a real second renderer and finds one value they still have to compute. Two adapters, written against the payload only, is the cheapest way to find that gap now instead of during a vendor migration.

## 3. Scope

1. `QuoteDocumentJsonAdapter.render(Id quoteId)` returning a JSON string.
2. `QuoteDocumentHtmlAdapter.render(Id quoteId)` returning an HTML string — a plain table per section, headings from `Column.label`, values formatted with `locale` and `currencyIsoCode`.
3. Both call `QuoteDocumentRenderService.getPayload(quoteId, expectedRequestId, expectedFingerprint)` and nothing else, with the expectations taken from a preceding generate-or-reuse ([step 01A](step-01a-extension-contracts.md) §6b). No SOQL, no CMDT reads, no arithmetic beyond formatting a number for display.
4. Production styling is explicitly not required. These prove structure, not appearance.
5. Neither adapter may be referenced by `QuoteDocumentGenerator`, `QuoteDocumentRowBuilder`, or any CMDT — dependency points one way only, from adapter to service.
6. DocuSign CLM is the third adapter and is rebuilt against this contract — launched from a Salesforce action that performs generate-or-reuse and binds the published snapshot ([`spec.md`](../spec.md) §4.1). A CLM Data Source querying the objects directly is not a conforming renderer and is not carried forward.

## 3a. Canonical semantic comparison

JSON and HTML are never byte-equivalent, so "the same document" needs a definition or the equivalence test becomes a matter of opinion. Two outputs are equivalent when, after reducing each to the canonical form below, the forms are identical:

| Aspect | Rule |
|---|---|
| Sections and columns | same codes, same order |
| Hidden elements | excluded from both — a hidden row appearing in one output is a failure, not a formatting difference |
| Numbers | compared as `Decimal` at the scale the payload carries, before any locale formatting. `0` and `null` are **distinct**: a zero prints, a null is an empty cell |
| Dates | `Date` and `DateTime` compared as typed values, never as rendered strings; the distinction is preserved, not collapsed |
| Currency | the ISO code is compared; the symbol, separator, and placement are renderer choices and are excluded |
| Booleans | compared as `true`/`false`, not as "Yes"/"✓" |
| Text | trailing and leading whitespace trimmed, internal runs of whitespace collapsed, newlines normalised to `\n` |
| Escaping | HTML escaping is undone before comparison; `&amp;` and `&` are the same value |
| Locale formatting | **excluded** from equivalence, and asserted separately: each adapter formats from the same typed value plus the payload's locale |

**The equivalence fixture must contain every distinction the table draws**, or the table is prose rather than verified behaviour. One fixture quote carrying: a null and a zero in the same column; a `Date` and a `DateTime`; a negative Decimal; a value whose scale matters; a non-default currency ISO code; `true` and `false`; `&`, `<`, `>`, quotes, and Unicode in text; leading and trailing whitespace; multiple internal spaces; an embedded newline; a hidden row, a hidden column, a hidden table, and a hidden block; an empty optional title and subtitle; every `Block_Type__c`; and every supported column `Data_Type__c`.

The canonicalizer lives in the test, not in the adapters. If an adapter needs to produce the canonical form itself, it has taken on logic the contract says belongs to the payload.

## 4. Out of scope

- A renderer inheritance hierarchy. `DocumentPayload` is the contract; an interface can be added when runtime polymorphism is a demonstrated requirement. This does not affect the generation contributor interfaces in Step 01A.
- PDF generation, file storage, ContentVersion, emailing.
- Making either adapter production-grade.

## 5. Acceptance criteria

- [ ] Both adapters produce output from a `Ready` quote with no exception.
- [ ] **Semantic equivalence test,** against the canonical comparison in §3a — not "looks the same".
- [ ] **Core-diff proof** per [`spec.md`](../spec.md) §9: no diff in the core class list, no modification to an existing shipped CMDT record, and a stated dependency direction. A new adapter genuinely needs no metadata at all, so for *this* step the diff outside the adapter class should be empty — that is not the standard applied to steps that add tables or columns.
- [ ] Neither adapter contains a SOQL query, a CMDT read, or a total calculation.
- [ ] Neither adapter needs a locale lookup or a translation — every string it prints came from the payload.

## 6. Verification method

```bash
sf apex run test --class-names QuoteDocumentAdapterTest --result-format human --wait 20
```

`QuoteDocumentAdapterTest`: `bothAdaptersProduceTheSameSemanticDocument` (over the full fixture above), `nullAndZeroAreDistinguished`, `dateAndDateTimeAreNotCollapsed`, `hiddenElementsAreAbsentFromBoth`, `escapedAndUnescapedTextCompareEqual`, `adaptersContainNoQueries`, `adaptersPerformNoCalculationOrTranslation`, `adapterThrowLeavesTheSnapshotUnchanged` (the testable half of the renderer-outage drill).

Core-diff proof, run on the adapter commit:

```bash
git show --stat HEAD -- force-app/main/default/classes force-app/main/default/objects force-app/main/default/customMetadata force-app/main/default/permissionsets
```

For an adapter, only the two new adapter classes and their tests may appear. Per [`spec.md`](../spec.md) §9 the reviewer also states the dependency direction — the stat alone can be satisfied by moving logic into a Flow or a formula field. Record the commit SHA in §7 — it is the evidence for the definition of done in [`spec.md`](../spec.md) §1.

## 7. Close-out

- **Date:**
- **Adapter commit SHA:**
- **Anything the adapters had to compute themselves:** *(must be empty — a non-empty answer sends work back to steps 01–03)*
- **Next step:** [`step-09-docs-and-closeout.md`](step-09-docs-and-closeout.md)
