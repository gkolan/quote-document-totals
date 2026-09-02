# Optional Products

## Status and scope

**Repository status:** The active `OPTIONAL_PRODUCTS` definition, Product Family grouping, customer-facing disclaimer, the **Quote Document - Optional Products** report, and `scripts/apex/optional-products-example.apex` ship in the repository.

**Org verification status:** Repository tests cover optional-only filtering. Target-org pricing, wording approval, and output are not verified here.

## Use case scenario

A Quote offers additional products that are priced but are not included in the amount the customer is agreeing to pay.

## What this produces

Salesforce creates one `Quote_Document_Table__c` record for this view and `Quote_Document_Row__c` records for the displayed lines. The same saved result can be viewed in Salesforce Reports and passed to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Confirm the `CPQ_Document_Totals` permission set is assigned.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Mark each offered add-on as Optional in the CPQ Quote Line Editor.

**Stop here if** optional items are included in the Quote's committed total, the disclaimer has not been approved, or the Quote is not calculated.

## Terms in plain language

| Setting             | Meaning                                                              |
| ------------------- | -------------------------------------------------------------------- |
| Optional Quote Line | A priced offer that the customer has not committed to buy.           |
| `OPTIONAL_ONLY`     | Include only lines whose CPQ Optional checkbox is selected.          |
| Intro Text          | The saved customer-facing disclaimer printed with this table.        |
| Optional total      | Information only; it must not be added to the committed Quote total. |
| Generated rows      | The saved values used by reports and the final document.             |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Open **Optional Products**. Enter or confirm these values:

| Field         | Value                                                                                                                                                                                                        |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Active        | `Selected`                                                                                                                                                                                                   |
| Table Code    | `OPTIONAL_PRODUCTS`                                                                                                                                                                                          |
| Display Title | `Optional Products`                                                                                                                                                                                          |
| Measure Set   | `PRICE_WATERFALL`                                                                                                                                                                                            |
| Amount Basis  | `Final Value`                                                                                                                                                                                                |
| Line Filter   | `OPTIONAL_ONLY`                                                                                                                                                                                              |
| Show Details  | `Selected`                                                                                                                                                                                                   |
| Intro Text    | `These products are optional and are NOT included in the quote's committed total. The amounts below are provided for information only; nothing in this table has been ordered or priced into the agreement.` |

4. Save the table definition.
5. Return to **Custom Metadata Types**, find **Quote Document Grouping**, and select **Manage Records**.
6. Open **Optional Products - PRODUCT_FAMILY** and confirm Dimension `PRODUCT_FAMILY`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Select **Active**, save, and generate document data for a representative sandbox Quote. If the result is wrong, clear **Active** before making corrections. Leave it selected for general use only after the rows and totals are correct.

## Worked example

```text
Optional Products
Premium Support            $2,500
Additional Storage         $1,200
Optional total             $3,700
```

Use optional Premium Support at $2,500 and optional Additional Storage at $1,200. The informational total is $3,700. Neither amount may increase the committed Quote total.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the table.
3. Its Quote Document Rows contain the displayed lines and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Optional Products** and filter it to the test Quote.
5. The final document shows the same saved values; the document template does not recalculate them.

## Troubleshooting

| Problem                           | What it means                                                           | What to do                                                                      |
| --------------------------------- | ----------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| A committed product appears       | Its Optional checkbox is selected incorrectly.                          | Correct the Quote Line, calculate, and generate again.                          |
| An offered add-on is missing      | It is not marked Optional.                                              | Select Optional, calculate, and generate again.                                 |
| Optional total affects amount due | A payable table or template is counting optional rows.                  | Verify the main table excludes optional lines and remove template calculations. |
| Disclaimer is absent              | Intro Text was cleared or the document ignores saved presentation text. | Restore the exact Intro Text and correct the document mapping.                  |
| Status is Failed                  | Generation rejected data or configuration.                              | Read **Document Data Error** and correct the named cause.                       |

## Deactivate or roll back

Clear **Active** on **Optional Products**, save, and generate again. Do not delete generated rows manually. Restore the exact definition and disclaimer to reactivate.

## Production checklist

- [ ] Every offered add-on is marked Optional.
- [ ] No committed line appears in this table.
- [ ] Optional amounts do not affect the committed total.
- [ ] The exact disclaimer is visible.
- [ ] The named report and document preview match the generated rows.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source Quote data, and generate again.
