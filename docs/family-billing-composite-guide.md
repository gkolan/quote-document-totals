# Family and Billing Composite — configuration and DocuSign guide

**Single source of truth for this view.** Self-contained — built to the standard in [`docs/documentation-standards.md`](documentation-standards.md).

**Status:** `FAMILY_BILLING_COMPOSITE` is already shipped and deployed as part of this repo's baseline. Nothing new to deploy for the table itself. The guide, worked-example script, and DocuSign instructions are new. No org/CLI access was available to run or click any of this — see §11.

---

## 1. What you're building

| View | Shape | Table code |
|---|---|---|
| **Family and Billing Composite** | One row per combined bucket — product family **and** charge type joined into a single label, e.g. `"Hardware / Recurring"` — with a subtotal per bucket and a grand total. **One level, not two.** | `FAMILY_BILLING_COMPOSITE` |

This is the "cut two ways at once, but as one flat list, not a nested tree" view — useful when a document needs "Hardware / Recurring" as a single line rather than a Hardware section with a Recurring sub-section inside it.

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
| `Group_Level__c` | **always 1 here** — a composite occupies one level, never two (that's the whole distinction from `GROUP_FAMILY_DETAIL`'s nesting; see `docs/group-family-detail-guide.md`) |
| `Display_Order__c` | the literal print order; always sort/iterate by this |
| `Display_Label__c` | generated automatically — for a composite bucket, this is the two parts joined by the separator, e.g. `"Hardware / Recurring"` |
| `Group_Dimension__c` / `Group_Value__c` | `Group_Dimension__c` reads `"SBQQ__Product__r.Family + CHARGE_TYPE"` (both part names joined) here — a composite's dimension label is genuinely different from a single-dimension table's |
| `Transaction_Type__c` | not populated — `PRICE_WATERFALL`, not `CHANGE` |
| `Product_Name__c`, `Product_Code__c`, `Product_Family__c`, `Charge_Type__c` | populated on every Detail row |
| `Quote_Line__c` | lookup back to the real `SBQQ__QuoteLine__c` |

### The two measure families

**`PRICE_WATERFALL`** — this table's family: `Amount_List__c`, `Amount_Regular__c`, `Amount_Discount__c`, `Amount_Net__c`, `Amount_Customer__c`, `Quantity__c`.

### How grouping works — composite, not nesting

Two grouping records on the **same `Level__c` (both `1`)** mean composite: one bucket labeled `"Hardware / Recurring"`, at a single depth — not a Hardware group containing a Recurring sub-group. This is the mirror image of `GROUP_FAMILY_DETAIL` (§ of that guide), which uses the same two kinds of dimension but on *different* levels to nest instead. Same two ingredients, two genuinely different documents, decided entirely by one field (`Level__c`).

One part here is a **field path** (`SBQQ__Product__r.Family`) and the other is a **computed dimension** (`CHARGE_TYPE`) — a composite can freely mix the two kinds; nothing about the composite mechanism cares which kind either part is.

---

## 3. Classification/business-logic caveats

None from transaction-type logic — `PRICE_WATERFALL`, not `CHANGE`.

**The one thing worth knowing about composites specifically:** a composite **multiplies** the number of possible groups — N families × M charge types, in the worst case — which is exactly why `Max_Groups__c` exists and why this particular table definition explicitly sets it (`50`, the same as the framework default, but set explicitly here rather than left to default, as a signal that this table was deliberately reviewed for the risk). If you ever add a third part to a composite, or a catalogue with many more families or charge types, re-check `Max_Groups__c` before deploying — a runaway composite fails loudly (`QuoteDocumentException`) rather than silently emitting a huge table, but "fails loudly" still means a broken document generation the first time someone hits it.

---

## 4. Configuration (already shipped)

### 4.1 `Quote_Document_Table_Def__mdt`

