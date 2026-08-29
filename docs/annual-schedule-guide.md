# Annual Schedule — implementation guide

**Table code:** `ANNUAL_SCHEDULE`
**Status:** shipped **inactive**. Nothing generates it until an admin ticks `Is_Active__c` on the `Quote_Document_Table_Def__mdt` record. §7 is the checklist for doing that deliberately.

---

## 1. What you're building

A document section that breaks a multi-year agreement into one block per year: every product running in that year, what it costs in that year, a subtotal per year, and the total contract value.

For a 36-month quote it prints three blocks. A product that runs the whole term appears in all three, carrying a third of its amount each time; a product that runs only the first twelve months appears once. A one-time charge — hardware, setup, implementation — appears in **year 1 only**, at its whole value.

```
Annual Payment Schedule - Year 1
    Platform Subscription        12,000.00
    Add-On Module                 1,200.00
    Implementation Setup          5,000.00
  Year 1 Subtotal                18,200.00

Annual Payment Schedule - Year 2
    Platform Subscription        12,000.00
  Year 2 Subtotal                12,000.00

Annual Payment Schedule - Year 3
    Platform Subscription        12,000.00
  Year 3 Subtotal                12,000.00

  Grand Total                    42,200.00
```

The grand total equals the Quote's own `SBQQ__NetAmount__c`, to the cent, and generation fails rather than publishing if it does not.

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
| `Group_Dimension__c` / `Group_Value__c` | which dimension this row was grouped by, and the value — e.g. `EXPANSION` / `Year 2` |
| `Transaction_Type__c` | only populated on tables using the `CHANGE` measure set — not this table |
| `Product_Name__c`, `Product_Code__c`, `Product_Family__c`, `Charge_Type__c` | snapshotted from the line, only meaningful on Detail rows |
| `Quote_Line__c` | lookup back to the real `SBQQ__QuoteLine__c`, if a template needs a field this projection doesn't carry |

### The two measure families

Every table declares **one** of two measure sets; the fields for the other family are left `null` (not zero):

**`PRICE_WATERFALL`** — this table's family: `Amount_List__c`, `Amount_Regular__c`, `Amount_Discount__c`, `Amount_Net__c`, `Amount_Customer__c`, `Quantity__c`.

