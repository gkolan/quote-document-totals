# Estimated Consumption Scenarios

## Status and scope

**Repository status:** Separate table output is implemented and tested. No scenario field, `CONSUMPTION_SCENARIOS` definition, grouping, columns, custom adjustment, content records, dedicated report, or example script ships.

**Org verification status:** The table-splitting mechanism is tested. Assumptions and scenario values must be supplied and approved in the target org.

## Use case scenario

A document needs low, expected, and high consumption illustrations without presenting all three as one payable total.

## What this produces

Salesforce creates one or more `Quote_Document_Table__c` records and the related `Quote_Document_Row__c` records needed for this view. The saved values can be reviewed in Salesforce before they are sent to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Assign the `CPQ_Document_Totals` permission set.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Create a Quote Line picklist named **Consumption Scenario** with API name `Consumption_Scenario__c` and values Low, Expected, and High; populate every scenario line.

**Stop here if** the field does not exist, a scenario line is blank, assumptions are not stored in Salesforce, or a reviewer could mistake the three alternatives for one payable Quote.

## Terms in plain language

| Setting                      | Meaning                                                      |
| ---------------------------- | ------------------------------------------------------------ |
| Partition                    | Create one generated table for each distinct scenario value. |
| Partition field              | Exact Quote Line field path `Consumption_Scenario__c`.       |
| Cross Partition Total `NONE` | Do not add Low, Expected, and High together.                 |
| Assumptions block            | Saved Salesforce text explaining volumes and pricing basis.  |
| Illustration                 | Informational scenario; not actual usage or invoice data.    |

## Configure in Salesforce

### Create the scenario field

1. Open **Setup → Object Manager → Quote Line → Fields & Relationships**.
2. Select **New**, choose **Picklist**, and select **Next**.
3. Set **Field Label** to `Consumption Scenario`. Confirm the resulting **Field Name** is `Consumption_Scenario` so the API name becomes `Consumption_Scenario__c`.
4. Enter the values `Low`, `Expected`, and `High`, one per line. Restrict the picklist to these values.
5. Grant edit access to the users or automation that assign scenarios and read access to document-generation users. Add the field to the administrator Quote Line layout.
6. If users assign the value in the CPQ Line Editor, open **Object Manager → Quote Line → Field Sets → Line Editor**, add **Consumption Scenario**, and save.
7. Populate exactly one value on every test Quote Line. Calculate and save the Quote.

### Create the table and assumptions

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Create a new record only after the assumption source is approved. Enter or confirm these values:

| Field                 | Value                             |
| --------------------- | --------------------------------- |
| Active                | `Cleared`                         |
| Table Code            | `CONSUMPTION_SCENARIOS`           |
| Table Name            | `Consumption Scenarios`           |
| Display Title         | `Estimated Consumption Scenarios` |
| Display Order         | `260`                             |
| Partition Dimension   | `Consumption_Scenario__c`         |
| Cross Partition Total | `NONE`                            |
| Measure Set           | `PRICE_WATERFALL`                 |
| Amount Basis          | `Final Value`                     |
| Line Filter           | `EXCLUDE_OPTIONAL`                |

4. Save the table definition.
5. From **Custom Metadata Types**, open **Quote Document Grouping** and select **Manage Records**.
6. Create **CONSUMPTION_SCENARIOS_PRODUCT_FAMILY** with Dimension `PRODUCT_FAMILY`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. In **Quote Document Content**, create the complete sandbox record in [Document content blocks — Example 3](34-document-content-blocks.md#example-3-consumption-assumptions-created-for-a-sandbox). It uses Block Code `CONSUMPTION_SCENARIO_ASSUMPTIONS`, locale `en_US`, type Notice, order `900`, heading `Consumption assumptions`, and Version `1`.
9. Return to the table definition and set **Assumptions Block Code** to `CONSUMPTION_SCENARIO_ASSUMPTIONS`.
10. Replace the example Block's volumes, date, source owner, and wording with reviewed organization values before production. Increase Version whenever the approved text changes.
11. Keep **Active** cleared until all three outputs and wording pass.

## Worked example

```text
Low Estimate              $18,000
Expected Estimate         $24,000
High Estimate             $32,000
No combined payable total
```

Create lines marked Low $18,000, Expected $24,000, and High $32,000. Generation must create three tables and no $74,000 combined total.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the generated table or tables.
3. Quote Document Rows show the saved details, subtotals, and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the Quote and `CONSUMPTION_SCENARIOS`.
5. The final document shows these saved values without recalculating them.

## Troubleshooting

| Problem                         | What it means                                      | What to do                                                |
| ------------------------------- | -------------------------------------------------- | --------------------------------------------------------- |
| One scenario is missing         | Its lines are blank or use another picklist value. | Correct the Quote Lines and generate again.               |
| A $74,000 total appears         | Cross-partition behavior is wrong.                 | Deactivate immediately and restore `NONE`.                |
| Assumptions appear only in Word | Content is not governed in Salesforce.             | Create the content record and map generated content.      |
| Status is Failed                | Partition or source data is invalid.               | Read **Document Data Error** and correct the named cause. |

## Deactivate or roll back

Clear **Active**, save, and generate again. Keep the scenario field and approved assumptions for audit; do not delete generated records manually.

## Production checklist

- [ ] Every scenario line has Low, Expected, or High.
- [ ] Assumptions are approved and stored in Salesforce.
- [ ] Three separate tables are generated.
- [ ] No combined scenario total exists.
- [ ] Document wording states that values are illustrations.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source data, and generate again.
