# Step 03 — Semantic keys and central localization

**Status: COMPLETE**
**Blocked by:** [step 02](step-02-column-snapshot-object.md)
**Blocks:** 05, 06, 07

---

## 1. Goal

Every printable string on a generated record is resolved once, centrally, from a semantic key against a locale dictionary — including the strings Apex builds today.

## 2. Why this step exists

Audit rows 7 and 8. The template is not the only place English is hardcoded: [`QuoteDocumentRowBuilder.cls:228`](../../../force-app/main/default/classes/QuoteDocumentRowBuilder.cls:228) concatenates `g.value + ' Subtotal'`, line 283 constructs a charge sentence, line 298 emits `Total`, and line 328 substitutes `'(unnamed)'`. Swapping the renderer would not fix any of those. Localization must be a generation stage, not an optional per-table customizer. The current inventory has 15 definitions, seven active, and only four customizer codes; hardcoding a denominator here would become stale again.

## 3. Scope

1. **Key catalogue.** Semantic keys only: `GRAND_TOTAL`, `SUBTOTAL`, `SECTION_TOTAL`, `GROUP_UNNAMED`, `COL_NET_CHANGE`, `TERMS_STANDARD`. An English phrase is never its own key.
2. **Dictionary.** Reuse [`QuoteDocumentKeyValueMap.get(category)`](../../../force-app/main/default/classes/QuoteDocumentKeyValueMap.cls) with `Category__c = 'LABELS_en_US'`, `'LABELS_fr'`, and so on. No new CMDT type — the existing one is exactly a keyed dictionary, and adding a second one to hold the same shape is the kind of duplication step 09 would have to explain away. Revisit only if long-form versioned clause text lands (step 04), which has different needs (length, versioning, headings).
3. **Resolver.** New `QuoteDocumentLabels`:
   - `QuoteDocumentLabels.forLocale(String locale)` loads one category once per transaction and caches it.
   - `resolve(String key)` — required text. Missing key throws; generation fails.
   - `resolve(String key, String fallback)` — optional text.
   - `format(String key, List<String> args)` for `'{0} Subtotal'`-shaped patterns, so word order is the translator's decision, not Apex's.
4. **Locale resolution,** in this order: explicit locale on a versioned generation request → configured schema-validated locale field path on Quote/Account → org default. Do not add overloaded methods for every caller. Stamp the winner on the Quote-level snapshot identity and each generated table. One locale per generated snapshot; a mixed-locale document is not supported in v1.
4a. **Argument and placeholder rules.** Two explicit fields (`Label_Arg_1__c`, `Label_Arg_2__c`) need stated semantics or every translator invents their own:

   - a template referencing an argument index that was not supplied fails `LABEL_ARGUMENT_MISSING`, naming key and index; `{2}` or higher is unsupported and fails at dictionary load, not at render;
   - a template supplied *more* arguments than it references is fine — translators reorder and drop by design;
   - a **required** argument resolving to null fails; it never renders as the literal `null` or as an empty gap;
   - argument values are substituted **literally**. `{`, `}`, apostrophe, ampersand, Unicode, and newlines pass through untouched, and a product name that happens to look like a semantic key is never re-resolved as one — substitution runs once, not recursively;
   - locale tags are normalised once, on the way in: case-insensitive, `fr` and `fr_FR` resolved by a documented rule, and an unsupported variant failing rather than silently matching a near neighbour.

5. **Duplicate keys fail.** [`QuoteDocumentKeyValueMap`](../../../force-app/main/default/classes/QuoteDocumentKeyValueMap.cls) resolves duplicates as "first row wins, in query order" — correct for a rate table, wrong for document labels, where it means the printed wording depends on undefined query order. Label categories are loaded through a strict path that fails on a duplicate key within one category, naming both records.

6. **Fallback policy,** per the step 00 decision, implemented as one CMDT-configurable value, not scattered `if` statements. Required text missing → fail generation with the key named. Silent blanking is never allowed.
7. **Route every construction site through the resolver:** subtotal, section-total, and grand-total labels in `QuoteDocumentRowBuilder`, `'(unnamed)'`, column labels, titles, and narrative text. The composite separator is presentation configuration and must also be locale/config resolved if it is printable; it is not necessarily a translatable word.

## 4. Out of scope

- Authoring real translations. One non-English category with a handful of keys is enough to prove the mechanism; the business supplies the rest.
- Localizing data values (product names, group values) — those come from CPQ records and are translated there, if at all.
- Number and currency *formatting*, which is the renderer's job. The contract passes typed values plus a locale; it does not pass pre-formatted currency strings.

## 5. Acceptance criteria