| Field | Value |
|---|---|
| `Table_Code__c` | `FAMILY_BILLING_COMPOSITE` |
| `Table_Name__c` | `Family and Billing Summary` |
| `Amount_Basis__c` | `Final Value` |
| `Line_Filter__c` | `EXCLUDE_OPTIONAL` |
| `Measure_Set__c` | `PRICE_WATERFALL` |
| `Show_Details__c` | `true` |
| `Show_Section_Totals__c` | `false` |
| `Is_Active__c` | `true` |
| `Display_Order__c` | `70` |
| `Max_Groups__c` | `50` — set explicitly, not left to default; see §3 |
| `Composite_Separator__c` | explicitly blank (`xsi:nil="true"`), **not omitted** — this is deliberate: a Custom Metadata deploy only writes fields present in the file, and Salesforce trims leading/trailing spaces from a stored text value, so entering `" / "` here would arrive as `"/"` and produce `"Hardware/Recurring"`. Leaving it explicitly nil gets the code default `" / "` with real spaces. |

File: `force-app/main/default/customMetadata/Quote_Document_Table_Def.FAMILY_BILLING_COMPOSITE.md-meta.xml` (already in the repo).

### 4.2 `Quote_Document_Grouping__mdt` (two records — same `Level__c`, this is the composite shape)

| Record | Sets | Value | `Level__c` | `Sequence__c` |
|---|---|---|---|---|
| `FAMILY_BILLING_FAMILY` | `Field_Path__c` | `SBQQ__Product__r.Family` | `1` | `10` |
| `FAMILY_BILLING_FREQUENCY` | `Dimension__c` | `CHARGE_TYPE` | `1` | `20` |

Files: `force-app/main/default/customMetadata/Quote_Document_Grouping.FAMILY_BILLING_FAMILY.md-meta.xml` and `...FAMILY_BILLING_FREQUENCY.md-meta.xml` (both already in the repo). **Both records share `Level__c = 1`** — that single fact is what makes this a composite instead of a two-level nest; `Sequence__c` (10, then 20) decides which part comes first inside the joined label, not which nests inside which.

### 4.3 What it prints

```
Hardware / One-Time              91,800
Software / One-Time               7,200
Service / One-Time                  410
Miscellaneous / One-Time          3,500
Recurring / Recurring                360
Total                           102,910
```

(One bucket per family-and-charge-type combination that actually occurs on the quote — not every possible combination, only the ones with real lines in them.)

---

## 5. Code changes

**None needed.** Both grouping records sharing `Level__c = 1` is a configuration choice, not code — the composite mechanism, the separator logic, and the `Max_Groups__c` ceiling all already exist in `QuoteDocumentRowBuilder.groupLines()` and `QuoteDocumentTableDefinition`.

---

## 6. Worked example

```bash
sf apex run --target-org gkCPQDev --file scripts/apex/family-billing-composite-example.apex
```

`scripts/apex/family-billing-composite-example.apex` builds the §4.3 table as real records, reusing the canonical family totals from `docs/product-family-summary-guide.md`'s worked example (same underlying quote), recombined into composite buckets so the two guides' numbers are directly cross-checkable. Safe to re-run: deletes only its own table first.

---

## 7. Deployment checklist

1. Already shipped — deploy the whole repo if setting up fresh; nothing table-specific to add.
2. Assign `CPQ_Document_Totals`.
3. Generate for a real quote, or run §6's script.
4. Verify:
   ```sql
   SELECT Row_Type__c, Group_Level__c, Group_Dimension__c, Display_Label__c, Amount_Net__c
   FROM Quote_Document_Row__c
   WHERE Quote_Document_Table__r.Table_Code__c = 'FAMILY_BILLING_COMPOSITE'
     AND Quote_Document_Table__r.Quote__c = :quoteId
   ORDER BY Display_Order__c
   ```
   Confirm every `Group Header`/`Subtotal` row has `Group_Level__c = 1` — if you ever see a `2` here, one of the two grouping records' `Level__c` got changed, and this table silently became a nested table instead of a composite (still valid output, just not what this guide describes).
5. Move to reports/DocuSign only after step 4 matches §4.3.

---

## 8. Salesforce reports

