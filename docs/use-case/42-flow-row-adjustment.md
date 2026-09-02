# Add a Flow-based row adjustment

## Status and scope

**Repository status:** Ready to configure. The active autolaunched Flow `QuoteDocumentSampleFlowContributor`, the Flow bridge, automated tests, and the inactive `FLOW_CONTRIBUTOR_EXAMPLE` table definition ship in this repository.

**Org verification status:** Not verified in your Salesforce org. Complete the test generation in this guide before activating the example or connecting a copied Flow to a production table.

This is advanced Salesforce configuration. It is suitable only for someone who can build and test an autolaunched Flow that works with a record collection. A Flow failure stops the entire document-generation attempt.

## Use case scenario

The generated rows need a small adjustment that normal table settings cannot provide. For example, the business wants to rename the Grand Total row and add a note without writing Apex.

## What this produces

The shipped example makes two visible changes after the standard rows have been calculated:

- It changes the Grand Total label to **Total Due**.
- It adds a note that says **Prices exclude applicable taxes.**

The note is displayed but does not change a subtotal or grand total.

## Before you start

Confirm all of the following:

- The Quote Document Totals metadata and Apex in this repository have been deployed.
- You can open **Setup**, **Flows**, and **Custom Metadata Types**.
- You can create a test Quote with at least one Quote Line.
- You understand how to create Flow variables and Assignment, Loop, and Decision elements.
- You will test with the inactive example before connecting a Flow to a production table.

**Stop here if** you have not built an autolaunched Flow with record variables before. Ask an experienced Salesforce administrator or developer to own the Flow build and review. You can still use the verification and rollback sections to check their work.

## Terms in plain language

| Term                | Meaning in this guide                                                                                                       |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| Autolaunched Flow   | A Flow that runs in the background without a screen. Document generation starts it.                                         |
| Row collection      | The complete list of `Quote Document Row` records produced for one table.                                                   |
| Input variable      | Information document generation passes into the Flow.                                                                       |
| Output variable     | Information the Flow passes back. The `rows` collection is both an input and an output.                                     |
| Row customizer Flow | The Flow API name saved on a table definition so it runs after the normal rows are built.                                   |
| Flow version        | A text value on the table definition that identifies the current Flow behavior. Increase it when the Flow's result changes. |
| Cache policy        | The rule that decides whether a previously generated result can be reused. `STANDARD` is correct for the shipped example.   |

## Configure in Salesforce

### 1. Test the shipped example first

1. In **Setup**, open **Custom Metadata Types**.
2. Find **Quote Document Table Definition** and select **Manage Records**.
3. Open **Flow Contributor Example**. Its table code is `FLOW_CONTRIBUTOR_EXAMPLE`.
4. Confirm these values before making a change:

   | Field                       | Required value                       |
   | --------------------------- | ------------------------------------ |
   | Amount Basis                | `Final Value`                        |
   | Line Filter                 | `ALL`                                |
   | Measure Set                 | `PRICE_WATERFALL`                    |
   | Show Details                | Selected                             |
   | Show Section Totals         | Not selected                         |
   | Row Customizer Flow         | `QuoteDocumentSampleFlowContributor` |
   | Row Customizer Flow Version | `1`                                  |
   | Cache Policy                | `STANDARD`                           |
   | Active                      | Not selected                         |

5. Select **Edit**, select **Active**, and save. Leave every other value unchanged for the first test.

### 2. Use the required Flow variables

A copied or new Flow must be **Autolaunched Flow (No Trigger)** and must use these exact API names and settings. Capitalization matters.

| API name          | Data type         | Record object           | Allow input | Allow output |
| ----------------- | ----------------- | ----------------------- | ----------- | ------------ |
| `rows`            | Record collection | `Quote_Document_Row__c` | Yes         | Yes          |
| `quoteId`         | Text              | Not applicable          | Yes         | No           |
| `tableCode`       | Text              | Not applicable          | Yes         | No           |
| `locale`          | Text              | Not applicable          | Yes         | No           |
| `currencyIsoCode` | Text              | Not applicable          | Yes         | No           |

Create two additional Flow resources for the pattern used by the sample:

| API name  | Data type | Record object           | Collection |
| --------- | --------- | ----------------------- | ---------- |
| `outRows` | Record    | `Quote_Document_Row__c` | Yes        |
| `noteRow` | Record    | `Quote_Document_Row__c` | No         |

### 3. Copy the safe row-handling pattern

1. Loop over `rows`.
2. Make any change to the current item from the loop.
3. Add the current item to `outRows`, including rows that were not changed.
4. After the loop, add any new rows to `outRows`.
5. Assign the complete `outRows` collection back to `rows`.
6. Save and activate the Flow.

The current item in a Flow loop is a copy. If the Flow changes that item but does not collect it into `outRows`, the change is lost. If the Flow returns only changed rows, all omitted document rows are removed.

