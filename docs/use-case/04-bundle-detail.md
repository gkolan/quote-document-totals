# Bundle Detail

## Status and scope

**Repository status:** The active `BUNDLE_DETAIL` definition, its Bundle grouping, the **Quote Document - Bundle Detail** report, and `scripts/apex/bundle-detail-example.apex` ship in the repository.

**Org verification status:** Repository tests cover bundle grouping. Target-org deployment and bundle pricing behavior are not verified here.

## Use case scenario

A Quote contains configured bundles. The document needs to show each bundle and the products included inside it.

## What this produces

Salesforce creates one `Quote_Document_Table__c` record for this view and `Quote_Document_Row__c` records for the displayed lines. The same saved result can be viewed in Salesforce Reports and passed to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Confirm the `CPQ_Document_Totals` permission set is assigned.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Use a calculated Quote containing a real CPQ bundle parent and its option lines.

**Stop here if** the test products are not configured as a CPQ bundle, component Quote Lines have lost their bundle relationship, or the generation action is unavailable.

## Terms in plain language

| Setting               | Meaning                                                                  |
| --------------------- | ------------------------------------------------------------------------ |
| Bundle                | A configured parent product and the option lines that belong beneath it. |
| Bundle grouping       | Keeps each parent and its components in one document section.            |
| Show Details selected | Prints component Quote Lines.                                            |
| `EXCLUDE_OPTIONAL`    | Excludes optional Quote Lines from the payable section.                  |
| Saved result          | The generated Table and Row records used by reports and documents.       |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Open **Bundle Detail**. Enter or confirm these values:

| Field         | Value              |
| ------------- | ------------------ |
| Active        | `Selected`         |
| Table Code    | `BUNDLE_DETAIL`    |
| Display Title | `Bundle Detail`    |
| Measure Set   | `PRICE_WATERFALL`  |
| Amount Basis  | `Final Value`      |
| Line Filter   | `EXCLUDE_OPTIONAL` |
| Show Details  | `Selected`         |

4. Save the table definition.
5. Return to **Custom Metadata Types**, find **Quote Document Grouping**, and select **Manage Records**.
6. Open **Bundle Detail - BUNDLE** and confirm Dimension `BUNDLE`, Level `1`, and Sequence `10`.
7. Save the grouping record.
8. Select **Active**, save, and generate document data for a representative sandbox Quote. If the result is wrong, clear **Active** before making corrections. Leave it selected for general use only after the rows and totals are correct.

## Worked example

```text
Customer Success Bundle
  Platform Subscription   $18,000
  Onboarding Service       $3,000
Bundle subtotal            $21,000
```

Use a Customer Success Bundle with an $18,000 Platform Subscription and $3,000 Onboarding Service. Confirm the section subtotal is $21,000 without counting a priced parent twice.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the table.
3. Its Quote Document Rows contain the displayed lines and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Bundle Detail** and filter it to the test Quote.
5. The final document shows the same saved values; the document template does not recalculate them.

## Troubleshooting

| Problem                                | What it means                                        | What to do                                                                                    |
| -------------------------------------- | ---------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| Component prints outside its bundle    | Its bundle relationship is missing or incorrect.     | Reconfigure the bundle in the Quote Line Editor, calculate, and generate again.               |
| Parent and components are both counted | The pricing model and counted-row behavior disagree. | Inspect saved inclusion flags and test priced-parent and priced-component bundles separately. |
| Bundle is missing                      | Its lines are optional, filtered, or incomplete.     | Check Optional values and bundle relationships.                                               |
| Status is Failed                       | Generation rejected the structure.                   | Read **Document Data Error** and correct the named source record.                             |

## Deactivate or roll back

Clear **Active** on **Bundle Detail**, save, and generate again. Do not delete saved rows manually. Restore the exact values in this guide to reactivate.

## Production checklist

- [ ] A priced-parent bundle was tested.
- [ ] A priced-component bundle was tested.
- [ ] Every component appears beneath the correct parent.
- [ ] No amount is counted twice.
- [ ] The named report and document preview match the generated rows.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source Quote data, and generate again.
