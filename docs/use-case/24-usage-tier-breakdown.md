# Usage Pricing Tier Breakdown

## Status and scope

**Repository status:** The `CONSUMPTION_TIER` expansion behavior and tests ship. No `USAGE_TIER_BREAKDOWN` definition, grouping, columns, dedicated report, or example script ships.

**Org verification status:** Reading CPQ consumption schedules is tested. The target org's schedules, rates, currencies, and output are not verified.

## Use case scenario

A usage-based Quote Line must show the Salesforce CPQ consumption pricing tiers that support the quoted amount.

## What this produces

Salesforce creates one or more `Quote_Document_Table__c` records and the related `Quote_Document_Row__c` records needed for this view. The saved values can be reviewed in Salesforce before they are sent to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Assign the `CPQ_Document_Totals` permission set.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Use a calculated usage Quote Line with an active CPQ Consumption Schedule and complete rate tiers.

**Stop here if** any included usage line has no Consumption Schedule, tiers overlap or have gaps, currencies differ, or the request is to calculate forecast usage. This table prints existing CPQ rates only.

## Terms in plain language

| Setting              | Meaning                                                         |
| -------------------- | --------------------------------------------------------------- |
| Consumption Schedule | CPQ record that holds usage pricing tiers.                      |
| Consumption Rate     | Lower boundary, upper boundary, and price for one tier.         |
| `CONSUMPTION_TIER`   | Create a document row from each existing CPQ rate tier.         |
| `RECURRING_ONLY`     | Include recurring usage products and exclude one-time products. |
| Display only         | This table does not price actual or forecast consumption.       |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Create a new record. Enter or confirm these values:

| Field               | Value                       |
| ------------------- | --------------------------- |
| Active              | `Cleared while configuring` |
| Table Code          | `USAGE_TIER_BREAKDOWN`      |
| Table Name          | `Usage Tier Breakdown`      |
| Display Title       | `Usage Pricing Tiers`       |
| Display Order       | `240`                       |
| Expander Code       | `CONSUMPTION_TIER`          |
| Expander Version    | `1`                         |
| Allocation Basis    | `EVEN`                      |
| Allocation Scale    | `2`                         |
| Sort Groups By      | `EXPANSION_ORDER`           |
| Measure Set         | `PRICE_WATERFALL`           |
| Amount Basis        | `Final Value`               |
| Line Filter         | `RECURRING_ONLY`            |
| Show Details        | `Selected`                  |
| Show Section Totals | `Cleared`                   |

4. Save the table definition.
5. From **Custom Metadata Types**, open **Quote Document Grouping** and select **Manage Records**.
6. Create **USAGE_TIER_BREAKDOWN_EXPANSION** with Table Definition `USAGE_TIER_BREAKDOWN`, Dimension `EXPANSION`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Keep **Active** cleared until every CPQ tier matches the worked example output.
9. Activate only for the controlled sandbox test.

## Worked example

```text
0–10,000 units             $2,000
10,001–25,000 units        $2,250
Total quoted usage         $4,250
```

Configure CPQ so the first tier contributes $2,000 and the second contributes $2,250 to the quoted amount. The saved rows must total $4,250 without recomputing the rates.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the generated table or tables.
3. Quote Document Rows show the saved details, subtotals, and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the Quote and `USAGE_TIER_BREAKDOWN`.
5. The final document shows these saved values without recalculating them.

## Troubleshooting

| Problem                            | What it means                                               | What to do                                                 |
| ---------------------------------- | ----------------------------------------------------------- | ---------------------------------------------------------- |
| A tier is missing                  | CPQ rate data is absent, inactive, or inaccessible.         | Correct the Consumption Schedule and calculate again.      |
| Tier boundaries overlap            | Source CPQ configuration is invalid for clear presentation. | Correct the CPQ rates before generation.                   |
| Document amount differs from Quote | A template is repricing or saved tiers are stale.           | Compare generated rows and remove template calculations.   |
| Status is Failed                   | Required tier data is missing.                              | Read **Document Data Error** and correct the named record. |

## Deactivate or roll back

Keep this unshipped definition inactive until tiers and totals pass. Clear **Active** and generate again to roll back. Do not delete generated rows manually.

## Production checklist

- [ ] Every usage line has a complete CPQ Consumption Schedule.
- [ ] Tier boundaries and currencies are correct.
- [ ] Generated tiers match CPQ records exactly.
- [ ] Tier amounts add to the quoted amount.
- [ ] The document performs no usage calculation.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source data, and generate again.
