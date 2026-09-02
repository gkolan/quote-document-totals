# Bundle Price Allocation

## Status and scope

**Repository status:** The registered `PACKAGE_COMPOSITION` row adjustment and its allocation behavior are implemented and tested. No `BUNDLE_PRICE_ALLOCATION` definition, grouping, columns, dedicated report, or example script ships.

**Org verification status:** Even allocation for zero-list-price components is tested. The target org's bundle pricing policy is not verified.

## Use case scenario

A bundle carries one price while its component Quote Lines are zero. The document needs a price beside each component without counting the bundle price twice.

## What this produces

Salesforce creates one `Quote_Document_Table__c` record for this view and `Quote_Document_Row__c` records for the displayed lines. The same saved result can be viewed in Salesforce Reports and passed to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Confirm the `CPQ_Document_Totals` permission set is assigned.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Obtain written approval to allocate zero-list-price components evenly for the first test.

**Stop here if** components require fair-value, cost, list-price, or revenue-allocation weights. Those policies require an approved weight source and a separately tested configuration.

## Terms in plain language

| Setting                        | Meaning                                                                                      |
| ------------------------------ | -------------------------------------------------------------------------------------------- |
| Package composition adjustment | Registered Salesforce code that moves the package amount to its components.                  |
| Even share                     | When component list amounts are all zero, give each eligible component an equal share.       |
| Counted row                    | A row included in totals. Component shares count; the displayed parent does not count again. |
| Source check                   | Component shares must add back to the parent price.                                          |
| Bundle grouping                | Keeps parent and component rows together.                                                    |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Create a new record based on the Bundle Detail pattern. Enter or confirm these values:

| Field                  | Value                       |
| ---------------------- | --------------------------- |
| Active                 | `Cleared while configuring` |
| Table Code             | `BUNDLE_PRICE_ALLOCATION`   |
| Table Name             | `Bundle Price Allocation`   |
| Display Title          | `Bundle Price Allocation`   |
| Display Order          | `160`                       |
| Measure Set            | `PRICE_WATERFALL`           |
| Amount Basis           | `Final Value`               |
| Line Filter            | `ALL`                       |
| Show Details           | `Selected`                  |
| Row Customizer Code    | `PACKAGE_COMPOSITION`       |
| Row Customizer Version | `1`                         |
| Cache Policy           | `STANDARD`                  |

4. Save the table definition.
5. Return to **Custom Metadata Types**, find **Quote Document Grouping**, and select **Manage Records**.
6. Create **BUNDLE_PRICE_ALLOCATION_BUNDLE** with Dimension `BUNDLE`, Level `1`, Sequence `10`. Do not add another grouping in the first test.
7. Save the grouping record.
8. Select **Active**, save, and generate document data for a representative sandbox Quote. If the result is wrong, clear **Active** before making corrections. Leave it selected for general use only after the rows and totals are correct.

## Worked example

```text
Platform Bundle            $12,000  (not counted again)
  Core Component            $6,000
  Analytics Component       $6,000
Counted total              $12,000
```

Use one $12,000 parent with two zero-list-price components. `PACKAGE_COMPOSITION` produces $6,000 per component; the parent may display $12,000 but must not count again. If component list amounts are populated, the adjustment uses those values as relative weights instead of dividing evenly.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the table.
3. Its Quote Document Rows contain the displayed lines and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the Quote and `BUNDLE_PRICE_ALLOCATION`.
5. The final document shows the same saved values; the document template does not recalculate them.

## Troubleshooting

| Problem                        | What it means                                                 | What to do                                                                      |
| ------------------------------ | ------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Total is $24,000               | Parent and component shares both count.                       | Deactivate immediately and correct inclusion flags.                             |
| Components are not $6,000 each | A component has a nonzero list amount or eligibility differs. | Confirm two eligible zero-list components and inspect their saved list amounts. |
| A component is missing         | Bundle relationship or filter is wrong.                       | Correct the Quote bundle, calculate, and generate again.                        |
| Status is Failed               | Source check or configuration failed.                         | Read **Document Data Error** and correct the named cause.                       |

## Deactivate or roll back

Keep the definition inactive until the $12,000 source check passes. Clear **Active** and generate again to roll back. Do not delete generated rows manually.

## Production checklist

- [ ] Equal allocation for zero-list components has written business approval.
- [ ] Exactly two eligible components produce $6,000 each.
- [ ] Parent is excluded from counted totals.
- [ ] Component shares add to $12,000 exactly.
- [ ] Report and document preview match saved inclusion flags.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source Quote data, and generate again.
