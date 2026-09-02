# Control detail rows, section totals, and table order

## Status and scope

**Repository status:** Detail, section-total, group-sort, and document-order controls ship and are tested.

**Org verification status:** Behavior is available; each target table's approved presentation and order require sandbox proof.

## Use case scenario

An administrator needs to control how much detail a table contains and where each generated section appears in the final document.

## What this produces

Saved rows and document sections with explicit visibility and numeric order used consistently by reports and document output.

## Before you start

Write down the intended whole-document order and whether each table needs details and section totals.

**Stop here if** two sections use the same order, an expanded table is expected to show section totals, or alphabetical sorting would violate the intended business sequence.

## Terms in plain language

| Term                | Meaning                                                      |
| ------------------- | ------------------------------------------------------------ |
| Detail row          | One qualifying Quote Line.                                   |
| Section total       | Recurring or One-Time cut of the same lines.                 |
| Table Display Order | Position among every table and content block.                |
| Group sorting       | Alphabetical or original Quote Line sequence.                |
| Row Display Order   | Generated numeric order the report and document must follow. |

### Configuration controls

| Requirement                             | Field                            | Behavior                                                                    |
| --------------------------------------- | -------------------------------- | --------------------------------------------------------------------------- |
| Print one row per qualifying Quote Line | `Show_Details__c`                | Selected includes Detail rows; cleared leaves generated headings and totals |
| Add Recurring and One-Time totals       | `Show_Section_Totals__c`         | Adds a second cut of the same lines above the grand total                   |
| Order tables and standalone content     | `Display_Order__c`               | Tables and content blocks share one document-wide sequence                  |
| Order groups inside a table             | `Sort_Groups_By__c`              | `ALPHABETICAL` or `LINE_SEQUENCE`                                           |
| Order rows inside a table               | generated row `Display_Order__c` | Assigned by generation; adapters must sort by it                            |

## Configure in Salesforce

1. Open **Setup → Custom Metadata Types → Quote Document Table Definition → Manage Records**.
2. Open the definition and choose whether Detail and Section Total rows are required.
3. Set a unique table display order. Use increments of ten so later sections can be inserted without renumbering everything.
4. Set **Sort Groups By** when alphabetical order is not the intended business order.
5. Review active `Quote_Document_Content__mdt` records before choosing the number: content blocks and tables cannot share the same display order.
6. Generate from a calculated sandbox Quote.

## Worked example

Assign table orders 10 and 30 and a content block order 20. Set the first table to details off/section totals on and the second to details on/section totals off. Generated output must follow 10, 20, 30 with the selected row shapes.

For a common Quote layout using supplied records, the Product Family Summary Table is order `10`, Quote Validity Block is `2000`, and Signature Instructions Block is `2100`. One generation creates all three sections. The Table's Grand Total remains a number from its saved Rows; neither Block is added to, subtracted from, or otherwise involved in that total.

For an assumptions-first layout, place the assumptions Block immediately before its Table, such as Block `250` followed by Table `260`. Also set the Table's **Assumptions Block Code** so generation stops if the required explanation is missing. See [Combine Blocks and totals in one document](34-document-content-blocks.md#combine-blocks-and-totals-in-one-document).

### Constraints that prevent ambiguous output

- Two tables, or a table and content block, at the same document order fail with `DOCUMENT_ORDER_DUPLICATE`.
- Expanded tables cannot also show section totals because that second cross-bucket total has no agreed meaning.
- `Group_Level__c` controls indentation; it does not determine print sequence.
- Every document tool must use generated `Display_Order__c`. Sorting by label, record name, or creation date can change the document.

## Generate and verify

- The Quote is `Ready` and each saved table is `Complete`.
- Each table's rows sort by row `Display_Order__c` in **Quote Document - Rendered View**. The shipped report groups tables by Table Code, so verify whole-document table and block order from the generated `Display_Order__c` values or the data supplied to the document tool.
- Detail rows are present or absent as configured.
- Recurring and One-Time Section Total rows appear only where approved.
- Grand totals still reconcile after presentation changes.

## Troubleshooting

| Problem                         | What it means                                                  | What to do                                             |
| ------------------------------- | -------------------------------------------------------------- | ------------------------------------------------------ |
| Duplicate-order error           | Two active sections share a number.                            | Assign unique orders and generate again.               |
| Detail rows appear unexpectedly | Show Details is selected.                                      | Clear it and regenerate.                               |
| Labels sort incorrectly         | Group sort mode is wrong or document ignores saved order.      | Set the intended mode and use generated Display Order. |
| Totals changed                  | Presentation configuration affected counted rows unexpectedly. | Deactivate and reconcile generated inclusion flags.    |

## Deactivate or roll back

Clear **Active** on the affected table while correcting order or visibility. Restore previous settings and generate again; never edit generated row order manually.

## Production checklist

- [ ] Every active table and block has a unique order.
- [ ] Detail and section-total choices are approved.
- [ ] Expanded tables do not request section totals.
- [ ] Reports and documents follow generated row order.
- [ ] Grand totals remain unchanged and reconciled.
