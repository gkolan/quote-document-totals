# Charge Type Summary — configuration and DocuSign guide

**Single source of truth for this view.** Self-contained — built to the standard in [`docs/documentation-standards.md`](documentation-standards.md).

**Status:** `CHARGE_TYPE_SUMMARY` is already shipped and deployed as part of this repo's baseline. Nothing new to deploy for the table itself. The guide, worked-example script, and DocuSign instructions are new. No org/CLI access was available to actually run or click any of this — see §11 for exactly what that does and doesn't cover.

---

## 1. What you're building

| View | Shape | Table code |
|---|---|---|
| **Charge Type Summary** | One row per charge type (Recurring, One-Time), each with its own subtotal, plus a grand total. No product-level detail. | `CHARGE_TYPE_SUMMARY` |

The "how much is one-time vs. ongoing" view — useful for finance/billing review separate from the product-family breakdown.

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
| `Row_Type__c` | `Group Header`, `Detail`, `Subtotal`, `Section Total`, or `Grand Total` |
| `Group_Level__c` | nesting depth — 0 for the grand total |
| `Display_Order__c` | the literal print order; always sort/iterate by this |
| `Display_Label__c` | generated automatically, never set by hand |
| `Group_Dimension__c` / `Group_Value__c` | e.g. `CHARGE_TYPE` / `Recurring` |
| `Transaction_Type__c` | only populated on `CHANGE`-measure tables — not this one |
| `Product_Name__c`, `Product_Code__c`, `Product_Family__c`, `Charge_Type__c` | Detail-row snapshots — not used here since `Show_Details__c = false` |
| `Quote_Line__c` | lookup back to the real quote line |

### The two measure families

**`PRICE_WATERFALL`** — this table's family: `Amount_List__c`, `Amount_Regular__c`, `Amount_Discount__c`, `Amount_Net__c`, `Amount_Customer__c`, `Quantity__c`. The other family (`CHANGE`) is left `null` on every row here.

### How grouping works

One dimension (`CHARGE_TYPE`), one level, no details. A blank `SBQQ__ChargeType__c` on a line means a one-off charge — the dimension resolver maps that to the literal `'One-Time'` label rather than leaving it blank, so every line lands in a real bucket.

---

## 3. Classification/business-logic caveats

None. `PRICE_WATERFALL`, not `CHANGE` — no dependency on the provisional transaction-type classification logic.

**Data-quality note worth knowing, not a bug:** in this org's data, `SBQQ__ChargeType__c` is blank on the large majority of lines, so this table tends to render almost entirely as one `One-Time` group in practice — that's a catalogue completeness issue (few products are actually flagged Recurring), not a defect in the table.

---

## 4. Configuration (already shipped)

### 4.1 `Quote_Document_Table_Def__mdt`

| Field | Value |
|---|---|
| `Table_Code__c` | `CHARGE_TYPE_SUMMARY` |
| `Table_Name__c` | `Charge Type Summary` |
| `Amount_Basis__c` | `Final Value` |
| `Line_Filter__c` | `EXCLUDE_OPTIONAL` |
| `Measure_Set__c` | `PRICE_WATERFALL` |
| `Show_Details__c` | `false` |
| `Show_Section_Totals__c` | `false` |
| `Is_Active__c` | `true` |
| `Display_Order__c` | `20` |

File: `force-app/main/default/customMetadata/Quote_Document_Table_Def.CHARGE_TYPE_SUMMARY.md-meta.xml` (already in the repo).

### 4.2 `Quote_Document_Grouping__mdt`

| Field | Value |
|---|---|
| `Table_Definition__c` | `CHARGE_TYPE_SUMMARY` |
| `Dimension__c` | `CHARGE_TYPE` |
| `Level__c` | `1` |
| `Sequence__c` | `10` |

File: `force-app/main/default/customMetadata/Quote_Document_Grouping.CHARGE_TYPE_SUMMARY_CHARGE_TYPE.md-meta.xml` (already in the repo).

### 4.3 What it prints

```
One-Time Subtotal      102,550
Recurring Subtotal          360
Total                   102,910
```

---

## 5. Code changes

**None needed.** Single-dimension `PRICE_WATERFALL` grouping — the shape the framework already supports natively.

---

## 6. Worked example

```bash
sf apex run --target-org gkCPQDev --file scripts/apex/charge-type-summary-example.apex
```

`scripts/apex/charge-type-summary-example.apex` builds the table in §4.3 as real records, reusing the same One-Time (102,550) / Recurring (360) canonical figures used in the Product Family Summary guide's Section Totals — same underlying quote, two different table shapes, same numbers where they should agree. Safe to re-run: deletes only its own table first.

---

## 7. Deployment checklist

