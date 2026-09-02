# Product Change Summary

## Status and scope

**Repository status:** The inactive `PRODUCT_SUMMARY` definition, Product Name grouping, displayed columns, and **Quote Document - Product Totals** report ship.

**Org verification status:** Product aggregation is tested; amendment classification remains provisional for the target org.

## Use case scenario

An amendment document needs one change total per Product so the customer can see which products increased or decreased.

## What this produces

Salesforce creates one or more `Quote_Document_Table__c` records and the related `Quote_Document_Row__c` records needed for this view. The saved values can be reviewed in Salesforce before they are sent to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Assign the `CPQ_Document_Totals` permission set.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Create a real amendment with one increased and one decreased product.

**Stop here if** product matching is ambiguous, renamed products must match historical names, or this view disagrees with the transaction summary.

## Terms in plain language

| Setting               | Meaning                                                  |
| --------------------- | -------------------------------------------------------- |
| Product Name grouping | Combine change amounts under the displayed Product name. |
| `CHANGE`              | Save before, after, and difference amounts.              |
| Net Change            | After amount minus before amount.                        |
| Show Details cleared  | Print one row per product.                               |
| Provisional           | Keep inactive until real amendment proof passes.         |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Open **Product Totals**. Enter or confirm these values:

| Field         | Value                                                   |
| ------------- | ------------------------------------------------------- |
| Active        | `Keep cleared until amendment verification is complete` |
| Table Code    | `PRODUCT_SUMMARY`                                       |
| Display Title | `Product Summary`                                       |
| Measure Set   | `CHANGE`                                                |
| Amount Basis  | `Net Change`                                            |
| Line Filter   | `EXCLUDE_OPTIONAL`                                      |
| Show Details  | `Cleared`                                               |

4. Save the table definition.
5. From **Custom Metadata Types**, open **Quote Document Grouping** and select **Manage Records**.
6. Open **Product Summary - PRODUCT_NAME** and confirm Dimension `PRODUCT_NAME`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Keep **Active** cleared until real-amendment verification passes.
9. Activate only for the controlled test and deactivate while correcting discrepancies.

## Worked example

```text
Platform Licenses          +$5,000
Premium Support            -$1,000
Net Change                 +$4,000
```

Platform Licenses +$5,000 and Premium Support -$1,000 must produce Net Change +$4,000.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the generated table or tables.
3. Quote Document Rows show the saved details, subtotals, and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Product Totals** and filter to the amendment Quote.
5. The final document shows these saved values without recalculating them.

## Troubleshooting

| Problem                                        | What it means                                | What to do                                                        |
| ---------------------------------------------- | -------------------------------------------- | ----------------------------------------------------------------- |
| Same product appears twice                     | Product matching keys differ.                | Compare source and amendment lines; keep inactive until resolved. |
| Change has wrong sign                          | Saved change or formatting is wrong.         | Inspect generated Amount Change first.                            |
| Product total disagrees with transaction total | A line is missing or classified differently. | Reconcile both reports line by line.                              |
| Status is Failed                               | Generation rejected comparison data.         | Read **Document Data Error** and correct the named cause.         |

## Deactivate or roll back

The shipped definition is inactive. Clear **Active** after any controlled test and generate again. Never delete generated records manually.

## Production checklist

- [ ] Real CPQ amendment used.
- [ ] Increased and decreased products tested.
- [ ] Product matching is unambiguous.
- [ ] Product and transaction totals agree.
- [ ] Definition remains inactive until approval.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source data, and generate again.
