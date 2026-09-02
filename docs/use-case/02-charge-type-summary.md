# Charge Type Summary

## Status and scope

**Repository status:** The active `CHARGE_TYPE_SUMMARY` definition, its Charge Type grouping, displayed columns, the **Quote Document - Charge Type Summary** report, and `scripts/apex/charge-type-summary-example.apex` ship in the repository.

**Org verification status:** Repository tests cover this behavior. Deployment and execution in the target Salesforce org are not verified by this guide.

## Use case scenario

A Quote includes implementation fees and recurring subscriptions. The document needs to separate one-time charges from recurring charges.

## What this produces

Salesforce creates one `Quote_Document_Table__c` record for this view and `Quote_Document_Row__c` records for the displayed lines. The same saved result can be viewed in Salesforce Reports and passed to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Confirm the `CPQ_Document_Totals` permission set is assigned.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Confirm that every test Quote Line has the intended Salesforce CPQ charge type.

**Stop here if** the Quote is not calculated, a test line has no usable charge type, or the permission set and generation action are unavailable.

## Terms in plain language

| Setting              | Meaning                                                                       |
| -------------------- | ----------------------------------------------------------------------------- |
| Charge Type          | The CPQ classification that separates one-time, recurring, and usage charges. |
| `PRICE_WATERFALL`    | Save calculated pricing amounts rather than calculate them in the document.   |
| `EXCLUDE_OPTIONAL`   | Leave optional Quote Lines out of this payable table.                         |
| Show Details cleared | Print one total per charge type, not every product.                           |
| Generated rows       | The saved result used by Salesforce reports and the final document.           |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Open **Charge Type Summary**. Enter or confirm these values:

| Field         | Value                    |
| ------------- | ------------------------ |
| Active        | `Selected`               |
| Table Code    | `CHARGE_TYPE_SUMMARY`    |
| Display Title | `Summary by Charge Type` |
| Measure Set   | `PRICE_WATERFALL`        |
| Amount Basis  | `Final Value`            |
| Line Filter   | `EXCLUDE_OPTIONAL`       |
| Show Details  | `Cleared`                |

4. Save the table definition.
5. Return to **Custom Metadata Types**, find **Quote Document Grouping**, and select **Manage Records**.
6. Open **Charge Type Summary - CHARGE_TYPE** and confirm Dimension `CHARGE_TYPE`, Level `1`, and Sequence `10`.
7. Save the grouping record.
8. Select **Active**, save, and generate document data for a representative sandbox Quote. If the result is wrong, clear **Active** before making corrections. Leave it selected for general use only after the rows and totals are correct.

## Worked example

```text
One-Time                  $5,000
Recurring                $24,000
Grand Total              $29,000
```

Use a calculated Quote with a $5,000 one-time implementation line and a $24,000 recurring subscription line. Optional lines must not contribute to the $29,000 result.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the table.
3. Its Quote Document Rows contain the displayed lines and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Charge Type Summary** and filter it to the test Quote.
5. The final document shows the same saved values; the document template does not recalculate them.

## Troubleshooting

| Problem                          | What it means                                            | What to do                                                                          |
| -------------------------------- | -------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| A charge is in the wrong row     | The Product or Quote Line has the wrong CPQ charge type. | Correct the source value, recalculate the Quote, and generate again.                |
| Optional charges appear          | The line is not marked Optional or the filter changed.   | Confirm the line and restore `EXCLUDE_OPTIONAL`.                                    |
| The example total is not $29,000 | Source pricing or table settings differ.                 | Compare saved rows with the calculated Quote before changing the document template. |
| Status is Failed                 | Salesforce rejected data or configuration.               | Read **Document Data Error**, correct the named cause, and generate again.          |

## Deactivate or roll back

Clear **Active** on **Charge Type Summary**, save, and generate the test Quote again. Do not delete generated rows manually. Restore the values in this guide and reactivate to roll forward.

## Production checklist

- [ ] Every included product has the intended charge type.
- [ ] Optional lines are excluded.
- [ ] Charge-type rows add to the payable Quote total.
- [ ] The named report matches the generated records.
- [ ] The document preview contains no pricing formula.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source Quote data, and generate again.
