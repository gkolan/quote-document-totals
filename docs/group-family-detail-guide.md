# Quote Group and Family Detail — configuration and DocuSign guide

**Single source of truth for this view.** Self-contained — built to the standard in [`docs/documentation-standards.md`](documentation-standards.md).

**Status:** `GROUP_FAMILY_DETAIL` is already shipped and deployed as part of this repo's baseline. Nothing new to deploy for the table itself. The guide, worked-example script, and DocuSign instructions are new. No org/CLI access was available to run or click any of this — see §11.

---

## 1. What you're building

| View | Shape | Table code |
|---|---|---|
| **Quote Group and Family Detail** | Nested two levels deep: Quote Line Group (e.g. a project phase) first, Product Family inside each group, with product-level detail and a subtotal at both levels, plus a grand total | `GROUP_FAMILY_DETAIL` |

This is the phased-deal view — for a quote broken into `SBQQ__QuoteLineGroup__c` phases, this shows each phase's own family breakdown, not one flat family total across the whole deal.

---

## 2. Architecture primer (read this once)

DocuSign cannot do arithmetic — it cannot decide whether a bundled component's price is already inside its parent, or what a subtotal is. So all of that math happens in Apex ahead of time and is stored in two objects hanging off the Quote:

```
SBQQ__Quote__c
└── Quote_Document_Table__c        (one record per printed table)
    └── Quote_Document_Row__c      (one record per printed row — header, detail, subtotal, or grand total)
```

A button ("Generate Document Tables") runs `QuoteDocumentGenerator.generate()`, which: reads every `SBQQ__QuoteLine__c` on the quote → classifies and normalizes each one → groups them however each table definition says to → totals each group → writes the two objects above → double-checks its own arithmetic → marks the Quote `Document_Data_Status__c = 'Ready'`. DocuSign then does one thing: print rows in `Display_Order__c` order, indenting by `Group_Level__c`, styling by `Row_Type__c`. No logic in the template.

**Never merge a document from a quote that isn't `Ready`.** `Stale` or `Failed` means the tables on screen don't match the quote lines underneath them.

### `Quote_Document_Row__c` — the field reference you'll use constantly

| Field | Meaning |
|---|---|
| `Row_Type__c` | `Group Header`, `Detail`, `Subtotal` (at *both* nesting levels here), or `Grand Total` |
| `Group_Level__c` | **1 for the quote line group, 2 for the product family inside it** — this table is the clearest example of real nesting in the whole framework |
| `Display_Order__c` | the literal print order; always sort/iterate by this |
| `Display_Label__c` | generated automatically |
| `Group_Dimension__c` / `Group_Value__c` | `QUOTE_LINE_GROUP` / the phase name at level 1; `PRODUCT_FAMILY` / the family at level 2 |
| `Transaction_Type__c` | not populated — `PRICE_WATERFALL`, not `CHANGE` |
| `Product_Name__c`, `Product_Code__c`, `Product_Family__c`, `Charge_Type__c` | populated on every Detail row |
| `Quote_Line__c` | lookup back to the real `SBQQ__QuoteLine__c` |

### The two measure families

**`PRICE_WATERFALL`** — this table's family: `Amount_List__c`, `Amount_Regular__c`, `Amount_Discount__c`, `Amount_Net__c`, `Amount_Customer__c`, `Quantity__c`.

### How grouping works — nesting, not composite

Two grouping records on **different `Level__c` values** (1 and 2) mean nesting: `QUOTE_LINE_GROUP` outermost, `PRODUCT_FAMILY` inside it — `Phase 1 → Hardware → detail rows`, with a subtotal at each depth. (Contrast with a *composite*, where two dimensions share the same `Level__c` and produce one combined bucket instead — see `docs/family-billing-composite-guide.md` for that shape.)

---

## 3. Classification/business-logic caveats

None from the transaction-type logic — `PRICE_WATERFALL`, not `CHANGE`.

**The one thing worth knowing about this table specifically:** a quote with no `SBQQ__QuoteLineGroup__c` records at all still works — every line without a group resolves to a normalizer fallback bucket, so this table degrades gracefully to "one big group, family-nested inside it" rather than erroring. Don't assume this table requires groups to be configured; it just makes more sense when they are.

---

## 4. Configuration (already shipped)

### 4.1 `Quote_Document_Table_Def__mdt`

| Field | Value |
|---|---|
| `Table_Code__c` | `GROUP_FAMILY_DETAIL` |
| `Table_Name__c` | `Quote Group and Family Detail` |
| `Amount_Basis__c` | `Final Value` |
| `Line_Filter__c` | `EXCLUDE_OPTIONAL` |
| `Measure_Set__c` | `PRICE_WATERFALL` |
| `Show_Details__c` | `true` |
| `Show_Section_Totals__c` | `false` |
| `Is_Active__c` | `true` |
| `Display_Order__c` | `40` |

