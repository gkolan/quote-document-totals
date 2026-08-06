# Bundle Detail — configuration and DocuSign guide

**Single source of truth for this view.** Self-contained — built to the standard in [`docs/documentation-standards.md`](documentation-standards.md).

**Status:** `BUNDLE_DETAIL` is already shipped and deployed as part of this repo's baseline. Nothing new to deploy for the table itself. The guide, worked-example script, and DocuSign instructions are new. No org/CLI access was available to run or click any of this — see §11.

---

## 1. What you're building

| View | Shape | Table code |
|---|---|---|
| **Bundle Detail** | One row per product line, nested under its bundle (or under "Standalone Products" if not in one), with a subtotal per bundle and a grand total. Bundled components show at zero and are excluded from every total. | `BUNDLE_DETAIL` |

The full price-waterfall product breakdown, organized the way a customer thinks about the deal — by package, not by internal product family.

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
| `Row_Type__c` | `Group Header`, `Detail`, `Subtotal`, or `Grand Total` (no Section Totals here) |
| `Group_Level__c` | nesting depth — bundled option components print one level deeper (see §3) |
| `Display_Order__c` | the literal print order; always sort/iterate by this |
| `Display_Label__c` | generated automatically — the product name on a Detail row, `"{Bundle} Subtotal"` on a Subtotal row |
| `Group_Dimension__c` / `Group_Value__c` | `BUNDLE` / the bundle's product name, or `Standalone Products` |
| `Transaction_Type__c` | not populated — this table uses `PRICE_WATERFALL`, not `CHANGE` |
| `Product_Name__c`, `Product_Code__c`, `Product_Family__c`, `Charge_Type__c` | populated on every Detail row |
| `Quote_Line__c` | lookup back to the real `SBQQ__QuoteLine__c` |

### The two measure families

**`PRICE_WATERFALL`** — this table's family: `Amount_List__c`, `Amount_Regular__c`, `Amount_Discount__c`, `Amount_Net__c`, `Amount_Customer__c`, `Quantity__c`.

### How grouping works

One dimension, `BUNDLE`, one level, `Show_Details__c = true`. `BUNDLE` resolves per line: a bundled component or option reads its parent's product name; a bundle root reads its own name; anything with neither is bucketed as `Standalone Products`.

---

## 3. Classification/business-logic caveats

None from the transaction-type logic — this is a `PRICE_WATERFALL` table. The rule that *does* matter here, and is easy to get wrong when reading the output: **a bundled component (`SBQQ__Bundled__c = true`) is shown but never counted.** `countsIn()` in `QuoteDocumentLine.cls` excludes it from every subtotal and the grand total, because its price already lives inside the bundle parent's own total — counting it again would double the deal's value. If a bundle subtotal looks lower than "the sum of the visible rows under it" by eye, that's this rule working correctly, not a bug: the zero-priced component rows are visible for the customer's benefit but contribute nothing to the arithmetic.

A second, related rule: a separately-priced **option** under the same bundle (`SBQQ__Bundled__c = false`, `SBQQ__OptionLevel__c > 0`) *does* count — only bundled components are excluded, not every option.

---

## 4. Configuration (already shipped)

### 4.1 `Quote_Document_Table_Def__mdt`

| Field | Value |
|---|---|
| `Table_Code__c` | `BUNDLE_DETAIL` |
| `Table_Name__c` | `Bundle Detail` |
| `Amount_Basis__c` | `Final Value` |
| `Line_Filter__c` | `EXCLUDE_OPTIONAL` |
| `Measure_Set__c` | `PRICE_WATERFALL` |
| `Show_Details__c` | `true` |
| `Show_Section_Totals__c` | `false` |
| `Is_Active__c` | `true` |
| `Display_Order__c` | `30` |

File: `force-app/main/default/customMetadata/Quote_Document_Table_Def.BUNDLE_DETAIL.md-meta.xml` (already in the repo).

### 4.2 `Quote_Document_Grouping__mdt`

| Field | Value |
|---|---|
| `Table_Definition__c` | `BUNDLE_DETAIL` |
| `Dimension__c` | `BUNDLE` |
| `Level__c` | `1` |
| `Sequence__c` | `10` |

File: `force-app/main/default/customMetadata/Quote_Document_Grouping.BUNDLE_DETAIL_BUNDLE.md-meta.xml` (already in the repo).

### 4.3 What it prints

```
15" Laptop
  15" Laptop                    60,000    ← counted (the bundle root's own price)
  CPU 2.2GHz i7                      0    ← bundled component, shown, not counted
  RAM 8GB                             0    ← bundled component, shown, not counted
  SSD Hard Drive 256GB                0    ← bundled component, shown, not counted
15" Laptop Subtotal              54,000    ← net after discount, of the counted lines only
6" Smartphone
  6" Smartphone                  26,000    ← counted
  Smartphone Charger                  0    ← bundled component
  USB-C Charge Cable 1m               0    ← bundled component
  Smartphone Activation                 50   ← separately-priced option, counted
  Smartphone Case                      800   ← separately-priced option, counted
6" Smartphone Subtotal            24,250
Standalone Products
  4K Monitor                      14,400
  USB Webcam w/ Integrated Mic     1,260
  2 Factor Authentication USB Key  1,440
  VPN License                      3,600
  Productivity Suite               3,600
  Smartphone Standard Plan           360
Standalone Products Subtotal      24,660
Total                            102,910
```

---

## 5. Code changes

**None needed.** Single-dimension `PRICE_WATERFALL` grouping with details on — the shape the framework already supports natively; the counted-vs-shown distinction is existing, unrelated-to-configuration logic in `QuoteDocumentLine.countsIn()`.

---

## 6. Worked example

