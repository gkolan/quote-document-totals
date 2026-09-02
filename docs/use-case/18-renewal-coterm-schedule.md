# Renewal and Co-Term Schedule

## Status and scope

**Repository status:** The `AMENDED_SUBSCRIPTION` source exists, but no `RENEWAL_COTERM` definition, grouping, columns, dedicated report, or example script ships.

**Org verification status:** Provisional. Renewal and co-term behavior has not been proven with a real CPQ renewal in the target org.

## Use case scenario

A renewal or co-term Quote needs to show the current subscription position and the new renewal amount over the applicable term.

## What this produces

Salesforce creates one or more `Quote_Document_Table__c` records and the related `Quote_Document_Row__c` records needed for this view. The saved values can be reviewed in Salesforce before they are sent to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Assign the `CPQ_Document_Totals` permission set.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Create the renewal through Salesforce CPQ and record the expected baseline, dates, quantities, and renewal prices before configuring this view.

**Stop here if** the Quote is not a CPQ-created renewal, co-term dates are incomplete, or `AMENDED_SUBSCRIPTION` does not match the target org's renewal data. Keep this pattern inactive.

## Terms in plain language

| Setting          | Meaning                                                               |
| ---------------- | --------------------------------------------------------------------- |
| Renewal baseline | Subscription values being renewed.                                    |
| Co-term          | Shorten or align a new subscription so it ends with an existing term. |
| `RECURRING_ONLY` | Exclude one-time lines from this recurring comparison.                |
| `CHANGE`         | Save current, renewal, and difference amounts.                        |
| Version `1`      | Current comparison behavior identity.                                 |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Create a new record. Enter or confirm these values:

| Field                     | Value                          |
| ------------------------- | ------------------------------ |
| Active                    | `Cleared`                      |
| Table Code                | `RENEWAL_COTERM`               |
| Table Name                | `Renewal and Co-Term Schedule` |
| Display Title             | `Renewal and Co-Term Schedule` |
| Display Order             | `180`                          |
| Comparison Source Code    | `AMENDED_SUBSCRIPTION`         |
| Comparison Source Version | `1`                            |
| Measure Set               | `CHANGE`                       |
| Amount Basis              | `Net Change`                   |
| Line Filter               | `RECURRING_ONLY`               |

4. Save the table definition.
5. From **Custom Metadata Types**, open **Quote Document Grouping** and select **Manage Records**.
6. Create **RENEWAL_COTERM_PRODUCT_FAMILY** with Table Definition `RENEWAL_COTERM`, Dimension `PRODUCT_FAMILY`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Keep **Active** cleared until a real renewal passes.
9. Generate only as a controlled sandbox test after all related metadata is complete.

## Worked example

```text
Current recurring amount      $24,000
Renewal recurring amount      $27,000
Renewal change                 +$3,000
```

Use a renewal whose current recurring amount is $24,000 and new recurring amount is $27,000. The saved change must be +$3,000. Verify co-termed lines separately by their actual dates.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the generated table or tables.
3. Quote Document Rows show the saved details, subtotals, and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the renewal Quote and `RENEWAL_COTERM`.
5. The final document shows these saved values without recalculating them.

## Troubleshooting

| Problem                   | What it means                                       | What to do                                                     |
| ------------------------- | --------------------------------------------------- | -------------------------------------------------------------- |
| One-time lines appear     | The filter changed.                                 | Restore `RECURRING_ONLY`.                                      |
| Renewal baseline is blank | Subscription references are missing or unsupported. | Keep inactive and verify the CPQ renewal source.               |
| Co-term amount is wrong   | Dates, proration, or CPQ renewal pricing differs.   | Recalculate CPQ and compare dates and final values row by row. |
| Status is Failed          | Comparison validation rejected the source.          | Read **Document Data Error** and correct the named cause.      |

## Deactivate or roll back

This definition starts inactive. Clear **Active** and generate again after any failed test. Never delete generated rows manually.

## Production checklist

- [ ] Renewal was created through Salesforce CPQ.
- [ ] Baseline subscriptions, renewal prices, and dates match CPQ.
- [ ] Co-term proration was checked line by line.
- [ ] One-time lines are excluded.
- [ ] The definition remains inactive until every check passes.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source data, and generate again.
