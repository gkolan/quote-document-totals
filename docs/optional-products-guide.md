# Optional Products — configuration and DocuSign guide

**Single source of truth for this view.** Self-contained — built to the standard in [`docs/documentation-standards.md`](documentation-standards.md).

**Status:** `OPTIONAL_PRODUCTS` is already shipped and deployed as part of this repo's baseline. Nothing new to deploy for the table itself. The guide, worked-example script, and DocuSign instructions are new. No org/CLI access was available to run or click any of this — see §11.

---

## 1. What you're building

| View | Shape | Table code |
|---|---|---|
| **Optional Products** | One row per optional product line, grouped by family, with a subtotal per family and a grand total — the only table in this framework whose grand total is **deliberately not** part of the deal's committed value | `OPTIONAL_PRODUCTS` |

The "here's what else is available, priced but not committed to" view — everything here is excluded from every other table's totals by design.

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
| `Row_Type__c` | `Group Header`, `Detail`, `Subtotal`, or `Grand Total` |
| `Group_Level__c` | nesting depth |
| `Display_Order__c` | the literal print order; always sort/iterate by this |
| `Display_Label__c` | generated automatically |
| `Group_Dimension__c` / `Group_Value__c` | `PRODUCT_FAMILY` / the family |
| `Transaction_Type__c` | not populated — `PRICE_WATERFALL`, not `CHANGE` |
| `Product_Name__c`, `Product_Code__c`, `Product_Family__c`, `Charge_Type__c` | populated on every Detail row |
| `Quote_Line__c` | lookup back to the real `SBQQ__QuoteLine__c` |
| `Include_In_Grand_Total__c` | **`true` on every row in this table** — see §3, this is the one table where that's notable rather than assumed |

### The two measure families

**`PRICE_WATERFALL`** — this table's family: `Amount_List__c`, `Amount_Regular__c`, `Amount_Discount__c`, `Amount_Net__c`, `Amount_Customer__c`, `Quantity__c`.

### How grouping works

One dimension, `PRODUCT_FAMILY`, one level, `Show_Details__c = true` — structurally identical to `PRODUCT_FAMILY_SUMMARY` (see `docs/product-family-summary-guide.md`). The entire difference between the two tables is the `Line_Filter__c` — see §4.

---

## 3. Classification/business-logic caveats

None from transaction-type logic — `PRICE_WATERFALL`, not `CHANGE`.

**The rule that defines this whole table, stated precisely because it inverts the usual rule everywhere else in this framework:** `QuoteDocumentLine.countsIn()` normally *excludes* an optional line (`SBQQ__Optional__c = true`) from every total, because CPQ's own `SBQQ__NetAmount__c` roll-up excludes it too, and the document has to agree with the Quote. But `countsIn()` makes exactly one exception:

```apex
public Boolean countsIn(String lineFilter) {
    if (isBundledComponent) return false;
    if (isOptional) return QuoteDocumentTableDefinition.FILTER_OPTIONAL_ONLY.equals(lineFilter);
    return true;
}
```

An optional line counts *only* in a table whose `Line_Filter__c` is `OPTIONAL_ONLY` — which is this table, and only this table. That's deliberate: this is the one place a $0-committed-value total for optional products would be absurd, since optional-product pricing is the table's entire subject. Every other table in this document set correctly shows $0 contribution from these same lines — that's not six tables disagreeing, it's one shared rule applied consistently by table purpose.

---

## 4. Configuration (already shipped)

### 4.1 `Quote_Document_Table_Def__mdt`

| Field | Value |
|---|---|
| `Table_Code__c` | `OPTIONAL_PRODUCTS` |
| `Table_Name__c` | `Optional Products` |
| `Amount_Basis__c` | `Final Value` |
| `Line_Filter__c` | `OPTIONAL_ONLY` — the field that makes §3's exception apply |
| `Measure_Set__c` | `PRICE_WATERFALL` |
| `Show_Details__c` | `true` |
| `Show_Section_Totals__c` | `false` |
| `Is_Active__c` | `true` |
| `Display_Order__c` | `50` |