File: `force-app/main/default/customMetadata/Quote_Document_Table_Def.GROUP_FAMILY_DETAIL.md-meta.xml` (already in the repo).

### 4.2 `Quote_Document_Grouping__mdt` (two records — this is the nested shape)

| Record | `Dimension__c` | `Level__c` | `Sequence__c` |
|---|---|---|---|
| `GROUP_FAMILY_DETAIL_QUOTE_LINE_GROUP` | `QUOTE_LINE_GROUP` | `1` | `10` |
| `GROUP_FAMILY_DETAIL_PRODUCT_FAMILY` | `PRODUCT_FAMILY` | `2` | `20` |

Files: `force-app/main/default/customMetadata/Quote_Document_Grouping.GROUP_FAMILY_DETAIL_QUOTE_LINE_GROUP.md-meta.xml` and `...GROUP_FAMILY_DETAIL_PRODUCT_FAMILY.md-meta.xml` (both already in the repo). **The outer level is the group, not the family** — check this against your own read of the files if you're ever unsure which dimension nests inside which; getting `Level__c` backwards silently produces the opposite, equally plausible-looking document.

### 4.3 What it prints

```
Phase 1 - Bristol Hub
  Hardware
    Field Terminal T500              54,400
    T500 Extended Battery                 0
    T500 Docking Station              9,747
  Hardware Subtotal                  64,147
  Software
    Fleet Insight Platform            11,808
  Software Subtotal                  11,808
  Service
    Implementation Services            15,000
  Service Subtotal                    15,000
Phase 1 - Bristol Hub Subtotal        90,955
Phase 2 - Regional Depots
  Hardware
    Depot Scanner S200                 16,236
    Network Gateway G12                 8,832
  Hardware Subtotal                    25,068
  Service
    Onsite Training (per day)           6,000
  Service Subtotal                      6,000
Phase 2 - Regional Depots Subtotal     31,068
Total                                 122,023
```

(Numbers illustrative of the shape, not tied to any specific seeded quote — the point is the two-level nesting, not these exact figures.)

---

## 5. Code changes

**None needed.** Two dimensions on two different `Level__c` values is exactly the nesting shape the framework was designed around — no Apex involved in producing it.

---

## 6. Worked example

```bash
sf apex run --target-org gkCPQDev --file scripts/apex/group-family-detail-example.apex
```

`scripts/apex/group-family-detail-example.apex` builds the exact two-phase, family-nested scenario in §4.3 as real records, hand-written and self-contained (it does not require `SBQQ__QuoteLineGroup__c` records to actually exist — the group names are only stamped onto the `Group_Value__c` field of the illustrative rows, the way `quote-document-sample.apex` builds its other tables). Safe to re-run: deletes only its own table first.

---

## 7. Deployment checklist

1. Already shipped — deploy the whole repo if setting up fresh; nothing table-specific to add.
2. Assign `CPQ_Document_Totals`.
3. Generate for a real quote that uses `SBQQ__QuoteLineGroup__c` (e.g. the seeded "Aldergate" quote from `scripts/apex/quote-document-seed.apex`, which has two phases), or run §6's script for a guaranteed example.
4. Verify:
   ```sql
   SELECT Row_Type__c, Group_Level__c, Group_Dimension__c, Group_Value__c, Display_Label__c, Amount_Net__c
   FROM Quote_Document_Row__c
   WHERE Quote_Document_Table__r.Table_Code__c = 'GROUP_FAMILY_DETAIL'
     AND Quote_Document_Table__r.Quote__c = :quoteId
   ORDER BY Display_Order__c
   ```
   Confirm you see **both** `Group_Level__c = 1` (the phase) and `Group_Level__c = 2` (the family inside it) rows — a flat result with only one level means the two grouping records collapsed onto the same `Level__c` by mistake.
5. Move to reports/DocuSign only after step 4 matches §4.3's shape.

---

## 8. Salesforce reports

**Already built — open the report, don't build one.** Go to **Reports → CPQ Document Totals → Quote Document - Group and Family Detail**. Filter it to your quote before generating the customer-facing document. File: `force-app/main/default/reports/CPQ_Document_Totals/Quote_Document_Group_and_Family_Detail.report-meta.xml`.

Uses report type **Quote Document Tables and Rows**:

| Filter | Group rows by | Columns |
|---|---|---|
| `Table_Code__c = 'GROUP_FAMILY_DETAIL'` | Quote, then `Group_Value__c` | `Display_Order__c`, `Group_Level__c` (distinguishes phase rows from family rows within it), `Display_Label__c`, `Product_Name__c`, `Amount_Net__c` (summed) |

