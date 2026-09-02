# Bundle Change Summary

## Status and scope

**Repository status:** The inactive `BUNDLE_SUMMARY` definition, Bundle grouping, displayed columns, and **Quote Document - Bundle Totals** report ship.

**Org verification status:** Bundle aggregation is tested; amendment classification remains provisional for the target org.

## Use case scenario

An amendment document needs one change total for each bundle rather than a long list of component changes.

## What this produces

Salesforce creates one or more `Quote_Document_Table__c` records and the related `Quote_Document_Row__c` records needed for this view. The saved values can be reviewed in Salesforce before they are sent to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Assign the `CPQ_Document_Totals` permission set.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Create a real amendment with changed, removed, and unchanged bundle components.

**Stop here if** component-to-parent relationships are missing, standalone products need bundle treatment, or bundle totals disagree with product and transaction views.

## Terms in plain language

| Setting              | Meaning                                           |
| -------------------- | ------------------------------------------------- |
| Bundle grouping      | Roll component changes up to their parent bundle. |
| `CHANGE`             | Save before, after, and difference amounts.       |
| Net Change           | Combined component impact for each bundle.        |
| Show Details cleared | Print one row per bundle.                         |
| Provisional          | Keep inactive until real amendment proof passes.  |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Open **Bundle Totals**. Enter or confirm these values:

| Field         | Value                                                   |
| ------------- | ------------------------------------------------------- |
| Active        | `Keep cleared until amendment verification is complete` |
| Table Code    | `BUNDLE_SUMMARY`                                        |
| Display Title | `Bundle Summary`                                        |
| Measure Set   | `CHANGE`                                                |
| Amount Basis  | `Net Change`                                            |
| Line Filter   | `EXCLUDE_OPTIONAL`                                      |
| Show Details  | `Cleared`                                               |

4. Save the table definition.
5. From **Custom Metadata Types**, open **Quote Document Grouping** and select **Manage Records**.
6. Open **Bundle Summary - BUNDLE** and confirm Dimension `BUNDLE`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Keep **Active** cleared until real-amendment verification passes.
9. Activate only for a controlled test and deactivate while correcting discrepancies.

## Worked example

```text
Sales Suite               +$6,000
Service Bundle            -$2,000
Net Change                +$4,000
```

Sales Suite +$6,000 and Service Bundle -$2,000 must produce Net Change +$4,000.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the generated table or tables.
3. Quote Document Rows show the saved details, subtotals, and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Bundle Totals** and filter to the amendment Quote.
5. The final document shows these saved values without recalculating them.

## Troubleshooting

| Problem                            | What it means                                     | What to do                                                |
| ---------------------------------- | ------------------------------------------------- | --------------------------------------------------------- |
| Component lands under wrong bundle | Bundle relationship is wrong or missing.          | Correct source configuration and regenerate.              |
| Bundle change double-counts parent | Parent and component inclusion overlap.           | Keep inactive and inspect generated inclusion flags.      |
| Bundle total disagrees with detail | A component is missing or classified differently. | Reconcile with Bundle and Product Grid.                   |
| Status is Failed                   | Generation rejected comparison data.              | Read **Document Data Error** and correct the named cause. |

## Deactivate or roll back

The shipped definition is inactive. Clear **Active** after testing and generate again. Do not delete generated records manually.

## Production checklist

- [ ] Real CPQ amendment used.
- [ ] Added, removed, and unchanged components tested.
- [ ] No parent/component double count exists.
- [ ] Bundle summary and detail agree.
- [ ] Definition remains inactive until approval.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source data, and generate again.
