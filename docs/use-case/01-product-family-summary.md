# Product Family Summary

## Status and scope

**Repository status:** The active `PRODUCT_FAMILY_SUMMARY` table definition, its Product Family grouping, four column definitions, the **Quote Document - Product Family Summary** report, and `scripts/apex/product-family-summary-example.apex` ship in this repository.

**Org verification status:** Repository tests cover the table behavior. This guide does not claim that the metadata has been deployed or run in your Salesforce org.

Use this guide to create one customer-facing row per Salesforce Product Family. It includes list amount, discount amount, and net amount. It excludes optional Quote Lines and does not print individual products.

## Use case scenario

A Quote contains products from the Software and Services Product Families. The proposal needs a short commercial summary instead of a line-by-line product list.

## What this produces

Generation saves one **Quote Document Table** record and its ordered **Quote Document Row** records. Salesforce reports and the document generator read those saved records. They do not calculate the prices again.

```text
Summary by Product Family       List      Discount         Net
Software                     $12,000      ($1,200)     $10,800
Services                      $5,000            $0       $5,000
Grand Total                  $17,000      ($1,200)     $15,800
```

## Before you start

You need:

- Salesforce CPQ and this package deployed to a sandbox;
- the `CPQ_Document_Totals` permission set;
- the **Generate Document Tables** action on the Quote page;
- at least one calculated Quote with non-optional Quote Lines; and
- a Product Family value on every Product used by the test Quote.

**Stop here if** any included Product has a blank Product Family, the Quote has not finished calculating, or you cannot open **Setup → Custom Metadata Types**. Correct that prerequisite before changing this table.

## Terms in plain language

| Salesforce setting       | What it means in this guide                                                                      |
| ------------------------ | ------------------------------------------------------------------------------------------------ |
| Table definition         | The saved setup record that describes this document section.                                     |
| Table Code               | The permanent identifier used by generation and reports. Do not translate or rename it.          |
| Product Family           | The standard Product field used to place Quote Lines into Software, Services, or another family. |
| `PRICE_WATERFALL`        | Save the list amount, discount amount, and final net amount.                                     |
| Final Value              | Use the final calculated CPQ amounts, after pricing and discounts.                               |
| `EXCLUDE_OPTIONAL`       | Ignore Quote Lines whose CPQ Optional checkbox is selected.                                      |
| Show Details             | When cleared, do not print individual products.                                                  |
| Show Section Totals      | When selected, save one subtotal for each Product Family.                                        |
| Column definition        | A setup record that controls one displayed column and its order.                                 |
| Generated table and rows | The read-only result that the report and final document display.                                 |

## Configure in Salesforce

The shipped values are the source of truth. Confirm them; do not create a duplicate definition.

1. Open **Setup**.
2. In **Quick Find**, enter **Custom Metadata Types**.
3. Select **Custom Metadata Types**.
4. Beside **Quote Document Table Definition**, select **Manage Records**.
5. Open **Product Family Summary**.
6. Confirm every value below.

| Field               | Exact value                 | Why                                                                        |
| ------------------- | --------------------------- | -------------------------------------------------------------------------- |
| Table Code          | `PRODUCT_FAMILY_SUMMARY`    | Connects the definition, grouping, columns, report, and generated records. |
| Table Name          | `Product Family Summary`    | Administrative name.                                                       |
| Display Title       | `Summary by Product Family` | Customer-facing heading.                                                   |
| Amount Basis        | `Final Value`               | Uses calculated CPQ values.                                                |
| Line Filter         | `EXCLUDE_OPTIONAL`          | Keeps optional products out of the payable summary.                        |
| Measure Set         | `PRICE_WATERFALL`           | Produces list, discount, and net amounts.                                  |
| Show Details        | Cleared                     | Produces family totals only.                                               |
| Show Section Totals | Selected                    | Produces one amount row per family.                                        |
| Display Order       | `10`                        | Places this table before tables with a larger order.                       |
| Active              | Selected                    | Makes the shipped definition eligible for generation.                      |

7. Select **Save** only if a value required correction.
8. Return to **Custom Metadata Types**.
9. Beside **Quote Document Grouping**, select **Manage Records**.
10. Open **Product Family Summary - PRODUCT_FAMILY** and confirm:

| Field            | Exact value              |
| ---------------- | ------------------------ |
| Table Definition | `PRODUCT_FAMILY_SUMMARY` |
| Dimension        | `PRODUCT_FAMILY`         |
| Level            | `1`                      |
| Sequence         | `10`                     |

