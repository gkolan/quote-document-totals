# How each row gets built — Part 1: Custom Metadata (shaping each row)

**Who this is for:** anyone — a business admin with no coding background, a junior Salesforce admin, or a junior developer. If a term feels unfamiliar anywhere in this file, check the [shared glossary](../quote-document-totals-creation-pipeline/00-glossary.md).

**How this folder is different from the last one:** [`../quote-document-totals-creation-pipeline/`](../quote-document-totals-creation-pipeline/01-custom-metadata-the-blueprint.md) explained how a whole `Quote_Document_Table__c` record and its full set of `Quote_Document_Row__c` children get created. This folder zooms in one level further: once you know a table is going to be built, **how does the system decide exactly how many rows it has, what type each one is, and what indentation level it sits at?** Same three angles (Custom Metadata, Apex, Flow), same one real pipeline underneath — just a closer look at the row-shaping part of it.

> **In one sentence:** the same two Custom Metadata Types from the other folder also determine, indirectly, exactly how many rows a table ends up with and what type each one is — this file walks through that connection in detail.

> **Same correction as before, worth repeating.** `Quote_Document_Table__c` and `Quote_Document_Row__c` records **are** "the Quote Document Totals rows" — there isn't a separate, later step that creates a *different* set of rows after the ones from the first folder. This folder is the same one generation pass, described in more row-level detail. Read the first folder's three files before this one if you haven't already — this folder assumes you already know the eight-step generation process from `02-apex-the-builder.md` in that folder.

---

## 1. The two fields that decide "how many rows," recapped and applied

From the previous folder, you already know the two Custom Metadata Types. Here, we're focused on exactly which of their fields control row *count* and row *shape*, specifically.

### `Quote_Document_Grouping__mdt` controls how many Group Header and Subtotal rows exist

Every distinct value found at every grouping level produces its own **Group Header** row and its own matching **Subtotal** row. This is the single biggest lever on row count in the whole framework, so it's worth a very concrete example.

Say a table is grouped by `PRODUCT_FAMILY` only (one grouping record, `Level__c = 1`), and the quote's lines fall into three different families: Hardware, Software, and Services. That alone produces:

- 3 Group Header rows (one per family)
- 3 Subtotal rows (one per family, matching each header)
- Plus however many Detail rows there are (one per quote line, covered in file 2 of this folder)
- Plus exactly 1 Grand Total row for the whole table

Now say you add a *second* grouping record on `Level__c = 2`, grouping by `CHARGE_TYPE` (Recurring vs. One-Time), and each of the three families happens to contain both charge types. Because `Level__c = 2` is a **different** level from `Level__c = 1`, this nests **inside** each family rather than combining with it — so now every one of the 3 families gets its own 2 charge-type sub-buckets:

- 3 outer Group Header rows (the families) + 3 outer Subtotal rows
- 3 × 2 = 6 inner Group Header rows (charge type, inside each family) + 6 inner Subtotal rows
- Plus Detail rows
- Plus 1 Grand Total row