**Already built — open the report, don't build one.** Go to **Reports → CPQ Document Totals → Quote Doc - Family & Billing Composite** (Salesforce report names cap at 40 characters, so this one is abbreviated from the guide title). Filter it to your quote before generating the customer-facing document. File: `force-app/main/default/reports/CPQ_Document_Totals/Quote_Document_Family_and_Billing_Composite.report-meta.xml`.

Uses report type **Quote Document Tables and Rows**:

| Filter | Group rows by | Columns |
|---|---|---|
| `Table_Code__c = 'FAMILY_BILLING_COMPOSITE'` | Quote (each row's `Display_Label__c` is already the composite bucket, e.g. `"Hardware / Recurring"`) | `Display_Label__c`, `Amount_Net__c` (summed) |

Unlike `GROUP_FAMILY_DETAIL`, a flat Summary report is enough here — there's only one grouping level to show, by design.

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
4. Save, Activate, **Preview Data** against a `Ready` quote — confirm `Table_Code = 'FAMILY_BILLING_COMPOSITE'` rows appear, and that `Display_Label` shows joined values like `"Hardware / One-Time"`.

### 9.2 Composer

1. **Composer → Templates**, open/attach the Data Source.
2. **Insert → Repeating Region** on `Quote_Document_Row`.
3. Insert `Value` tags for `Display_Label` and `Amount_Net`.
4. Save.

### 9.3 The tag block

> **Filtering moved into the data.** A renderer prints every row it is given, in `Display_Order` order, and asks no questions about which rows belong. `Is_Displayed` is decided during generation, so every renderer reaches the same answer instead of each template re-deriving it — see [the render contract](quote-document-totals.md#the-render-contract).


```
<# <Repeating NodeSet="//Quote_Document_Table[Table_Code='FAMILY_BILLING_COMPOSITE']/Quote_Document_Row"> #>
<# <Conditional Test="Is_Displayed='true'"> #>
<# <Value Select="Display_Label"/> #>     <# <Value Select="Amount_Net"/> #>
<# </Conditional> #>
<# </Repeating> #>
```

No indentation logic needed — every real row here sits at the same level (`Group_Level__c = 1`), which is the one structural simplification a composite table gives you over a nested one at the template-authoring stage: no `Group_Level__c`-based indentation math required.

### 9.4 Publish and connect

**Save & Close → Publish** in Composer; confirm the **Generate Document** quick action exists on the Quote page layout; configure Template Rules; generate from a real Quote record.

### 9.5 Before trusting it

Confirm `Document_Data_Status__c = 'Ready'`, generate, cross-check against §7 step 4's SOQL — and specifically confirm the bucket count is sane (not dozens of near-empty buckets), which would indicate the composite is multiplying more combinations than the catalogue actually needs (§3's `Max_Groups__c` risk, made visible rather than merely theoretical).

---

## 10. Scratch-org reproduction

Covered by `scripts/scratch-org-bootstrap.sh` — see `docs/quote-line-type-bundle-reporting-guide.md` §14 for prerequisites.

---

## 11. Review & score

| # | Criterion | Score | Note |
|---|---|---|---|
| 1 | Self-contained | 1.0 | Full primer and DocuSign setup repeated |
| 2 | Grounded in real code | 1.0 | Both grouping records read directly; `Composite_Separator__c` nil behavior confirmed against the actual deployed file's comment |
| 3 | Config vs. code | 1.0 | Correctly states none needed, explains exactly which field (`Level__c` equality) makes this a composite |
| 4 | Deployable artifacts | 1.0 | Cites exact already-shipped file paths |
| 5 | Worked example + script | 1.0 | Numbers cross-check against the Product Family Summary guide; dedicated, scoped script |
| 6 | Deployment checklist | 1.0 | Includes the specific `Group_Level__c` sanity check unique to composites |
| 7 | Reporting section | 1.0 | Points at a real, deployed report by name; correctly notes a flat report suffices here, unlike the nested table |
| 8 | DocuSign section | 1.0 | Click-by-click, correctly notes no indentation logic is needed for a composite |
| 9 | Honest verification status | 1.0 | States plainly nothing was run in a live org |
| 10 | Scratch-org reproduction | 1.0 | Points at the shared bootstrap script |

**Score: 10.0 / 10**
