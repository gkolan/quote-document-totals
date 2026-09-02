# Minimum Commitment and Shortfall

## Status and scope

**Repository status:** Informational rows and Flow row adjustment are implemented and tested. No commitment fields, calculation Flow, `MINIMUM_COMMITMENT` definition, grouping, columns, content, dedicated report, or example script ships.

**Org verification status:** This is not turnkey. The target org must own and approve the commitment and expected-usage values before an administrator builds or activates the table.

## Use case scenario

A document needs to show a minimum commitment, expected usage, and the shortfall without adding the shortfall to the amount due.

## What this produces

Salesforce creates one or more `Quote_Document_Table__c` records and the related `Quote_Document_Row__c` records needed for this view. The saved values can be reviewed in Salesforce before they are sent to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Assign the `CPQ_Document_Totals` permission set.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Create Quote currency fields `Minimum_Commitment__c` and `Expected_Usage_Value__c`; populate them from the contract and approved forecasting source.

**Stop here if** either field is blank, the source owner has not approved the values, or the shortfall should change the payable Quote total. This table displays the supplied values; it does not calculate the forecast or contract amount.

## Terms in plain language

| Setting              | Meaning                                                                     |
| -------------------- | --------------------------------------------------------------------------- |
| Minimum commitment   | Contractual minimum supplied on the Quote.                                  |
| Expected usage value | Approved forecast supplied on the Quote.                                    |
| Shortfall            | `MAX(Minimum Commitment - Expected Usage Value, 0)`.                        |
| Informational row    | Visible row excluded from subtotals and Grand Total.                        |
| Flow row adjustment  | Reviewed autolaunched Flow that adds the supplied values to generated rows. |

## Configure in Salesforce

### Create the Quote source fields

1. Open **Setup → Object Manager → Quote → Fields & Relationships**.
2. Create a Currency field labeled **Minimum Commitment** with API name `Minimum_Commitment__c`, length 16, and 2 decimal places.
3. Create a Currency field labeled **Expected Usage Value** with API name `Expected_Usage_Value__c`, length 16, and 2 decimal places.
4. Grant edit access only to the approved source process and its administrators. Grant read access to document-generation users.
5. Add both fields to the administrator Quote layout. Populate them on the test Quote with $100,000 and $82,000.

### Create the table and Flow

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Create a new record only after the commitment source is approved. Enter or confirm these values:

| Field                       | Value                                           |
| --------------------------- | ----------------------------------------------- |
| Active                      | `Cleared`                                       |
| Table Code                  | `MINIMUM_COMMITMENT`                            |
| Table Name                  | `Minimum Commitment`                            |
| Display Title               | `Minimum Commitment`                            |
| Display Order               | `280`                                           |
| Measure Set                 | `PRICE_WATERFALL`                               |
| Amount Basis                | `Final Value`                                   |
| Line Filter                 | `EXCLUDE_OPTIONAL`                              |
| Assumptions Block Code      | `MINIMUM_COMMITMENT_ASSUMPTIONS`                |
| Row Customizer Flow         | `QuoteDocumentMinimumCommitmentRows`            |
| Row Customizer Flow Version | `1`                                             |
| Cache Policy                | `DECLARED_DEPENDENCIES`                         |
| Contributor Dependency Set  | `Minimum_Commitment__c,Expected_Usage_Value__c` |

4. Save the table definition.
5. From **Custom Metadata Types**, open **Quote Document Grouping** and select **Manage Records**.
6. Create **MINIMUM_COMMITMENT_PRODUCT_FAMILY** with Dimension `PRODUCT_FAMILY`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Build autolaunched Flow `QuoteDocumentMinimumCommitmentRows` using the exact Flow variables and complete-row return steps in [Flow-based row adjustment](42-flow-row-adjustment.md). It must read the Quote whose ID is supplied in `quoteId`, add Expected Usage, Minimum Commitment, and Shortfall as visible rows with both total-inclusion fields clear, and return every original row plus the three new rows.
9. In **Quote Document Content**, create this sandbox record. It does not ship and its sample source and date must be replaced before production.

| Field         | Sandbox example value                                                                                                                                                                                                                               |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Record Label  | `Content en_US - MINIMUM_COMMITMENT_ASSUMPTIONS`                                                                                                                                                                                                    |
| Block Code    | `MINIMUM_COMMITMENT_ASSUMPTIONS`                                                                                                                                                                                                                    |
| Locale        | `en_US`                                                                                                                                                                                                                                             |
| Block Type    | Notice                                                                                                                                                                                                                                              |
| Display Order | `270`                                                                                                                                                                                                                                               |
| Heading       | `Minimum commitment assumptions`                                                                                                                                                                                                                    |
| Body          | `Illustration only. The minimum commitment is supplied by the approved contract record. Expected usage is supplied by the Revenue Operations forecast dated August 15, 2026. The shortfall is information only and is not added to the amount due.` |
| Version       | `1`                                                                                                                                                                                                                                                 |
| Active        | Selected for the controlled sandbox test                                                                                                                                                                                                            |

10. Confirm **Assumptions Block Code** on the table is `MINIMUM_COMMITMENT_ASSUMPTIONS`. Replace the sample source, date, and wording with reviewed organization values before production.

## Worked example

```text
Minimum commitment        $100,000
Expected usage             $82,000
Shortfall                  $18,000  (information only)
Amount due                 $82,000
```

Set Minimum Commitment to $100,000 and Expected Usage Value to $82,000. The Flow adds an $18,000 informational shortfall. Amount due remains $82,000; adding shortfall to it is a failure.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the generated table or tables.
3. Quote Document Rows show the saved details, subtotals, and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the Quote and `MINIMUM_COMMITMENT`.
5. Open the Quote Document Blocks related list and confirm `MINIMUM_COMMITMENT_ASSUMPTIONS` appears immediately before the Table at order `270` with Source Version `1`.
6. The final document shows the saved rows and Block without recalculating them.

## Troubleshooting

| Problem                  | What it means                            | What to do                                                                      |
| ------------------------ | ---------------------------------------- | ------------------------------------------------------------------------------- |
| Shortfall is not $18,000 | Source fields or Flow arithmetic differ. | Compare both Quote fields and Flow formula.                                     |
| Amount due is $100,000   | Shortfall was counted.                   | Deactivate and set both inclusion flags false on the shortfall row.             |
| Old values are reused    | Dependencies or version are wrong.       | Restore both dependency paths and bump the Flow version after behavior changes. |
| Status is Failed         | Flow or row validation failed.           | Read **Document Data Error** and correct the named cause.                       |

## Deactivate or roll back

Clear **Active**, save, and generate again. To disable only the adjustment, clear **Row Customizer Flow**, increase **Row Customizer Flow Version** by one, run `Database.executeBatch(new QuoteDocumentInvalidationJob(), 200);` in Execute Anonymous, and generate again. Do not delete generated rows manually.

## Production checklist

- [ ] Both source fields have named business owners.
- [ ] Flow arithmetic returns $18,000 for the example.
- [ ] Shortfall is visible and excluded from totals.
- [ ] Assumptions state source and effective date.
- [ ] Reuse changes when either source field changes.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source data, and generate again.
