# Rebate or Incentive Illustration

## Status and scope

**Repository status:** Informational rows, separate tables, and Flow adjustment are implemented and tested. No rebate fields, rule Flow, `REBATE_ILLUSTRATION` definition, grouping, columns, content, dedicated report, or example script ships.

**Org verification status:** This needs organization setup. The rebate owner must supply the status and amount; this table does not decide eligibility.

## Use case scenario

A document needs to show the current price and a possible rebate separately because the rebate depends on a future condition.

## What this produces

Salesforce creates one or more `Quote_Document_Table__c` records and the related `Quote_Document_Row__c` records needed for this view. The saved values can be reviewed in Salesforce before they are sent to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Assign the `CPQ_Document_Totals` permission set.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Create Quote fields `Rebate_Status__c` with values Guaranteed and Contingent, and currency field `Rebate_Amount__c`; populate them from the approved incentive process.

**Stop here if** eligibility is unresolved, the amount is calculated only in a document template, or a contingent rebate is expected to reduce the current payable total.

## Terms in plain language

| Setting             | Meaning                                                            |
| ------------------- | ------------------------------------------------------------------ |
| Guaranteed          | Approved amount whose treatment is owned by the source process.    |
| Contingent          | Possible future amount that does not reduce today's payable total. |
| Informational row   | Visible row excluded from payable subtotals and Grand Total.       |
| Assumptions block   | Saved condition and approval wording.                              |
| Flow row adjustment | Flow that reads approved fields and adds the illustration row.     |

## Configure in Salesforce

### Create the Quote source fields

1. Open **Setup → Object Manager → Quote → Fields & Relationships**.
2. Create a restricted Picklist field labeled **Rebate Status**, API name `Rebate_Status__c`, with values `Guaranteed` and `Contingent`.
3. Create a Currency field labeled **Rebate Amount**, API name `Rebate_Amount__c`, length 16, and 2 decimal places.
4. Grant edit access only to the approved incentive process and its administrators. Grant read access to document-generation users.
5. Add both fields to the administrator Quote layout. Set the worked-example Quote to `Contingent` and $5,000.

### Create the table and Flow

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Create a new record only after the rebate source and rule are approved. Enter or confirm these values:

| Field                       | Value                               |
| --------------------------- | ----------------------------------- |
| Active                      | `Cleared`                           |
| Table Code                  | `REBATE_ILLUSTRATION`               |
| Table Name                  | `Rebate Illustration`               |
| Display Title               | `Rebate Illustration`               |
| Display Order               | `290`                               |
| Measure Set                 | `PRICE_WATERFALL`                   |
| Amount Basis                | `Final Value`                       |
| Line Filter                 | `EXCLUDE_OPTIONAL`                  |
| Assumptions Block Code      | `REBATE_CONDITIONS`                 |
| Row Customizer Flow         | `QuoteDocumentRebateRows`           |
| Row Customizer Flow Version | `1`                                 |
| Cache Policy                | `DECLARED_DEPENDENCIES`             |
| Contributor Dependency Set  | `Rebate_Status__c,Rebate_Amount__c` |

4. Save the table definition.
5. From **Custom Metadata Types**, open **Quote Document Grouping** and select **Manage Records**.
6. Create **REBATE_ILLUSTRATION_PRODUCT_FAMILY** with Dimension `PRODUCT_FAMILY`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Build autolaunched Flow `QuoteDocumentRebateRows` using the exact Flow variables and complete-row return steps in [Flow-based row adjustment](42-flow-row-adjustment.md). It reads the Quote whose ID is supplied in `quoteId` and adds the rebate as a visible row with both total-inclusion fields clear.
9. In **Quote Document Content**, create this sandbox record. It does not ship and it does not decide rebate eligibility.

| Field         | Sandbox example value                                                                                                                                                                                                                  |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Record Label  | `Content en_US - REBATE_CONDITIONS`                                                                                                                                                                                                    |
| Block Code    | `REBATE_CONDITIONS`                                                                                                                                                                                                                    |
| Locale        | `en_US`                                                                                                                                                                                                                                |
| Block Type    | Notice                                                                                                                                                                                                                                 |
| Display Order | `285`                                                                                                                                                                                                                                  |
| Heading       | `Rebate conditions`                                                                                                                                                                                                                    |
| Body          | `Illustration only. The possible rebate is contingent on the customer meeting the approved incentive terms. Sample source: Incentive Operations decision dated August 15, 2026. The rebate does not reduce the current payable total.` |
| Version       | `1`                                                                                                                                                                                                                                    |
| Active        | Selected for the controlled sandbox test                                                                                                                                                                                               |

10. Confirm **Assumptions Block Code** on the table is `REBATE_CONDITIONS`. Replace the sample condition, source owner, date, and wording with reviewed organization values before production.

## Worked example

```text
Current price              $50,000
Possible rebate             $5,000  (conditional)
Current payable total      $50,000
```

Set current price to $50,000, Rebate Status to Contingent, and Rebate Amount to $5,000. Current payable total stays $50,000.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the generated table or tables.
3. Quote Document Rows show the saved details, subtotals, and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the Quote and `REBATE_ILLUSTRATION`.
5. Open the Quote Document Blocks related list and confirm `REBATE_CONDITIONS` appears immediately before the Table at order `285` with Source Version `1`.
6. The final document shows the saved rows and Block without recalculating them.

## Troubleshooting

| Problem                   | What it means                           | What to do                                                         |
| ------------------------- | --------------------------------------- | ------------------------------------------------------------------ |
| Payable total is $45,000  | Contingent rebate was counted.          | Deactivate and set both inclusion flags false.                     |
| Rebate wording is missing | Content record is absent or not mapped. | Restore `REBATE_CONDITIONS` and regenerate.                        |
| Old amount is reused      | Dependencies or version are wrong.      | Restore both dependency paths and bump version after Flow changes. |
| Status is Failed          | Flow or validation failed.              | Read **Document Data Error** and correct the named cause.          |

## Deactivate or roll back

Clear **Active**, save, and generate again. To disable only the adjustment, clear **Row Customizer Flow**, increase **Row Customizer Flow Version** by one, run `Database.executeBatch(new QuoteDocumentInvalidationJob(), 200);` in Execute Anonymous, and generate again. Never delete generated rows manually.

## Production checklist

- [ ] Rebate status and amount have named owners.
- [ ] Contingent rebate does not reduce payable total.
- [ ] Conditions, source, and date are stored in Salesforce.
- [ ] Flow output matches the source fields.
- [ ] Reuse changes when status or amount changes.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source data, and generate again.
