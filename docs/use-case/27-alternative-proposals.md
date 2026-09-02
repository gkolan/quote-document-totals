# Alternative Proposals

## Status and scope

**Repository status:** Separate table output is implemented and tested. No proposal-option field, `ALTERNATIVE_PROPOSALS` definition, grouping, columns, content, dedicated report, or example script ships.

**Org verification status:** Partition behavior is tested. Option assignment, commercial approval, and target-org output are not verified.

## Use case scenario

One Quote presents Basic, Recommended, and Premium alternatives. Each option needs its own table and none of the options should be added together.

## What this produces

Salesforce creates one or more `Quote_Document_Table__c` records and the related `Quote_Document_Row__c` records needed for this view. The saved values can be reviewed in Salesforce before they are sent to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Assign the `CPQ_Document_Totals` permission set.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Create a Quote Line picklist named **Proposal Option** with API name `Proposal_Option__c` and values Basic, Recommended, and Premium; populate every option line.

**Stop here if** the field is missing, a line belongs to more than one option, a payable base line is unintentionally repeated, or the customer has already selected one option that should instead become the Quote.

## Terms in plain language

| Setting                      | Meaning                                                 |
| ---------------------------- | ------------------------------------------------------- |
| Partition                    | Create a separate table for each Proposal Option value. |
| Partition field              | Exact Quote Line field path `Proposal_Option__c`.       |
| Cross Partition Total `NONE` | Never add mutually exclusive options together.          |
| Recommended                  | A label, not an automatic selection or approval.        |
| Option total                 | Price of that option alone.                             |

## Configure in Salesforce

### Create the option field

1. Open **Setup → Object Manager → Quote Line → Fields & Relationships**.
2. Select **New**, choose **Picklist**, and select **Next**.
3. Set **Field Label** to `Proposal Option`. Confirm the resulting Field Name is `Proposal_Option` and the API name is `Proposal_Option__c`.
4. Enter `Basic`, `Recommended`, and `Premium`, one value per line. Restrict the picklist to these values.
5. Grant edit access to the users or automation that assign options and read access to document-generation users.
6. Open **Object Manager → Quote Line → Field Sets → Line Editor**, add **Proposal Option**, and save so the value can be assigned in the CPQ Line Editor.
7. Populate exactly one option on every test line, then calculate and save the Quote.

### Create the table

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Create a new record. Enter or confirm these values:

| Field                 | Value                       |
| --------------------- | --------------------------- |
| Active                | `Cleared while configuring` |
| Table Code            | `ALTERNATIVE_PROPOSALS`     |
| Table Name            | `Alternative Proposals`     |
| Display Title         | `Proposal Options`          |
| Display Order         | `270`                       |
| Partition Dimension   | `Proposal_Option__c`        |
| Cross Partition Total | `NONE`                      |
| Measure Set           | `PRICE_WATERFALL`           |
| Amount Basis          | `Final Value`               |
| Line Filter           | `EXCLUDE_OPTIONAL`          |

4. Save the table definition.
5. From **Custom Metadata Types**, open **Quote Document Grouping** and select **Manage Records**.
6. Create **ALTERNATIVE_PROPOSALS_PRODUCT_FAMILY** with Dimension `PRODUCT_FAMILY`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Keep **Active** cleared until option ownership and totals are reviewed.
9. Activate only for the controlled sandbox test.

## Worked example

```text
Basic Option               $20,000
Recommended Option         $28,000
Premium Option             $36,000
No combined payable total
```

Create Basic $20,000, Recommended $28,000, and Premium $36,000. Generation must create three tables and no $84,000 combined total.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the generated table or tables.
3. Quote Document Rows show the saved details, subtotals, and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the Quote and `ALTERNATIVE_PROPOSALS`.
5. The final document shows these saved values without recalculating them.

## Troubleshooting

| Problem                                       | What it means                                         | What to do                                                             |
| --------------------------------------------- | ----------------------------------------------------- | ---------------------------------------------------------------------- |
| A line appears in wrong option                | Its Proposal Option value is wrong.                   | Correct the Quote Line and generate again.                             |
| $84,000 combined total appears                | Mutually exclusive options are being summed.          | Deactivate immediately and restore `NONE`.                             |
| Base product appears three times unexpectedly | Shared lines were copied without a documented policy. | Decide whether each option owns a separate line and correct the Quote. |
| Status is Failed                              | Partition data is invalid.                            | Read **Document Data Error** and correct the named cause.              |

## Deactivate or roll back

Clear **Active**, save, and generate again. Preserve the option field values for review; do not delete generated records manually.

## Production checklist

- [ ] Every line has exactly one option.
- [ ] Shared/base-line treatment is documented.
- [ ] Each table contains only its option.
- [ ] No cross-option total exists.
- [ ] Customer-facing wording does not imply all options are payable.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source data, and generate again.
