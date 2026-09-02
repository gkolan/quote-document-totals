# Averages, Percentages, Peaks, and Ending Balances

## Status and scope

**Repository status:** Column rules `MAX`, `RATIO`, `LAST`, and `NONE` are implemented and tested. This guide configures the peak-Quantity example on a monthly table; no separate table definition or report is required.

**Org verification status:** Aggregation behavior is tested. Each target column's business meaning must still be approved in the org.

## Use case scenario

A monthly table repeats 100 licenses each month. Its grand total must show a peak of 100 licenses, not a sum of 1,200.

## What this produces

Salesforce creates one or more `Quote_Document_Table__c` records and the related `Quote_Document_Row__c` records needed for this view. The saved values can be reviewed in Salesforce before they are sent to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Assign the `CPQ_Document_Totals` permission set.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Identify one column and write down whether its Grand Total means peak, ratio, ending value, or no total.

**Stop here if** the business owner cannot state the correct total rule, a numerator or denominator can be zero unexpectedly, or one column is being asked to mean different things in different sections.

## Terms in plain language

| Rule    | Meaning                                                                |
| ------- | ---------------------------------------------------------------------- |
| `MAX`   | Largest displayed value; use for peak licenses.                        |
| `RATIO` | Total numerator divided by total denominator; use for a weighted rate. |
| `LAST`  | Last value in saved display order; use for ending balance.             |
| `NONE`  | Do not print a total because no total is meaningful.                   |
| `SUM`   | Add values; wrong for the four cases above.                            |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. For the peak example, open the Quantity column belonging to `MONTHLY_SUBSCRIPTION_SUMMARY` and confirm these values:

| Field                   | Value    |
| ----------------------- | -------- |
| Aggregation Rule        | `MAX`    |
| Aggregation Numerator   | `Blank`  |
| Aggregation Denominator | `Blank`  |
| Data Type               | `Number` |

4. Save the table definition.
5. From **Custom Metadata Types**, open **Quote Document Grouping** and select **Manage Records**.
6. Leave the table's existing monthly grouping unchanged; total behavior belongs on the Quantity column.
7. Save the grouping record.
8. Keep the table inactive while testing the column change.
9. Activate only for the controlled sandbox generation.

## Worked example

```text
January licenses              100
February licenses             100
March licenses                100
Peak licenses                 100
```

Three monthly rows of 100 must produce Peak licenses 100. A value of 300 proves the rule is wrong.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the generated table or tables.
3. Quote Document Rows show the saved details, subtotals, and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the test Quote and monthly table.
5. The final document shows these saved values without recalculating them.

## Troubleshooting

| Problem                     | What it means                             | What to do                                                |
| --------------------------- | ----------------------------------------- | --------------------------------------------------------- |
| Peak is 300                 | Column still uses `SUM`.                  | Set `MAX` and regenerate.                                 |
| Ending balance adds periods | Ending column uses `SUM`.                 | Use `LAST` and confirm saved order.                       |
| Ratio averages percentages  | Direct averaging is incorrect.            | Configure numerator and denominator fields for `RATIO`.   |
| Status is Failed            | Column binding or aggregation is invalid. | Read **Document Data Error** and correct the named cause. |

## Deactivate or roll back

Clear **Active** on the affected table before changing a rule. Restore the previous column metadata and generate again. Do not edit generated totals manually.

## Production checklist

- [ ] Business owner approved the column meaning.
- [ ] Peak example returns 100.
- [ ] Section and Grand Total rules both pass.
- [ ] Ratio denominator-zero behavior was tested when used.
- [ ] Report and document preview match saved totals.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source data, and generate again.
