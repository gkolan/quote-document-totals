# Review generated output through Salesforce Reports

## Status and scope

**Repository status:** Report types, the **CPQ Document Totals** folder, Rendered View, failure report, totals report, and per-view reports ship. One-click Quote links do not ship.

**Org verification status:** Report metadata is present. Deployment, folder access, filters, and results require org verification.

## Use case scenario

Sales, operations, and administrators need a readable preview of saved document data before it reaches the final document tool.

## What this produces

A Salesforce review path for current saved rows and failures without treating reports as the signed document.

## Before you start

Generate a known Quote successfully and confirm the reviewer has access to the report folder, Quote, Tables, and Rows.

**Stop here if** the Quote is not Ready, reviewers intend to sum mixed row types, or a report is being treated as the exact whole-document sequence.

## Terms in plain language

| Term           | Meaning                                                                    |
| -------------- | -------------------------------------------------------------------------- |
| Rendered View  | Human review of saved rows within each generated table.                    |
| Row Type       | Heading, Detail, Subtotal, Section Total, or Grand Total.                  |
| Counted Detail | Source row intended for reconciliation without repeated totals.            |
| Report type    | Salesforce definition controlling fields available to reports.             |
| Document tool  | Tool that produces the final file; Salesforce reports are only for review. |

## Configure in Salesforce

1. Open **Setup → Reports and Dashboards Settings** and confirm reporting is enabled for intended users.
2. Open the **CPQ Document Totals** report folder and share it with the approved reviewer group.
3. Do not modify shipped reports first; clone one for org-specific filters.
4. Preserve Row Display Order ascending and required Table Code filters.

### Primary review reports

| Report                                 | Use it for                                                                                                       |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| **Quote Document - Rendered View**     | Every generated row, grouped by Quote and Table Code, with rows in display order                                 |
| **Quote Document Generation Failures** | Quotes whose last attempt failed, with the stored error                                                          |
| **Quote Document - Totals by Family**  | Detail-only reconciliation to the Quote net amount                                                               |
| Per-view reports                       | Focused review of Product Family, Charge Type, Bundle, Optional Product, Discount, and other shipped definitions |

The reports use `Quote_Document_Tables_and_Rows__c` or `Quote_Document_Status__c`. The status report type intentionally has no table join so it can include Quotes that have never generated successfully.

## Worked example

Generate a Quote whose payable Product Family rows total $15,800. Rendered View must show the same family rows and Grand Total; the detail-only reconciliation report must equal the CPQ Quote amount without summing subtotal and Grand Total rows again.

### Review one Quote

1. Confirm the Quote's **Document Data Status** is `Ready`.
2. Open **Reports → CPQ Document Totals → Quote Document - Rendered View**.
3. Select **Filters → Add Filter**, choose **Quote: Quote Name**, set the operator to **equals**, enter the exact Quote Name shown on the Quote record, and select **Apply**. If Quote Names are not unique, open a returned Quote link and verify it is the intended record before relying on the report.
4. Read rows within each table in row display order. The shipped report groups tables by Table Code rather than table display order.
5. Confirm headings, row types, indentation levels, visibility, amounts, quantities, subtotals, section totals, and grand totals.
6. Open the matching per-view report for deeper business checks.

### Reporting safety rules

- Do not sum a report that mixes Detail, Subtotal, Section Total, and Grand Total rows; that counts the same money more than once.
- A report intended to calculate totals must include only the Detail rows whose amounts count toward that total.
- Rendered View is close to the row stream, but it is not an exact whole-document sequence: it does not interleave narrative blocks and its table groups are not sorted by table `Display_Order__c`.
- Add new custom fields to the custom report type explicitly. Creating a field on the object does not expose it automatically.
- A report is a review screen, not a replacement for the final document or a signed file.

### Quote-scoped links

The repository currently contains a planning specification for one-click Quote report links, but no `Quote_Document_Report_Link__mdt`, Flow, or LWC implementation. Until that feature is built, users open the report and apply the Quote filter. Do not document planned links as deployed behavior.

## Generate and verify

- Intended users can open the folder and reports.
- Row order within every Rendered View table matches generated row `Display_Order__c`; whole-document table and block order is checked against the data supplied to the document tool.
- A failed Quote appears in **Quote Document Generation Failures**.
- A detail-only reconciliation report agrees with the Quote amount.

## Troubleshooting

| Problem                  | What it means                                          | What to do                                                              |
| ------------------------ | ------------------------------------------------------ | ----------------------------------------------------------------------- |
| Report total is too high | Mixed row types were summed.                           | Filter to the intended counted Detail rows or inspect Grand Total only. |
| Quote is absent          | Access or filters exclude it, or it has no saved rows. | Confirm Ready status, record access, and report filters.                |
| Row order differs        | Report sort is not saved Display Order.                | Restore ascending row Display Order.                                    |
| New field is unavailable | Report type does not expose it.                        | Add the field to the custom report type and redeploy/retest.            |

## Deactivate or roll back

Restore the shipped report metadata or remove access to an incorrect clone. Report changes do not justify editing generated records. Keep planned one-click links out of user instructions until implemented.

## Production checklist

- [ ] Folder sharing matches reviewer access.
- [ ] Rendered View follows row Display Order.
- [ ] Reconciliation excludes repeated totals.
- [ ] Failure report shows a controlled failed Quote.
- [ ] Reports are described as review tools, not signed artifacts.
