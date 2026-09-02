# Product Family and Billing Frequency Summary

## Status and scope

**Repository status:** The active `FAMILY_BILLING_COMPOSITE` definition, its two grouping records, the **Quote Doc - Family & Billing Composite** report, and `scripts/apex/family-billing-composite-example.apex` ship in the repository.

**Org verification status:** Repository tests cover combined labels. Target-org billing-frequency data and output are not verified here.

## Use case scenario

A Quote contains monthly and annual products in the same Product Family. The document needs rows such as “Software — Monthly” and “Software — Annual.”

## What this produces

Salesforce creates one `Quote_Document_Table__c` record for this view and `Quote_Document_Row__c` records for the displayed lines. The same saved result can be viewed in Salesforce Reports and passed to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Confirm the `CPQ_Document_Totals` permission set is assigned.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Confirm Product Family and Billing Frequency are populated on every included line.

**Stop here if** an included line lacks either value, the Quote is not calculated, or generation is unavailable.

## Terms in plain language

| Setting             | Meaning                                                                    |
| ------------------- | -------------------------------------------------------------------------- |
| Combined label      | One row label made from Product Family and Billing Frequency.              |
| Same grouping level | Join both values into one label instead of nesting them.                   |
| Sequence            | Put Product Family first and Billing Frequency second.                     |
| Composite separator | The text between the values; the shipped blank value uses the default `/`. |
| Maximum groups      | Stop generation if unexpected data creates more than 50 combinations.      |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Open **Family and Billing Composite**. Enter or confirm these values:

| Field               | Value                                                 |
| ------------------- | ----------------------------------------------------- |
| Active              | `Selected`                                            |
| Table Code          | `FAMILY_BILLING_COMPOSITE`                            |
| Display Title       | `Family and Billing Summary`                          |
| Composite Separator | `Blank; generated labels use the default / separator` |
| Measure Set         | `PRICE_WATERFALL`                                     |
| Amount Basis        | `Final Value`                                         |
| Line Filter         | `EXCLUDE_OPTIONAL`                                    |

4. Save the table definition.
5. Return to **Custom Metadata Types**, find **Quote Document Grouping**, and select **Manage Records**.
6. Confirm **FAMILY_BILLING_FAMILY** is Level `1`, Sequence `10`, Dimension `PRODUCT_FAMILY`.
7. Confirm **FAMILY_BILLING_FREQUENCY** is Level `1`, Sequence `20`, Dimension `BILLING_FREQUENCY`.
8. Save only if a value required correction.
9. Generate document data for the calculated sandbox Quote.

## Worked example

```text
Software / Monthly        $1,500
Software / Annual         $12,000
Services / One-Time        $4,000
```

The three rows must remain distinct and total $17,500.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the table.
3. Its Quote Document Rows contain the displayed lines and totals.
4. Open **Reports → CPQ Document Totals → Quote Doc - Family & Billing Composite** and filter it to the test Quote.
5. The final document shows the same saved values; the document template does not recalculate them.

## Troubleshooting

| Problem                         | What it means                                      | What to do                                                                |
| ------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------- |
| Label contains a blank part     | Product Family or Billing Frequency is missing.    | Correct the Product or Quote Line, calculate, and generate again.         |
| Values are nested               | The grouping levels differ.                        | Set both grouping records to Level `1`.                                   |
| Billing frequency appears first | Sequences are reversed.                            | Restore Product Family Sequence `10` and Billing Frequency Sequence `20`. |
| Status is Failed                | Data exceeded a guard or configuration is invalid. | Read **Document Data Error** and correct the named cause.                 |

## Deactivate or roll back

Clear **Active** on **Family and Billing Composite**, save, and generate again. Restore the shipped values to reactivate. Do not delete generated records manually.

## Production checklist

- [ ] Every included line has both source values.
- [ ] Labels use Product Family first and Billing Frequency second.
- [ ] No more than 50 combinations are expected.
- [ ] Rows reconcile to the payable Quote total.
- [ ] The named report and document preview match the generated rows.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source Quote data, and generate again.
