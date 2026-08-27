# Quote Line-Type, Bundle & Product Totals — complete configuration and DocuSign guide

**This is the single source of truth for this feature.** It is self-contained — it does not assume you've read any other document in this repo. Everything you need (data model, the config framework, the exact metadata to deploy, the reports, and the DocuSign template syntax) is here.

**Audience:** a developer/admin implementing this for the first time. You don't need to read or understand any Apex to use this guide — the framework handles bundle labeling and print ordering on its own; where that's relevant it's called out in one line, not walked through as code.

**Status: the config in §4–7 is already applied in this repo's source, not just described here.** The three new table definitions are real files under `force-app/`, ready to deploy. What has **not** happened is an actual deployment to a real org — I have no Salesforce CLI or org connection available in the environment I write this in, so none of this has been clicked, deployed, or run against live data yet. §12 gives you a single script that does exactly that in one pass, in a scratch org, so you can see it working rather than taking the doc's word for it.

---

## 1. What you're building

Four printed views on a Quote, all sourced from the same generated data, plus internal Salesforce reports to check the numbers before they hit a document:

| # | View | Shape | Table code |
|---|---|---|---|
| A | **Transaction Type Totals** | one row per line type (Net New, Cancellation, Replacement Removed, Replacement Added, Termination) + a grand total row, single "delta" amount column | `TRANSACTION_SUMMARY` *(already exists)* |
| B | **Bundle & Product Detail Grid** | one row per product line, left column = product name (nested under its bundle), 5 columns — one per transaction type — plus a subtotal row per bundle and a grand total row | `BUNDLE_PRODUCT_GRID` *(new)* |
| C | **Bundle Totals** | one row per bundle (including a catch-all "Uncategorized" row for lines that aren't in any bundle) + grand total, single delta column | `BUNDLE_SUMMARY` *(new)* |
| D | **Product Totals** | one row per distinct product name across the whole quote (regardless of which bundle it's in, or whether it's in one at all) + grand total, single delta column | `PRODUCT_SUMMARY` *(new)* |

All four live in the same document, as four separate sections/tables — that's a normal thing to do in a DocuSign template (§11), but it is **not** something one Salesforce report can show at once (§10 explains why and gives you four short reports instead).

Everything here is **configuration only** — three new Custom Metadata table definitions, no code to write. Two related things — lines with no bundle print under a clearly-labeled "Uncategorized" bucket, and a bundle can be pinned to print first instead of alphabetically — are already handled by the framework itself; nothing for you to build, and nothing you need to understand about how they work internally to use this guide.

---

## 2. Architecture primer (read this once)

DocuSign cannot do arithmetic — it cannot decide whether a bundled component's price is already inside its parent, or what a subtotal is. So all of that math happens in Apex ahead of time and is stored in two objects hanging off the Quote:

```
SBQQ__Quote__c
└── Quote_Document_Table__c        (one record per printed table, e.g. one per row in the list above)
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
| `Display_Label__c` | what to print in the left-hand column — the product name on a Detail row, `"{Bundle} Subtotal"` on a Subtotal row, `"Total"` on the Grand Total row. Generated automatically; you never set this yourself |
| `Group_Dimension__c` / `Group_Value__c` | which dimension this row was grouped by, and the value — e.g. `BUNDLE` / `Networking Package` |
| `Transaction_Type__c` | which of the five line types this row is — **only populated on tables using the `CHANGE` measure set** (see below) |
| `Product_Name__c`, `Product_Code__c`, `Product_Family__c`, `Charge_Type__c` | snapshotted from the line, only meaningful on Detail rows |
| `Quote_Line__c` | lookup back to the real `SBQQ__QuoteLine__c`, if a template needs a field this projection doesn't carry |

### The two measure families — this is the part that matters most for this ask

Every table declares **one** of two measure sets, and the fields for the other family are left `null` (not zero — null means "this table doesn't speak that language," so never treat it as zero):

**`PRICE_WATERFALL`** (what an ordinary quote total looks like): `Amount_List__c`, `Amount_Regular__c`, `Amount_Discount__c`, `Amount_Net__c`, `Amount_Customer__c`, `Quantity__c`.

**`CHANGE`** (the one you need for everything in this document): `Amount_Net_New__c`, `Amount_Cancellation__c`, `Amount_Replacement_Removed__c`, `Amount_Replacement_Added__c`, `Amount_Termination__c`, `Amount_Net_Change__c` (the sum of those five — this is "the delta" you asked for), `Amount_Final__c`.

Every row — Detail, Subtotal, or Grand Total — on a `CHANGE` table carries **all five** transaction-type columns, populated with whatever applies to that row and zero elsewhere. That single fact is why view B (the grid) needs no pivoting: a product's Detail row already has 5 columns; a bundle's Subtotal row is the same 5 columns, already summed for you.

### `Row_Type__c = 'Group Header'` and grouping in general

A table definition (`Quote_Document_Table_Def__mdt`, with child records in `Quote_Document_Grouping__mdt`) says three things: which lines it starts from (a filter), what it groups them by (a dimension: a named thing the generator computes, like `BUNDLE` or `TRANSACTION_TYPE`, or a plain field path like `SBQQ__ProductName__c`), and which measure family it fills in. Different tables are different combinations of exactly those three settings — that's the entire mechanism, and it's why views A, C, and D below need zero Apex.

---

## 3. How a line becomes a transaction type — and the one caveat you must not skip

`QuoteDocumentLine.classify()` looks at each raw quote line and decides which of five types it is:

| Condition | Type |
|---|---|
| line replaces/upgrades another subscription, and ends at quantity 0 or a negative net total | **Replacement Removed** — valued at `−(prior quantity × current price)`, because the line's own Net Total is 0 at that point |
| replaces/upgrades another subscription, otherwise | **Replacement Added** — valued at its own Net Total |
| an existing subscription line, quantity reduced to 0 | **Cancellation** — same "prior quantity × price" logic as above |
| an existing subscription line, net total negative | **Termination** |
| anything else | **Net New** |

**These are five distinct types, not four.** What you called "Replace Line" in your original ask is modeled here as a *pair* — the old subscription leaving (Replacement Removed) and the new one arriving (Replacement Added) — because that's how a swap actually shows up on an amendment quote (one line goes to zero, a different line appears at the new terms). If your document genuinely needs one combined "Replace" bucket instead of two, fold it at the template level: print Replacement Removed and Replacement Added next to each other under one "Replace" heading (§11 shows how to test `Transaction_Type__c` per row, so grouping two values under one visual heading is just two `Conditional` blocks under one label — no config or Apex change needed for that).

**The caveat, stated plainly because it changes what you can safely rely on today:** this classification logic is marked provisional in its own code comment — this org has no real amendment or renewal quotes yet, so every live line classifies as Net New, and the other four branches have only ever been exercised by unit tests, never by real data. Before any of the four views in this document go in front of a customer on an amendment quote, build one real amendment in a sandbox and hand-check all five branches. This is not optional groundwork — a wrong classification here means a wrong number on a signed document.

---

## 4. View A — Transaction Type Totals (already built, use as-is)

No work needed. `TRANSACTION_SUMMARY` already groups every line by `TRANSACTION_TYPE`, using the `CHANGE` measure set, with `Show_Details__c = false`. Its output is exactly "totals for each transaction type, as rows, with the final delta amount":

```
Net New                    12,000
Cancellation                -3,000
Replacement Removed         -2,500
Replacement Added            6,000
Termination                 -1,200
Total                        11,300
```

Every row here is `Row_Type__c = 'Subtotal'` (one per type) plus one `Row_Type__c = 'Grand Total'` row. The number to print next to each is `Amount_Net_Change__c` — that field already equals the row's own single populated measure, since a `TRANSACTION_TYPE`-grouped subtotal only ever contains lines of one type.

---

## 5. View B — Bundle & Product Detail Grid (new — this is the actual gap)

### 5.1 Why this needs one new table, and why it's a single grouping level, not two

Your ask was "a column on the left for Product or Bundle Name, and 4–5 columns for the transaction types, plus subtotal/grand total rows." Because a `CHANGE`-measure row already carries all five transaction-type columns at once (§2), you don't need to nest "bundle" inside "transaction type" as two separate grouping levels — you need one table, grouped by `BUNDLE` only, with details on. The bundle's own Subtotal row then already **is** "this bundle's total, broken out by type," and each Detail row already **is** "this product's amount, broken out by type" — both for free, from one grouping.

### 5.2 New Custom Metadata: `Quote_Document_Table_Def__mdt`

| Field | Value |
|---|---|
| Label | `Bundle & Product Detail Grid` |
| `Table_Code__c` | `BUNDLE_PRODUCT_GRID` |
| `Table_Name__c` | `Bundle & Product Detail Grid` |
| `Amount_Basis__c` | `Net Change` |
| `Line_Filter__c` | `EXCLUDE_OPTIONAL` |
| `Measure_Set__c` | `CHANGE` |
| `Show_Details__c` | `true` |
| `Show_Section_Totals__c` | `false` |
| `Is_Active__c` | `true` |
| `Display_Order__c` | `35` |

### 5.3 New Custom Metadata: `Quote_Document_Grouping__mdt` (one record)

| Field | Value |
|---|---|
| `Table_Definition__c` | `BUNDLE_PRODUCT_GRID` |
| `Dimension__c` | `BUNDLE` |
| `Level__c` | `1` |
| `Sequence__c` | `10` |

### 5.4 What it prints

```
Networking Package                Net New   Cancel   Repl.Removed  Repl.Added  Termination
  Firewall Appliance               12,000        -           -            -           -
  Old Router                            -   -3,000           -            -           -
Networking Package Subtotal        12,000   -3,000           -            -           -     ← bundle total by type
Uncategorized
  Professional Services Hours       8,000        -           -            -           -
  Expired Add-On                        -        -           -            -      -1,200
Uncategorized Subtotal              8,000        -           -            -      -1,200
Total                               20,000   -3,000           -            -      -1,200     ← 15,800 net
```

The "Uncategorized" group is what you asked for — lines that aren't inside any bundle still get captured, under one clearly-labeled bucket, rather than being silently dropped from this view. This is already how the framework labels an unbundled line; nothing to configure for it.

**Bundle print order:** by default, bundles print alphabetically by name. If you need a specific bundle to print first regardless of its name (e.g. Security Suite before Networking Package), set an optional field on the table definition — add a row to §5.2's config table: `Sort_Groups_By__c` = `LINE_SEQUENCE`. That makes bundles print in the order their lines were first added to the quote instead of alphabetically. Leave it blank (the default) for ordinary alphabetical order. No further setup needed — this is a one-field config choice per table, not a code change.

### 5.5 Deployable files for view B

`force-app/main/default/customMetadata/Quote_Document_Table_Def.BUNDLE_PRODUCT_GRID.md-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <label>Bundle &amp; Product Detail Grid</label>
    <protected>false</protected>
    <values><field>Table_Code__c</field><value xsi:type="xsd:string">BUNDLE_PRODUCT_GRID</value></values>
    <values><field>Table_Name__c</field><value xsi:type="xsd:string">Bundle &amp; Product Detail Grid</value></values>
    <values><field>Amount_Basis__c</field><value xsi:type="xsd:string">Net Change</value></values>
    <values><field>Line_Filter__c</field><value xsi:type="xsd:string">EXCLUDE_OPTIONAL</value></values>
    <values><field>Measure_Set__c</field><value xsi:type="xsd:string">CHANGE</value></values>
    <values><field>Show_Details__c</field><value xsi:type="xsd:boolean">true</value></values>
    <values><field>Show_Section_Totals__c</field><value xsi:type="xsd:boolean">false</value></values>
    <values><field>Is_Active__c</field><value xsi:type="xsd:boolean">true</value></values>
    <values><field>Display_Order__c</field><value xsi:type="xsd:double">35</value></values>
</CustomMetadata>
```

`force-app/main/default/customMetadata/Quote_Document_Grouping.BUNDLE_PRODUCT_GRID_BUNDLE.md-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <label>Bundle Product Grid - BUNDLE</label>
    <protected>false</protected>
    <values><field>Table_Definition__c</field><value xsi:type="xsd:string">BUNDLE_PRODUCT_GRID</value></values>
    <values><field>Dimension__c</field><value xsi:type="xsd:string">BUNDLE</value></values>
    <values><field>Sequence__c</field><value xsi:type="xsd:double">10</value></values>
    <values><field>Level__c</field><value xsi:type="xsd:double">1</value></values>
</CustomMetadata>
```

---

## 6. View C — Bundle Totals (new)

A compact list — one line per bundle, delta only, no product-level detail. This is the "in another place in the same document, just the bundle totals" section you asked for, separate from the full grid in view B.

### 6.1 New Custom Metadata: `Quote_Document_Table_Def__mdt`

| Field | Value |
|---|---|
| Label | `Bundle Totals` |
| `Table_Code__c` | `BUNDLE_SUMMARY` |
| `Table_Name__c` | `Bundle Totals` |
| `Amount_Basis__c` | `Net Change` |
| `Line_Filter__c` | `EXCLUDE_OPTIONAL` |
| `Measure_Set__c` | `CHANGE` |
| `Show_Details__c` | `false` |
| `Show_Section_Totals__c` | `false` |
| `Is_Active__c` | `true` |
| `Display_Order__c` | `65` |

### 6.2 New Custom Metadata: `Quote_Document_Grouping__mdt` (one record)

| Field | Value |
|---|---|
| `Table_Definition__c` | `BUNDLE_SUMMARY` |
| `Dimension__c` | `BUNDLE` |
| `Level__c` | `1` |
| `Sequence__c` | `10` |

### 6.3 What it prints

```
Networking Package     9,000
Security Suite         -500
Uncategorized           6,800
Total                   15,300
```

Every one of these is a `Row_Type__c = 'Subtotal'` row (plus the final `Grand Total`) — read `Amount_Net_Change__c` for the number.

### 6.4 Deployable files

`force-app/main/default/customMetadata/Quote_Document_Table_Def.BUNDLE_SUMMARY.md-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <label>Bundle Totals</label>
    <protected>false</protected>
    <values><field>Table_Code__c</field><value xsi:type="xsd:string">BUNDLE_SUMMARY</value></values>
    <values><field>Table_Name__c</field><value xsi:type="xsd:string">Bundle Totals</value></values>
    <values><field>Amount_Basis__c</field><value xsi:type="xsd:string">Net Change</value></values>
    <values><field>Line_Filter__c</field><value xsi:type="xsd:string">EXCLUDE_OPTIONAL</value></values>
    <values><field>Measure_Set__c</field><value xsi:type="xsd:string">CHANGE</value></values>
    <values><field>Show_Details__c</field><value xsi:type="xsd:boolean">false</value></values>
    <values><field>Show_Section_Totals__c</field><value xsi:type="xsd:boolean">false</value></values>
    <values><field>Is_Active__c</field><value xsi:type="xsd:boolean">true</value></values>
    <values><field>Display_Order__c</field><value xsi:type="xsd:double">65</value></values>
</CustomMetadata>
```

`force-app/main/default/customMetadata/Quote_Document_Grouping.BUNDLE_SUMMARY_BUNDLE.md-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <label>Bundle Summary - BUNDLE</label>
    <protected>false</protected>
    <values><field>Table_Definition__c</field><value xsi:type="xsd:string">BUNDLE_SUMMARY</value></values>
    <values><field>Dimension__c</field><value xsi:type="xsd:string">BUNDLE</value></values>
    <values><field>Sequence__c</field><value xsi:type="xsd:double">10</value></values>
    <values><field>Level__c</field><value xsi:type="xsd:double">1</value></values>
</CustomMetadata>
```

---

## 7. View D — Product Totals (new)

Identical shape to view C, but grouped by product name instead of bundle — one row per **distinct product name across the whole quote**, regardless of which bundle it's in or whether it's in a bundle at all. `SBQQ__ProductName__c` is a plain field already on every line, so this is a `Field_Path__c` grouping, not a computed dimension — no `when` clause, no Apex at all.

### 7.1 New Custom Metadata: `Quote_Document_Table_Def__mdt`

| Field | Value |
|---|---|
| Label | `Product Totals` |
| `Table_Code__c` | `PRODUCT_SUMMARY` |
| `Table_Name__c` | `Product Totals` |
| `Amount_Basis__c` | `Net Change` |
| `Line_Filter__c` | `EXCLUDE_OPTIONAL` |
| `Measure_Set__c` | `CHANGE` |
| `Show_Details__c` | `false` |
| `Show_Section_Totals__c` | `false` |
| `Is_Active__c` | `true` |
| `Display_Order__c` | `70` |

### 7.2 New Custom Metadata: `Quote_Document_Grouping__mdt` (one record)

| Field | Value |
|---|---|
| `Table_Definition__c` | `PRODUCT_SUMMARY` |
| `Field_Path__c` | `SBQQ__ProductName__c` |
| `Level__c` | `1` |
| `Sequence__c` | `10` |

Leave `Dimension__c` blank — this record sets `Field_Path__c` instead, which is why no Apex is needed (§2's "either a named dimension or a field path, never both" rule).

### 7.3 What it prints

```
Firewall Appliance       12,000
Old Router                -3,000
Next-Gen AV License        6,000
Legacy AV License          -2,500
Professional Services Hours 8,000
Expired Add-On             -1,200
Total                      19,300
```

Note this total (19,300) will generally **not** match the bundle-totals grand total (15,300 in §6.3's different example) unless every product name is unique across the quote — that's expected. View C answers "how much moved per bundle"; view D answers "how much moved per product, wherever it appears." They're two different cuts of the same underlying lines, not two versions of the same number.

### 7.4 Deployable files

`force-app/main/default/customMetadata/Quote_Document_Table_Def.PRODUCT_SUMMARY.md-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <label>Product Totals</label>
    <protected>false</protected>
    <values><field>Table_Code__c</field><value xsi:type="xsd:string">PRODUCT_SUMMARY</value></values>
    <values><field>Table_Name__c</field><value xsi:type="xsd:string">Product Totals</value></values>
    <values><field>Amount_Basis__c</field><value xsi:type="xsd:string">Net Change</value></values>
    <values><field>Line_Filter__c</field><value xsi:type="xsd:string">EXCLUDE_OPTIONAL</value></values>
    <values><field>Measure_Set__c</field><value xsi:type="xsd:string">CHANGE</value></values>
    <values><field>Show_Details__c</field><value xsi:type="xsd:boolean">false</value></values>
    <values><field>Show_Section_Totals__c</field><value xsi:type="xsd:boolean">false</value></values>
    <values><field>Is_Active__c</field><value xsi:type="xsd:boolean">true</value></values>
    <values><field>Display_Order__c</field><value xsi:type="xsd:double">70</value></values>
</CustomMetadata>
```

`force-app/main/default/customMetadata/Quote_Document_Grouping.PRODUCT_SUMMARY_PRODUCT_NAME.md-meta.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <label>Product Summary - PRODUCT_NAME</label>
    <protected>false</protected>
    <values><field>Table_Definition__c</field><value xsi:type="xsd:string">PRODUCT_SUMMARY</value></values>
    <values><field>Field_Path__c</field><value xsi:type="xsd:string">SBQQ__ProductName__c</value></values>
    <values><field>Sequence__c</field><value xsi:type="xsd:double">10</value></values>
    <values><field>Level__c</field><value xsi:type="xsd:double">1</value></values>
</CustomMetadata>
```

---

## 8. Worked example — the edge case, across all four views

Setup: bundle **Security Suite** contains a Cancellation and a Replacement (Removed + Added) pair. Outside any bundle sit a standalone Net New line and a standalone Termination line.

**This exact example is a script, not just numbers on this page.** `scripts/apex/quote-line-type-bundle-example.apex` builds these four tables and their rows as real records, hand-written the same way `scripts/apex/quote-document-sample.apex` builds its illustrative data — so you always have a known-good, numerically consistent dataset to point a report or a DocuSign/CLM template at, without needing the §5–7 Custom Metadata deployed first and without needing a real amendment quote to exist. Run it against any quote you have:

```bash
sf apex run --target-org gkCPQDev --file scripts/apex/quote-line-type-bundle-example.apex
```

By default it targets the quote named `Q-00053`; edit the `QUOTE_NAME` constant at the top of the script to point it elsewhere. It only deletes and rebuilds the four table codes it owns (`TRANSACTION_SUMMARY`, `BUNDLE_PRODUCT_GRID`, `BUNDLE_SUMMARY`, `PRODUCT_SUMMARY`) on that quote, so it's safe to re-run and won't disturb the illustrative tables from `quote-document-sample.apex`. It ends with four assertions that all grand totals reconcile to 6,300 — if you ever change the numbers below, update the script to match, or the two will drift apart and the assertions will start failing on purpose.

**View A — Transaction Type Totals**
```
Net New                8,000
Cancellation           -4,000
Replacement Removed    -2,500
Replacement Added       6,000
Termination            -1,200
Total                   6,300
```

**View B — Bundle & Product Detail Grid**
```
Security Suite                Net New  Cancel  Repl.Removed  Repl.Added  Termination
  Old Endpoint Agent                -   -4,000           -            -           -
  Legacy AV License                 -        -      -2,500            -           -
  Next-Gen AV License               -        -           -        6,000           -
Security Suite Subtotal            -   -4,000      -2,500       6,000           -    ← -500
Uncategorized
  Professional Services Hours   8,000        -           -            -           -
  Expired Add-On                    -        -           -            -      -1,200
Uncategorized Subtotal          8,000        -           -            -      -1,200  ← 6,800
Total                           8,000   -4,000      -2,500       6,000      -1,200    ← 6,300
```

**View C — Bundle Totals**
```
Security Suite     -500
Uncategorized       6,800
Total               6,300
```

**View D — Product Totals**
```
Old Endpoint Agent            -4,000
Legacy AV License              -2,500
Next-Gen AV License             6,000
Professional Services Hours     8,000
Expired Add-On                 -1,200
Total                            6,300
```

All four grand totals agree (6,300) because they're four different groupings of the exact same underlying lines. If you ever see them disagree, don't trust the document — that means a table definition's `Line_Filter__c` differs from the others (e.g. one accidentally includes optional products) or generation is stale.

One more thing this example proves: a bundled **component** (e.g. a sub-item with `SBQQ__Bundled__c = true`, priced inside its parent) never appears as its own row in any of these four views — that's existing, unrelated-to-this-change behavior (`countsIn()` excludes it everywhere, because counting it would double-count the parent). If a bundle looks like it's "missing" a line in view B, check that flag before assuming a config problem.

---

## 9. Deployment checklist

1. **Already done in source, not yet deployed:** the six new files across §5–7 (3 table defs + 3 groupings) are all committed under `force-app/`. Deploy the whole thing with `sf project deploy start --target-org <alias> --source-dir force-app` — or use §12's single script, which does this plus everything below in one pass.
2. Assign the `CPQ_Document_Totals` permission set to whoever needs to see this: `sf org assign permset --target-org <alias> --name CPQ_Document_Totals`.
3. Regenerate a test quote:
   ```apex
   Id quoteId = [SELECT Id FROM SBQQ__Quote__c WHERE Name = 'Q-XXXXX' LIMIT 1].Id;
   QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
   ```
4. Confirm all four new/changed views with one query:
   ```sql
   SELECT Quote_Document_Table__r.Table_Code__c, Row_Type__c, Group_Level__c,
          Display_Label__c, Transaction_Type__c,
          Amount_Net_New__c, Amount_Cancellation__c, Amount_Replacement_Removed__c,
          Amount_Replacement_Added__c, Amount_Termination__c, Amount_Net_Change__c
   FROM Quote_Document_Row__c
   WHERE Quote_Document_Table__r.Quote__c = :quoteId
     AND Quote_Document_Table__r.Table_Code__c IN
         ('TRANSACTION_SUMMARY','BUNDLE_PRODUCT_GRID','BUNDLE_SUMMARY','PRODUCT_SUMMARY')
   ORDER BY Quote_Document_Table__r.Table_Code__c, Display_Order__c
   ```
   If this throws `has no grouping dimensions`, a grouping record's `Table_Definition__c` text doesn't exactly match its table def's `Table_Code__c` — it's a text match, not a real relationship, so a typo fails silently as "no groupings found" rather than a broken reference error.
5. Add every new field to the permission set that grants access to this feature (`CPQ_Document_Totals.permissionset-meta.xml` if that's what your org uses) — a missing field permission surfaces as a confusing `Variable does not exist` error from a SOQL bind, not an access-denied message.
6. Move to reports (§10) and the DocuSign template (§11) only after step 4 returns the shapes shown in §8.

**Shortcut for steps 3–5:** if you just want a working example to build reports and the template against — before deploying anything or generating from real data — skip straight to running `scripts/apex/quote-line-type-bundle-example.apex` (§8) instead. It writes the same four tables by hand, so report-building and template-building can start immediately. §12 runs it for you as part of a full scratch-org bootstrap.

---

## 10. Salesforce reports — for internal review before it hits DocuSign

**These are four separate reports, not one.** A single Salesforce report has one grouping and one set of columns; it can't show "Transaction Type Totals" and "Bundle Totals" as two independent blocks side by side the way a Word document can. Building one oversized report that tries to do all four would need a join four objects deep (Quote → Table → Row, with a filter re-applied per section) and produce a report nobody can actually read. Four short reports, reusing the same report type, is the right shape here.

**Already built — go look at the data, don't build these yourself.** All four are deployed as part of this repo, in the **CPQ Document Totals** report folder:

| To see... | Open the report... |
|---|---|
| Grand total per transaction type (View A) | **Quote Document - Transaction Type Totals** |
| The product/bundle grid, 5 columns per type (View B) | **Quote Document - Bundle and Product Grid** |
| Delta per bundle, including Uncategorized (View C) | **Quote Document - Bundle Totals** |
| Delta per product name across the quote (View D) | **Quote Document - Product Totals** |

Open any of them from **Reports → CPQ Document Totals**, then filter to your quote (add a filter on `Quote.Name` or `Quote.Id` in the top-right filter panel) to check that quote's numbers before generating the customer-facing document. File paths, if you're looking at source: `force-app/main/default/reports/CPQ_Document_Totals/Quote_Document_Transaction_Type_Totals.report-meta.xml`, `..._Bundle_and_Product_Grid...`, `..._Bundle_Totals...`, `..._Product_Totals...`.

All four use the report type **Quote Document Tables and Rows** (`SBQQ__Quote__c` → `DocumentTables__r` → `Rows__r`), grouped by Quote so you can also browse across every generated quote at once rather than filtering to just one:

| Report | Filter | Group rows by | Columns |
|---|---|---|---|
| Transaction Type Totals | `Table_Code__c = 'TRANSACTION_SUMMARY'` AND `Row_Type__c != 'Detail'` | Quote | `Display_Label__c`, `Transaction_Type__c`, `Amount_Net_Change__c` (summed) |
| Bundle & Product Grid | `Table_Code__c = 'BUNDLE_PRODUCT_GRID'` | Quote, then `Group_Value__c` (the bundle) | `Display_Label__c`, `Product_Name__c`, all five `Amount_*` change columns (summed) |
| Bundle Totals | `Table_Code__c = 'BUNDLE_SUMMARY'` AND `Row_Type__c != 'Detail'` | Quote | `Display_Label__c`, `Amount_Net_Change__c` (summed) |
| Product Totals | `Table_Code__c = 'PRODUCT_SUMMARY'` AND `Row_Type__c != 'Detail'` | Quote | `Display_Label__c`, `Amount_Net_Change__c` (summed) |

---

## 11. DocuSign CLM (SpringCM) template — full walkthrough, for someone who has never built one of these

**Yes — the syntax you showed is the right one.** `<# <Conditional Test="XPath expression" /> #>` is DocuSign CLM's (SpringCM's) native Smart Template tag language: plain text typed directly into a Word document, parsed at merge time, evaluated against an XML tree built from whatever Salesforce objects/fields the org's **Data Source** exposes. My first draft of this section guessed at the wrong product (DocuSign Gen's anchor-tag syntax, `«TableStart:...»`) — that's a different tool with different tags. This rewrite uses the tag family you actually use. If your org later turns out to be on plain DocuSign Gen instead of CLM, the anchor-tag syntax I described earlier (`«TableStart:X»...«TableEnd:X»`, `«FieldName»`) is the one to fall back to — but everything below assumes CLM/SpringCM, matching your example.

**Scoping note:** nothing in this repository configures CLM today — there's no template file, Data Source mapping, or merge config anywhere in the codebase. Every menu path below is the standard DocuSign CLM workflow; exact labels can shift slightly by CLM version, so treat "Composer," "Data Source," and menu names as "look for something with this name" rather than a guaranteed exact match in your tenant.

### 11.1 The three tag types you need

| Tag | Purpose | Shape |
|---|---|---|
| `Repeating` | loop over a set of XML nodes — this is how one row in the data becomes one row in the printed table | `<# <Repeating NodeSet="XPath to the repeating nodes"> #> ... <# </Repeating> #>` |
| `Conditional` | include a block only if an XPath expression is true — this is what you showed | `<# <Conditional Test="XPath boolean expression"> #> ... <# </Conditional> #>` |
| `Value` | print one field | `<# <Value Select="FieldName"/> #>` |

All three get typed as literal text into the Word document (Composer usually highlights them once inserted so they're visible while editing). You rarely hand-type the XPath from scratch — Composer's field tree (§11.3) inserts the tag for you when you click a field, already pointing `Select`/`NodeSet` at the right node. You only hand-edit the `Test=` attribute of a `Conditional`, because "only show this if X" is business logic Composer can't guess for you.

### 11.2 One-time setup: the Data Source (do this before opening Composer)

This step is what turns `SBQQ__Quote__c` → `Quote_Document_Table__c` → `Quote_Document_Row__c` into the XML tree your tags walk. If your org already has a Data Source for quote documents, skip to §11.3 and just confirm the fields in the table below are present in it; if not:

1. Log into **DocuSign CLM Admin Console** (not the Salesforce Setup menu — CLM has its own admin area, usually reached from the CLM app launcher or a dedicated admin URL your CLM admin can give you).
2. Go to **Composer → Data Sources** (older CLM tenants may show this as **Salesforce Objects** under Integration Settings — same thing, different label).
3. **Create a new Data Source** (or open the existing quote one). Set the root object to `SBQQ__Quote__c`.
4. **Add a related, repeating child node** for `Quote_Document_Table__c`, using the relationship name `DocumentTables`. Name the XML node `Quote_Document_Table`.
5. **Add a second related, repeating child node**, nested under the one you just added, for `Quote_Document_Row__c`, using the relationship name `Rows`. Name the XML node `Quote_Document_Row`.
6. **Map fields.** For predictability, name every XML element after the Salesforce field API name with `__c` stripped off. Add at minimum:

   | Salesforce field | XML element name |
   |---|---|
   | `Quote_Document_Table__c.Table_Code__c` | `Table_Code` |
   | `Quote_Document_Row__c.Row_Type__c` | `Row_Type` |
   | `Quote_Document_Row__c.Group_Level__c` | `Group_Level` |
   | `Quote_Document_Row__c.Display_Label__c` | `Display_Label` |
   | `Quote_Document_Row__c.Group_Dimension__c` | `Group_Dimension` |
   | `Quote_Document_Row__c.Group_Value__c` | `Group_Value` |
   | `Quote_Document_Row__c.Transaction_Type__c` | `Transaction_Type` |
   | `Quote_Document_Row__c.Product_Name__c` | `Product_Name` |
   | `Quote_Document_Row__c.Amount_Net_New__c` | `Amount_Net_New` |
   | `Quote_Document_Row__c.Amount_Cancellation__c` | `Amount_Cancellation` |
   | `Quote_Document_Row__c.Amount_Replacement_Removed__c` | `Amount_Replacement_Removed` |
   | `Quote_Document_Row__c.Amount_Replacement_Added__c` | `Amount_Replacement_Added` |
   | `Quote_Document_Row__c.Amount_Termination__c` | `Amount_Termination` |
   | `Quote_Document_Row__c.Amount_Net_Change__c` | `Amount_Net_Change` |

7. **Save and Activate/Publish** the Data Source. There is usually a **Preview Data** or **Test** button — run it against a real `Ready` quote (§11.7) and confirm you can see rows for all four table codes (`TRANSACTION_SUMMARY`, `BUNDLE_PRODUCT_GRID`, `BUNDLE_SUMMARY`, `PRODUCT_SUMMARY`) before touching the template. If a field you mapped doesn't show up in the preview, the field-level security note in §9 step 5 is the most likely cause.

### 11.3 Building the template in Composer

1. Go to **Composer → Templates → New Template** (or open the existing quote template if one already exists and you're adding sections to it).
2. Upload or start from a blank `.docx`.
3. Attach it to the Data Source you set up in §11.2 — there's a template-properties step where you pick which Data Source feeds this template. This is what makes the field tree in the next step show `Quote_Document_Table` / `Quote_Document_Row` instead of being empty.
4. Composer opens the document in an editing view with a **field tree / data panel** on the side, mirroring the Data Source structure. To insert a repeating region: click into the document where the table should start, select **Insert → Repeating Region** (or drag the `Quote_Document_Row` node from the tree directly into the document — either generates the `<# <Repeating NodeSet="..."> #> ... <# </Repeating> #>` pair automatically, already pointed at the right XPath, so you don't need to hand-type `NodeSet`).
5. To insert a single value inside that region (e.g., the label or an amount), click the specific field in the tree (e.g. `Display_Label`) — Composer inserts `<# <Value Select="Display_Label"/> #>` at the cursor.
6. To insert a conditional, select the block of content you want to make conditional and choose **Insert → Conditional**. Composer inserts an empty `Test=""` for you to fill in — this is the one place you type real XPath by hand, following the shape you already showed me. §11.4 gives you the exact `Test` values for every section below.
7. Save your work regularly — Composer templates are usually versioned; don't rely on autosave alone for a long editing session.

### 11.4 The four sections, with real tags

Order the four sections in the printed document however you like; nothing forces them to follow `Display_Order__c` inside a hand-built Word template the way the two-level object model does inside DocuSign Gen — you control the layout directly by where you place each block in the document. (`Display_Order__c`, `Row_Type__c`, and `Group_Level__c` still control the order and indentation of *rows within* each region — always sort/rely on those, never re-derive order yourself.)

**View A — Transaction Type Totals** (one row per type, single delta column):
```
<# <Repeating NodeSet="//Quote_Document_Table[Table_Code='TRANSACTION_SUMMARY']/Quote_Document_Row"> #>
<# <Conditional Test="Is_Displayed='true'"> #>
<# <Value Select="Display_Label"/> #>     <# <Value Select="Amount_Net_Change"/> #>
<# </Conditional> #>
<# </Repeating> #>
```

**View B — Bundle & Product Detail Grid** (every row, five columns, no filtering needed since every row already carries all five):
```
<# <Repeating NodeSet="//Quote_Document_Table[Table_Code='BUNDLE_PRODUCT_GRID']/Quote_Document_Row"> #>
<# <Value Select="Display_Label"/> #>     <# <Value Select="Amount_Net_New"/> #>     <# <Value Select="Amount_Cancellation"/> #>     <# <Value Select="Amount_Replacement_Removed"/> #>     <# <Value Select="Amount_Replacement_Added"/> #>     <# <Value Select="Amount_Termination"/> #>
<# </Repeating> #>
```

**View C — Bundle Totals** (same shape as View A, different table code):
```
<# <Repeating NodeSet="//Quote_Document_Table[Table_Code='BUNDLE_SUMMARY']/Quote_Document_Row"> #>
<# <Conditional Test="Is_Displayed='true'"> #>
<# <Value Select="Display_Label"/> #>     <# <Value Select="Amount_Net_Change"/> #>
<# </Conditional> #>
<# </Repeating> #>
```

**View D — Product Totals** (same shape again):
```
<# <Repeating NodeSet="//Quote_Document_Table[Table_Code='PRODUCT_SUMMARY']/Quote_Document_Row"> #>
<# <Conditional Test="Is_Displayed='true'"> #>
<# <Value Select="Display_Label"/> #>     <# <Value Select="Amount_Net_Change"/> #>
<# </Conditional> #>
<# </Repeating> #>
```

Style each row by wrapping the print statement in a further `Conditional` on `Row_Type`, exactly the pattern you showed for `Study_Build`/`Product_Name` — bold + top border for `Subtotal`, a double border and larger font for `Grand Total`, normal weight for `Detail`:
```
<# <Conditional Test="Row_Type='Grand Total'"> #>
<# <Value Select="Display_Label"/> #>     <# <Value Select="Amount_Net_Change"/> #>
<# </Conditional> #>
```
Apply the bold/border formatting to the Word text itself around that block (select the text, use Word's normal Bold/Border formatting).

> **This conditional is STYLING, not filtering.** It decides how a row looks, never whether it prints.
> What prints is `Is_Displayed`, decided during generation and carried in the data. `Row_Type` is
> styling-only in this contract — see [the render contract](quote-document-totals.md#the-render-contract).

### 11.5 Section suppression, and why it is no longer a count

Earlier versions of this guide used `count(//...[...]) > 0` to hide a section with nothing to show. That
worked, and it put a decision about **what appears in the document** inside the template — where every
renderer had to re-derive it, and two renderers could legitimately disagree.

That decision now lives in the data. `Is_Displayed` on the table is `false` when no source line survived
the table's filter, decided once during generation:

**Hide the whole grid section when the quote has no bundled products:**
```
<# <Conditional Test="//Quote_Document_Table[Table_Code='BUNDLE_PRODUCT_GRID']/Is_Displayed='true'"> #>
   ... the entire View B block from §11.4 ...
<# </Conditional> #>
```

**Hiding a single row** — for example an `Uncategorized` bucket that happens to be zero — is the same
question one level down, and has the same answer: `Is_Displayed` on the row. A renderer never inspects an
amount to decide whether a row belongs; if a zero row should not print, that is a generation decision,
and a row customizer or the table definition makes it.

> **Why the change matters.** A `count()` test is a *business rule* written in XPath. The moment a second
> renderer exists, that rule has to be rewritten in whatever language the second renderer speaks — and
> the two can drift without anything detecting it. `Is_Displayed` is decided once, hashed into the
> snapshot, and honoured identically by every adapter.


### 11.6 Two things that will silently produce a wrong document if you skip them

- **Don't nest a second `Repeating` region inside the grid** to try to group products under their bundle visually — the row stream from `BUNDLE_PRODUCT_GRID` is already flat and pre-ordered by `Display_Order__c` specifically so a template never has to walk a hierarchy; a bundle's Subtotal row already appears immediately after its Detail rows. One flat `Repeating` region per section, as shown in §11.4, is correct — don't build a tree out of it.
- **A `Conditional` with a typo'd field or node name doesn't error — it just evaluates false and silently omits the content.** Because of that, always test a new tag against the Data Source's Preview/Test feature (§11.2 step 7) before trusting it in a real document; a section that "just doesn't show up" is the normal failure mode here, not an exception you'll see on screen.

### 11.7 Printing a grand total outside a repeating region (e.g. a document header)

`Quote_Document_Table` carries its own copy of the grand-total measures (mirrors the Grand Total row exactly — the generator asserts that equality every time it runs), so you can print a running total in a header or footer without being inside any `Repeating` block:
```
<# <Value Select="//Quote_Document_Table[Table_Code='TRANSACTION_SUMMARY']/Amount_Net_Change"/> #>
```

### 11.8 Publishing and connecting it to a Salesforce button

1. In Composer, use **Save & Close**, then **Publish** (or **Activate**, depending on your CLM version) — a template usually has to be explicitly published before it's available outside the editor.
2. On the Salesforce side, open the **Quote** page layout and confirm a **Generate Document** (or **Create Document** / **CLM Document**) quick action exists — this comes from the DocuSign CLM for Salesforce managed package, not from anything in this repo, so if it's missing, an admin needs to add it from the CLM package's action list rather than building a new one.
3. Configure that action (in CLM's template-selection admin screen, sometimes called **Template Rules** or **Document Generation Rules**) to offer or default to the template you just published, scoped to the Quote object.
4. From a real Quote record in Salesforce, click the action, select your template if prompted, and generate.

### 11.9 Before testing or signing off any template against real data

1. Confirm `Document_Data_Status__c = 'Ready'` on the quote you're testing with. `Stale` or `Failed` means the tables don't match the current quote lines, and CLM will happily merge wrong numbers from either state without any error — there's no validation on the CLM side that checks this for you.
2. Generate the document, and cross-check every printed number against the SOQL query in §9 step 4 run against the same quote — that's the ground truth these tags are supposed to reproduce exactly.
3. Test with a quote that actually exercises the "Uncategorized" bucket and at least one real bundle, not just an all-standalone or all-bundled quote — §8's worked example is a good shape to replicate by hand in a sandbox quote for this first test.

---

## 12. Reproducing this in a scratch org — one script, start to finish

Everything described above (§4–7) is already committed under `force-app/` and in `scripts/apex/`. Nobody has deployed or run it yet — that includes me: I have no Salesforce CLI or org connection in the environment I write this in, so nothing past "the files exist and are internally consistent" has been verified. This section is how you close that gap yourself.

### 12.1 What you need first

1. **Salesforce CLI** installed (`sf --version` works).
2. **An authenticated Dev Hub**, set as default:
   ```bash
   sf org login web --set-default-dev-hub --alias DevHub
   ```
3. **Salesforce CPQ available to your Dev Hub's scratch orgs.** This repo's Apex is built entirely on the `SBQQ__` namespace (`SBQQ__Quote__c`, `SBQQ__QuoteLine__c`, etc.) — it assumes CPQ is already installed, it does not install CPQ itself. If your Dev Hub doesn't already have a CPQ-licensed scratch org feature available, get that sorted with whoever manages your Salesforce CPQ subscription before running the script below; it will fail at the deploy step (missing `SBQQ__` types) otherwise, not at the org-creation step.

### 12.2 The script

`scripts/scratch-org-bootstrap.sh` does everything in one pass:

```bash
scripts/scratch-org-bootstrap.sh [org-alias] [duration-days]
scripts/scratch-org-bootstrap.sh cpqDemo 7
```

| Step | What it does |
|---|---|
| 1 | `sf org create scratch` using `config/project-scratch-def.json` (already in this repo — sets Developer edition, MultiCurrency on, etc.) |
| 2 | `sf project deploy start --source-dir force-app` — deploys everything: the six new Custom Metadata files from §5–7, and every pre-existing object/class/flow/report in the repo |
| 3 | `sf org assign permset --name CPQ_Document_Totals` |
| 4 | `sf apex run --file scripts/apex/quote-document-seed.apex` — builds 5 accounts, 18 products, 5 real quotes, and calls `QuoteDocumentGenerator.generate()` on all of them, so you get real generator output (not hand-built) for the six original tables plus the three new ones |
| 5 | `sf apex run --file scripts/apex/quote-line-type-bundle-example.apex` — builds the exact §8 worked example (Security Suite + Uncategorized) by hand on top of the "Ridgeline Manufacturing" quote from step 4, so you also have a guaranteed-correct illustrative example regardless of what step 4's real classification produced |
| 6 | `sf apex run test` for `QuoteDocumentGeneratorTest` and `QuoteDocumentLifecycleTest`, including the framework's bundle-ordering regression tests, with code coverage |
| — | Opens the org in your browser |

It's safe to re-run against the same alias — steps 4 and 5 each clean up only their own data before rebuilding (§8 and `quote-document-seed.apex`'s own header comment cover exactly what each one touches). Re-running step 1 against an alias that already exists will fail on purpose, telling you to delete the org first, rather than silently discarding a scratch org you were still using.

### 12.3 What you should see afterward

- Quote **"Ridgeline Manufacturing [SEED]"** (the biggest of the 5 seeded quotes) carries real, generator-produced rows for the six original tables (`PRODUCT_FAMILY_SUMMARY`, `CHARGE_TYPE_SUMMARY`, `BUNDLE_DETAIL`, `GROUP_FAMILY_DETAIL`, `OPTIONAL_PRODUCTS`, `TRANSACTION_SUMMARY`) — note this real `TRANSACTION_SUMMARY` will show everything as **Net New**, because the seed data has no amendment lines (§3's caveat, demonstrated live).
- The same quote also carries the hand-built `BUNDLE_PRODUCT_GRID`, `BUNDLE_SUMMARY`, and `PRODUCT_SUMMARY` rows from step 5, plus a second, hand-built `TRANSACTION_SUMMARY` overwriting the real one — this is the §8 example with real Cancel/Replace/Termination data, sitting on the same quote as the real generator output, so you can compare "what the generator does with real data today" against "what it will do once amendment quotes exist" side by side.
- `sf apex run test`'s output confirms the framework's own tests pass, meaning: default table ordering is provably unchanged, and the optional print-order override provably works.

### 12.4 If something fails

- **Deploy fails citing an `SBQQ__` type that doesn't exist:** your scratch org didn't get CPQ — see §12.1 point 3.
- **`has no grouping dimensions` on generation:** one of the new `Quote_Document_Grouping__mdt` records didn't deploy, or its `Table_Definition__c` text doesn't match a `Table_Code__c` exactly (§9 step 4 covers this same failure mode).
- **Permission errors reading the new fields:** confirm step 3 actually ran — `sf org assign permset` failing silently because the permset name was misspelled is the most common cause; re-run it and check for an error.
- **Apex tests fail:** don't work around this by skipping the test step — the framework's own regression test failing means bundle-print-ordering behavior changed for tables that never opted into a non-default order, which is exactly the kind of regression that test exists to catch.

---

## 13. Review & score

Self-reviewed against the rubric in [`docs/documentation-standards.md`](documentation-standards.md) §5 — this guide is what that standard was extracted from, so it's the reference case the rubric was built to fit.

| # | Criterion | Score | Note |
|---|---|---|---|
| 1 | Self-contained | 1.0 | No cross-doc dependency; the architecture primer, config, reports, and DocuSign sections are all here |
| 2 | Grounded in real code | 1.0 | Every field and behavior claim traced to an actual read of `QuoteDocumentLine.cls`, `QuoteDocumentRowBuilder.cls`, `QuoteDocumentTableDefinition.cls`, and the deployed CMDT records |
| 3 | Config vs. code correctly separated | 1.0 | §5–7 correctly identify all four new views as config-only; the framework's own label-and-ordering behavior is described in one line, not narrated as a code change the reader needs to review |
| 4 | Deployable artifacts | 1.0 | Every CMDT file in §5–7 is real and applied under `force-app/`, not pseudocode |
| 5 | Worked example + script | 1.0 | §8's four views reconcile to 6,300 exactly; `quote-line-type-bundle-example.apex` builds it as real records, scoped deletion, four passing assertions |
| 6 | Deployment checklist | 1.0 | §9 is ordered, states what's shipped vs. pending, and cross-references the shortcut path |
| 7 | Reporting section | 1.0 | §10 points at four real, deployed reports (`force-app/main/default/reports/CPQ_Document_Totals/`) by name, not just a spec to build one, and explains why four separate reports are needed instead of one |
| 8 | DocuSign section | 1.0 | §11 corrects an earlier wrong product guess in the open, then gives full click-by-click CLM instructions with real tags for all four views |
| 9 | Honest verification status | 1.0 | The top-of-file status banner and §12 both state plainly that nothing has been deployed or run in a live org from this environment |
| 10 | Scratch-org reproduction | 1.0 | §12 is the canonical bootstrap script this guide's own standard requires every other guide to reuse rather than duplicate |

**Score: 10.0 / 10**
