# Transaction Change Summary

## Status and scope

**Repository status:** The inactive `TRANSACTION_SUMMARY` definition, `TRANSACTION_SUMMARY_TRANSACTION_TYPE` grouping, displayed columns, and **Quote Document - Transaction Type Totals** report ship.

**Org verification status:** Change aggregation is tested, but transaction classification remains provisional until compared with a real CPQ amendment in the target org.

## Use case scenario

An amendment document needs totals for products that were added, removed, cancelled, or otherwise changed.

## What this produces

Salesforce creates one or more `Quote_Document_Table__c` records and the related `Quote_Document_Row__c` records needed for this view. The saved values can be reviewed in Salesforce before they are sent to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Assign the `CPQ_Document_Totals` permission set.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Create a real amendment containing at least one addition, removal, and cancellation.

**Stop here if** the amendment was hand-built, any line's transaction category is unclear, or the four amendment views disagree. Keep all provisional definitions inactive.

## Terms in plain language

| Setting              | Meaning                                                             |
| -------------------- | ------------------------------------------------------------------- |
| Transaction Type     | Change category such as Added, Removed, or Cancelled.               |
| `CHANGE`             | Save before, after, and difference amounts.                         |
| Net Change           | Positive and negative changes added together.                       |
| Show Details cleared | Print category totals rather than product lines.                    |
| Provisional          | Built, but not approved for production until real-org proof passes. |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Open **Transaction Summary**. Enter or confirm these values:

| Field         | Value                                                   |
| ------------- | ------------------------------------------------------- |
| Active        | `Keep cleared until amendment verification is complete` |
| Table Code    | `TRANSACTION_SUMMARY`                                   |
| Display Title | `Transaction Summary`                                   |
| Measure Set   | `CHANGE`                                                |
| Amount Basis  | `Net Change`                                            |
| Line Filter   | `EXCLUDE_OPTIONAL`                                      |
| Show Details  | `Cleared`                                               |

4. Save the table definition.
5. From **Custom Metadata Types**, open **Quote Document Grouping** and select **Manage Records**.
6. Open **Transaction Summary - TRANSACTION_TYPE** and confirm Dimension `TRANSACTION_TYPE`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Keep **Active** cleared until the real-amendment proof passes.
9. Activate only for a controlled test, then clear it again while resolving any mismatch.

## Worked example

```text
Added                     +$8,000
Removed                   -$3,000
Cancelled                 -$1,000
Net Change                +$4,000
```

Added +$8,000, Removed -$3,000, and Cancelled -$1,000 must produce Net Change +$4,000.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the generated table or tables.
3. Quote Document Rows show the saved details, subtotals, and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Transaction Type Totals** and filter to the amendment Quote.
5. The final document shows these saved values without recalculating them.

## Troubleshooting

| Problem                         | What it means                                       | What to do                                                         |
| ------------------------------- | --------------------------------------------------- | ------------------------------------------------------------------ |
| A line has the wrong category   | Provisional classification does not match this org. | Keep inactive and compare the source line with CPQ amendment data. |
| Negative changes print positive | Sign handling or document formatting is wrong.      | Verify saved Amount Change before changing the document.           |
| Net Change is not +$4,000       | A category is missing or double-counted.            | Reconcile every generated row to the amendment.                    |
| Status is Failed                | Generation rejected comparison data.                | Read **Document Data Error** and correct the named cause.          |

## Deactivate or roll back

The shipped definition is inactive. If activated for testing, clear **Active**, save, and generate again. Do not delete generated records manually.

## Production checklist

- [ ] A real CPQ amendment was used.
- [ ] Added, removed, cancelled, and unchanged cases were reviewed.
- [ ] Signs and Net Change reconcile.
- [ ] All four amendment views agree.
- [ ] Definition remains inactive until approval.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source data, and generate again.
