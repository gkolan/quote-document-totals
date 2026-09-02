# Customer Product Numbers

## Status and scope

**Repository status:** The `PRODUCT_ALIAS` expansion and Quote Document Product Alias metadata type ship and are tested. No `CUSTOMER_PRODUCT_NUMBERS` definition, grouping, columns, dedicated report, or example script ships.

**Org verification status:** Alias matching and missing-alias failure are tested. Target customer mappings and output are not verified.

## Use case scenario

A customer requires its own purchasing codes on the document instead of the Product Codes used in Salesforce.

## What this produces

Salesforce creates one or more `Quote_Document_Table__c` records and the related `Quote_Document_Row__c` records needed for this view. The saved values can be reviewed in Salesforce before they are sent to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Assign the `CPQ_Document_Totals` permission set.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Obtain the customer's approved part number for every included Salesforce Product Code.

**Stop here if** any included product lacks a customer code, one Salesforce Product has more than one possible match, or the buyer has not confirmed the customer code. Generation stops instead of showing the seller code.

## Terms in plain language

| Setting             | Meaning                                                                   |
| ------------------- | ------------------------------------------------------------------------- |
| Product alias       | Customer part number mapped to a Salesforce Product Code.                 |
| `PRODUCT_ALIAS`     | Replace or expand the seller product identity with customer mappings.     |
| Weight              | Relative split when one seller product maps to multiple customer numbers. |
| Missing mapping     | A blocking data error, not a reason to print the seller code.             |
| Generated alias row | Saved customer-facing code, Quantity, and amount.                         |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Create a new record. Enter or confirm these values:

| Field               | Value                       |
| ------------------- | --------------------------- |
| Active              | `Cleared while configuring` |
| Table Code          | `CUSTOMER_PRODUCT_NUMBERS`  |
| Table Name          | `Customer Product Numbers`  |
| Display Title       | `Customer Product Numbers`  |
| Display Order       | `250`                       |
| Expander Code       | `PRODUCT_ALIAS`             |
| Expander Version    | `1`                         |
| Allocation Basis    | `EVEN`                      |
| Allocation Scale    | `2`                         |
| Sort Groups By      | `EXPANSION_ORDER`           |
| Measure Set         | `PRICE_WATERFALL`           |
| Amount Basis        | `Final Value`               |
| Line Filter         | `EXCLUDE_OPTIONAL`          |
| Show Details        | `Selected`                  |
| Show Section Totals | `Cleared`                   |

4. Save the table definition.
5. From **Custom Metadata Types**, open **Quote Document Grouping** and select **Manage Records**.
6. Create **CUSTOMER_PRODUCT_NUMBERS_EXPANSION** with Table Definition `CUSTOMER_PRODUCT_NUMBERS`, Dimension `EXPANSION`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. In **Quote Document Product Alias**, create active mappings for every included Product Code before activating the table.
9. Activate only for the controlled sandbox test.

## Worked example

```text
CUST-100-A        60 units     $6,000
CUST-100-B        40 units     $4,000
Total            100 units    $10,000
```

Map one $10,000, Quantity 100 seller product to `CUST-100-A` with weight 60 and `CUST-100-B` with weight 40. Expected shares are 60/$6,000 and 40/$4,000.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the generated table or tables.
3. Quote Document Rows show the saved details, subtotals, and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the Quote and `CUSTOMER_PRODUCT_NUMBERS`.
5. The final document shows these saved values without recalculating them.

## Troubleshooting

| Problem                          | What it means                                 | What to do                                                        |
| -------------------------------- | --------------------------------------------- | ----------------------------------------------------------------- |
| Generation reports missing alias | No active mapping matches the Product Code.   | Add the customer-confirmed mapping and generate again.            |
| Seller code prints               | The document bypasses generated alias rows.   | Correct the document mapping; do not add template fallback logic. |
| Shares do not total 100/$10,000  | Mapping weights or quantity precision differ. | Correct active alias records and regenerate.                      |
| Status is Failed                 | Alias validation rejected a mapping.          | Read **Document Data Error** and correct the named cause.         |

## Deactivate or roll back

Clear **Active** on the table definition and generate again. Deactivate an incorrect alias instead of deleting generated rows. Restore confirmed mappings before reactivation.

## Production checklist

- [ ] Buyer confirmed every customer part number.
- [ ] Every included Product Code has an active mapping.
- [ ] Multi-alias weights and quantities reconcile.
- [ ] No seller-code fallback appears.
- [ ] Rendered View and document preview match saved alias rows.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source data, and generate again.