This is exactly why `Max_Groups__c` (from the previous folder's file 1) exists as a safety limit — a few nested levels, each with a handful of real-world values, can multiply out to a lot of rows surprisingly fast. If your actual grouping instructions would produce more buckets than `Max_Groups__c` allows, generation stops with a clear error rather than quietly building an enormous table.

### `Field_Path__c` groupings work exactly the same way as `Dimension__c` groupings

It doesn't matter whether a `Quote_Document_Grouping__mdt` record uses a built-in `Dimension__c` (like `PRODUCT_FAMILY`) or a raw `Field_Path__c` (like `SBQQ__Group__r.SBQQ__BillingFrequency__c`) — row counting works identically either way. The system simply looks at every distinct value that field or dimension produces across the quote's lines, and gives each distinct value its own Group Header + Subtotal pair. If your quote has lines with three different billing frequencies (Monthly, Quarterly, Annual), grouping by that field path produces three buckets, exactly the same as grouping by three product families would.

### `Quote_Document_Table_Def__mdt` fields that change row *shape*, not just row count

| Field | What it changes about the rows |
|---|---|
| `Show_Details__c` | If `false`, **no Detail rows are created at all** — the table shows only headings, subtotals, and the grand total. This is the single field that decides whether Detail-type rows exist in a table's row set. |
| `Show_Section_Totals__c` | If `true`, an *extra* set of rows is added — one **Section Total** row per distinct Charge Type found across the whole table, sitting alongside (not nested under) the regular group subtotals. These rows always sit at `Group_Level__c = 0`, same depth as the Grand Total, since they cut across the grouping a different way rather than belonging to any one group. |
| `Measure_Set__c` | Doesn't change row *count*, but changes which `Amount_*` fields get filled in on every row — `PRICE_WATERFALL` fills `Amount_List__c`/`Amount_Regular__c`/`Amount_Discount__c`/`Amount_Net__c`/`Amount_Customer__c`/`Quantity__c`; `CHANGE` fills the seven change-specific fields instead (`Amount_Net_New__c`, `Amount_Cancellation__c`, and so on), and also causes every Detail row to additionally fill in `Transaction_Type__c`. |
| `Line_Filter__c` | Decides which quote lines even reach the row-building step at all — a line filtered out here never produces a Detail row, and never contributes to any Subtotal or Grand Total either. |

---

## 2. A complete worked example, tying rows back to metadata

Let's use the same three quote lines from the previous folder's Q-00123 example, but this time set up a table that actually groups them, so you can see every row that comes out and trace each one back to a specific metadata setting.

**The quote lines:**

| Line | Product | Product Family | Net Total | Optional? |
|---|---|---|---|---|
| 1 | Laptop | Hardware | $1,800 | No |
| 2 | Extended Warranty | Services | $300 | Yes |
| 3 | Docking Station | Hardware | $72 | No |

**The table definition** (`Quote_Document_Table_Def__mdt`):

| Field | Value |
|---|---|
| `Table_Code__c` | `FAMILY_BREAKDOWN` |
| `Line_Filter__c` | `EXCLUDE_OPTIONAL` |
| `Measure_Set__c` | `PRICE_WATERFALL` |
| `Show_Details__c` | `true` |
| `Show_Section_Totals__c` | `false` |

**The grouping record** (`Quote_Document_Grouping__mdt`) — just one, since we're grouping one level deep:

| Field | Value |
|---|---|
| `Table_Definition__c` | `FAMILY_BREAKDOWN` |
| `Dimension__c` | `PRODUCT_FAMILY` |
| `Level__c` | `1` |
| `Sequence__c` | `1` |

**What happens:** `Line_Filter__c = EXCLUDE_OPTIONAL` removes Line 2 (the optional Extended Warranty) before grouping even starts, so only Lines 1 and 3 are grouped — and both of them happen to be in the Hardware family. The result is exactly one bucket:

| `Row_Type__c` | `Display_Label__c` | `Group_Level__c` | `Amount_Net__c` | Which metadata setting caused this row |
|---|---|---|---|---|
| Group Header | Hardware | 1 | *(blank)* | The one `PRODUCT_FAMILY` grouping record, `Level__c = 1` |
| Detail | Laptop | 1 | $1,800 | `Show_Details__c = true` on the table definition |
| Detail | Docking Station | 1 | $72 | `Show_Details__c = true` on the table definition |
| Subtotal | Hardware Subtotal | 1 | $1,872 | The same one grouping record — every Group Header gets a matching Subtotal automatically |
| Grand Total | Total | 0 | $1,872 | Always created, once per table, regardless of any grouping settings |

Notice the Extended Warranty line simply never appears anywhere — not as a Detail row, not folded into any subtotal — because `Line_Filter__c = EXCLUDE_OPTIONAL` removed it before row-building ever started. That's a Custom Metadata decision, made in file 1's table definition, and it's the reason this table has zero rows related to Services at all, even though the Custom Metadata never explicitly says "hide Services."

**A note on why the Detail rows above show `Group_Level__c = 1`, the same as their Group Header, rather than one number deeper.** It's easy to assume a Detail row must always sit one level "inside" the heading above it, the way a nested folder sits inside its parent folder — but that's not quite how this framework works. `Group_Level__c` exists to tell a document template how far to indent a *heading or subtotal*, not to give every single Detail row its own unique depth. A Detail row simply inherits the same `Group_Level__c` as the innermost Group Header it's printed under; the printed order (handled by `Display_Order__c`, covered in file 2 of this folder) is what actually keeps it visually underneath that heading, not a deeper indentation number. The one exception is a table grouped by `BUNDLE`: there, each Detail row's indentation is increased further, based on that specific product's own position inside the bundle (a top-level bundle product vs. one of its optional components), so a bundle's internal structure is still visible even though "BUNDLE" itself is only one grouping level. File 2 of this folder shows exactly where that one exception is decided in the code.

---

## 3. Two things Custom Metadata deliberately does **not** control at the row level

- **Which exact dollar figure lands on a row.** The Custom Metadata says *which* measure family (`Measure_Set__c`) and *which* lines are included (`Line_Filter__c`) — but the actual arithmetic that adds up a group's lines into a Subtotal, or all counted lines into a Grand Total, is Apex, not metadata. That's [02-apex-builds-each-row.md](02-apex-builds-each-row.md).
- **The exact order rows print in.** `Display_Order__c` on every individual row is a number Apex assigns automatically as it builds each row (counting up by 10s), not something set anywhere in Custom Metadata. A document template is only ever supposed to sort by that field — never by trying to infer order from anything else.

**Next:** [02-apex-builds-each-row.md](02-apex-builds-each-row.md) — the code that turns these metadata instructions into the actual saved row fields.