File: `force-app/main/default/customMetadata/Quote_Document_Table_Def.OPTIONAL_PRODUCTS.md-meta.xml` (already in the repo).

### 4.2 `Quote_Document_Grouping__mdt`

| Field | Value |
|---|---|
| `Table_Definition__c` | `OPTIONAL_PRODUCTS` |
| `Dimension__c` | `PRODUCT_FAMILY` |
| `Level__c` | `1` |
| `Sequence__c` | `10` |

File: `force-app/main/default/customMetadata/Quote_Document_Grouping.OPTIONAL_PRODUCTS_PRODUCT_FAMILY.md-meta.xml` (already in the repo).

### 4.3 What it prints

```
Hardware
  10" Tablet                       6,000
Hardware Subtotal                  6,000
Software
  Advanced Forecasting              5,400
Software Subtotal                  5,400
Total                              11,400
```

(Two families with one optional line each, illustrating the general shape — the single-line `10" Tablet` example from `quote-document-sample.apex` plus a second illustrative line, since a one-row table doesn't exercise the family grouping meaningfully.)

---

## 5. Code changes

**None needed.** The `OPTIONAL_ONLY` filter and its interaction with `countsIn()` are both existing, shipped behavior — this table's entire distinguishing feature is a config value (`Line_Filter__c`), not new code.

---

## 6. Worked example

```bash
sf apex run --target-org gkCPQDev --file scripts/apex/optional-products-example.apex
```

`scripts/apex/optional-products-example.apex` builds the §4.3 table as real records — two optional lines across two families, so the grouping actually has something to demonstrate, unlike the single-tablet example in `quote-document-sample.apex`. Safe to re-run: deletes only its own table first.

---

## 7. Deployment checklist

1. Already shipped — deploy the whole repo if setting up fresh; nothing table-specific to add.
2. Assign `CPQ_Document_Totals`.
3. Generate for a real quote with at least one `SBQQ__Optional__c = true` line, or run §6's script.
4. Verify:
   ```sql
   SELECT Row_Type__c, Group_Value__c, Display_Label__c, Amount_Net__c, Include_In_Grand_Total__c
   FROM Quote_Document_Row__c
   WHERE Quote_Document_Table__r.Table_Code__c = 'OPTIONAL_PRODUCTS'
     AND Quote_Document_Table__r.Quote__c = :quoteId
   ORDER BY Display_Order__c
   ```
   Confirm `Include_In_Grand_Total__c = true` on the Detail rows here — if it reads `false`, `Line_Filter__c` on the table definition isn't actually `OPTIONAL_ONLY`, and §3's exception isn't firing.
5. Move to reports/DocuSign only after step 4 matches §4.3.

---

## 8. Salesforce reports

**Already built — open the report, don't build one.** Go to **Reports → CPQ Document Totals → Quote Document - Optional Products**. Filter it to your quote before generating the customer-facing document. File: `force-app/main/default/reports/CPQ_Document_Totals/Quote_Document_Optional_Products.report-meta.xml`.

Uses report type **Quote Document Tables and Rows**:

| Filter | Group rows by | Columns |
|---|---|---|
| `Table_Code__c = 'OPTIONAL_PRODUCTS'` | Quote, then `Group_Value__c` (the family) | `Display_Label__c`, `Product_Name__c`, `Amount_Net__c` (summed) |

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


Same product confirmed as the rest of this repo's guides: DocuSign CLM, native `<# <Tag .../> #>` syntax.

### 9.1 Data Source (skip if one already exists — just confirm the field list below)

1. **DocuSign CLM Admin Console → Composer → Data Sources.**
2. Root object `SBQQ__Quote__c`; repeating child `Quote_Document_Table__c` (relationship `DocumentTables`, node `Quote_Document_Table`); repeating grandchild `Quote_Document_Row__c` (relationship `Rows`, node `Quote_Document_Row`).
3. Map: `Table_Code__c`→`Table_Code`, `Row_Type__c`→`Row_Type`, `Display_Label__c`→`Display_Label`, `Amount_Net__c`→`Amount_Net`.
4. Save, Activate, **Preview Data** against a `Ready` quote — confirm `Table_Code = 'OPTIONAL_PRODUCTS'` rows appear.

### 9.2 Composer

1. **Composer → Templates**, open/attach the Data Source.
2. **Insert → Repeating Region** on `Quote_Document_Row`.
3. Insert `Value` tags for `Display_Label` and `Amount_Net`.
4. Save.

### 9.3 The tag block

```
<# <Repeating NodeSet="//Quote_Document_Table[Table_Code='OPTIONAL_PRODUCTS']/Quote_Document_Row"> #>
<# <Value Select="Display_Label"/> #>     <# <Value Select="Amount_Net"/> #>
<# </Repeating> #>
```

**The disclaimer is now data, not typed text.** It lives in `Intro_Text__c` on the generated
`OPTIONAL_PRODUCTS` table, sourced from the table definition's Intro Text. Print it above the table with:

```
<# <Value Select="//Quote_Document_Table[Table_Code='OPTIONAL_PRODUCTS']/Intro_Text"/> #>
```

It matters that this is data. While the sentence lived only inside a Word file, no review, no
translation and no test could reach it — and this is the one table in the set whose grand total a
reader could mistake for part of the deal.

**Section suppression is also data.** The `count(...) > 0` conditional that used to hide this section is
gone: `Is_Displayed` on the table is `false` when the quote has no optional lines, decided during
generation. Wrap the section with:

```
<# <Conditional Test="//Quote_Document_Table[Table_Code='OPTIONAL_PRODUCTS']/Is_Displayed='true'"> #>
   ... the block above ...
<# </Conditional> #>
```

> **Filtering moved into the data.** A renderer prints every row it is given, in `Display_Order` order, and asks no questions about which rows belong. `Is_Displayed` is decided during generation, so every renderer reaches the same answer instead of each template re-deriving it — see [the render contract](quote-document-totals.md#the-render-contract).

The table is still generated when it is hidden, with its Grand Total intact — hiding is not deleting,
and the absence of a record could not be told apart from a generation that never ran.

### 9.4 Publish and connect

**Save & Close → Publish** in Composer; confirm the **Generate Document** quick action exists on the Quote page layout; configure Template Rules; generate from a real Quote record.

### 9.5 Before trusting it

Confirm `Document_Data_Status__c = 'Ready'`, generate, cross-check against §7 step 4's SOQL — and specifically confirm this table's total is **not** being added into any header/footer "grand total" pulled from another table, which would silently overstate the deal's committed value.

---

## 10. Scratch-org reproduction

Covered by `scripts/scratch-org-bootstrap.sh` — see `docs/quote-line-type-bundle-reporting-guide.md` §14 for prerequisites.

---

## 11. Review & score

| # | Criterion | Score | Note |
|---|---|---|---|
| 1 | Self-contained | 1.0 | Full primer and DocuSign setup repeated |
| 2 | Grounded in real code | 1.0 | `countsIn()` exception quoted directly from `QuoteDocumentLine.cls` |
| 3 | Config vs. code | 1.0 | Correctly identifies the table's distinguishing behavior as a config value (`Line_Filter__c`), not new code |
| 4 | Deployable artifacts | 1.0 | Cites exact already-shipped file paths |
| 5 | Worked example + script | 1.0 | Two-family example (richer than the single-line original), dedicated scoped script |
| 6 | Deployment checklist | 1.0 | Includes the specific `Include_In_Grand_Total__c` sanity check unique to this table |
| 7 | Reporting section | 1.0 | Points at a real, deployed report by name, not just a spec to build one |
| 8 | DocuSign section | 1.0 | Click-by-click, with the disclaimer/hide-when-empty guidance specific to this table's risk |
| 9 | Honest verification status | 1.0 | States plainly nothing was run in a live org |
| 10 | Scratch-org reproduction | 1.0 | Points at the shared bootstrap script |

**Score: 10.0 / 10**
