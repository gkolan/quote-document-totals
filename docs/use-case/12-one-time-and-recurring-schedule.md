# One-Time and Recurring Charges in One Schedule

## Status and scope

**Repository status:** Period expansion and one-time placement are implemented and tested. No `MIXED_CHARGE_SCHEDULE` definition, grouping, columns, dedicated report, or example script ships.

**Org verification status:** The mechanism is tested. The target org's charge classification, dates, and output are not verified.

## Use case scenario

A Quote contains a setup fee and a recurring subscription. The setup fee must appear once while the subscription amount is spread across periods.

## What this produces

Salesforce creates one `Quote_Document_Table__c` record for this view and `Quote_Document_Row__c` records for the displayed lines. The same saved result can be viewed in Salesforce Reports and passed to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Confirm the `CPQ_Document_Totals` permission set is assigned.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Use a calculated 12-month Quote with one $2,000 setup fee and one $12,000 recurring subscription.

**Stop here if** charge types are wrong, dates are incomplete, or the agreement requires a treatment other than placing the setup fee in Month 1.

## Terms in plain language

| Setting           | Meaning                                                                    |
| ----------------- | -------------------------------------------------------------------------- |
| `PERIOD`          | Create rows from equal calendar periods.                                   |
| Period Months `1` | Create monthly rows.                                                       |
| `FIRST_PERIOD`    | Put a one-time line in Month 1 only.                                       |
| `SPREAD`          | Divide a one-time line across all periods; do not use it for this example. |
| `EXPANSION`       | Group the generated shares by month.                                       |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Create a new record. Enter or confirm these values:

| Field                     | Value                       |
| ------------------------- | --------------------------- |
| Active                    | `Cleared while configuring` |
| Table Code                | `MIXED_CHARGE_SCHEDULE`     |
| Table Name                | `Mixed Charge Schedule`     |
| Display Title             | `Charges by Period`         |
| Display Order             | `120`                       |
| Expander Code             | `PERIOD`                    |
| Expander Version          | `1`                         |
| Period Months             | `1`                         |
| Period One-Time Placement | `FIRST_PERIOD`              |
| Allocation Basis          | `EVEN`                      |
| Allocation Scale          | `2`                         |
| Sort Groups By            | `EXPANSION_ORDER`           |
| Measure Set               | `PRICE_WATERFALL`           |
| Amount Basis              | `Final Value`               |
| Line Filter               | `EXCLUDE_OPTIONAL`          |
| Show Section Totals       | `Cleared`                   |

4. Save the table definition.
5. Return to **Custom Metadata Types**, find **Quote Document Grouping**, and select **Manage Records**.
6. Create **MIXED_CHARGE_SCHEDULE_EXPANSION** with Dimension `EXPANSION`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Select **Active**, save, and generate document data for a representative sandbox Quote. If the result is wrong, clear **Active** before making corrections. Leave it selected for general use only after the rows and totals are correct.

## Worked example

```text
Month 1   Setup $2,000 + Subscription $1,000
Month 2                  Subscription $1,000
Month 3                  Subscription $1,000
```

Month 1 is $3,000; Months 2–12 are $1,000 each; Grand Total is $14,000. The $2,000 fee must appear once.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the table.
3. Its Quote Document Rows contain the displayed lines and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the Quote and `MIXED_CHARGE_SCHEDULE`.
5. The final document shows the same saved values; the document template does not recalculate them.

## Troubleshooting

| Problem                       | What it means                                | What to do                                                |
| ----------------------------- | -------------------------------------------- | --------------------------------------------------------- |
| Setup fee appears every month | One-time placement or charge type is wrong.  | Restore `FIRST_PERIOD` and correct source classification. |
| Recurring amount appears once | Subscription dates or charge type are wrong. | Correct CPQ data, calculate, and generate again.          |
| Total is not $14,000          | Source pricing or allocation differs.        | Compare saved shares with CPQ final values.               |
| Status is Failed              | Period data is invalid.                      | Read **Document Data Error** and correct the named cause. |

## Deactivate or roll back

Keep the definition inactive until the fee appears once and totals reconcile. Clear **Active** and generate again to roll back. Do not delete generated records manually.

## Production checklist

- [ ] Charge types and dates are correct.
- [ ] Period Months is 1.
- [ ] One-time placement is `FIRST_PERIOD`.
- [ ] The fee appears once.
- [ ] All months add to CPQ net amount.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source Quote data, and generate again.
