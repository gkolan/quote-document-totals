# Cost Allocation by Department or Location

## Status and scope

**Repository status:** Schedule allocation is implemented and tested. No `DEPARTMENT_ALLOCATION` definition, department schedule records, grouping, columns, dedicated report, or example script ships.

**Org verification status:** Relative-weight allocation is tested. Department ownership and target-org output are not verified.

## Use case scenario

A Quote amount must be divided among Sales, Operations, and Finance for internal approval or customer billing.

## What this produces

Salesforce creates one `Quote_Document_Table__c` record for this view and `Quote_Document_Row__c` records for the displayed lines. The same saved result can be viewed in Salesforce Reports and passed to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Confirm the `CPQ_Document_Totals` permission set is assigned.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Obtain the approved allocation owners and weights; decide explicitly whether units are divided.

**Stop here if** any cost has no owner, the output will be mistaken for separate payable Quotes, or the unit-allocation decision is not documented.

## Terms in plain language

| Setting                   | Meaning                                                                                      |
| ------------------------- | -------------------------------------------------------------------------------------------- |
| Relative weights          | 5/3/2 and 50/30/20 produce the same split.                                                   |
| Schedule Divides Quantity | Selected divides seats or units; cleared repeats or omits them according to column behavior. |
| Allocation Scale `2`      | Currency rounds to cents.                                                                    |
| Source check              | All department shares must add back to the original line.                                    |
| `EXPANSION`               | Group saved shares by department.                                                            |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Create a new record. Enter or confirm these values:

| Field                     | Value                                  |
| ------------------------- | -------------------------------------- |
| Active                    | `Cleared while configuring`            |
| Table Code                | `DEPARTMENT_ALLOCATION`                |
| Table Name                | `Department Allocation`                |
| Display Title             | `Cost Allocation`                      |
| Display Order             | `150`                                  |
| Expander Code             | `SCHEDULE`                             |
| Expander Version          | `1`                                    |
| Schedule Code             | `DEPARTMENTS_SALES_OPS_FINANCE`        |
| Schedule Divides Quantity | `Cleared for this amount-only example` |
| Allocation Basis          | `EVEN`                                 |
| Allocation Scale          | `2`                                    |
| Sort Groups By            | `EXPANSION_ORDER`                      |
| Measure Set               | `PRICE_WATERFALL`                      |
| Amount Basis              | `Final Value`                          |
| Line Filter               | `EXCLUDE_OPTIONAL`                     |
| Show Section Totals       | `Cleared`                              |

4. Save the table definition.
5. Return to **Custom Metadata Types**, find **Quote Document Grouping**, and select **Manage Records**.
6. Create **DEPARTMENT_ALLOCATION_EXPANSION** with Dimension `EXPANSION`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Return to **Custom Metadata Types**, find **Quote Document Schedule**, and select **Manage Records**.
9. Create these three active records:

| Record label            | Schedule Code                   | Bucket Code             | Label Key               | Weight | Display Order |
| ----------------------- | ------------------------------- | ----------------------- | ----------------------- | -----: | ------------: |
| Department - Sales      | `DEPARTMENTS_SALES_OPS_FINANCE` | `DEPARTMENT_SALES`      | `DEPARTMENT_SALES`      |      5 |            10 |
| Department - Operations | `DEPARTMENTS_SALES_OPS_FINANCE` | `DEPARTMENT_OPERATIONS` | `DEPARTMENT_OPERATIONS` |      3 |            20 |
| Department - Finance    | `DEPARTMENTS_SALES_OPS_FINANCE` | `DEPARTMENT_FINANCE`    | `DEPARTMENT_FINANCE`    |      2 |            30 |

10. In **Quote Document Key Value**, create three records with **Category** `LABELS_en_US`: `DEPARTMENT_SALES` = `Sales`, `DEPARTMENT_OPERATIONS` = `Operations`, and `DEPARTMENT_FINANCE` = `Finance`.
11. No column records are required for the first test. Salesforce creates the normal `PRICE_WATERFALL` columns when a table has no active column records of its own.
12. Return to the table definition, select **Active**, save, and generate the worked-example Quote. If the result is wrong, clear **Active** before making corrections.

## Worked example

```text
Sales — 50%               $30,000
Operations — 30%          $18,000
Finance — 20%             $12,000
```

Create Sales/Operations/Finance rows with weights 5/3/2. A $60,000 Quote becomes $30,000/$18,000/$12,000.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the table.
3. Its Quote Document Rows contain the displayed lines and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the Quote and `DEPARTMENT_ALLOCATION`.
5. The final document shows the same saved values; the document template does not recalculate them.

## Troubleshooting

| Problem                        | What it means                             | What to do                                                |
| ------------------------------ | ----------------------------------------- | --------------------------------------------------------- |
| Shares do not add to $60,000   | Source total, rows, or weights differ.    | Restore all active rows and compare CPQ total.            |
| Units are divided unexpectedly | Schedule Divides Quantity is selected.    | Clear it for this amount-only example.                    |
| An allocation owner is missing | Its schedule row is absent or inactive.   | Add or activate it before generation.                     |
| Status is Failed               | Allocation validation rejected the setup. | Read **Document Data Error** and correct the named cause. |

## Deactivate or roll back

Keep the definition inactive until every owner and source check passes. Clear **Active** and generate again to roll back. Never delete generated rows manually.

## Production checklist

- [ ] Every cost owner is represented.
- [ ] Weights are approved and documented as relative.
- [ ] Quantity behavior is explicit.
- [ ] Shares add to the payable Quote total.
- [ ] Output is not represented as payment status.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source Quote data, and generate again.
