# Amendment Before-and-After

## Status and scope

**Repository status:** The `AMENDED_SUBSCRIPTION` comparison source is implemented and tested against constructed Subscription records. No `AMENDMENT_COMPARISON` definition, grouping, columns, dedicated report, or example script ships.

**Org verification status:** Provisional. It has not been proven against a real Salesforce CPQ amendment created through the target org's amendment process.

## Use case scenario

An amendment Quote must show the customer’s existing subscription amount, the amended amount, and the difference.

## What this produces

Salesforce creates one or more `Quote_Document_Table__c` records and the related `Quote_Document_Row__c` records needed for this view. The saved values can be reviewed in Salesforce before they are sent to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Assign the `CPQ_Document_Totals` permission set.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Create a contracted Quote and its amendment through Salesforce CPQ; do not hand-build the amendment Quote.

**Stop here if** the amendment was not created by CPQ, amended Quote Lines do not reference the subscriptions they change, or anyone expects this provisional pattern to be enabled in production before row-by-row proof.

## Terms in plain language

| Setting                | Meaning                                                                                |
| ---------------------- | -------------------------------------------------------------------------------------- |
| Baseline               | The existing Subscription values before the amendment.                                 |
| `AMENDED_SUBSCRIPTION` | Read the subscriptions referenced by the amendment Quote Lines.                        |
| Version `1`            | Identity for the current matching behavior; change it only when that behavior changes. |
| `CHANGE`               | Save before, after, and difference amounts.                                            |
| Net Change             | After amount minus before amount.                                                      |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Create a new record. Enter or confirm these values:

| Field                     | Value                  |
| ------------------------- | ---------------------- |
| Active                    | `Cleared`              |
| Table Code                | `AMENDMENT_COMPARISON` |
| Table Name                | `Amendment Comparison` |
| Display Title             | `Amendment Comparison` |
| Display Order             | `170`                  |
| Comparison Source Code    | `AMENDED_SUBSCRIPTION` |
| Comparison Source Version | `1`                    |
| Measure Set               | `CHANGE`               |
| Amount Basis              | `Net Change`           |
| Line Filter               | `EXCLUDE_OPTIONAL`     |

4. Save the table definition.
5. From **Custom Metadata Types**, open **Quote Document Grouping** and select **Manage Records**.
6. Create **AMENDMENT_COMPARISON_PRODUCT_FAMILY** with Table Definition `AMENDMENT_COMPARISON`, Dimension `PRODUCT_FAMILY`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Keep **Active** cleared until the worked example and a real amendment both pass.
9. Generate only in the controlled sandbox test after all related metadata is complete.

## Worked example

```text
Software     Before $10,000   After $14,000   Change +$4,000
Services     Before  $3,000   After  $2,000   Change -$1,000
```

Use a real amendment where Software moves from $10,000 to $14,000 and Services moves from $3,000 to $2,000. Changes are +$4,000 and -$1,000; net change is +$3,000.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the generated table or tables.
3. Quote Document Rows show the saved details, subtotals, and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the amendment Quote and `AMENDMENT_COMPARISON`.
5. The final document shows these saved values without recalculating them.

## Troubleshooting

| Problem                                | What it means                                                 | What to do                                                                                |
| -------------------------------------- | ------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Every line is shown as added           | Baseline Subscription links are missing.                      | Recreate the amendment through CPQ and inspect its Subscription references.               |
| Removed line is absent                 | The baseline match did not produce the expected removal.      | Keep the definition inactive and record the mismatch; do not patch the document template. |
| Before/after amounts disagree with CPQ | Classification or source fields are provisional for this org. | Compare each row with the contracted Quote and amendment.                                 |
| Status is Failed                       | Comparison validation rejected the source.                    | Read **Document Data Error** and correct the named cause.                                 |

## Deactivate or roll back

This definition starts inactive. If a test activated it, clear **Active**, save, and generate again. Do not delete generated rows manually.

## Production checklist

- [ ] Amendment was created through Salesforce CPQ.
- [ ] Every changed line has the correct baseline Subscription.
- [ ] Added, removed, increased, and decreased cases were tested.
- [ ] Every before, after, and change amount matches CPQ.
- [ ] The definition remains inactive until all tests pass.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source data, and generate again.