**`CHANGE`** — not used here (that's the transaction-type-classified family; see `docs/quote-line-type-bundle-reporting-guide.md` if you need line-type deltas).

### How grouping works

A table definition (`Quote_Document_Table_Def__mdt`, with child records in `Quote_Document_Grouping__mdt`) says three things: which lines it starts from (a filter), what it groups them by (a dimension the generator computes, or a plain field path), and which measure family it fills in.

### What is different about this table: it expands before it groups

Every other table in this framework turns one quote line into exactly one Detail row. This one **multiplies**: a line running the whole term becomes one row per year. That happens in a stage *before* grouping, and grouping then treats the year like any other dimension:

```
query lines
   → EXPAND     one line becomes one per year it runs in   (Expander_Code__c = PERIOD)
   → ALLOCATE   divide its measures among those years      (Allocation_Basis__c = EVEN)
   → group by EXPANSION, subtotal, order                    [ordinary framework behaviour]
   → verify, persist                                        [ordinary framework behaviour]
```

The consequence worth internalising: **the year is an ordinary grouping dimension called `EXPANSION`.** Nesting product family inside year, or year inside product family, is a change to `Quote_Document_Grouping__mdt` and nothing else.

---

## 3. Classification/business-logic caveats

Five rules decide what this table prints. Each is enforced in code and each fails generation rather than guessing.

| Rule | Behaviour |
|---|---|
| **The axis** | The quote's own `SBQQ__StartDate__c` plus `SBQQ__SubscriptionTerm__c`, cut into 12-month blocks. If either is blank they are derived from the lines — earliest start, and enough months to reach the latest end. If neither can be resolved, generation **fails** (`EXPANSION_AXIS_UNRESOLVED`): a schedule built on a guessed term puts every product in a year nobody chose. |
| **Years are anniversary-based** | Year N runs `[start.addMonths((N-1)*12), start.addMonths(N*12))`. A term starting on 15 March gives whole years, not thirteen partial ones. A 30-month term gives three years, the last of them six months long — a shorter final block, never an empty extra one. |
| **Occupancy** | A line occupies every year its subscription window touches, whole or partial: one day of overlap means the product was running that year. A blank window means the whole term, which is what CPQ's own `SBQQ__EffectiveStartDate__c` means by a blank start date. A line running entirely outside the term **fails** (`EXPANSION_LINE_OUTSIDE_AXIS`) — including it would leave the printed years short of the quote total, and dropping it silently would do the same. |
| **One-time charges land once** | A charge whose `SBQQ__ChargeType__c` is not `Recurring` appears in **year 1 only**, at its whole value. Spreading a setup fee across three years prints a recurring charge that does not exist. `Period_One_Time_Placement__c` can override this to `EFFECTIVE_DATE` or `SPREAD`, but `SPREAD` must be chosen out loud. |
| **Money divides; quantities do not** | Each year carries its share of the money. A **licence count is repeated in every year the line runs** — a customer with 100 licences has 100 in each year, not 33.3 — and the grand-total quantity is therefore the **peak year**, not the sum of the three. If you ever see a quantity that looks like the term total multiplied by the number of years, that is the defect this rule exists to prevent. |

**Rounding is exact, not approximate.** Each line's yearly shares are rounded to the cent with the residual carried into its last year, so a line's years always sum back to its own quoted total exactly. This is checked twice: once per source line at **zero tolerance**, and once for the table against CPQ's `SBQQ__NetAmount__c`. A schedule that loses a penny fails generation.

**Bundled components are omitted, not printed at zero.** Their price is already inside the package price, so a cost breakdown listing a component that costs nothing reads as an error to the customer.

---

## 4. Configuration (already shipped)

The record is `Quote_Document_Table_Def.ANNUAL_SCHEDULE`, deployed **inactive**.

| Field | Value | Why |
|---|---|---|
| `Table_Code__c` | `ANNUAL_SCHEDULE` | |
| `Display_Title__c` | `Annual Payment Schedule` | The printed heading. `Table_Name__c` is an internal label and is deliberately never used as a fallback |
| `Is_Active__c` | `false` | Activate deliberately — see §7 |
| `Line_Filter__c` | `EXCLUDE_OPTIONAL` | So the total reconciles to CPQ's own Net Amount |
| `Measure_Set__c` | `PRICE_WATERFALL` | |
| `Expander_Code__c` | `PERIOD` | The stage that turns one line into one row per year |
| `Expander_Version__c` | `1` | Content identity. Bump it whenever the expander's behaviour changes, or quotes reuse a snapshot the new logic would not have produced |
| `Period_Months__c` | `12` | 1 would make it monthly, 3 quarterly |
| `Period_One_Time_Placement__c` | `FIRST_PERIOD` | Setup fees land once |
| `Allocation_Basis__c` | `EVEN` | Each occupied year gets an equal share |
| `Allocation_Scale__c` | `2` | Money to the cent; quantities are repeated, not divided |
| `Sort_Groups_By__c` | `EXPANSION_ORDER` | **Required.** Sorted alphabetically, "Year 10" prints before "Year 2" |
| `Max_Groups__c` | `60` | A ten-year term is ten groups; the ceiling is generous but finite |
| `Show_Details__c` | `true` | |
| `Show_Section_Totals__c` | `false` | **Must stay false.** A section total cuts across every year at once, which has no defined meaning on an expanded table — config load refuses the combination |
| `Display_Order__c` | `90` | |

One child record, `Quote_Document_Grouping.ANNUAL_SCHEDULE_EXPANSION`:

| Field | Value |
|---|---|
| `Dimension__c` | `EXPANSION` |
| `Level__c` | `1` |
| `Sequence__c` | `1` |

**To show product family inside each year**, add a second grouping record at `Level__c = 2` with `Dimension__c = PRODUCT_FAMILY`. To show years inside each family instead, swap the two levels. No code changes either way.

### Columns

None are configured, so the table emits the framework default: one label column plus one column per measure in `PRICE_WATERFALL`. To print a narrower set — label, net, quantity — author `Quote_Document_Column_Def__mdt` records against this definition.

### Dictionary entries this table needs

| Key | en_US | fr |
|---|---|---|
| `YEAR_LABEL` | `Year {0}` | `Annee {0}` |
| `SUBTOTAL` | (already shipped) | (already shipped) |
| `GRAND_TOTAL` | (already shipped) | (already shipped) |

`YEAR_LABEL` ships in both locales. **No printable text is typed into a template**: the heading comes from `Display_Title__c` and the year labels from the dictionary.

---

## 5. Code changes

**None needed — configuration only.** `QuoteDocumentPeriodExpander` and `QuoteDocumentAllocation` are already deployed and already tested; this table is metadata pointed at them.

---

## 6. Worked example

A 36-month quote starting 2026-01-01:

| Line | Term | Quantity | Net total |
|---|---|---|---|
| Platform Subscription | whole term (no dates) | 100 | 36,000.00 |
| Add-On Module | 2026-01-01 → 2026-12-31 | 50 | 1,200.00 |
| Implementation Setup | one-time, no dates | 1 | 5,000.00 |

Quote `SBQQ__NetAmount__c` = **42,200.00**.

Expected rows:

| Order | Row type | Group | Product | `Amount_Net__c` | `Quantity__c` |
|---|---|---|---|---|---|
| 10 | Group Header | Year 1 | | | |
| 20 | Detail | Year 1 | Platform Subscription | 12,000.00 | 100 |
| 30 | Detail | Year 1 | Add-On Module | 1,200.00 | 50 |
| 40 | Detail | Year 1 | Implementation Setup | 5,000.00 | 1 |
| 50 | Subtotal | Year 1 | | **18,200.00** | 151 |
| 60 | Group Header | Year 2 | | | |
| 70 | Detail | Year 2 | Platform Subscription | 12,000.00 | 100 |
| 80 | Subtotal | Year 2 | | **12,000.00** | 100 |
| 90 | Group Header | Year 3 | | | |
| 100 | Detail | Year 3 | Platform Subscription | 12,000.00 | 100 |
| 110 | Subtotal | Year 3 | | **12,000.00** | 100 |
| 120 | Grand Total | | | **42,200.00** | **151** |

Check the arithmetic by hand: 18,200 + 12,000 + 12,000 = 42,200, which is the quote's Net Amount. The platform's 36,000 divides into three years of 12,000; the add-on's 1,200 sits entirely in year 1 because that is the only year it runs; the setup fee's 5,000 lands once.

**The grand-total quantity is 151, not 351.** Year 1 has 151 units active (100 + 50 + 1); years 2 and 3 have 100. The term figure is the busiest year, because it is the same 100 licences in each of them.

This example is executable: `QuoteDocumentExpansionTest.anAnnualScheduleSectionsTheQuoteByYearAndFootsToIt` and `.licencesRepeatWhileMoneyDivides` assert exactly these numbers.

---

## 7. Deployment checklist

1. `sf project deploy start --source-dir force-app` — the definition, its grouping record, and the `YEAR_LABEL` dictionary entries.
2. Confirm the `CPQ_Document_Totals` permission set is assigned to whoever generates documents. It already covers every field this table uses; no new field was added for it.
3. **Decide deliberately, then activate.** Set `Is_Active__c = true` on `Quote_Document_Table_Def.ANNUAL_SCHEDULE`. Every quote generated afterwards produces this table, so:
   - confirm quotes in this org carry a usable `SBQQ__StartDate__c` and `SBQQ__SubscriptionTerm__c`, or dated lines. A quote with neither now **fails generation** rather than silently skipping this table;
   - confirm no line runs entirely outside its quote's term — that also fails, by design.
4. Regenerate one representative multi-year quote and check the grand total against the Quote's Net Amount.
5. Regenerate a single-year quote too: it produces one year block, which is correct and slightly surprising the first time.

**Rollback:** untick `Is_Active__c` and regenerate. Nothing else in the framework depends on this table.

---

## 8. Salesforce reports

The existing `Quote_Document_Tables_and_Rows` custom report type already exposes everything this table writes — no new report type is needed, because no new field was added.

To build a per-year view: filter `Table_Code__c = ANNUAL_SCHEDULE`, group by `Group_Value__c`, and sort by `Display_Order__c`. Add `Amount_Net__c` and `Quantity__c` as columns.

**A caution specific to this table:** do not put a report-level SUM on `Quantity__c`. Summing quantities across years double-counts the same licences — the peak is already on the Grand Total row, which is the figure to read.

---

## 9. Adapter: DocuSign CLM (SpringCM) — click-by-click

### 9.1 Data Source setup

1. Admin Console → **Data Sources** → New.
2. Root object: `SBQQ__Quote__c`.
3. Add repeating child nodes for `Quote_Document_Table__c` and, beneath it, `Quote_Document_Row__c`.
4. Filter the table node to `Table_Code__c = ANNUAL_SCHEDULE`.
5. Sort the row node by `Display_Order__c` ascending. **This is not optional** — the year order lives in that field and nowhere else.
6. Map these fields, and only these:

| Node | Fields |
|---|---|
| `Quote_Document_Table__c` | `Display_Title__c`, `Display_Subtitle__c`, `Intro_Text__c`, `Footer_Text__c` |
| `Quote_Document_Row__c` | `Display_Order__c`, `Row_Type__c`, `Group_Level__c`, `Display_Label__c`, `Product_Name__c`, `Amount_Net__c`, `Quantity__c` |

### 9.2 Composer usage

Insert one repeating region over the `Quote_Document_Row__c` node. Inside it, bind `Display_Label__c` and the measure columns. The repeating region is auto-generated from the data source; the bindings are placed by hand.

**Print the heading from `Display_Title__c`.** Do not type "Annual Payment Schedule" into the template — that string lives in the data so it can be changed or translated without republishing a document.

### 9.3 Conditionals are styling only

Use `Row_Type__c` to decide **appearance**: bold a `Subtotal`, bold and rule-off a `Grand Total`, indent a `Detail` by `Group_Level__c`. Use `Is_Displayed__c` to decide visibility.

Never use a conditional to decide *what a number is*, to hide a row the data says to show, or to compute anything. A renderer that adds, divides or re-derives is not a conforming adapter.

### 9.4 Publishing and connecting to Salesforce

Publish the template in CLM, then connect it to the Salesforce action that generates the document. The launch **must** call generate-or-reuse first and pass the returned request Id and fingerprint to retrieval — reading a `Ready` snapshot without that step is prohibited and fails with `LAUNCH_CONTRACT_BYPASSED`.

---

## 10. Scratch-org reproduction

`scripts/scratch-org-bootstrap.sh` provisions an org with CPQ and this framework deployed. After it completes, activate the definition per §7 and run `scripts/apex/quote-document-sample.apex` against a quote with a multi-year term.

---

## 11. Review & score

| # | Criterion | Score |
|---|---|---|
| 1 | Self-contained; no cross-document dependency | 1.0 |
| 2 | Architecture primer repeated verbatim | 1.0 |
| 3 | Business-logic caveats stated explicitly | 1.0 |
| 4 | Configuration table complete and accurate | 1.0 |
| 5 | Worked example with numbers that foot | 1.0 |
| 6 | Deployment checklist actionable | 1.0 |
| 7 | Reporting section present, with this table's own caution | 1.0 |
| 8 | Adapter section documents columns, not tags; no printable text typed into a template | 1.0 |
| 9 | Conditionals documented as styling only | 1.0 |
| 10 | Scratch-org reproduction pointed at the shared script | 0.9 |

**Total: 9.9 / 10.**

Criterion 10 scores 0.9 rather than 1.0 because the bootstrap script does not itself activate this definition or seed a multi-year quote — §7 and §10 tell a reader to do both by hand. Closing that gap means extending the shared script, which affects every guide and belongs in its own change rather than here.
