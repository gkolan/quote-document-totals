# Project Phase Breakdown

## Status and scope

**Repository status:** Schedule allocation is implemented and tested. No `PROJECT_PHASES` definition, phase schedule records, grouping, columns, dedicated report, or example script ships.

**Org verification status:** The allocation mechanism is tested. Phase names, weights, and target-org output are not verified.

## Use case scenario

Services on a Quote must be presented across Discovery, Build, and Launch phases.

## What this produces

Salesforce creates one `Quote_Document_Table__c` record for this view and `Quote_Document_Row__c` records for the displayed lines. The same saved result can be viewed in Salesforce Reports and passed to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Confirm the `CPQ_Document_Totals` permission set is assigned.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Obtain signed phase names and allocation percentages from the statement of work.

**Stop here if** the phase amounts are independently priced in CPQ rather than allocated, or Discovery/Build/Launch and 20/60/20 are not the approved terms.

## Terms in plain language

| Setting              | Meaning                                                   |
| -------------------- | --------------------------------------------------------- |
| Phase schedule       | Named rows that divide a final amount by relative weight. |
| Weight               | Phase share: 20, 60, and 20 in this example.              |
| Allocation Scale `2` | Round currency to cents.                                  |
| `EXPANSION`          | Group saved shares by phase.                              |
| Final Value          | Allocate CPQ's final calculated amount.                   |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Create a new record. Enter or confirm these values:

| Field               | Value                            |
| ------------------- | -------------------------------- |
| Active              | `Cleared while configuring`      |
| Table Code          | `PROJECT_PHASES`                 |
| Table Name          | `Project Phases`                 |
| Display Title       | `Project Phase Breakdown`        |
| Display Order       | `140`                            |
| Expander Code       | `SCHEDULE`                       |
| Expander Version    | `1`                              |
| Schedule Code       | `PROJECT_DISCOVERY_BUILD_LAUNCH` |
| Allocation Basis    | `EVEN`                           |
| Allocation Scale    | `2`                              |
| Sort Groups By      | `EXPANSION_ORDER`                |
| Measure Set         | `PRICE_WATERFALL`                |
| Amount Basis        | `Final Value`                    |
| Line Filter         | `EXCLUDE_OPTIONAL`               |
| Show Section Totals | `Cleared`                        |

4. Save the table definition.
5. Return to **Custom Metadata Types**, find **Quote Document Grouping**, and select **Manage Records**.
6. Create **PROJECT_PHASES_EXPANSION** with Dimension `EXPANSION`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Return to **Custom Metadata Types**, find **Quote Document Schedule**, and select **Manage Records**.
9. Create these three active records:

| Record label              | Schedule Code                    | Bucket Code       | Label Key         | Weight | Display Order |
| ------------------------- | -------------------------------- | ----------------- | ----------------- | -----: | ------------: |
| Project Phase - Discovery | `PROJECT_DISCOVERY_BUILD_LAUNCH` | `PHASE_DISCOVERY` | `PHASE_DISCOVERY` |     20 |            10 |
| Project Phase - Build     | `PROJECT_DISCOVERY_BUILD_LAUNCH` | `PHASE_BUILD`     | `PHASE_BUILD`     |     60 |            20 |
| Project Phase - Launch    | `PROJECT_DISCOVERY_BUILD_LAUNCH` | `PHASE_LAUNCH`    | `PHASE_LAUNCH`    |     20 |            30 |

10. In **Quote Document Key Value**, create three records with **Category** `LABELS_en_US`: `PHASE_DISCOVERY` = `Discovery`, `PHASE_BUILD` = `Build`, and `PHASE_LAUNCH` = `Launch`.
11. No column records are required for the first test. Salesforce creates the normal `PRICE_WATERFALL` columns when a table has no active column records of its own.
12. Return to the table definition, select **Active**, save, and generate the worked-example Quote. If the result is wrong, clear **Active** before making corrections.

## Worked example

```text
Discovery — 20%            $8,000
Build — 60%               $24,000
Launch — 20%               $8,000
```

Create Discovery/Build/Launch schedule rows with weights 20/60/20. A $40,000 service becomes $8,000/$24,000/$8,000.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the table.
3. Its Quote Document Rows contain the displayed lines and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the Quote and `PROJECT_PHASES`.
5. The final document shows the same saved values; the document template does not recalculate them.

## Troubleshooting

| Problem              | What it means                                        | What to do                                                |
| -------------------- | ---------------------------------------------------- | --------------------------------------------------------- |
| Phase order is wrong | Schedule display orders are wrong.                   | Set 10/20/30 and generate again.                          |
| Amounts differ       | Weights or source total differ.                      | Compare schedule records and CPQ final value.             |
| A phase is missing   | Its schedule record is inactive or has another code. | Correct and activate the record.                          |
| Status is Failed     | Schedule validation failed.                          | Read **Document Data Error** and correct the named cause. |

## Deactivate or roll back

Keep the definition inactive until phase output is approved. Clear **Active** and generate again to roll back. Do not delete generated rows manually.

## Production checklist

- [ ] Phase names and weights match the signed scope.
- [ ] All phase records share the exact schedule code.
- [ ] Orders are 10/20/30.
- [ ] Phase amounts add to CPQ net amount.
- [ ] The document states these are allocated amounts.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source Quote data, and generate again.