11. Return to **Custom Metadata Types**.
12. Beside **Quote Document Column Definition**, select **Manage Records**.
13. Confirm these four active records. The order is left to right in the document.

| Record         | Column code    | Order | Type     | Saved row field      |
| -------------- | -------------- | ----: | -------- | -------------------- |
| PFS - Label    | `COL_LABEL`    |    10 | Text     | Generated row label  |
| PFS - List     | `COL_LIST`     |    20 | Currency | `Amount_List__c`     |
| PFS - Discount | `COL_DISCOUNT` |    30 | Currency | `Amount_Discount__c` |
| PFS - Net      | `COL_NET`      |    40 | Currency | `Amount_Net__c`      |

Do not place headings or formulas only in a Word template. The generated column records control what every supported document generator receives.

## Worked example

Use the shipped `scripts/apex/product-family-summary-example.apex` script when the sandbox contains the required CPQ foundation data.

For a hand-built test, calculate a Quote with these final values:

| Product             | Product Family | Optional | List amount | Discount | Net amount |
| ------------------- | -------------- | -------- | ----------: | -------: | ---------: |
| Enterprise Platform | Software       | No       |     $12,000 |   $1,200 |    $10,800 |
| Implementation      | Services       | No       |      $5,000 |       $0 |     $5,000 |
| Training Add-on     | Services       | Yes      |      $2,000 |       $0 |     $2,000 |

The generated payable table must exclude Training Add-on. Software plus Services must equal $15,800 net. List amount must equal $17,000 and discount must equal $1,200. The optional $2,000 belongs only in an optional-products table.

## Generate and verify

1. Open the calculated sandbox Quote.
2. Select **Generate Document Tables**.
3. Wait until **Document Data Status** is **Ready**. If it becomes **Failed**, read **Document Data Error** before doing anything else.
4. Open the **Quote Document Tables** related list.
5. Open the row whose Table Code is `PRODUCT_FAMILY_SUMMARY`.
6. Confirm the generated table is **Complete** and its Grand Total net amount is $15,800 for the worked example.
7. Open its **Quote Document Rows**. Confirm Software, Services, and Grand Total exist; confirm Training Add-on does not exist.
8. Open **Reports → CPQ Document Totals → Quote Document - Product Family Summary**.
9. Filter to the test Quote when the report is not already Quote-scoped.
10. Confirm the report shows the same rows and amounts as the generated records.
11. Preview the final document and confirm it displays those saved values without a template formula.

## Troubleshooting

| Problem                                   | What it means                                                                     | What to do                                                                                                            |
| ----------------------------------------- | --------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- |
| A product appears under an unnamed family | Its Product Family is blank.                                                      | Edit the Product, set Product Family, recalculate the Quote, and generate again.                                      |
| An optional product appears               | The line is not marked Optional or the Line Filter changed.                       | Check the Quote Line Optional checkbox and confirm `EXCLUDE_OPTIONAL`.                                                |
| Individual products appear                | Show Details is selected.                                                         | Clear Show Details and generate again.                                                                                |
| Discount has the wrong sign or value      | The document is not showing the saved discount field or CPQ has not recalculated. | Recalculate the Quote, generate again, and verify `Amount_Discount__c` in the saved row before changing the template. |
| The report is empty                       | The Quote has no current generated table, or a report filter excludes it.         | Generate the Quote, confirm the table exists, then filter the named report to that Quote.                             |
| Document Data Status is Failed            | Salesforce rejected data or configuration.                                        | Read Document Data Error, correct the named cause, and generate again. Do not bypass the check.                       |

## Deactivate or roll back

1. Open **Setup → Custom Metadata Types → Quote Document Table Definition → Manage Records**.
2. Open **Product Family Summary**.
3. Clear **Active** and save.
4. Generate the test Quote again. The new current result must not contain `PRODUCT_FAMILY_SUMMARY`.
5. Do not delete generated Table or Row records by hand. Generation owns their lifecycle.
6. To restore the shipped behavior, return the exact values in this guide, select **Active**, save, and generate again.

## Production checklist

- [ ] The exact table, grouping, and four column records match this guide.
- [ ] Every included Product has a meaningful Product Family.
- [ ] The test Quote has been calculated successfully.
- [ ] Optional Quote Lines are absent from this table.
- [ ] Family rows add to the CPQ Quote net amount for payable lines.
- [ ] The named Salesforce report matches the saved rows.
- [ ] The document preview matches Salesforce and performs no pricing calculation.
- [ ] A user with the intended production permissions completed the test.
