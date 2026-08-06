# How each row gets built — Part 2: Apex (building each row)

**Who this is for:** anyone — a business admin with no coding background, a junior Salesforce admin, or a junior developer. If a term feels unfamiliar anywhere in this file, check the [shared glossary](../quote-document-totals-creation-pipeline/00-glossary.md).

**Read [01-custom-metadata-shapes-each-row.md](01-custom-metadata-shapes-each-row.md) first.** This file explains the one Apex class responsible for turning the metadata instructions from file 1 into actual saved field values on `Quote_Document_Row__c` records: `QuoteDocumentRowBuilder`.

> **In one sentence:** this file explains, field by field, exactly what determines the value in every column of every generated row, using the same worked example as the rest of this folder.

> **Same one-pipeline correction as the rest of this series.** `QuoteDocumentRowBuilder` isn't one of "3 independent Apex options" for building rows — it's the one and only class in this framework that builds rows, called internally by `QuoteDocumentGenerator` (from the previous folder's file 2) once per table, every single time. There's nothing to choose between here; this is simply the part of the one pipeline that happens to do row-shaping specifically.

---

## 1. Every field a row can have, and exactly what sets it

This table lists every field on `Quote_Document_Row__c` involved in row-building, and, in plain English, what determines its value. Refer back to this table anytime you're looking at an actual generated row and wondering "why does it say that?"

| Field | What sets it | Example |
|---|---|---|
| `Row_Type__c` | Which part of the building process created this row — see the row types table below | `Detail` |
| `Group_Level__c` | How deeply nested this row's *heading* is, used by a document template purely to decide indentation. `0` means "table-wide," not inside any group (this is where the Grand Total, and any Section Total rows, always sit). `1` is the outermost Group Header level. `2` is a Group Header nested one level inside that, and so on, matching however many nesting levels your grouping metadata defines (see file 1 of this folder). **A Detail row copies the same `Group_Level__c` as the innermost Group Header it belongs to — it does not automatically go one level deeper**, with one specific exception explained in §2, Step C below (tables grouped by `BUNDLE`). | `1` |
| `Row_Key__c` | A unique internal identifier Apex builds for this row, so it can never be confused with a different row even if their labels happen to look similar. Built differently depending on row type (shown below). | `SUBTOTAL:PRODUCT_FAMILY:HARDWARE` |
| `Display_Label__c` | The text printed in the left-hand column. For a Detail row, this is the product name; for a Group Header or Subtotal, it's the group's value (plus the word "Subtotal" for the subtotal); for the Grand Total, it's always literally "Total." | `Hardware Subtotal` |
| `Display_Order__c` | The exact print position. Starts at 10 for the first row of a table and counts up by 10 for every row after it, in the exact order Apex builds them — a document template sorts by this field and nothing else. | `20` |
| `Is_Displayed__c` | Whether this row should actually be shown on the printed document. Almost always `true`; a row customizer (a rare, developer-only extension point) can set this `false` for a row that needs to exist for the math but shouldn't be visible. | `true` |
| `Include_In_Subtotal__c` | Whether this row's own dollar amount should be added into the Subtotal above it. | `true` for a Detail row, `false` for a Group Header/Subtotal/Section Total/Grand Total (since those rows are the *result* of adding things up, not another thing to add) |
| `Include_In_Grand_Total__c` | Same idea, but for whether this row feeds the table's overall Grand Total. | Same pattern as above |
| `Group_Dimension__c` | Which grouping (`PRODUCT_FAMILY`, a field path, etc.) this row belongs to — copied from the metadata in file 1. Blank on the Grand Total, since it doesn't belong to any one grouping. | `PRODUCT_FAMILY` |
| `Group_Value__c` | The actual value within that dimension — the specific family name, the specific charge type, and so on. | `Hardware` |
| `Group_Key__c` | The internal path describing exactly which bucket this row is in, including any parent buckets it's nested under. Used internally to keep nested groups from colliding with each other. | `PRODUCT_FAMILY:HARDWARE` |
| `Quote_Line__c` | Only set on a Detail row — a direct lookup to the actual `SBQQ__QuoteLine__c` record this row represents. Every other row type leaves this blank, because a heading or a total doesn't represent one single quote line. | *(a Quote Line record Id)* |
| `Product_Name__c`, `Product_Code__c`, `Product_Family__c`, `Charge_Type__c` | Only set on a Detail row — copied straight from that one quote line, for convenience when reporting on rows without having to look up the Quote Line itself. | `Laptop`, `LAPTOP-001`, `Hardware`, `Recurring` |
| `Transaction_Type__c` | Only set on a Detail row, and only when the table's `Measure_Set__c` is `CHANGE` (not `PRICE_WATERFALL`) — describes what kind of change this line represents (new, cancelled, replaced, etc.). | `Net New` |
| `Amount_List__c`, `Amount_Regular__c`, `Amount_Discount__c`, `Amount_Net__c`, `Amount_Customer__c`, `Quantity__c` | The dollar/quantity figures, filled in only when `Measure_Set__c = PRICE_WATERFALL`. On a Detail row, these are that one line's own figures. On a Group Header/Subtotal/Section Total/Grand Total, these are the *sum* of every counted row beneath it. | `$1,800.00` |
| `Amount_Net_New__c`, `Amount_Cancellation__c`, `Amount_Replacement_Removed__c`, `Amount_Replacement_Added__c`, `Amount_Termination__c`, `Amount_Net_Change__c`, `Amount_Final__c` | The same idea, but filled in only when `Measure_Set__c = CHANGE`. | *(varies)* |

### The six row types, and where each one comes from

| `Row_Type__c` value | Where it comes from | Counts toward totals? |
|---|---|---|
| **Group Header** | One created automatically for every distinct value at every grouping level, from file 1's metadata | No — it's a heading, not money |
| **Detail** | One created automatically for every individual quote line that survived the table's `Line_Filter__c`, as long as `Show_Details__c = true` | Yes |
| **Subtotal** | One created automatically to match every Group Header, holding the sum of everything inside that group | No — it's a total, not new money on top of what it's summing |
| **Section Total** | Only created if `Show_Section_Totals__c = true` — one per distinct Charge Type across the whole table | No |
| **Grand Total** | Always created, exactly once per table, no matter what | No |
| **Informational**, **Discount**, **Rounding**, **Note** | Only ever added by a developer-written extension (a "row customizer") for a specific table that needs something a plain grouping can't express — not something an admin configures through the two Custom Metadata Types alone | Depends on the specific customizer |

---

## 2. Walking through the build, in the order the code actually does it

Using the same Family Breakdown example from file 1 (Lines 1 and 3, both Hardware, after the optional Line 2 is filtered out):

### Step A — Group the lines

The code looks at the one `PRODUCT_FAMILY` grouping instruction and sorts the two surviving lines into buckets by their family value. Both lines have `Product_Family__c = Hardware`, so there's exactly one bucket, containing both lines.

If there had been a *second* grouping level (say, Charge Type nested inside Family), this same step would run again *inside* the Hardware bucket, splitting it further — this is what "nesting" means mechanically: the same grouping step repeating itself for each level, each time only looking at the lines already inside its parent bucket.

### Step B — For each bucket, create its Group Header

The Hardware bucket gets one Group Header row: `Row_Type__c = Group Header`, `Group_Level__c = 1`, `Display_Label__c = Hardware`, `Row_Key__c = HEADER:PRODUCT_FAMILY:HARDWARE`.

### Step C — Inside the bucket, create Detail rows (if this is the innermost level and `Show_Details__c` allows it)

Since Hardware has no further nested grouping beneath it, this is the innermost level, so its two lines each get a Detail row, in the same order they appear on the quote:

- Laptop: `Row_Type__c = Detail`, `Group_Level__c = 1` (the same level as the Hardware Group Header it prints underneath — see the note below on why it isn't deeper), `Amount_Net__c = $1,800`, `Include_In_Subtotal__c = true`, `Include_In_Grand_Total__c = true`
- Docking Station: `Row_Type__c = Detail`, `Group_Level__c = 1`, `Amount_Net__c = $72`, same inclusion flags

> **Why a Detail row doesn't automatically get a deeper `Group_Level__c` than its heading.** It's a reasonable first guess that a Detail row sitting "inside" a heading should be indented one level further than that heading, the way a nested computer folder sits deeper than the folder around it. This framework doesn't work that way: a Detail row simply copies the same `Group_Level__c` as the innermost Group Header above it. What actually keeps a Detail row printing directly underneath its heading is `Display_Order__c` (explained further down this file) — the document always prints strictly in `Display_Order__c` order, and Apex builds every Detail row's order number to fall immediately after its Group Header and immediately before its Subtotal, so the visual grouping comes from *print order*, not from a deeper indentation number.
>
> **The one deliberate exception: tables grouped by `BUNDLE`.** When a table's grouping is the `BUNDLE` dimension specifically, each Detail row's `Group_Level__c` *is* pushed deeper than its Group Header — by however many "option levels" that specific product sits at inside its bundle (a bundle's main product is option level 0; an option nested one layer inside the bundle is level 1; and so on). This is a deliberate special case so a complex bundle's internal structure — main product, then its options, then options-of-options — is still visible in the indentation on a document, even though `BUNDLE` itself only counts as one single grouping level. Every other kind of grouping (`PRODUCT_FAMILY`, `CHARGE_TYPE`, a custom field path, and so on) does **not** get this extra push, which is why the Laptop and Docking Station rows above stay at `Group_Level__c = 1`, matching their Hardware heading exactly.

### Step D — Add up everything counted in the bucket, and create its Subtotal

The code adds together every row inside the Hardware bucket where `Include_In_Subtotal__c = true` — both Detail rows qualify — giving `Amount_Net__c = $1,872`. This becomes the Subtotal row: `Row_Type__c = Subtotal`, `Group_Level__c = 1` (same level as its matching Group Header), `Display_Label__c = Hardware Subtotal`, `Row_Key__c = SUBTOTAL:PRODUCT_FAMILY:HARDWARE`.

### Step E — Section Totals, only if turned on

`Show_Section_Totals__c = false` in this example, so this step is skipped entirely — no Section Total rows are created.

### Step F — The Grand Total, always

The code adds together every row anywhere in the table where `Include_In_Grand_Total__c = true` — again, both Detail rows — giving `Amount_Net__c = $1,872`. One single Grand Total row is created: `Row_Type__c = Grand Total`, `Group_Level__c = 0`, `Display_Label__c = Total`, `Row_Key__c = GRAND_TOTAL`.

### The final row set, with `Display_Order__c` assigned as each row was built

| Order | `Row_Type__c` | `Group_Level__c` | `Display_Label__c` | `Amount_Net__c` |
|---|---|---|---|---|
| 10 | Group Header | 1 | Hardware | *(blank)* |
| 20 | Detail | 1 | Laptop | $1,800.00 |
| 30 | Detail | 1 | Docking Station | $72.00 |
| 40 | Subtotal | 1 | Hardware Subtotal | $1,872.00 |
| 50 | Grand Total | 0 | Total | $1,872.00 |

Read down the `Order` column and you can see exactly how a document template reconstructs the visual grouping purely from print order: Hardware's heading prints first, both of its Detail rows print directly after it, its Subtotal prints right after that, and only then does the Grand Total appear. Nothing about `Group_Level__c` alone tells you that story — it only controls *indentation*; `Display_Order__c` is what controls *sequence*, and a template is only ever supposed to rely on that one field for ordering.

This is the exact same information shown in file 1, but now you can see *why* each row has the field values it does — every single one traces back either to a specific metadata setting (file 1) or to one specific step in this build process.

---

## 3. What this class does **not** decide

- **Which lines make it into the table at all.** That's `Line_Filter__c`, applied by `QuoteDocumentGenerator` before `QuoteDocumentRowBuilder` even starts (covered in the previous folder's file 2).
- **Whether the final numbers are actually correct.** `QuoteDocumentRowBuilder` builds the rows; the five safety checks that confirm the math is right run afterward, in `QuoteDocumentGenerator` itself (also covered in the previous folder's file 2, step 7).
- **How the rows get saved to Salesforce.** This class only produces the rows as not-yet-saved records in memory. `QuoteDocumentGenerator` is the one that actually inserts them.

**Next:** [03-flow-and-each-row.md](03-flow-and-each-row.md) — a short file explaining, very deliberately, why there is nothing more to say about Flow's role at the row level.
