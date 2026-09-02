# Separate Purchasing Entities

## Status and scope

**Repository status:** Separate-table output and cross-partition `SUM` are implemented and tested. No purchasing-entity field, `PURCHASING_ENTITIES` definition, grouping, columns, dedicated report, or example script ships.

**Org verification status:** Partition behavior is tested. Legal entity assignment, currency treatment, and target-org documents are not verified.

## Use case scenario

One Quote covers two legal entities, but each entity needs its own table or document output containing only its share.

## What this produces

Salesforce creates one or more `Quote_Document_Table__c` records and the related `Quote_Document_Row__c` records needed for this view. The saved values can be reviewed in Salesforce before they are sent to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Assign the `CPQ_Document_Totals` permission set.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Create required Quote Line text field **Purchasing Entity** with API name `Purchasing_Entity__c`; populate every payable line with one legally approved entity name.

**Stop here if** a line is blank, belongs to multiple entities, entities use different Quote currencies, or separate signatures require separate Quotes under the organization's legal process.

## Terms in plain language

| Setting                     | Meaning                                                                    |
| --------------------------- | -------------------------------------------------------------------------- |
| Partition                   | Create one table per distinct entity value.                                |
| Partition field             | Exact Quote Line field `Purchasing_Entity__c`.                             |
| Cross Partition Total `SUM` | Add entity totals because they divide one payable Quote.                   |
| Complementary parts         | Each line belongs once; all entities together equal the Quote.             |
| Separate output             | Separate table, not automatically a separate Salesforce Quote or contract. |

## Configure in Salesforce

### Create the purchasing-entity field

1. Open **Setup → Object Manager → Quote Line → Fields & Relationships**.
2. Select **New**, choose **Text**, and select **Next**.
3. Set **Field Label** to `Purchasing Entity`, **Length** to `255`, and confirm the API name is `Purchasing_Entity__c`.
4. Grant edit access to the users or automation that assign legal entities and read access to document-generation users.
5. Open **Object Manager → Quote Line → Field Sets → Line Editor**, add **Purchasing Entity**, and save.
6. Populate exactly one approved entity name on every payable test line, then calculate and save the Quote.

### Create the table

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Create a new record. Enter or confirm these values:

| Field                 | Value                       |
| --------------------- | --------------------------- |
| Active                | `Cleared while configuring` |
| Table Code            | `PURCHASING_ENTITIES`       |
| Table Name            | `Purchasing Entities`       |
| Display Title         | `Purchasing Entity Summary` |
| Display Order         | `310`                       |
| Partition Dimension   | `Purchasing_Entity__c`      |
| Cross Partition Total | `SUM`                       |
| Measure Set           | `PRICE_WATERFALL`           |
| Amount Basis          | `Final Value`               |
| Line Filter           | `EXCLUDE_OPTIONAL`          |

4. Save the table definition.
5. From **Custom Metadata Types**, open **Quote Document Grouping** and select **Manage Records**.
6. Create **PURCHASING_ENTITIES_PRODUCT_FAMILY** with Dimension `PRODUCT_FAMILY`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Keep **Active** cleared until every line has exactly one entity.
9. Activate only for the controlled sandbox test.

## Worked example

```text
North America Entity      $35,000
European Entity           $25,000
Combined Quote Total      $60,000
```

Assign $35,000 of lines to North America Entity and $25,000 to European Entity. Two tables must total $60,000 together without duplicating a line.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the generated table or tables.
3. Quote Document Rows show the saved details, subtotals, and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the Quote and `PURCHASING_ENTITIES`.
5. The final document shows these saved values without recalculating them.

## Troubleshooting

| Problem                       | What it means                                     | What to do                                                |
| ----------------------------- | ------------------------------------------------- | --------------------------------------------------------- |
| A line is in no table         | Purchasing Entity is blank or filtered.           | Populate exactly one entity and regenerate.               |
| A line appears twice          | Source data or a custom adjustment duplicated it. | Deactivate and reconcile every source line.               |
| Combined total is not $60,000 | Entity tables are incomplete or overlapping.      | Compare partition rows with all payable Quote Lines.      |
| Status is Failed              | Partition or total validation failed.             | Read **Document Data Error** and correct the named cause. |

## Deactivate or roll back

Clear **Active**, save, and generate again. Preserve entity assignments for audit or clear them through an approved data change; never delete generated records manually.

## Production checklist

- [ ] Every payable line has exactly one entity.
- [ ] All entities share the Quote currency.
- [ ] Each table contains only its entity's lines.
- [ ] Cross-partition total equals the Quote.
- [ ] Legal process confirms whether separate tables are sufficient.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source data, and generate again.
