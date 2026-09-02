# Multi-Year Schedule

## Status and scope

**Repository status:** The inactive `ANNUAL_SCHEDULE` definition and `ANNUAL_SCHEDULE_EXPANSION` grouping ship in the repository. No dedicated report or example script ships; use **Quote Document - Rendered View** and the numeric test below.

**Org verification status:** Period expansion is tested. The target org's multi-year CPQ data and output are not verified here.

## Use case scenario

A three-year Quote needs a separate section for each contract year so the customer can see when each amount applies.

## What this produces

Salesforce creates one `Quote_Document_Table__c` record for this view and `Quote_Document_Row__c` records for the displayed lines. The same saved result can be viewed in Salesforce Reports and passed to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Confirm the `CPQ_Document_Totals` permission set is assigned.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Use a calculated 36-month Quote whose line dates and segment amounts are final.

**Stop here if** the Quote term is not 36 months, segment dates overlap or have gaps, or the signed agreement does not place one-time charges in Year 1.

## Terms in plain language

| Setting              | Meaning                                         |
| -------------------- | ----------------------------------------------- |
| `PERIOD`             | Create named rows from equal date periods.      |
| Period Months `12`   | Create one row for each contract year.          |
| `FIRST_PERIOD`       | Put a one-time charge in Year 1 only.           |
| `EXPANSION` grouping | Group generated shares by their year.           |
| Period sequence      | Numeric order that keeps Year 2 before Year 10. |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Open **Annual Schedule**. Enter or confirm these values:

| Field                     | Value                          |
| ------------------------- | ------------------------------ |
| Active                    | `Select after sandbox testing` |
| Table Code                | `ANNUAL_SCHEDULE`              |
| Display Title             | `Annual Payment Schedule`      |
| Expander Code             | `PERIOD`                       |
| Expander Version          | `1`                            |
| Period Months             | `12`                           |
| Period One-Time Placement | `FIRST_PERIOD`                 |
| Allocation Basis          | `EVEN`                         |
| Allocation Scale          | `2`                            |
| Sort Groups By            | `EXPANSION_ORDER`              |
| Measure Set               | `PRICE_WATERFALL`              |
| Amount Basis              | `Final Value`                  |
| Line Filter               | `EXCLUDE_OPTIONAL`             |
| Show Section Totals       | `Cleared`                      |

4. Save the table definition.
5. Return to **Custom Metadata Types**, find **Quote Document Grouping**, and select **Manage Records**.
6. Open **ANNUAL_SCHEDULE_EXPANSION** and confirm Dimension `EXPANSION`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Select **Active**, save, and generate document data for a representative sandbox Quote. If the result is wrong, clear **Active** before making corrections. Leave it selected for general use only after the rows and totals are correct.

## Worked example

```text
Year 1                    $18,000
Year 2                    $12,000
Year 3                    $12,000
Grand Total               $42,000
```

Use a $6,000 one-time fee plus $12,000 recurring in each of three years. Year 1 is $18,000, Years 2 and 3 are $12,000 each, and total is $42,000.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the table.
3. Its Quote Document Rows contain the displayed lines and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the Quote and `ANNUAL_SCHEDULE`.
5. The final document shows the same saved values; the document template does not recalculate them.

## Troubleshooting

| Problem                   | What it means                             | What to do                                                |
| ------------------------- | ----------------------------------------- | --------------------------------------------------------- |
| Fee appears every year    | One-time placement is not `FIRST_PERIOD`. | Restore it and generate again.                            |
| Years sort alphabetically | Generated period order was ignored.       | Make the report or document use saved Display Order.      |
| A year amount is wrong    | Segment dates or CPQ amounts differ.      | Correct and calculate the Quote before generation.        |
| Status is Failed          | Period data or configuration is invalid.  | Read **Document Data Error** and correct the named cause. |

## Deactivate or roll back

Clear **Active** on **Annual Schedule**, save, and generate again. Restore exact shipped values to reactivate; do not delete generated records.

## Production checklist

- [ ] Term and segment dates are complete.
- [ ] One-time charges appear in Year 1 only.
- [ ] Years use saved numeric order.
- [ ] Annual rows add to CPQ net amount.
- [ ] Rendered View and document preview match.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source Quote data, and generate again.