### 4. Connect a copied Flow to a table

1. In **Setup**, open **Custom Metadata Types**.
2. Find **Quote Document Table Definition** and select **Manage Records**.
3. Open the table that should use the adjustment and select **Edit**.
4. Set **Row Customizer Flow** to the Flow's API name, not its displayed label. Do not include a version number.
5. Set **Row Customizer Flow Version** to `1` for the first release.
6. Set **Cache Policy** to `STANDARD` unless a reviewed design specifically requires another shipped policy.
7. Save the table definition.

Do not place both a Row Customizer Flow and a registered Apex row customizer on the same table unless the combined order and totals have been deliberately designed and tested.

## Worked example

Assume a Quote produces two Detail rows and one Grand Total row. When `FLOW_CONTRIBUTOR_EXAMPLE` runs, the shipped Flow:

1. keeps every original row;
2. finds the row whose Row Type is `Grand Total` and changes its Display Label to `Total Due`; and
3. appends this row:

| Field                  | Example result                     |
| ---------------------- | ---------------------------------- |
| Row Type               | `Note`                             |
| Row Key                | `FLOW_SAMPLE_NOTE`                 |
| Display Label          | `Prices exclude applicable taxes.` |
| Group Level            | `0`                                |
| Display Order          | `99000`                            |
| Is Displayed           | Selected                           |
| Include in Subtotal    | Not selected                       |
| Include in Grand Total | Not selected                       |

Because both inclusion fields are clear, the note does not change money values.

## Generate and verify

1. Open a test Quote that has at least one Quote Line.
2. Select **Generate Document Tables**.
3. Wait until **Document Data Status** is `Ready`.
4. Open the related **Quote Document Tables** list and select **Flow Contributor Example**.
5. Open its related **Quote Document Rows**.
6. Confirm the Grand Total row displays `Total Due`.
7. Confirm one row has Row Key `FLOW_SAMPLE_NOTE` and the expected note text.
8. Confirm the note's two inclusion fields are not selected.
9. Compare the Grand Total amount with the Quote total. The text changes must not change the amount.
10. Generate the same Quote again. Confirm the attempt succeeds and the note appears only once in the current table result.

Do not connect the Flow to a production table until every check passes.

## Troubleshooting

| Problem                                          | What it means                                                                                                 | What to do                                                                                                                                    |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Generation says the Flow cannot be found         | The saved API name does not match an active autolaunched Flow.                                                | Open the Flow in Setup, copy its **API Name**, activate it, and save that exact name in **Row Customizer Flow**.                              |
| Generation reports a missing or invalid variable | A required variable name, type, input setting, or output setting differs from this guide.                     | Compare all five variables with the table in this guide. Pay attention to capitalization and to `rows` being both input and output.           |
| Changed labels do not appear                     | The loop item was changed but not returned in the output collection.                                          | Add every loop item to `outRows`, then assign `outRows` back to `rows` after the loop.                                                        |
| Standard rows disappear                          | The Flow returned only new or changed rows.                                                                   | Rebuild `outRows` from every original row, add new rows, and return the complete collection.                                                  |
| Generation fails after the Flow was edited       | The Flow returned an invalid row, duplicate row key, duplicate display order, or totals that no longer agree. | Open the generation error, undo the last Flow change, and retest one change at a time. New informational rows must not be included in totals. |
| Old output is reused after a Flow change         | The table still identifies the old Flow behavior.                                                             | Increase **Row Customizer Flow Version**, save, run the invalidation batch described below, and generate again.                               |

## Deactivate or roll back

To stop using the shipped example, clear **Active** on `FLOW_CONTRIBUTOR_EXAMPLE`.

To remove a Flow adjustment from another table:

1. Edit the table definition.
2. Clear **Row Customizer Flow**.
3. Increase **Row Customizer Flow Version** from its current whole number, such as `1`, to the next whole number, such as `2`.
4. Save.
5. Ask a Salesforce developer or administrator with Execute Anonymous access to run:

   ```apex
   Database.executeBatch(new QuoteDocumentInvalidationJob(), 200);
   ```

6. Generate an affected test Quote again and confirm the standard rows return.

Do not delete Quote Document Table or Row records by hand. The generation process owns those records.

## Production checklist

- [ ] The Flow is autolaunched and active.
- [ ] All five Flow variables have the exact API names, types, and input/output settings.
- [ ] Every original row is collected and returned.
- [ ] Every new row has a unique Row Key and Display Order.
- [ ] Informational rows are excluded from subtotals and grand totals.
- [ ] The table definition uses the Flow API name.
- [ ] The Flow version identifies the behavior being released.
- [ ] A test Quote generated successfully twice.
- [ ] The displayed rows and Grand Total were checked.
- [ ] The rollback steps were tested outside production.
