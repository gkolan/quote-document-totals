# Product-only list without amounts

## Status and scope

**Repository status:** Non-money columns and `Suppress_Amounts__c` ship, but no active product-only definition, displayed-column set, Flow adjustment, dedicated report, or complete product-only example ships.

**Org verification status:** Supported pattern requiring sandbox proof. It is not a turnkey stock table.

## Use case scenario

A proposal needs an included-products section, but prices, discounts, subtotals, and totals must not appear in that section.

## What this produces

```text
Included products
  Cloud Platform
  Premium Support
  Implementation Services
```

The generated Salesforce result remains the source of truth. The document tool must print only the configured label and product columns; it must not hide amount fields with template formulas.

## Before you start

Choose whether optional lines and Quantity belong in the list. Use a calculated Quote containing three known products.

**Stop here if** the section may contain prices, subtotals, or totals; use a priced-table guide instead. Also stop if aggregate rows must be hidden and no reviewed Flow adjustment exists.

## Terms in plain language

| Setting          | Meaning                                                                            |
| ---------------- | ---------------------------------------------------------------------------------- |
| Displayed column | Column the final document receives and may print.                                  |
| Suppress Amounts | Allows an expanded list to omit allocated money; it does not erase backing values. |
| Is Displayed     | Saved yes/no decision controlling whether a row may print.                         |
| Aggregate row    | Heading, subtotal, section total, or Grand Total rather than a product row.        |
| Template formula | Document-side logic; it must not decide what content exists.                       |

## Configure in Salesforce

### Create the table definition

1. In **Setup**, open **Custom Metadata Types**.
2. Find **Quote Document Table Definition**, select **Manage Records**, and select **New**.
3. Enter these values for the worked example:

   | Field                       | Value                          |
   | --------------------------- | ------------------------------ |
   | Label                       | `Product Only List`            |
   | Active                      | Cleared                        |
   | Table Code                  | `PRODUCT_ONLY_LIST`            |
   | Table Name                  | `Product Only List`            |
   | Display Title               | `Included products`            |
   | Amount Basis                | `Final Value`                  |
   | Line Filter                 | `EXCLUDE_OPTIONAL`             |
   | Measure Set                 | `PRICE_WATERFALL`              |
   | Show Details                | Selected                       |
   | Show Section Totals         | Cleared                        |
   | Suppress Amounts            | Cleared                        |
   | Display Order               | `320`                          |
   | Row Customizer Flow         | `QuoteDocumentProductOnlyRows` |
   | Row Customizer Flow Version | `1`                            |
   | Cache Policy                | `STANDARD`                     |

4. Before saving, check the other active table definitions and Document Content records. If `320` is already used as a Display Order, use the first unused multiple of 10 above 320. Tables and content blocks cannot share an order.
5. Save the inactive definition.

### Create the one displayed column

1. Return to **Custom Metadata Types**, find **Quote Document Column Definition**, and select **Manage Records**.
2. Create an active record labeled `Product Only - Product Name` with these values: **Table Definition** `PRODUCT_ONLY_LIST`, **Column Code** `COL_PRODUCT_NAME`, **Display Order** `10`, **Data Type** `Text`, and **Value Field** `Product_Name__c`.
3. Do not create a column whose Value Field begins with `Amount_`. The explicit Product Name record replaces the normal money-column defaults for this table.

### Create the Flow that hides headings and totals

1. In **Setup → Flows**, select **New Flow → Autolaunched Flow (No Trigger)**.
2. Create the five input variables and `outRows` collection exactly as listed in [Flow-based row adjustment](42-flow-row-adjustment.md). The `rows` record collection must allow both input and output.
3. Add a Loop over `rows`.
4. Inside the loop, add a Decision named **Is Detail Row**. Its Yes outcome checks whether the current item's `Row_Type__c` equals `Detail`.
5. On the Yes path, assign the current item's `Is_Displayed__c` to True. On the default path, assign it to False.
6. Join both paths into an Assignment that adds the current item to `outRows`, then return to the Loop.
7. After the Loop, assign `outRows` back to `rows`.
8. Save the Flow with label **Quote Document Product Only Rows** and API name `QuoteDocumentProductOnlyRows`. Activate it.
9. Return to the table definition, confirm the Flow API name and version, select **Active**, and save.
10. Calculate the worked-example Quote and select **Generate Document Tables**.

## Worked example

Use Cloud Platform, Premium Support, and Implementation Services. Configure Label/Product Name only. Expected output is exactly the three names shown above, with no currency heading, amount cell, subtotal, or Grand Total.

### Important distinction

`Suppress_Amounts__c` tells generation that an expanded list intentionally has no allocated money. It does not erase saved values. The displayed column choices are what keep amounts out of the data sent to the document tool; backing values may still exist for verification and administrative reporting.

## Generate and verify

- **Document Data Status** is `Ready`.
- The generated table has only the intended displayed columns, and the data supplied to the document tool contains no amount column for this table.
- Optional products are included or excluded as approved.
- Any heading, subtotal, section-total, or grand-total rows that must not print have `Is_Displayed__c = false` before retrieval.
- The final document contains no currency heading, amount cell, subtotal, or grand-total row for this section.

## Troubleshooting

| Problem                 | What it means                         | What to do                                                                       |
| ----------------------- | ------------------------------------- | -------------------------------------------------------------------------------- |
| Currency column appears | An amount column remains active.      | Deactivate that column and generate again.                                       |
| Totals print            | Aggregate rows remain displayed.      | Use the reviewed Flow to set their Is Displayed value to false before retrieval. |
| Products are missing    | Filter or Is Displayed excludes them. | Correct the table filter or Flow output.                                         |
| Status is Failed        | Configuration is invalid.             | Read **Document Data Error**; do not add fake allocation merely to silence it.   |

## Deactivate or roll back

Clear **Active**, save, and generate again. Deactivate custom columns or clear the Flow reference to roll back; never delete generated records manually.

## Production checklist

- [ ] Optional-line policy is explicit.
- [ ] Only approved non-money columns are active.
- [ ] No aggregate row prints.
- [ ] Data supplied to the document tool contains no amount column for this table.
- [ ] Final document contains the intended product names only.