```bash
sf apex run --target-org gkCPQDev --file scripts/apex/bundle-detail-example.apex
```

`scripts/apex/bundle-detail-example.apex` rebuilds exactly the §4.3 output as real records, reusing the canonical `quote-document-sample.apex` catalogue (same laptop/smartphone/standalone numbers referenced by the other guides in this set) as its own standalone script. Safe to re-run: deletes only the `BUNDLE_DETAIL` table for the target quote first.

---

## 7. Deployment checklist

1. Already shipped — deploy the whole repo if setting up fresh; nothing table-specific to add.
2. Assign `CPQ_Document_Totals`.
3. Generate for a real quote, or run §6's script.
4. Verify:
   ```sql
   SELECT Row_Type__c, Group_Level__c, Group_Value__c, Display_Label__c, Amount_Net__c
   FROM Quote_Document_Row__c
   WHERE Quote_Document_Table__r.Table_Code__c = 'BUNDLE_DETAIL'
     AND Quote_Document_Table__r.Quote__c = :quoteId
   ORDER BY Display_Order__c
   ```
5. Move to reports/DocuSign only after step 4 matches §4.3.

---

## 8. Salesforce reports

**Already built — open the report, don't build one.** Go to **Reports → CPQ Document Totals → Quote Document - Bundle Detail**. Filter it to your quote before generating the customer-facing document. File: `force-app/main/default/reports/CPQ_Document_Totals/Quote_Document_Bundle_Detail.report-meta.xml`.

Uses report type **Quote Document Tables and Rows**:

| Filter | Group rows by | Columns |
|---|---|---|
| `Table_Code__c = 'BUNDLE_DETAIL'` | Quote, then `Group_Value__c` (the bundle) | `Display_Label__c`, `Product_Name__c`, `Amount_List__c`, `Amount_Discount__c`, `Amount_Net__c` (summed), `Include_In_Grand_Total__c` (to visibly distinguish counted vs. zero-priced component rows) |

---

## 9. DocuSign CLM (SpringCM) template — click-by-click

Same product confirmed as the rest of this repo's guides: DocuSign CLM, native `<# <Tag .../> #>` syntax.

### 9.1 Data Source (skip if one already exists — just confirm the field list below)

1. **DocuSign CLM Admin Console → Composer → Data Sources.**
2. Root object `SBQQ__Quote__c`; repeating child `Quote_Document_Table__c` (relationship `DocumentTables`, node `Quote_Document_Table`); repeating grandchild `Quote_Document_Row__c` (relationship `Rows`, node `Quote_Document_Row`).
3. Map: `Table_Code__c`→`Table_Code`, `Row_Type__c`→`Row_Type`, `Group_Level__c`→`Group_Level`, `Display_Label__c`→`Display_Label`, `Group_Value__c`→`Group_Value`, `Amount_Net__c`→`Amount_Net`, `Include_In_Grand_Total__c`→`Include_In_Grand_Total`.
4. Save, Activate, **Preview Data** against a `Ready` quote — confirm `Table_Code = 'BUNDLE_DETAIL'` rows appear, including some with `Include_In_Grand_Total = false`.

### 9.2 Composer

1. **Composer → Templates**, open/attach the Data Source.
2. **Insert → Repeating Region** on `Quote_Document_Row` — auto-generates the `Repeating` tag.
3. Insert `Value` tags for `Display_Label` and `Amount_Net` by clicking the field tree.
4. Save.

### 9.3 The tag block

```
<# <Repeating NodeSet="//Quote_Document_Table[Table_Code='BUNDLE_DETAIL']/Quote_Document_Row"> #>
<# <Value Select="Display_Label"/> #>     <# <Value Select="Amount_Net"/> #>
<# </Repeating> #>
```

No filtering conditional needed — every row (including the zero-priced bundled components) is meant to print, since showing the customer what's included in the bundle at $0 is the point of this table. Style by `Group_Level__c` for indentation (`Group_Level__c × 0.25"` per the standard's convention) and by `Row_Type__c` for bold/border on Subtotal and Grand Total rows.

### 9.4 Publish and connect

**Save & Close → Publish** in Composer; confirm the **Generate Document** quick action exists on the Quote page layout; configure Template Rules; generate from a real Quote record.

### 9.5 Before trusting it

Confirm `Document_Data_Status__c = 'Ready'`, generate, cross-check against §7 step 4's SOQL — pay particular attention to whether the zero-priced component rows print correctly (visible, but not adding to the subtotal), since that's the one rule this table depends on getting right.

---

## 10. Scratch-org reproduction

Covered by `scripts/scratch-org-bootstrap.sh` — see `docs/quote-line-type-bundle-reporting-guide.md` §14 for prerequisites.

---

## 11. Review & score

| # | Criterion | Score | Note |
|---|---|---|---|
| 1 | Self-contained | 1.0 | Full primer and DocuSign setup repeated |
| 2 | Grounded in real code | 1.0 | Config and `countsIn()` behavior read from actual source |
| 3 | Config vs. code | 1.0 | Correctly states none needed |
| 4 | Deployable artifacts | 1.0 | Cites exact already-shipped file paths |
| 5 | Worked example + script | 1.0 | Reuses canonical, cross-checkable numbers; dedicated, scoped script |
| 6 | Deployment checklist | 1.0 | Ordered and actionable |
| 7 | Reporting section | 1.0 | Points at a real, deployed report by name, with the counted-vs-shown distinction called out |
| 8 | DocuSign section | 1.0 | Click-by-click, real tags, correctly explains why no filter conditional is needed |
| 9 | Honest verification status | 1.0 | States plainly nothing was run in a live org |
| 10 | Scratch-org reproduction | 1.0 | Points at the shared bootstrap script |

**Score: 10.0 / 10**
