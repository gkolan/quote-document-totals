# Monthly Subscription Breakdown

## Status and scope

**Repository status:** The inactive `MONTHLY_SUBSCRIPTION_SUMMARY` definition, Label and Net columns, localization examples, registered monthly adjustment, and `scripts/apex/monthly-subscription-example.apex` ship. A Quantity column and dedicated report do not ship; this guide creates the Quantity column and uses **Quote Document - Rendered View**.

**Org verification status:** Automated tests cover monthly allocation and peak Quantity. Target-org deployment and execution are not verified here.

## Use case scenario

A subscription is quoted for several months, but the document needs a month-by-month view of cost while repeating the licensed Quantity instead of adding it twelve times.

## What this produces

Salesforce creates one `Quote_Document_Table__c` record for this view and `Quote_Document_Row__c` records for the displayed lines. The same saved result can be viewed in Salesforce Reports and passed to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Confirm the `CPQ_Document_Totals` permission set is assigned.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Use a calculated subscription Quote with a start date, end date, and term that agree.

**Stop here if** subscription dates are incomplete, the Quote is not calculated, or monthly allocation is not the signed commercial treatment.

## Terms in plain language

| Setting             | Meaning                                                                     |
| ------------------- | --------------------------------------------------------------------------- |
| Monthly allocation  | Divide the final subscription amount across calendar months.                |
| Repeated Quantity   | Show the active license count each month without adding it across months.   |
| Peak Quantity       | The largest monthly license count; 100 repeated for 12 months remains 100.  |
| `EXCLUDE_OPTIONAL`  | Leave optional lines out of the payable schedule.                           |
| Inactive definition | The metadata ships, but an administrator must test before selecting Active. |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Open **Monthly Subscription Summary**. Enter or confirm these values:

| Field                  | Value                               |
| ---------------------- | ----------------------------------- |
| Active                 | `Select only after sandbox testing` |
| Table Code             | `MONTHLY_SUBSCRIPTION_SUMMARY`      |
| Display Title          | `Monthly Subscription Costs`        |
| Line Filter            | `EXCLUDE_OPTIONAL`                  |
| Measure Set            | `PRICE_WATERFALL`                   |
| Amount Basis           | `Final Value`                       |
| Show Details           | `Selected`                          |
| Show Section Totals    | `Cleared`                           |
| Row Customizer Code    | `MONTHLY_SUBSCRIPTION`              |
| Row Customizer Version | `1`                                 |
| Cache Policy           | `STANDARD`                          |
| Max Groups             | `24`                                |
| Display Order          | `95`                                |

4. Save the table definition.
5. Return to **Custom Metadata Types**, find **Quote Document Column Definition**, and select **Manage Records**.
6. Confirm **MSS - Label** is active with Table Definition `MONTHLY_SUBSCRIPTION_SUMMARY`, Column Code `COL_LABEL`, Display Order `10`, and Data Type `Text`.
7. Confirm **MSS - Net** is active with the same Table Definition, Column Code `COL_NET`, Display Order `20`, Data Type `Currency`, and Value Field `Amount_Net__c`.
8. Create **MSS - Quantity** with Table Definition `MONTHLY_SUBSCRIPTION_SUMMARY`, Column Code `COL_QUANTITY`, Display Order `15`, Data Type `Number`, Value Field `Quantity__c`, Aggregation Rule `MAX`, and Active selected. Leave Aggregation Numerator and Aggregation Denominator blank.
9. Do not create a Quote Document Grouping record for this example. The registered monthly adjustment creates and orders the month rows.
10. Return to **Monthly Subscription Summary**, select **Active**, save, and generate the worked-example Quote. If the result is wrong, clear **Active** before making corrections.

## Worked example

```text
January     100 licenses   $1,000
February    100 licenses   $1,000
March       100 licenses   $1,000
Total       100 peak       $3,000
```

For three months at $1,000 and 100 licenses per month, amount totals $3,000 and peak Quantity is 100, not 300.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the table.
3. Its Quote Document Rows contain the displayed lines and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the Quote and table code `MONTHLY_SUBSCRIPTION_SUMMARY`.
5. The final document shows the same saved values; the document template does not recalculate them.

## Troubleshooting

| Problem                       | What it means                                          | What to do                                                       |
| ----------------------------- | ------------------------------------------------------ | ---------------------------------------------------------------- |
| Quantity totals 300           | Quantity is being summed instead of treated as a peak. | Restore the shipped Quantity aggregation and generate again.     |
| A month is missing            | Quote dates or period generation do not cover it.      | Correct dates, calculate, and generate again.                    |
| Amount total differs from CPQ | Allocation or source pricing is stale.                 | Recalculate and inspect saved rows before changing the template. |
| Status is Failed              | Generation rejected data or configuration.             | Read **Document Data Error** and correct the named cause.        |

## Deactivate or roll back

Clear **Active** on **Monthly Subscription Summary**, save, and generate again. Restore shipped metadata to roll forward. Never delete generated rows manually.

## Production checklist

- [ ] Dates and term are complete.
- [ ] Every expected month appears once.
- [ ] Monthly amounts add to CPQ net amount.
- [ ] Peak Quantity is not summed.
- [ ] Rendered View and document preview match saved rows.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source Quote data, and generate again.
