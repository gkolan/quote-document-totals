# View generated tables and rows in related lists

## Status and scope

**Repository status:** Fact, Table, Column, Row, and Block relationships, fields, and permission-set access ship. Table and Row tabs ship.

**Org verification status:** Objects are tested. Related-list placement and user visibility require manual org configuration.

## Use case scenario

An administrator needs to inspect the saved records behind a generated document without running SOQL.

## What this produces

Quote → Facts, Tables, Rows, and Blocks navigation for record-level troubleshooting, with useful columns visible on each layout.

## Before you start

Identify the administrator Quote and Table layouts and confirm the permission set is assigned.

**Stop here if** ordinary sales users must not see diagnostic amounts or identity fields and layout/permission requirements have not been approved.

## Terms in plain language

| Term           | Meaning                                                       |
| -------------- | ------------------------------------------------------------- |
| Related list   | Child records shown on a parent record page.                  |
| Document Table | One generated document section for one Quote.                 |
| Document Row   | One heading, detail, subtotal, section total, or Grand Total. |
| Document Fact  | One typed header value, such as Customer or Expiration Date.  |
| Document Block | Reviewed wording at document, Table, or Row level.            |
| Display Order  | Saved numeric print order.                                    |
| Inclusion flag | Whether a row contributes to a subtotal or Grand Total.       |

## Configure in Salesforce

### Configure the related lists

1. In **Setup → Object Manager → Quote → Page Layouts**, open the layout used by administrators.
2. Add the **Document Tables** related list. This is the relationship from `Quote_Document_Table__c.Quote__c`.
3. Add the **Document Facts** and **Quote Document Blocks** related lists to the same Quote layout.
4. Configure Table columns such as Table Code, Display Title, Display Order, Status, Row Count, Generated On, Locale, Source Identity, and Source Version.
5. Configure Fact columns such as Fact Code, Display Label, Data Type, Display Order, and the applicable typed value.
6. Configure Block columns such as Block Code, Placement, Related Table, Related Row, Source Version, and Approval Identity.
7. In **Object Manager → Quote Document Table → Page Layouts**, add the **Rows** and **Columns** related lists.
8. Configure Row columns such as Display Order, Row Type, Total Role, Display Label, Product Code, Quantity, Unit Price, displayed amount fields, Include in Grand Total, and Is Displayed.
9. Assign the `CPQ_Document_Totals` permission set and confirm the **Quote Document Tables** and **Quote Document Rows** tabs are visible to administrators who need direct access.

## Worked example

Generate a Quote with Product Family Summary. Navigate from the Quote to its table code `PRODUCT_FAMILY_SUMMARY`, then to its rows. Confirm Software, Services, and Grand Total appear in ascending Display Order.

### How to inspect one Quote

1. Confirm the Quote status is `Ready`.
2. Open **Document Tables** and select the table whose code matches the document section.
3. Confirm the table status is `Complete`, its locale and generation time are correct, and its row count is plausible.
4. Open **Rows** and sort by **Display Order** ascending.
5. Inspect row type, indentation level, display label, visibility, and inclusion flags before inspecting amounts.

### Intended use

Related lists are a record-level troubleshooting tool, not the primary document preview. Their default presentation is flat, sorting is easy to lose, and they do not reproduce the full ordered document. Use **Quote Document - Rendered View** for human review and the ordered data supplied to the document tool for the final document.

## Generate and verify

- A permitted administrator can navigate Quote → Document Table → Rows.
- A normal sales user sees only the access the organization intends.
- Row order is explicitly sorted by `Display_Order__c`.
- The records agree with the Rendered View report and the generated document.

## Troubleshooting

| Problem                      | What it means                                              | What to do                                                |
| ---------------------------- | ---------------------------------------------------------- | --------------------------------------------------------- |
| Related list is missing      | Wrong layout or relationship was selected.                 | Add the list to the assigned layout.                      |
| Rows appear unordered        | Related list sort is not Display Order ascending.          | Change the related-list sort.                             |
| User sees no records         | Permission set or record access is missing.                | Verify object/field and Quote access.                     |
| Records differ from document | Document is reading another result or sorting differently. | Confirm Quote Ready, Request Id, and saved Display Order. |

## Deactivate or roll back

Restore the prior page layouts or remove diagnostic columns if access is too broad. Layout rollback does not delete data. Never edit or delete generated records from related lists.

## Production checklist

- [ ] Administrator can navigate Quote → Table → Rows.
- [ ] Columns and ascending Display Order are configured.
- [ ] Sales visibility matches the approved access model.
- [ ] Related lists agree with Rendered View.
- [ ] Users understand related lists are diagnostic, not the final document.
