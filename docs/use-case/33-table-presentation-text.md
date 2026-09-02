# Table titles, subtitles, introduction text, and footer text

## Status and scope

**Repository status:** All four presentation fields ship on the table definition and generated table.

**Org verification status:** Copying and change detection are tested. Customer wording and target document output require org approval.

## Use case scenario

An administrator needs to change the customer-facing words around a generated table without editing Apex or placing permanent wording inside a document template.

## What this produces

One saved table heading, optional second heading, introduction, and footer copied into the generated result used by every document output.

## Before you start

Obtain approved wording and identify the exact table definition it belongs to.

**Stop here if** the wording is a standalone clause, signature instruction, or notice between tables; use a Document Content record instead.

## Terms in plain language

| Term          | Meaning                                                             |
| ------------- | ------------------------------------------------------------------- |
| Display Title | Required customer-facing table heading.                             |
| Subtitle      | Optional second heading line.                                       |
| Intro Text    | Paragraph immediately before one table.                             |
| Footer Text   | Paragraph immediately after one table.                              |
| Saved result  | Copy tied to one generation; later wording edits do not rewrite it. |

### Choose the correct field

| Printed content                       | Configuration field   | Scope                               |
| ------------------------------------- | --------------------- | ----------------------------------- |
| Main table heading                    | `Display_Title__c`    | Required on every active definition |
| Optional second heading line          | `Display_Subtitle__c` | One table                           |
| Paragraph immediately above the table | `Intro_Text__c`       | One table                           |
| Paragraph immediately below the table | `Footer_Text__c`      | One table                           |

`Table_Name__c` is an administrator-facing name and is never a fallback for the printable title.

## Configure in Salesforce

1. Open **Setup → Custom Metadata Types → Quote Document Table Definition → Manage Records**.
2. Open the definition.
3. Enter a customer-approved **Display Title**. An active definition with a blank title fails configuration loading.
4. Add the optional subtitle, introduction, and footer only when they belong to this table.
5. Save and generate from a calculated sandbox Quote.
6. Review the generated **Quote Document Table** record. The four values are copied into the saved result so later setup edits cannot silently rewrite an already-reviewed result.

### When not to use these fields

Use `Quote_Document_Content__mdt` for standalone notices, terms, clauses, signature instructions, or headings between tables. Do not invent an empty table merely to carry document-level prose.

## Worked example

Set Display Title to `Subscription Summary`, Subtitle to `Three-year term`, Intro Text to `The amounts below exclude optional products.`, and Footer Text to `Taxes are not included.` Generate once, then change the subtitle to `Thirty-six-month term` and generate again. Only the current result may show the changed subtitle.

## Generate and verify

- The Quote is `Ready` after generation.
- The generated table contains the expected `Display_Title__c`, `Display_Subtitle__c`, `Intro_Text__c`, and `Footer_Text__c` values.
- No customer-facing heading is typed only into the template.
- The document tool prints only records whose generated **Is Displayed** value is selected. Template conditions may control styling, but they must not decide which saved content exists.
- After changing wording, generation creates a current saved result that matches the new configuration.

## Troubleshooting

| Problem                          | What it means                                           | What to do                                                                              |
| -------------------------------- | ------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| Heading is blank                 | Display Title is missing.                               | Obtain the customer-facing title from the business owner, enter it, and generate again. |
| Old wording remains              | Quote was not regenerated or document reads stale data. | Generate and confirm Quote status is Ready.                                             |
| Clause appears under wrong table | Table fields were used for document-level prose.        | Move it to a Document Content record.                                                   |
| Template wording differs         | Text is hardcoded in the template.                      | Remove duplicate template text and map saved fields.                                    |

## Deactivate or roll back

Restore the previous approved text and generate again. To remove the entire table, clear its **Active** value; do not edit generated records manually.

## Production checklist

- [ ] Display Title is present and approved.
- [ ] Optional text belongs to this table.
- [ ] Generated table stores all four expected values.
- [ ] Regeneration reflects wording changes.
- [ ] No duplicate permanent wording exists only in the template.
