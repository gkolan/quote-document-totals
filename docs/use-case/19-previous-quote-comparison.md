# Previous Quote Comparison

## Status and scope

**Repository status:** The `SOURCE_QUOTE` comparison source and tests ship. No `PREVIOUS_QUOTE_COMPARISON` definition, grouping, columns, dedicated report, or example script ships.

**Org verification status:** Source-Quote comparison is tested. The target org's revision process and Quote access are not verified.

## Use case scenario

A revised proposal needs to show how the current Quote differs from an earlier Quote revision.

## What this produces

Salesforce creates one or more `Quote_Document_Table__c` records and the related `Quote_Document_Row__c` records needed for this view. The saved values can be reviewed in Salesforce before they are sent to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Assign the `CPQ_Document_Totals` permission set.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Create the revision through CPQ so `SBQQ__Source__c` points to the earlier Quote.

**Stop here if** `SBQQ__Source__c` is blank, points to the wrong revision, or the generating user cannot read the earlier Quote and its lines.

## Terms in plain language

| Setting           | Meaning                                                                     |
| ----------------- | --------------------------------------------------------------------------- |
| Source Quote      | The earlier Quote revision used as the baseline.                            |
| `SBQQ__Source__c` | Standard CPQ lookup populated on a revision; used here by exact field path. |
| `SOURCE_QUOTE`    | Compare current Quote Lines with the readable source Quote.                 |
| Version `1`       | Current comparison behavior identity.                                       |
| `CHANGE`          | Save previous, current, and difference amounts.                             |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Create a new record. Enter or confirm these values:

| Field                     | Value                         |
| ------------------------- | ----------------------------- |
| Active                    | `Cleared while configuring`   |
| Table Code                | `PREVIOUS_QUOTE_COMPARISON`   |
| Table Name                | `Previous Quote Comparison`   |
| Display Title             | `Changes from Previous Quote` |
| Display Order             | `190`                         |
| Comparison Source Code    | `SOURCE_QUOTE`                |
| Comparison Source Version | `1`                           |
| Comparison Source Field   | `SBQQ__Source__c`             |
| Measure Set               | `CHANGE`                      |
| Amount Basis              | `Net Change`                  |
| Line Filter               | `EXCLUDE_OPTIONAL`            |

4. Save the table definition.
5. From **Custom Metadata Types**, open **Quote Document Grouping** and select **Manage Records**.
6. Create **PREVIOUS_QUOTE_COMPARISON_PRODUCT_FAMILY** with Table Definition `PREVIOUS_QUOTE_COMPARISON`, Dimension `PRODUCT_FAMILY`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Keep **Active** cleared until the worked example passes.
9. Activate only for the controlled sandbox generation, then deactivate while correcting discrepancies.

## Worked example

```text
Software     Previous $12,000   Current $15,000   Change +$3,000
Services     Previous  $4,000   Current  $3,000   Change -$1,000
```

Use a source Quote with Software $12,000 and Services $4,000, then a revision with Software $15,000 and Services $3,000. Changes are +$3,000 and -$1,000; net change is +$2,000.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the generated table or tables.
3. Quote Document Rows show the saved details, subtotals, and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the current Quote and `PREVIOUS_QUOTE_COMPARISON`.
5. The final document shows these saved values without recalculating them.

## Troubleshooting

| Problem                           | What it means                                         | What to do                                                |
| --------------------------------- | ----------------------------------------------------- | --------------------------------------------------------- |
| Every line is added               | `SBQQ__Source__c` is blank or wrong.                  | Correct the revision relationship and generate again.     |
| Generation says source is missing | User cannot read the earlier Quote or it was deleted. | Restore access or select a valid readable source Quote.   |
| Rows match the wrong revision     | Source lookup points to another Quote.                | Correct it and generate again.                            |
| Status is Failed                  | Comparison validation rejected the source.            | Read **Document Data Error** and correct the named cause. |

## Deactivate or roll back

Clear **Active**, save, and generate again to remove the comparison from the current output. Do not delete generated records manually.

## Production checklist

- [ ] `SBQQ__Source__c` points to the intended revision.
- [ ] Generating users can read both Quotes and their lines.
- [ ] Added, removed, and changed lines were tested.
- [ ] Previous/current/change arithmetic reconciles.
- [ ] Rendered View and document preview match saved rows.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source data, and generate again.
