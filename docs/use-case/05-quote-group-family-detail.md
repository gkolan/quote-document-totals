# Quote Line Group and Product Family Detail

## Status and scope

**Repository status:** The active `GROUP_FAMILY_DETAIL` definition, both grouping records, the **Quote Document - Group and Family Detail** report, and `scripts/apex/group-family-detail-example.apex` ship in the repository.

**Org verification status:** Repository tests cover two-level grouping. Target-org page layout, data, and output are not verified here.

## Use case scenario

A Quote uses Quote Line Groups for phases or workstreams. The document needs each Quote Line Group as a section, with Product Families inside it.

## What this produces

Salesforce creates one `Quote_Document_Table__c` record for this view and `Quote_Document_Row__c` records for the displayed lines. The same saved result can be viewed in Salesforce Reports and passed to the document generation tool.

## Before you start

- Test in a sandbox with a Quote that contains the required Salesforce CPQ data.
- Confirm the `CPQ_Document_Totals` permission set is assigned.
- Keep **Active** cleared while completing the configuration. Select it only for a controlled sandbox test.
- Assign every included Quote Line to the intended CPQ Quote Line Group and Product Family.

**Stop here if** an included line has no intended Quote Line Group or Product Family, the Quote is not calculated, or generation is unavailable.

## Terms in plain language

| Setting               | Meaning                                              |
| --------------------- | ---------------------------------------------------- |
| Quote Line Group      | A CPQ section such as a phase, site, or workstream.  |
| Level 1               | The outer section printed first.                     |
| Level 2               | The Product Family section printed inside Level 1.   |
| Sequence              | The order in which grouping parts are applied.       |
| Show Details selected | Prints individual products beneath the two headings. |

## Configure in Salesforce

1. From **Setup**, enter **Custom Metadata Types** in Quick Find.
2. Open **Custom Metadata Types**, find **Quote Document Table Definition**, and select **Manage Records**.
3. Open **Quote Group and Family Detail**. Enter or confirm these values:

| Field         | Value                        |
| ------------- | ---------------------------- |
| Active        | `Selected`                   |
| Table Code    | `GROUP_FAMILY_DETAIL`        |
| Display Title | `Detail by Group and Family` |
| Measure Set   | `PRICE_WATERFALL`            |
| Amount Basis  | `Final Value`                |
| Line Filter   | `EXCLUDE_OPTIONAL`           |
| Show Details  | `Selected`                   |

4. Save the table definition.
5. Return to **Custom Metadata Types**, find **Quote Document Grouping**, and select **Manage Records**.
6. Confirm **Group Detail - QUOTE_LINE_GROUP** uses Dimension `QUOTE_LINE_GROUP`, Level `1`, Sequence `10`.
7. Confirm **Group Detail - PRODUCT_FAMILY** uses Dimension `PRODUCT_FAMILY`, Level `2`, Sequence `20`.
8. Save only if a value required correction.
9. Generate document data for the calculated sandbox Quote.

## Worked example

```text
Phase 1
  Software                 $10,000
  Services                  $4,000
Phase 1 subtotal           $14,000
```

Use Phase 1 with $10,000 of Software and $4,000 of Services. The Phase 1 subtotal must be $14,000, and both families must remain inside Phase 1.

## Generate and verify

1. **Document Data Status** on the Quote should show **Ready**.
2. The Quote Document Tables related list contains the table.
3. Its Quote Document Rows contain the displayed lines and totals.
4. Open **Reports → CPQ Document Totals → Quote Document - Group and Family Detail** and filter it to the test Quote.
5. The final document shows the same saved values; the document template does not recalculate them.

## Troubleshooting

| Problem                           | What it means                         | What to do                                                       |
| --------------------------------- | ------------------------------------- | ---------------------------------------------------------------- |
| A line appears in the wrong phase | Its Quote Line Group is wrong.        | Move it in the Quote Line Editor, calculate, and generate again. |
| A family is unnamed               | The source Product Family is blank.   | Set Product Family on the Product and generate again.            |
| Families appear outside phases    | Grouping levels or sequences changed. | Restore Level 1/Sequence 10 and Level 2/Sequence 20.             |
| Status is Failed                  | Generation rejected data or grouping. | Read **Document Data Error** and correct the named cause.        |

## Deactivate or roll back

Clear **Active** on **Quote Group and Family Detail**, save, and generate again. Do not delete generated records manually. Restore this guide's settings to reactivate.

## Production checklist

- [ ] Every included line has the correct Quote Line Group.
- [ ] Every included Product has a Product Family.
- [ ] Outer and inner headings appear in the intended order.
- [ ] Subtotals reconcile to the Quote.
- [ ] The named report and document preview match saved rows.

If generation fails, read **Document Data Error** on the Quote, correct the configuration or source Quote data, and generate again.
