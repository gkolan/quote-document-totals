# Discount Summary

## Status and scope

**Repository status:** The active `DISCOUNT_SUMMARY` definition, its Product Family grouping, the **Quote Document - Discount Summary** report, and `scripts/apex/discount-summary-example.apex` ship in the repository.

**Org verification status:** Repository tests cover saved list, discount, and net amounts. Deployment and execution in the target org are not verified here.

## Use case scenario

A Quote contains discounts across several Product Families. The document needs to show where the discount was applied and how it affects the net total.

## What this produces

Salesforce creates one `Quote_Document_Table__c` record for this view and `Quote_Document_Row__c` records for the displayed lines. The same saved result can be viewed in Salesforce Reports and passed to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Confirm the `CPQ_Document_Totals` permission set is assigned.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Calculate the test Quote and confirm its CPQ list, discount, and net amounts before generation.

**Stop here if** the Quote has a pending calculation, the expected discount is not visible in CPQ, or the permission set and generation action are unavailable.

## Terms in plain language

| Setting                 | Meaning                                                         |
| ----------------------- | --------------------------------------------------------------- |
| Price waterfall         | The path from list amount through discount to final net amount. |
| Final Value             | Use CPQ's final calculated values.                              |
| Product Family grouping | Keep related discounted products together.                      |
| Show Details selected   | Save individual product rows beneath each family.               |
| Generated rows          | The saved values the report and document display.               |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Open **Discount Summary**. Enter or confirm these values:

| Field         | Value              |
| ------------- | ------------------ |
| Active        | `Selected`         |
| Table Code    | `DISCOUNT_SUMMARY` |
| Display Title | `Discount Summary` |
| Measure Set   | `PRICE_WATERFALL`  |
| Amount Basis  | `Final Value`      |
| Line Filter   | `EXCLUDE_OPTIONAL` |
| Show Details  | `Selected`         |

4. Save the table definition.
5. Return to **Custom Metadata Types**, find **Quote Document Grouping**, and select **Manage Records**.
6. Open **Discount Summary - PRODUCT_FAMILY** and confirm Dimension `PRODUCT_FAMILY`, Level `1`, and Sequence `10`.
7. Save the grouping record.
8. Select **Active**, save, and generate document data for a representative sandbox Quote. If the result is wrong, clear **Active** before making corrections. Leave it selected for general use only after the rows and totals are correct.

## Worked example

```text
Software list price       $20,000
Discount                  -$2,000
Software net              $18,000
```

Use one Software line with a $20,000 list amount, a $2,000 discount, and an $18,000 net amount. The saved arithmetic must satisfy $20,000 - $2,000 = $18,000.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the table.
3. Its Quote Document Rows contain the displayed lines and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Discount Summary** and filter it to the test Quote.
5. The final document shows the same saved values; the document template does not recalculate them.

## Troubleshooting

| Problem                               | What it means                                              | What to do                                                          |
| ------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------- |
| Discount is zero                      | CPQ did not save a discount on the calculated line.        | Correct pricing, calculate, and generate again.                     |
| Net does not equal list less discount | Source pricing is stale or the wrong fields are displayed. | Recalculate, inspect saved rows, and verify the configured columns. |
| Optional products appear              | The line filter or Optional checkbox is wrong.             | Restore `EXCLUDE_OPTIONAL` or correct the Quote Line.               |
| Status is Failed                      | Generation rejected data or configuration.                 | Read **Document Data Error** and correct the named cause.           |

## Deactivate or roll back

Clear **Active** on **Discount Summary**, save, and generate again. Never delete generated rows by hand. Restore the exact settings in this guide to reactivate it.

## Production checklist

- [ ] The Quote is fully calculated.
- [ ] List less discount equals net for the worked example.
- [ ] Optional lines are excluded.
- [ ] The named report matches the generated records.
- [ ] The document displays saved values without recalculation.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source Quote data, and generate again.
