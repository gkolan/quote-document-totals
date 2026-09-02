# Bundle and Product Change Detail

## Status and scope

**Repository status:** The inactive `BUNDLE_PRODUCT_GRID` definition, Bundle grouping, displayed columns, and **Quote Document - Bundle and Product Grid** report ship.

**Org verification status:** Bundle detail generation is tested; amendment classification remains provisional for the target org.

## Use case scenario

An amendment document needs each bundle as a section with the changed products shown inside it.

## What this produces

Salesforce creates one or more `Quote_Document_Table__c` records and the related `Quote_Document_Row__c` records needed for this view. The saved values can be reviewed in Salesforce before they are sent to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Assign the `CPQ_Document_Totals` permission set.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Create a real amendment that adds, removes, and moves components between bundles.

**Stop here if** removed components lose their expected parent context, moved products cannot be assigned clearly, or this detail disagrees with Bundle Totals.

## Terms in plain language

| Setting               | Meaning                                                   |
| --------------------- | --------------------------------------------------------- |
| Bundle section        | Parent heading under which changed component rows appear. |
| Show Details selected | Print individual changed products.                        |
| `CHANGE`              | Save before, after, and difference amounts.               |
| Bundle change         | Sum of counted component changes in that section.         |
| Provisional           | Keep inactive until real amendment proof passes.          |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Open **Bundle & Product Detail Grid**. Enter or confirm these values:

| Field         | Value                                                   |
| ------------- | ------------------------------------------------------- |
| Active        | `Keep cleared until amendment verification is complete` |
| Table Code    | `BUNDLE_PRODUCT_GRID`                                   |
| Display Title | `Products by Bundle`                                    |
| Measure Set   | `CHANGE`                                                |
| Amount Basis  | `Net Change`                                            |
| Line Filter   | `EXCLUDE_OPTIONAL`                                      |
| Show Details  | `Selected`                                              |

4. Save the table definition.
5. From **Custom Metadata Types**, open **Quote Document Grouping** and select **Manage Records**.
6. Open **Bundle Product Grid - BUNDLE** and confirm Dimension `BUNDLE`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Keep **Active** cleared until real-amendment verification passes.
9. Activate only for a controlled test and deactivate while correcting discrepancies.

## Worked example

```text
Sales Suite
  Platform Licenses        +$5,000
  Analytics                 +$1,000
Bundle change               +$6,000
```

Platform Licenses +$5,000 and Analytics +$1,000 beneath Sales Suite must equal the +$6,000 Bundle change.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the generated table or tables.
3. Quote Document Rows show the saved details, subtotals, and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Bundle and Product Grid** and filter to the amendment Quote.
5. The final document shows these saved values without recalculating them.

## Troubleshooting

| Problem                             | What it means                                   | What to do                                                |
| ----------------------------------- | ----------------------------------------------- | --------------------------------------------------------- |
| Product appears under wrong bundle  | Source or baseline bundle relationship differs. | Compare both Quotes and keep inactive until resolved.     |
| Removed component disappears        | Provisional matching did not preserve context.  | Record the mismatch and do not fix it in the template.    |
| Detail does not equal bundle change | A row is missing or counted incorrectly.        | Inspect inclusion flags and reconcile every component.    |
| Status is Failed                    | Generation rejected comparison data.            | Read **Document Data Error** and correct the named cause. |

## Deactivate or roll back

The shipped definition is inactive. Clear **Active** after testing and generate again. Never delete generated records manually.

## Production checklist

- [ ] Real CPQ amendment used.
- [ ] Added, removed, and moved components tested.
- [ ] Every detail row has expected bundle context.
- [ ] Detail adds to Bundle Totals exactly.
- [ ] Definition remains inactive until approval.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source data, and generate again.
