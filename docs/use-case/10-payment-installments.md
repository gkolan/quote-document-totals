# Payment Installments and Milestones

## Status and scope

**Repository status:** Allocation behavior and the three `PAYMENT_MILESTONES` schedule records ship and are tested. The repository does not ship a `PAYMENT_INSTALLMENTS` table definition, grouping, columns, dedicated report, or example script.

**Org verification status:** The 30/40/30 arithmetic is asserted in automated tests. An administrator must create inactive metadata and verify it in the target sandbox.

## Use case scenario

A $60,000 Quote is payable 30% at signing, 40% at delivery, and 30% at acceptance.

## What this produces

Salesforce creates one `Quote_Document_Table__c` record for this view and `Quote_Document_Row__c` records for the displayed lines. The same saved result can be viewed in Salesforce Reports and passed to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Confirm the `CPQ_Document_Totals` permission set is assigned.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Confirm the signed payment terms are exactly 30% at signing, 40% at delivery, and 30% at acceptance.

**Stop here if** those terms differ, the Quote is not final, or your document must show invoice or payment status. This table shows agreed terms; it does not track collections.

## Terms in plain language

| Setting              | Meaning                                                                |
| -------------------- | ---------------------------------------------------------------------- |
| Schedule             | Named milestone rows and their relative weights.                       |
| Weight               | Each milestone's share; 30, 40, and 30 divide the Quote in that ratio. |
| Allocation Scale `2` | Round currency to two decimal places and place any residual safely.    |
| `EXPANSION`          | Group the generated shares by milestone.                               |
| Inactive first       | Prevent incomplete metadata from affecting document generation.        |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Create a new record. Enter or confirm these values:

| Field               | Value                       |
| ------------------- | --------------------------- |
| Active              | `Cleared while configuring` |
| Table Code          | `PAYMENT_INSTALLMENTS`      |
| Table Name          | `Payment Installments`      |
| Display Title       | `Payment Schedule`          |
| Display Order       | `100`                       |
| Expander Code       | `SCHEDULE`                  |
| Expander Version    | `1`                         |
| Schedule Code       | `PAYMENT_MILESTONES`        |
| Allocation Basis    | `EVEN`                      |
| Allocation Scale    | `2`                         |
| Sort Groups By      | `EXPANSION_ORDER`           |
| Measure Set         | `PRICE_WATERFALL`           |
| Amount Basis        | `Final Value`               |
| Line Filter         | `EXCLUDE_OPTIONAL`          |
| Show Section Totals | `Cleared`                   |

4. Save the table definition.
5. Return to **Custom Metadata Types**, find **Quote Document Grouping**, and select **Manage Records**.
6. Create grouping record **PAYMENT_INSTALLMENTS_EXPANSION** with Table Definition `PAYMENT_INSTALLMENTS`, Dimension `EXPANSION`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Return to **Custom Metadata Types**, find **Quote Document Schedule**, and select **Manage Records**.
9. Confirm the three shipped active records below. Do not create duplicates.

| Label                           | Schedule Code        | Bucket Code            | Label Key              | Weight | Display Order |
| ------------------------------- | -------------------- | ---------------------- | ---------------------- | -----: | ------------: |
| Payment Milestones - Signing    | `PAYMENT_MILESTONES` | `MILESTONE_SIGNING`    | `MILESTONE_SIGNING`    |     30 |            10 |
| Payment Milestones - Delivery   | `PAYMENT_MILESTONES` | `MILESTONE_DELIVERY`   | `MILESTONE_DELIVERY`   |     40 |            20 |
| Payment Milestones - Acceptance | `PAYMENT_MILESTONES` | `MILESTONE_ACCEPTANCE` | `MILESTONE_ACCEPTANCE` |     30 |            30 |

10. No column records are required for the first test. With no active column records for `PAYMENT_INSTALLMENTS`, Salesforce creates the normal label, list, discount, and net columns for `PRICE_WATERFALL`.
11. Return to the table definition, select **Active**, save, and generate the worked-example Quote. If the result is wrong, clear **Active** before making corrections.

## Worked example

```text
Signing — 30%            $18,000
Delivery — 40%           $24,000
Acceptance — 30%         $18,000
Grand Total              $60,000
```

The three shares are $18,000, $24,000, and $18,000. They must add to $60,000 exactly.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the table.
3. Its Quote Document Rows contain the displayed lines and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the Quote and `PAYMENT_INSTALLMENTS`.
5. The final document shows the same saved values; the document template does not recalculate them.

## Troubleshooting

| Problem                       | What it means                                          | What to do                                                             |
| ----------------------------- | ------------------------------------------------------ | ---------------------------------------------------------------------- |
| A milestone is missing        | Its schedule record is inactive or has the wrong code. | Restore `PAYMENT_MILESTONES` and activate all three rows.              |
| Amounts do not add to $60,000 | Source total or weights differ.                        | Compare the calculated Quote and schedule records.                     |
| Quantity prints as zero       | Quantity has no meaning for a payment milestone.       | Remove the Quantity column; do not represent “not applicable” as zero. |
| Status is Failed              | Allocation validation rejected the setup.              | Read **Document Data Error** and correct the named cause.              |

## Deactivate or roll back

Keep the new definition inactive until verification passes. To remove it later, clear **Active**, save, and generate again. Do not delete generated rows manually.

## Production checklist

- [ ] Signed terms match 30/40/30.
- [ ] All three shipped schedule records are active.
- [ ] The grouping and displayed columns are complete.
- [ ] Shares add to the Quote net amount exactly.
- [ ] The output does not imply that payment was received.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source Quote data, and generate again.
