# Free Periods and Promotional Pricing

## Status and scope

**Repository status:** Zero-weight allocation is implemented and tested. No `PROMOTIONAL_SCHEDULE` definition, promotion schedule records, grouping, columns, dedicated report, or example script ships.

**Org verification status:** The mechanism is tested; the target promotion, wording, and amounts are not verified.

## Use case scenario

A subscription includes a free introductory period followed by paid periods. The free period must appear as exactly zero.

## What this produces

Salesforce creates one `Quote_Document_Table__c` record for this view and `Quote_Document_Row__c` records for the displayed lines. The same saved result can be viewed in Salesforce Reports and passed to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Confirm the `CPQ_Document_Totals` permission set is assigned.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Obtain the signed promotion schedule and a customer-facing explanation for the zero-price period.

**Stop here if** the Quote total does not already reflect the promotion, the free period is not contractually approved, or the wording is missing. This table explains CPQ pricing; it does not create a discount.

## Terms in plain language

| Setting             | Meaning                                                                   |
| ------------------- | ------------------------------------------------------------------------- |
| Zero weight         | Allocate exactly $0 to that period while still printing it.               |
| Positive weight     | Give a paid period a relative share of the final Quote amount.            |
| Schedule code       | One permanent identifier shared by the definition and its period records. |
| Allocation residual | A rounding difference; it must never be placed in a free period.          |
| Narrative           | Saved text explaining why a visible period is $0.                         |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Create a new record. Enter or confirm these values:

| Field               | Value                          |
| ------------------- | ------------------------------ |
| Active              | `Cleared while configuring`    |
| Table Code          | `PROMOTIONAL_SCHEDULE`         |
| Table Name          | `Promotional Schedule`         |
| Display Title       | `Promotional Payment Schedule` |
| Display Order       | `110`                          |
| Expander Code       | `SCHEDULE`                     |
| Expander Version    | `1`                            |
| Schedule Code       | `PROMO_INTRO_2_FREE`           |
| Allocation Basis    | `EVEN`                         |
| Allocation Scale    | `2`                            |
| Sort Groups By      | `EXPANSION_ORDER`              |
| Measure Set         | `PRICE_WATERFALL`              |
| Amount Basis        | `Final Value`                  |
| Line Filter         | `EXCLUDE_OPTIONAL`             |
| Show Section Totals | `Cleared`                      |

4. Save the table definition.
5. Return to **Custom Metadata Types**, find **Quote Document Grouping**, and select **Manage Records**.
6. Create **PROMOTIONAL_SCHEDULE_EXPANSION** with Dimension `EXPANSION`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Return to **Custom Metadata Types**, find **Quote Document Schedule**, and select **Manage Records**.
9. Create these three active records:

| Record label                | Schedule Code        | Bucket Code    | Label Key      | Weight | Display Order |
| --------------------------- | -------------------- | -------------- | -------------- | -----: | ------------: |
| Promo - Introductory Period | `PROMO_INTRO_2_FREE` | `PROMO_INTRO`  | `PROMO_INTRO`  |      0 |            10 |
| Promo - Paid Period 1       | `PROMO_INTRO_2_FREE` | `PROMO_PAID_1` | `PROMO_PAID_1` |      1 |            20 |
| Promo - Paid Period 2       | `PROMO_INTRO_2_FREE` | `PROMO_PAID_2` | `PROMO_PAID_2` |      1 |            30 |

10. In **Quote Document Key Value**, create these records. Set **Category** to `LABELS_en_US` for all three: key `PROMO_INTRO`, value `Introductory Period`; key `PROMO_PAID_1`, value `Paid Period 1`; and key `PROMO_PAID_2`, value `Paid Period 2`.
11. No column records are required for the first test. Salesforce creates the normal `PRICE_WATERFALL` columns when a table has no active column records of its own.
12. Return to the table definition, select **Active**, save, and generate the worked-example Quote. If the result is wrong, clear **Active** before making corrections.

## Worked example

```text
Introductory Period           $0
Paid Period 1              $6,000
Paid Period 2              $6,000
Grand Total               $12,000
```

Create three schedule records under `PROMO_INTRO_2_FREE`: Introductory Period, order 10, weight 0; Paid Period 1, order 20, weight 1; Paid Period 2, order 30, weight 1. A $12,000 Quote becomes $0, $6,000, and $6,000.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the table.
3. Its Quote Document Rows contain the displayed lines and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the Quote and `PROMOTIONAL_SCHEDULE`.
5. The final document shows the same saved values; the document template does not recalculate them.

## Troubleshooting

| Problem                 | What it means                                 | What to do                                                   |
| ----------------------- | --------------------------------------------- | ------------------------------------------------------------ |
| Free period is missing  | Zero-weight rows are being hidden.            | Restore the schedule row and verify generated visibility.    |
| Free period shows $0.01 | Rounding residual was assigned incorrectly.   | Deactivate the definition and correct allocation before use. |
| Total differs from CPQ  | The table is repricing instead of allocating. | Restore Final Value and compare saved shares.                |
| Status is Failed        | Weights or configuration are invalid.         | Read **Document Data Error** and correct the named cause.    |

## Deactivate or roll back

Keep the new definition inactive until the $0 period and total pass. To roll back, clear **Active**, save, and generate again. Never delete generated rows manually.

## Production checklist

- [ ] CPQ already contains the approved promotional price.
- [ ] The free period has weight 0 and remains visible.
- [ ] Paid periods have positive weights.
- [ ] No rounding amount lands in the free period.
- [ ] Saved explanatory text is visible.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source Quote data, and generate again.