- [x] No `Display_Label__c`, `Display_Title__c`, or column label is produced by string concatenation outside `QuoteDocumentLabels`.
- [x] `grep -rn "' Subtotal'\|(unnamed)" force-app/main/default/classes/*.cls` returns nothing outside `QuoteDocumentLabels` and its test.
- [x] Generating with `LABELS_fr` present produces French subtotal labels and French column headings on every table, including tables with no row customizer.
- [x] A missing *required* key fails generation with a message naming the key and the locale.
- [x] A missing *optional* key follows the configured fallback and never blanks.
- [x] An unsupported locale fails generation rather than falling through to English by accident.
- [x] `Locale__c` is populated on every generated table.

## 6. Verification method

```bash
sf apex run test --class-names QuoteDocumentLabelsTest --class-names QuoteDocumentGeneratorTest --result-format human --wait 20
```

New `QuoteDocumentLabelsTest`: `everyGeneratedStringResolvesFromTheDictionary`, `missingRequiredKeyFailsGeneration`, `missingOptionalKeyUsesConfiguredFallback`, `unsupportedLocaleFailsGeneration`, `localizationAppliesToTablesWithNoRowCustomizer`, `templateWithZeroOneAndTwoArguments`, `unsupportedArgumentIndexFailsAtDictionaryLoad`, `missingRequiredArgumentFails`, `argumentContainingBracesApostropheAmpersandUnicodeAndNewlineIsLiteral`, `argumentIsNeverReResolvedAsAKey`, `localeTagNormalisation`, `duplicateKeyInOneCategoryFails`.

Manual check on a regenerated quote:

```sql
SELECT Table_Code__c, Locale__c, Display_Title__c FROM Quote_Document_Table__c WHERE Quote__c = :quoteId
```

## 7. Close-out

- **Date:** 2026-08-27
- **Delivered:** `QuoteDocumentLabels` (strict loader, resolver, formatter), `QuoteDocumentLocale` (resolution order), `Label_Key__c` / `Label_Arg_1__c` / `Label_Arg_2__c` on the row, `Locale__c` populated on every table, and two dictionary categories — `LABELS_en_US` and `LABELS_fr`.
- **Acceptance grep is clean.** `grep -rn "' Subtotal'\|(unnamed)" force-app/main/default/classes/*.cls` returns nothing outside `QuoteDocumentLabels` and its test.
- **The grep found a construction site the audit did not name.** [`QuoteDocumentIndustryRowCustomizer.cls:149`](../../../force-app/main/default/classes/QuoteDocumentIndustryRowCustomizer.cls:149) concatenated `bucket.industryName + ' Subtotal'`. Routing only the four sites §2 lists would have left the seam quietly reintroducing exactly the hardcoded English this step removes from core. `QuoteDocumentRowCustomizerContext` now carries `labels`, so **contributors are held to the same rule as core** — which is the more important outcome than the single line fixed.
- **`'(unnamed)'` is gone rather than relocated.** It lived in `defaultRow()`, the one place a translator could never reach and no test would look. Blank group values now resolve `GROUP_UNNAMED` from the dictionary at the call site, and `defaultRow()` **fails loudly** on a blank label instead of inventing wording. `Display_Label__c` is a required field, so the alternative — passing null through — would have been a DML error with no explanation.
- **Word order belongs to the dictionary.** `'{0} Subtotal'` in English, `'Sous-total {0}'` in French. A concatenation in Apex cannot express that difference, which is the whole reason this is a template rather than a `+`. Pinned by `theDeployedEnglishAndFrenchDictionariesLoad`.
- **Substitution is literal and runs exactly once.** Split-and-join rather than `replace()`, so a product named `Widget {1}` or literally `GRAND_TOTAL` prints as itself. Re-resolving substituted values is how a customer's product name silently becomes a total label. Braces, apostrophes, ampersands, Unicode and newlines all pass through untouched, each asserted.
- **Duplicate keys fail, unlike `QuoteDocumentKeyValueMap`.** Its "first row wins, in query order" policy is right for a rate table and unacceptable here — it would make the printed wording of a customer document depend on an order the platform does not guarantee. Labels load through a strict path instead. The existing class is untouched; its policy is correct for what it was built for.
- **`{2}` and higher fail at dictionary LOAD, not at render**, so a translator finds out on deployment rather than when the one quote that exercises that table reaches a customer.
- **An unsupported locale fails.** Falling through to English by accident is the one outcome nobody notices in testing and everybody notices in a signed document. A region-qualified tag falls back to its base language; a base language never expands to a region, so `fr` cannot silently pick up `LABELS_fr_CA`.
- **Test evidence:** `QuoteDocumentLabelsTest`, 18/18. Full suite 179 local tests, 97% — only the 5 pre-existing org-only failures.

### One deviation from §5 worth stating plainly

`duplicateKeyInOneCategoryFails` asserts the strict loader's behaviour rather than deploying a deliberately duplicated metadata record. A real duplicate would break every other test in the org, since the dictionary loads on any generation. The throw path is implemented and named; it is not exercised by fixture, and calling that a passing test without saying so would be dishonest.

- **Next step:** [`step-04-narrative-blocks.md`](step-04-narrative-blocks.md)
