# Step 01 — Table presentation fields

**Status: COMPLETE**
**Blocked by:** [step 00](step-00-audit-and-contract-principles.md), [step 01A](step-01a-extension-contracts.md)
**Blocks:** 02, 03, 06, 07

---

## 1. Goal

Every generated `Quote_Document_Table__c` carries its own printable title and its own visibility decision, so no renderer has to type a heading into a template or evaluate `count(...) > 0` to hide a section.

## 2. Why this step exists

Audit rows 1 and 5. The record's `Name` is `"Q-00063 - Family and Billing Summary"` — built for list views and searchability ([`QuoteDocumentGenerator.cls:403`](../../../force-app/main/default/classes/QuoteDocumentGenerator.cls:403)) and abbreviated to 80 characters. Printing it would put the quote number in the middle of the document. `Table_Name__c` on the CMTD holds the right string but never reaches the record.

## 3. Scope

1. Add to `Quote_Document_Table__c`:

   | Field | Type | Required before Ready | Notes |
   |---|---|---|---|
   | `Display_Title__c` | Text(255) | yes | The printable heading. |
   | `Display_Subtitle__c` | Text(255) | no | Only populated when a definition supplies one. |
   | `Intro_Text__c` | Long Text | no | Carries the optional-products disclaimer (audit row 6). |
   | `Footer_Text__c` | Long Text | no | |
   | `Is_Displayed__c` | Checkbox, default true | yes | False when the table generated but must not print. |
   | `Locale__c` | Text(10) | yes | Populated in step 03; add the field here so the schema settles once. |

2. Add matching optional fields to `Quote_Document_Table_Def__mdt`: `Display_Title__c`, `Display_Subtitle__c`, `Intro_Text__c`, `Footer_Text__c`. `Table_Name__c` stays as the admin-facing name; it is not the printable title, and conflating them is what step 09 has to explain.
3. Populate in `QuoteDocumentGenerator.newTable()`. **No fallback to `Table_Name__c`** — an active definition with no title fails config load, naming the definition. A fallback here is how half the tables end up printing an admin-facing name nobody reviewed ([`spec.md`](../spec.md) §4).
4. Set `Is_Displayed__c = false` when the table produced no qualifying source/detail lines, replacing the `count(...) > 0` XPath. Do not infer this from `Row_Count__c`: `QuoteDocumentRowBuilder` always emits a Grand Total row, so an otherwise empty table still has at least one row. Do not delete the table; its Grand Total and counts are evidence generation ran.
5. Populate `Intro_Text__c` on `OPTIONAL_PRODUCTS` with the disclaimer currently living only in Word.
6. Add every new field to `CPQ_Document_Totals.permissionset-meta.xml`.

## 4. Out of scope

- Column labels (step 02).
- Translating any of these strings (step 03) — English literals from the CMDT are correct output for this step.
- Changing what `Name` contains.

## 5. Acceptance criteria

- [x] Fields deployed and in the permission set.
- [x] Every table on a freshly generated quote has a non-blank `Display_Title__c` that does not contain the quote number.
- [x] A quote with no optional lines produces an `OPTIONAL_PRODUCTS` table with `Is_Displayed__c = false`, no qualifying Detail row, and a valid Grand Total row; no assertion expects `Row_Count__c = 0`.
- [x] A quote with optional lines produces the same table with `Is_Displayed__c = true`.
- [x] `Intro_Text__c` on that table matches the disclaimer text in [`optional-products-guide.md:192`](../../../docs/optional-products-guide.md:192).
- [x] Existing test classes still pass unchanged.

## 6. Verification method

```bash
sf project deploy start --source-dir force-app
sf apex run test --tests QuoteDocumentGeneratorTest --tests QuoteDocumentLifecycleTest --result-format human --wait 20
```

Then, against a regenerated quote:

```sql
SELECT Table_Code__c, Name, Display_Title__c, Is_Displayed__c, Row_Count__c
FROM Quote_Document_Table__c WHERE Quote__c = :quoteId ORDER BY Display_Order__c
```

Pass: `Display_Title__c` non-blank on every row, differs from `Name`, and the `Is_Displayed__c` flags match the two optional-lines cases above.

New Apex tests: `everyGeneratedTableHasAPrintableTitle`, `aTableWithNoCountedRowsIsNotDisplayed`.

## 7. Close-out

- **Date:** 2026-08-27
- **Delivered:** six fields on `Quote_Document_Table__c` (`Display_Title__c`, `Display_Subtitle__c`, `Intro_Text__c`, `Footer_Text__c`, `Is_Displayed__c`, `Locale__c`), four on `Quote_Document_Table_Def__mdt`, all six table fields added to `CPQ_Document_Totals`. Snapshotted in `newTable()`. All 16 definitions now carry a `Display_Title__c`, and `OPTIONAL_PRODUCTS` carries its disclaimer.
- **No fallback, as specified.** `validatePresentationConfig()` fails an active definition with no `Display_Title__c`, naming it. `Table_Name__c` stays the admin-facing name. A fallback would have surfaced in a customer's document rather than a deployment log, and in every table at once.
- **`Is_Displayed__c` keys off qualifying LINES, not Detail rows.** The obvious rule - no Detail rows means hide - is wrong: a summary table (`Show_Details__c = false`) never emits a Detail row even when it has plenty of data, so that rule would have hidden `CHARGE_TYPE_SUMMARY` and every table like it. `Row_Count__c` is wrong the other way, since the builder always emits a Grand Total. "Did any source line survive the filter" is what the `count(...) > 0` XPath was really asking.
- **A test premise that was wrong, and what it cost:** the first draft of `aTableWithNoQualifyingLinesIsNotDisplayed` assumed the fixture had no optional lines. It has one, so the test asserted `Is_Displayed__c = false` against a table that correctly displayed. The test now deletes the optional lines to create the empty case rather than assuming it. Worth recording because that assertion would have passed for the wrong reason had it been written a shade looser.
- **Hidden is not deleted.** A table with no qualifying lines is still generated, verified, and carries its Grand Total - absence of a record cannot be told apart from generation never having run.
- **Test evidence:** `QuoteDocumentPresentationTest`, 5/5. Full suite 146 local tests; the same 5 pre-existing org-only failures noted in [step 01A](step-01a-extension-contracts.md) §11 remain and are unrelated.
- **Locale__c** is deployed but unpopulated, as scoped - [step 03](step-03-semantic-keys-and-localization.md) fills it. The schema is settled so step 02 and 03 do not reshape this object twice.
- **Next step:** [`step-02-column-snapshot-object.md`](step-02-column-snapshot-object.md)
