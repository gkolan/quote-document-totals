# Delivery Schedule by Units

## Status and scope

**Repository status:** Quantity allocation by schedule is implemented and tested. No `DELIVERY_SCHEDULE` definition, schedule records, grouping, columns, dedicated report, or example script ships.

**Org verification status:** The mechanism is tested. Actual delivery dates, unit precision, and target-org output are not verified.

## Use case scenario

A Quote contains 1,000 units that will be delivered in three shipments. The document must divide Quantity across the delivery dates.

## What this produces

Salesforce creates one `Quote_Document_Table__c` record for this view and `Quote_Document_Row__c` records for the displayed lines. The same saved result can be viewed in Salesforce Reports and passed to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Confirm the `CPQ_Document_Totals` permission set is assigned.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Obtain three approved delivery dates and confirm whole-unit allocation is permitted.

**Stop here if** deliveries can contain fractional units, dates are not approved, or the three deliveries must not divide both Quantity and amount.

## Terms in plain language

| Setting                   | Meaning                                                                 |
| ------------------------- | ----------------------------------------------------------------------- |
| Schedule weight           | Relative share assigned to one delivery.                                |
| Schedule Divides Quantity | Divide units as well as currency.                                       |
| Allocation Scale `0`      | Produce whole units for this example.                                   |
| Residual                  | Final rounding unit placed so all deliveries equal the source Quantity. |
| `EXPANSION`               | Group saved shares by delivery.                                         |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Create a new record. Enter or confirm these values:

| Field                     | Value                       |
| ------------------------- | --------------------------- |
| Active                    | `Cleared while configuring` |
| Table Code                | `DELIVERY_SCHEDULE`         |
| Table Name                | `Delivery Schedule`         |
| Display Title             | `Delivery Schedule`         |
| Display Order             | `130`                       |
| Expander Code             | `SCHEDULE`                  |
| Expander Version          | `1`                         |
| Schedule Code             | `DELIVERY_APR_MAY_JUN`      |
| Schedule Divides Quantity | `Selected`                  |
| Allocation Basis          | `EVEN`                      |
| Allocation Scale          | `0`                         |
| Sort Groups By            | `EXPANSION_ORDER`           |
| Measure Set               | `PRICE_WATERFALL`           |
| Amount Basis              | `Final Value`               |
| Line Filter               | `EXCLUDE_OPTIONAL`          |
| Show Section Totals       | `Cleared`                   |

4. Save the table definition.
5. Return to **Custom Metadata Types**, find **Quote Document Grouping**, and select **Manage Records**.
6. Create **DELIVERY_SCHEDULE_EXPANSION** with Dimension `EXPANSION`, Level `1`, Sequence `10`.
7. Save the grouping record.
8. Return to **Custom Metadata Types**, find **Quote Document Schedule**, and select **Manage Records**.
9. Create these three active records:

| Record label     | Schedule Code          | Bucket Code      | Label Key        | Weight | Display Order |
| ---------------- | ---------------------- | ---------------- | ---------------- | -----: | ------------: |
| Delivery - April | `DELIVERY_APR_MAY_JUN` | `DELIVERY_APRIL` | `DELIVERY_APRIL` |      3 |            10 |
| Delivery - May   | `DELIVERY_APR_MAY_JUN` | `DELIVERY_MAY`   | `DELIVERY_MAY`   |      4 |            20 |
| Delivery - June  | `DELIVERY_APR_MAY_JUN` | `DELIVERY_JUNE`  | `DELIVERY_JUNE`  |      3 |            30 |

10. In **Quote Document Key Value**, create three records with **Category** `LABELS_en_US`: `DELIVERY_APRIL` = `April delivery`, `DELIVERY_MAY` = `May delivery`, and `DELIVERY_JUNE` = `June delivery`.
11. In **Quote Document Column Definition**, create an active Quantity column for this table: **Table Definition** `DELIVERY_SCHEDULE`, **Column Code** `COL_QUANTITY`, **Display Order** `20`, **Data Type** `Number`, **Value Field** `Quantity__c`. Also create an active label column with code `COL_LABEL`, order `10`, and type `Text`; leave its Value Field blank.
12. Return to the table definition, select **Active**, save, and generate the worked-example Quote. If the result is wrong, clear **Active** before making corrections.

## Worked example

```text
April delivery              300 units
May delivery                400 units
June delivery               300 units
Total                      1,000 units
```

Create schedule rows April/May/June with weights 3/4/3 and orders 10/20/30. A Quantity of 1,000 divides to 300/400/300.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the table.
3. Its Quote Document Rows contain the displayed lines and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Rendered View** and filter to the Quote and `DELIVERY_SCHEDULE`.
5. The final document shows the same saved values; the document template does not recalculate them.

## Troubleshooting

| Problem                   | What it means                                     | What to do                                                  |
| ------------------------- | ------------------------------------------------- | ----------------------------------------------------------- |
| Quantities repeat         | Schedule Divides Quantity is cleared.             | Select it and generate again.                               |
| Quantities are fractional | Allocation Scale is not 0.                        | Use the business-approved precision; use 0 for whole units. |
| Total is not 1,000        | A schedule row is missing or weights are invalid. | Restore all three active rows and generate again.           |
| Status is Failed          | Allocation validation rejected the setup.         | Read **Document Data Error** and correct the named cause.   |

## Deactivate or roll back

Keep the definition inactive until units and amounts reconcile. Clear **Active** and generate again to roll back. Never delete generated records manually.

## Production checklist

- [ ] Dates and weights are approved.
- [ ] Unit precision is documented.
- [ ] Delivery quantities equal source Quantity.
- [ ] Delivery amounts equal source net amount.
- [ ] Rows use chronological saved order.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source Quote data, and generate again.