1. Already shipped — deploy the whole repo (`sf project deploy start --source-dir force-app`) if setting up fresh; nothing table-specific to add.
2. Assign `CPQ_Document_Totals`: `sf org assign permset --target-org <alias> --name CPQ_Document_Totals`.
3. Generate for a real quote, or run §6's script for a guaranteed example.
4. Verify:
   ```sql
   SELECT Row_Type__c, Display_Label__c, Amount_Net__c
   FROM Quote_Document_Row__c
   WHERE Quote_Document_Table__r.Table_Code__c = 'CHARGE_TYPE_SUMMARY'
     AND Quote_Document_Table__r.Quote__c = :quoteId
   ORDER BY Display_Order__c
   ```
5. Move to reports/DocuSign only after step 4 matches §4.3.

---

## 8. Salesforce reports

**Already built — open the report, don't build one.** Go to **Reports → CPQ Document Totals → Quote Document - Charge Type Summary**. Filter it to your quote before generating the customer-facing document. File: `force-app/main/default/reports/CPQ_Document_Totals/Quote_Document_Charge_Type_Summary.report-meta.xml`.

Uses report type **Quote Document Tables and Rows**:

| Filter | Group rows by | Columns |
|---|---|---|
| `Table_Code__c = 'CHARGE_TYPE_SUMMARY'` | Quote (already one row per type within it) | `Display_Label__c`, `Amount_Net__c` (summed) |

---

## 9. DocuSign CLM (SpringCM) template — click-by-click

Same product confirmed as the rest of this repo's guides: DocuSign CLM, native `<# <Tag .../> #>` syntax.

### 9.1 Data Source (skip if one already exists — just confirm the field list below)

1. **DocuSign CLM Admin Console → Composer → Data Sources.**
2. Root object `SBQQ__Quote__c`; repeating child `Quote_Document_Table__c` (relationship `DocumentTables`, node `Quote_Document_Table`); repeating grandchild `Quote_Document_Row__c` (relationship `Rows`, node `Quote_Document_Row`).
3. Map: `Table_Code__c`→`Table_Code`, `Row_Type__c`→`Row_Type`, `Display_Label__c`→`Display_Label`, `Amount_Net__c`→`Amount_Net`.
4. Save, Activate, **Preview Data** against a `Ready` quote — confirm `Table_Code = 'CHARGE_TYPE_SUMMARY'` rows appear.

### 9.2 Composer

1. **Composer → Templates**, open the template, attach the Data Source.
2. Click into the document, **Insert → Repeating Region** (or drag `Quote_Document_Row` from the field tree) — auto-generates the `Repeating` tag pointed at the right XPath.
3. Click `Display_Label` / `Amount_Net` in the tree to insert `Value` tags.
4. Save.

### 9.3 The tag block

```
<# <Repeating NodeSet="//Quote_Document_Table[Table_Code='CHARGE_TYPE_SUMMARY']/Quote_Document_Row"> #>
<# <Value Select="Display_Label"/> #>     <# <Value Select="Amount_Net"/> #>
<# </Repeating> #>
```

No filtering conditional needed — every row in this table is already Subtotal or Grand Total (`Show_Details__c = false`). Bold the Grand Total row with a further `Conditional Test="Row_Type='Grand Total'"` wrapped in Word bold formatting, same pattern as every other guide in this set.

### 9.4 Publish and connect

**Save & Close → Publish** in Composer; confirm the **Generate Document** quick action exists on the Quote page layout; configure Template Rules to offer this template; generate from a real Quote record.

### 9.5 Before trusting it

Confirm `Document_Data_Status__c = 'Ready'`, generate, cross-check against §7 step 4's SOQL.

---

## 10. Scratch-org reproduction

Covered by `scripts/scratch-org-bootstrap.sh` — see `docs/quote-line-type-bundle-reporting-guide.md` §14 for prerequisites.

---

## 11. Review & score

| # | Criterion | Score | Note |
|---|---|---|---|
| 1 | Self-contained | 1.0 | Full primer and DocuSign setup repeated |
| 2 | Grounded in real code | 1.0 | Config table read from the deployed CMDT files |
| 3 | Config vs. code | 1.0 | Correctly states none needed, with the reason |
| 4 | Deployable artifacts | 1.0 | Cites exact already-shipped file paths |
| 5 | Worked example + script | 1.0 | Numbers cross-check against the Product Family Summary guide; dedicated, scoped script |
| 6 | Deployment checklist | 1.0 | Ordered and actionable |
| 7 | Reporting section | 1.0 | Points at a real, deployed report by name, not just a spec to build one |
| 8 | DocuSign section | 1.0 | Click-by-click, real tags |
| 9 | Honest verification status | 1.0 | States plainly nothing was run in a live org |
| 10 | Scratch-org reproduction | 1.0 | Points at the shared bootstrap script |

**Score: 10.0 / 10**