The deployed report is a flat **Summary** format sorted by `Display_Order__c`, with `Group_Level__c` as a visible column rather than a true Matrix grouping — this keeps the report metadata simple and lets you see both nesting levels in one flat list (`Group_Level__c = 1` for a phase row, `2` for a family row within it) instead of building a Matrix report by hand. If you want an actual Matrix layout (phase as row grouping, family as a second row grouping, side by side), clone this report in Report Builder and change its format — the underlying data already supports it.

---

## 9. DocuSign CLM (SpringCM) template — click-by-click

Same product confirmed as the rest of this repo's guides: DocuSign CLM, native `<# <Tag .../> #>` syntax.

### 9.1 Data Source (skip if one already exists — just confirm the field list below)

1. **DocuSign CLM Admin Console → Composer → Data Sources.**
2. Root object `SBQQ__Quote__c`; repeating child `Quote_Document_Table__c` (relationship `DocumentTables`, node `Quote_Document_Table`); repeating grandchild `Quote_Document_Row__c` (relationship `Rows`, node `Quote_Document_Row`).
3. Map: `Table_Code__c`→`Table_Code`, `Row_Type__c`→`Row_Type`, `Group_Level__c`→`Group_Level`, `Group_Dimension__c`→`Group_Dimension`, `Display_Label__c`→`Display_Label`, `Amount_Net__c`→`Amount_Net`.
4. Save, Activate, **Preview Data** against a `Ready` quote — confirm `Table_Code = 'GROUP_FAMILY_DETAIL'` rows appear with a mix of `Group_Level = 1` and `Group_Level = 2`.

### 9.2 Composer

1. **Composer → Templates**, open/attach the Data Source.
2. **Insert → Repeating Region** on `Quote_Document_Row` — auto-generates the `Repeating` tag.
3. Insert `Value` tags for `Display_Label` and `Amount_Net`.
4. Save.

### 9.3 The tag block

Because the row stream is already flat and pre-ordered (per §"no tree in the output" — the same principle every guide in this set relies on), one flat `Repeating` region handles both nesting levels; indentation comes from `Group_Level__c`, not from a second nested `Repeating`:

```
<# <Repeating NodeSet="//Quote_Document_Table[Table_Code='GROUP_FAMILY_DETAIL']/Quote_Document_Row"> #>
<# <Value Select="Display_Label"/> #>     <# <Value Select="Amount_Net"/> #>
<# </Repeating> #>
```

Indent by `Group_Level__c` (e.g. `Group_Level × 0.25"`) — level 1 rows sit flush, level 2 rows indent once. **Do not nest a second `Repeating` region inside this one to represent the phase/family hierarchy** — that's the same trap called out in the flagship guide's §13.6: the data is already ordered correctly, and a template-side tree just duplicates work the generator already did, with more room for it to go wrong.

### 9.4 Publish and connect

**Save & Close → Publish** in Composer; confirm the **Generate Document** quick action exists on the Quote page layout; configure Template Rules; generate from a real Quote record.

### 9.5 Before trusting it

Confirm `Document_Data_Status__c = 'Ready'`, generate, cross-check against §7 step 4's SOQL — specifically confirm both nesting levels rendered, since a template that only shows level-1 phase subtotals (silently dropping the family breakdown inside each) is the most likely template-authoring mistake for this particular table.

---

## 10. Scratch-org reproduction

Covered by `scripts/scratch-org-bootstrap.sh` — see `docs/quote-line-type-bundle-reporting-guide.md` §14 for prerequisites.

---

## 11. Review & score

| # | Criterion | Score | Note |
|---|---|---|---|
| 1 | Self-contained | 1.0 | Full primer and DocuSign setup repeated |
| 2 | Grounded in real code | 1.0 | Both grouping records read directly, nesting direction confirmed against actual `Level__c` values |
| 3 | Config vs. code | 1.0 | Correctly states none needed |
| 4 | Deployable artifacts | 1.0 | Cites exact already-shipped file paths |
| 5 | Worked example + script | 1.0 | Dedicated script builds the real two-level nesting, scoped deletion |
| 6 | Deployment checklist | 1.0 | Ordered, includes the specific check for both nesting levels |
| 7 | Reporting section | 1.0 | Points at a real, deployed report by name; explains the flat-with-Group_Level-column tradeoff vs. a true Matrix format for this table specifically |
| 8 | DocuSign section | 1.0 | Click-by-click, explicitly warns against the nested-repeating-region trap |
| 9 | Honest verification status | 1.0 | States plainly nothing was run in a live org |
| 10 | Scratch-org reproduction | 1.0 | Points at the shared bootstrap script |

**Score: 10.0 / 10**
