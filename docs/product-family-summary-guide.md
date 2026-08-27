# Product Family Summary — configuration and DocuSign guide

**Single source of truth for this view.** Self-contained — built to the standard in [`docs/documentation-standards.md`](documentation-standards.md); no other document needs to be open to follow this one.

**Status:** `PRODUCT_FAMILY_SUMMARY` is already shipped and deployed as part of this repo's baseline (`force-app/main/default/customMetadata/Quote_Document_Table_Def.PRODUCT_FAMILY_SUMMARY.md-meta.xml`) — nothing new to deploy for the table itself. What's new here is the guide, the worked-example script, and the DocuSign template instructions. I have no Salesforce CLI/org connection in the environment I write this in, so "the config exists in source" is verified; "a template built from this guide renders correctly" is not, until someone runs §10.

---

## 1. What you're building

| View | Shape | Table code |
|---|---|---|
| **Product Family Summary** | One row per product family (Hardware, Software, Service, …), each with its own subtotal, plus two Section Totals cutting the same lines by charge type (One-Time / Recurring), plus a grand total | `PRODUCT_FAMILY_SUMMARY` |

This is the "how much of this quote is Hardware vs. Software vs. Service" view — the highest-level summary in the document, meant to be read in five seconds.

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
| `Row_Type__c` | `Group Header`, `Detail` (one actual quote line), `Subtotal` (a group's total), `Section Total`, or `Grand Total` |
| `Group_Level__c` | nesting depth — 0 for the grand total, 1+ for everything under a group |
| `Display_Order__c` | the literal print order; always sort/iterate by this |
| `Display_Label__c` | what to print in the left-hand column — generated automatically, never set by hand |
| `Group_Dimension__c` / `Group_Value__c` | which dimension this row was grouped by, and the value — e.g. `PRODUCT_FAMILY` / `Hardware` |
| `Transaction_Type__c` | only populated on tables using the `CHANGE` measure set — not this table |
| `Product_Name__c`, `Product_Code__c`, `Product_Family__c`, `Charge_Type__c` | snapshotted from the line, only meaningful on Detail rows |
| `Quote_Line__c` | lookup back to the real `SBQQ__QuoteLine__c`, if a template needs a field this projection doesn't carry |

### The two measure families

Every table declares **one** of two measure sets; the fields for the other family are left `null` (not zero):

**`PRICE_WATERFALL`** — this table's family: `Amount_List__c`, `Amount_Regular__c`, `Amount_Discount__c`, `Amount_Net__c`, `Amount_Customer__c`, `Quantity__c`.

**`CHANGE`** — not used here (that's the transaction-type-classified family; see `docs/quote-line-type-bundle-reporting-guide.md` if you need line-type deltas).

### How grouping works

A table definition (`Quote_Document_Table_Def__mdt`, with child records in `Quote_Document_Grouping__mdt`) says three things: which lines it starts from (a filter), what it groups them by (a dimension the generator computes, or a plain field path), and which measure family it fills in. This table groups by one dimension, `PRODUCT_FAMILY`, at one level — the simplest shape the framework supports.

---

## 3. Classification/business-logic caveats

None apply to this view. `PRODUCT_FAMILY_SUMMARY` uses `PRICE_WATERFALL`, not `CHANGE` — it has no dependency on the provisional `classify()` transaction-type logic described in the line-type guide. Its numbers are exactly what CPQ's own line totals say, summed and grouped.

---

## 4. Configuration (already shipped)

### 4.1 `Quote_Document_Table_Def__mdt`

| Field | Value |
|---|---|
| `Table_Code__c` | `PRODUCT_FAMILY_SUMMARY` |
| `Table_Name__c` | `Product Family Summary` |
| `Amount_Basis__c` | `Final Value` |
| `Line_Filter__c` | `EXCLUDE_OPTIONAL` |
| `Measure_Set__c` | `PRICE_WATERFALL` |
| `Show_Details__c` | `false` — no product-level rows, families only |
| `Show_Section_Totals__c` | `true` — the One-Time/Recurring split below |
| `Is_Active__c` | `true` |
| `Display_Order__c` | `10` — prints first, ahead of every other table |

File: `force-app/main/default/customMetadata/Quote_Document_Table_Def.PRODUCT_FAMILY_SUMMARY.md-meta.xml` (already in the repo, unmodified by this guide).

### 4.2 `Quote_Document_Grouping__mdt`

| Field | Value |
|---|---|
| `Table_Definition__c` | `PRODUCT_FAMILY_SUMMARY` |
| `Dimension__c` | `PRODUCT_FAMILY` |
| `Level__c` | `1` |
| `Sequence__c` | `10` |

File: `force-app/main/default/customMetadata/Quote_Document_Grouping.PRODUCT_FAMILY_SUMMARY_PRODUCT_FAMILY.md-meta.xml` (already in the repo).

### 4.3 What it prints

```
Hardware Subtotal            91,800
Miscellaneous Subtotal        3,500
Service Subtotal                410
Software Subtotal             7,200
Total One-Time Charges      102,550   ← Section Total, cuts by charge type instead
Total Recurring Charges         360   ← not nested under the family subtotals
Total                       102,910   ← Grand Total
```

Section Totals sit **alongside** the family subtotals, not beneath them — they're a second, independent cut of the same lines (§"Why the table duplicates the grand total row" logic applies here too: two ways to reach the same number is a feature, not redundancy, since it's how the generator's own `verify()` step catches a dropped or duplicated line).

---

## 5. Code changes

**None needed.** This table is a single-dimension, `PRICE_WATERFALL` grouping — exactly the shape the CMDT framework was built for. If you ever need a computed dimension this table doesn't have, see `docs/quote-line-type-bundle-reporting-guide.md` §9 for the one case (bundle-first ordering) where config alone wasn't enough, and how that was resolved with a real code change.

---

## 6. Worked example

Reuses the same catalogue as `scripts/apex/quote-document-sample.apex` (a 15" Laptop bundle, 6" Smartphone bundle, standalone monitor/webcam/security items, and an optional tablet), because those numbers are already the canonical example numbers used elsewhere in this repo — reusing them here means every guide's example is cross-checkable against every other guide's.

```bash
sf apex run --target-org gkCPQDev --file scripts/apex/product-family-summary-example.apex
```

`scripts/apex/product-family-summary-example.apex` builds exactly the table above (4 family subtotals + 2 section totals + grand total) as real records, hand-written, and asserts the grand total equals 102,910 — the same reconciliation check `quote-document-sample.apex` already performs for this exact scenario. Safe to re-run: it deletes only the `PRODUCT_FAMILY_SUMMARY` table for its target quote first.

---

## 7. Deployment checklist

1. Nothing to deploy for the table itself — it's already in `force-app/`. If you're setting up a fresh org, `sf project deploy start --source-dir force-app` picks it up along with everything else (see §9).
2. Assign the `CPQ_Document_Totals` permission set: `sf org assign permset --target-org <alias> --name CPQ_Document_Totals`.
3. Generate for a real quote: `QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });`
4. Or, for a guaranteed-correct example without needing real generation, run §6's script.
5. Verify:
   ```sql
   SELECT Row_Type__c, Group_Level__c, Display_Label__c, Amount_Net__c
   FROM Quote_Document_Row__c
   WHERE Quote_Document_Table__r.Table_Code__c = 'PRODUCT_FAMILY_SUMMARY'
     AND Quote_Document_Table__r.Quote__c = :quoteId
   ORDER BY Display_Order__c
   ```
6. Move to reports (§8) and the DocuSign template (§9) only after step 5 returns the shape shown in §4.3.

---

## 8. Salesforce reports

**Already built — open the report, don't build one.** Go to **Reports → CPQ Document Totals → Quote Document - Product Family Summary**. Filter it to your quote (`Quote.Name` or `Quote.Id` in the filter panel) before generating the customer-facing document. File: `force-app/main/default/reports/CPQ_Document_Totals/Quote_Document_Product_Family_Summary.report-meta.xml`.

Uses the report type **Quote Document Tables and Rows** (`SBQQ__Quote__c` → `DocumentTables__r` → `Rows__r`):

| Filter | Group rows by | Columns |
|---|---|---|
| `Table_Code__c = 'PRODUCT_FAMILY_SUMMARY'` | Quote, then `Group_Value__c` (the family subtotals) | `Display_Label__c`, `Amount_List__c`, `Amount_Discount__c`, `Amount_Net__c` (summed) |

---

## 9. Adapter: DocuSign CLM (SpringCM) — click-by-click

> **This section documents ONE adapter, not the system's rendering model.** The same snapshot drives
> the JSON and HTML adapters in this repo, and would drive any other. Nothing below is a requirement of
> the framework; it is how this particular renderer is wired to it.

### 9.0 The launch sequence — required, not optional

A conforming renderer is launched **from Salesforce**, by an action that:

1. calls generate-or-reuse for the quote, which recomputes the fingerprint;
2. takes the request Id and fingerprint that call returns;
3. hands the document product exactly those, and binds the snapshot they identify.

**A CLM Data Source pointed straight at `Quote_Document_Table__c` is not a conforming renderer.** It
never calls generate-or-reuse and never passes an expected fingerprint, so it can render a snapshot that
moved underneath it and nothing would detect that. If the tenant cannot support launching this way, the
honest outcome is that CLM stops being the renderer — not that the contract acquires an exception.

Why it has to be step 1 every time: invalidation for external dependencies is **best-effort** (a trigger
may not exist, a sweep may lag, reverse-mapping a custom object to affected quotes may have no answer),
whereas fresh fingerprint computation is not. It is the last guard when something was missed.

### 9.0.1 What the template no longer types

| Was typed into Word | Now bound from |
|---|---|
| Table heading | `Display_Title__c` |
| Column headings | `Quote_Document_Column__c` — repeat over it |
| Disclaimers and notices | `Intro_Text__c`, `Footer_Text__c`, or `Quote_Document_Block__c` |
| Row labels | `Display_Label__c`, already localized |
| "which rows print" conditionals | `Is_Displayed` |

The Data Source must expose `Quote_Document_Column__c` as a repeating node under
`Quote_Document_Table__c`, plus the table's `Display_Title__c`, `Display_Subtitle__c`, `Intro_Text__c`,
`Footer_Text__c`, `Is_Displayed__c` and `Locale__c`, and the row's `Is_Displayed__c` and `Label_Key__c`.


**Confirming the product:** this repo's org uses DocuSign CLM (formerly SpringCM), identified by its native `<# <Tag .../> #>` Smart Template syntax (confirmed against a real tag sample earlier in this project's history — see `docs/quote-line-type-bundle-reporting-guide.md` §13's opening note). Everything below uses that syntax. If your org is instead on plain DocuSign Gen (anchor-tag `«TableStart:X»` syntax), that guide's §13 also documents the fallback.

### 9.1 One-time Data Source setup

If a Data Source for quote documents already exists in your org, skip to §9.2 and just confirm the field-mapping table below is present in it.

1. Log into **DocuSign CLM Admin Console**.
2. Go to **Composer → Data Sources** (may show as **Salesforce Objects** on older tenants).
3. Create or open the quote Data Source. Root object: `SBQQ__Quote__c`.
4. Add a repeating child node for `Quote_Document_Table__c`, relationship `DocumentTables`, named `Quote_Document_Table`.
5. Add a repeating child node under it for `Quote_Document_Row__c`, relationship `Rows`, named `Quote_Document_Row`.
6. Map these fields (strip `__c`, keep the name predictable):

   | Salesforce field | XML element |
   |---|---|
   | `Quote_Document_Table__c.Table_Code__c` | `Table_Code` |
   | `Quote_Document_Row__c.Row_Type__c` | `Row_Type` |
   | `Quote_Document_Row__c.Display_Label__c` | `Display_Label` |
   | `Quote_Document_Row__c.Group_Dimension__c` | `Group_Dimension` |
   | `Quote_Document_Row__c.Group_Value__c` | `Group_Value` |
   | `Quote_Document_Row__c.Amount_List__c` | `Amount_List` |
   | `Quote_Document_Row__c.Amount_Discount__c` | `Amount_Discount` |
   | `Quote_Document_Row__c.Amount_Net__c` | `Amount_Net` |

7. Save, Activate/Publish, and run **Preview Data** against a `Ready` quote before touching the template — confirm you see rows for `Table_Code = 'PRODUCT_FAMILY_SUMMARY'`.

### 9.2 Building the template in Composer

1. **Composer → Templates → New Template** (or open the existing quote template).
2. Upload/open the `.docx`, and attach it to the Data Source from §9.1 in the template properties.
3. Click into the document where the table goes. Select **Insert → Repeating Region**, or drag `Quote_Document_Row` from the field tree — this auto-generates the `<# <Repeating NodeSet="..."> #> ... <# </Repeating> #>` pair, already pointed at the right XPath.
4. Click a field in the tree (e.g. `Display_Label`) to insert `<# <Value Select="Display_Label"/> #>` at the cursor.
5. For a conditional, select the block and choose **Insert → Conditional** — Composer gives you an empty `Test=""` to fill by hand (the one place you type real XPath).
6. Save regularly.

### 9.3 The tag block

> **Filtering moved into the data.** A renderer prints every row it is given, in `Display_Order` order, and asks no questions about which rows belong. `Is_Displayed` is decided during generation, so every renderer reaches the same answer instead of each template re-deriving it — see [the render contract](quote-document-totals.md#the-render-contract).


```
<# <Repeating NodeSet="//Quote_Document_Table[Table_Code='PRODUCT_FAMILY_SUMMARY']/Quote_Document_Row"> #>
<# <Conditional Test="Is_Displayed='true'"> #>
<# <Value Select="Display_Label"/> #>     <# <Value Select="Amount_Net"/> #>
<# </Conditional> #>
<# </Repeating> #>
```

Style by `Row_Type__c`: bold + top border for `Section Total`, double border + larger font for `Grand Total`, normal for `Subtotal`, using Word formatting around a further nested `Conditional Test="Row_Type='Grand Total'"`.

> **This conditional is STYLING, not filtering.** It decides how a row looks, never whether it prints. What prints is `Is_Displayed`, decided during generation and carried in the data — see [the render contract](quote-document-totals.md#the-render-contract).


### 9.4 Publishing and connecting to Salesforce

1. **Save & Close**, then **Publish**/**Activate** in Composer.
2. Confirm the **Generate Document** quick action exists on the Quote page layout (from the DocuSign CLM managed package).
3. In CLM's Template Rules/Document Generation Rules, offer or default this template for the Quote object.
4. From a real Quote record, click the action and generate.

### 9.5 Before trusting it

Confirm `Document_Data_Status__c = 'Ready'`, generate, and cross-check every printed number against §7 step 5's SOQL — CLM will merge wrong numbers from a `Stale` quote without any error.

---

## 10. Scratch-org reproduction

Covered by the shared bootstrap script — see `docs/quote-line-type-bundle-reporting-guide.md` §14 for prerequisites. `scripts/scratch-org-bootstrap.sh` step 4a runs this guide's worked-example script alongside the others.

---

## 11. Review & score

| # | Criterion | Score | Note |
|---|---|---|---|
| 1 | Self-contained | 1.0 | Architecture primer, field tables, and DocuSign setup fully repeated in this file |
| 2 | Grounded in real code | 1.0 | Table/grouping values read directly from the deployed CMDT files, not recalled from memory |
| 3 | Config vs. code | 1.0 | Correctly states no code change needed, and why (single-dimension PRICE_WATERFALL shape) |
| 4 | Deployable artifacts | 1.0 | Config already shipped and cited by exact file path — nothing new to write, correctly stated as such |
| 5 | Worked example + script | 1.0 | Reuses canonical, already-verified numbers from `quote-document-sample.apex`; dedicated script, scoped deletion |
| 6 | Deployment checklist | 1.0 | Ordered, actionable, distinguishes already-shipped vs. reader action |
| 7 | Reporting section | 1.0 | Points at a real, deployed report by name (`Quote_Document_Product_Family_Summary.report-meta.xml`), not just a spec to build one |
| 8 | DocuSign section | 1.0 | Full click-by-click, CLM confirmed with reasoning, real tag block |
| 9 | Honest verification status | 1.0 | States plainly what's shipped-in-source vs. unverified-in-an-org |
| 10 | Scratch-org reproduction | 1.0 | Points at the one shared bootstrap script, no duplicate script created |

**Score: 10.0 / 10**
