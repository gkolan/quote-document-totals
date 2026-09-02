# Translated document content and labels

## Status and scope

**Repository status:** Locale selection, label dictionaries, content fallback rules, and `en_US`/`fr` examples ship.

**Org verification status:** Resolution behavior is tested. Each translation requires qualified review in the target org.

## Use case scenario

The same Quote document must be generated in another language without relying on the user who clicked the button or on hardcoded template text.

## What this produces

One complete saved result in one normalized language, with translated labels and content and unchanged financial values.

## Before you start

Choose the Quote field that stores the document language and obtain a complete reviewed translation dictionary.

**Stop here if** required keys are missing, the translator has not reviewed placeholders and punctuation, or the same saved result would mix languages.

## Terms in plain language

| Term                | Meaning                                                                       |
| ------------------- | ----------------------------------------------------------------------------- |
| Locale              | Language code such as `en_US`, `fr`, or `fr_FR`.                              |
| Default locale      | Language used when the configured Quote field is blank.                       |
| Label key           | Stable code such as `GRAND_TOTAL` whose value is translated.                  |
| Placeholder         | `{0}` or `{1}`, replaced with a value while preserving translated word order. |
| Exact/base fallback | `fr_FR` may use `fr`; `fr` never guesses a region.                            |

### How locale is selected

One generated saved result has exactly one locale. Generation selects it in this order:

1. the Quote field path configured by `DOCUMENT_CONFIG / LOCALE_FIELD_PATH` in `Quote_Document_Key_Value__mdt`;
2. `DOCUMENT_CONFIG / DEFAULT_LOCALE`, falling back to the stable repository default `en_US`.

The current Flow and Apex generation entry points do not expose a production locale override parameter. To choose per Quote, configure a Quote field path and populate that field.

The running user's locale is deliberately ignored so two users cannot generate different documents from the same Quote by accident.

## Configure in Salesforce

### Configure labels

1. In **Quote Document Key Value** Custom Metadata, create a category named `LABELS_<locale>`, for example `LABELS_fr`.
2. Add every label key the active definitions require, including `GRAND_TOTAL`, `SUBTOTAL`, `SECTION_TOTAL`, `GROUP_UNNAMED`, and `COL_LABEL`. Add `PARTITIONED_TITLE` when an active partitioned table uses it.
3. Translate the complete phrase. Preserve supported placeholders `{0}` and `{1}` where required; word order belongs to the translator.
4. Do not duplicate a key within one category. Generation rejects ambiguous dictionaries.

### Configure narrative content

Create matching **Quote Document Content** records for the locale. An exact locale match wins; a region-qualified locale such as `fr_FR` may fall back to base language `fr`. A base language never guesses a region.

Fallback applies to the complete set of Blocks, not one Block at a time. For example, if any active `fr_FR` Content record exists, generation uses the `fr_FR` set and does not fill its missing Blocks from `fr`. Create every required Block for `fr_FR`, or create none and use the complete reviewed `fr` set.

## Worked example

Generate the same Quote first with `en_US`, then `fr`. Amounts and row counts must be identical. English `Grand Total` becomes reviewed French `Total général`; no English label remains in the French result. The supplied `QUOTE_VALIDITY` and `SIGNATURE_INSTRUCTIONS` Blocks must also change to the exact French examples in [Document content blocks](34-document-content-blocks.md#example-2-supplied-french-blocks).

## Generate and verify

1. Set the Quote field configured by `LOCALE_FIELD_PATH`, or verify the intended organization default.
2. Select **Generate Document Tables**.
3. Confirm the Quote is `Ready` and every generated table and block carries the expected normalized locale.
4. Review headings, column labels, row labels, notices, punctuation, placeholders, dates, currency, and reading order with a qualified reviewer.
5. Generate the same Quote in a second locale and confirm the saved result is rebuilt with the new locale and change check rather than producing mixed-language output.

Unsupported locales and missing required keys stop generation (`LOCALE_UNSUPPORTED` or `LABEL_KEY_MISSING`). Salesforce does not silently switch to English.

## Troubleshooting

| Problem            | What it means                                                    | What to do                                                        |
| ------------------ | ---------------------------------------------------------------- | ----------------------------------------------------------------- |
| Unsupported locale | No complete dictionary is available.                             | Add and review the locale or choose a supported Quote value.      |
| Missing label key  | Active configuration requests an untranslated key.               | Add that key to the same language category.                       |
| Mixed language     | Template text or incomplete content bypasses saved translations. | Remove hardcoded wording and complete dictionary/content records. |
| Wrong language     | Locale field path or Quote value is wrong.                       | Correct DOCUMENT_CONFIG and regenerate.                           |

## Deactivate or roll back

Restore the prior Quote locale and generate again. Deactivate incomplete translated content and do not advertise a locale until its full dictionary passes. Never edit generated labels manually.

## Production checklist

- [ ] Quote locale field and default are documented.
- [ ] Every required label key is translated.
- [ ] All content blocks exist in the tested language.
- [ ] Qualified reviewer approved placeholders and wording.
- [ ] Row counts and financial values match across languages.
