# Quote Document Totals — architecture and maintenance guide

**Audience:** the developer who inherits this and has to keep it working.
**Assumed knowledge:** Apex, triggers, SOQL, Salesforce CPQ basics.
**Status:** deployed to `gkCPQDev`, 29 tests passing, verified against Q-00053.

Read sections 1–4 before changing anything. Section 9 is the "I need to do X" index.

---

## 1. What this is and why it exists

DocuSign Gen/CLM generates a document from a Quote. It can print fields and repeat over related lists, but it cannot do arithmetic: it cannot decide whether a bundle component's price is already inside its parent, whether an optional product counts, or what a subtotal is. Asking a Word template to work that out is how documents end up with wrong numbers on them, and a wrong number on a signed document is a commercial problem, not a bug report.

So the arithmetic happens in Apex, ahead of time, and lands in two custom objects hanging off the Quote:

```
SBQQ__Quote__c
└── Quote_Document_Table__c        (one per table in the document)
    └── Quote_Document_Row__c      (headers, details, subtotals, grand totals)
```

DocuSign then does one thing: print rows in `Display_Order__c` order, indenting by `Group_Level__c`, styling by `Row_Type__c`. No logic.

**The hierarchy depth is not an accident.** DocuSign documents support fields from up to two levels of related lists. Quote → Table → Row uses exactly that budget. Adding a third object between them would break template traversal, which is why an early proposal for a `Quote_Document_Generation__c` object was dropped in favour of a status field on the Quote.

### The one rule that matters

> Quote Lines are the source of truth. Everything in these two objects is a disposable projection that can be rebuilt at any time.

Every design decision below follows from that. Generated data is never repaired, migrated, or merged — it is deleted and rebuilt.

---

## 2. The data model

### `Quote_Document_Table__c` — one generated table

| Field | Type | Notes |
|---|---|---|
| `Name` | Text(80) | `Q-00053 - Bundle Detail`. Cosmetic, for list views. |
| `Quote__c` | **Lookup** → `SBQQ__Quote__c`, required, `deleteConstraint = Cascade` | Child relationship `DocumentTables`. See §2.1. |
| `Quote_Number__c` | Formula (Text) | `Quote__r.Name`. **Use this, not the Name** — a formula cannot drift. |
| `Table_Code__c` | Text(60) | `BUNDLE_DETAIL`. The stable identifier a template references. |
| `Table_Key__c` | Text(120), External ID, Unique | `<QuoteId>:<TableCode>`. Keyed on the **Id**, not the number, because Ids never change. |
| `Display_Order__c` | Number(3,0) | Order within the document. Increments of ten. |
| `Amount_Basis__c` | Picklist | What the amounts *mean*: Final Value, Net Change, TCV, ACV… |
| `Group_Dimensions__c` | Text(255) | `QUOTE_LINE_GROUP > PRODUCT_FAMILY`. Traceability only. |
| `Line_Filter__c` | Text(40) | Which lines it was built from. |
| `Measure_Set__c` | Text(40) | `PRICE_WATERFALL` or `CHANGE`. |
| `Status__c` | Picklist | Generating / Complete / Failed. |
| `Generated_On__c`, `Row_Count__c` | | Diagnostics. |
| 13 measure fields | Currency / Number | Copied from the Grand Total row. |

### `Quote_Document_Row__c` — one row

| Group | Fields |
|---|---|
| Relationships | `Quote_Document_Table__c` (Master-Detail, `Rows`), `Quote_Line__c` (Lookup, clears on delete) |
| Structure | `Row_Type__c`, `Display_Order__c`, `Row_Key__c`, `Group_Level__c` |
| Grouping | `Group_Dimension__c`, `Group_Value__c`, `Group_Key__c`, `Display_Label__c` |
| Inclusion | `Is_Displayed__c`, `Include_In_Subtotal__c`, `Include_In_Grand_Total__c` |
| Snapshots | `Product_Name__c`, `Product_Code__c`, `Product_Family__c`, `Charge_Type__c`, `Transaction_Type__c` |
| Measures | the same 13 |

`Row_Type__c`: **Group Header** · **Detail** · **Subtotal** (a grouping node) · **Section Total** (a logical slice such as Recurring) · **Grand Total** · **Informational** · **Discount** · **Rounding** · **Note**.

The last three exist only through the `QuoteDocumentRowCustomizer` extension point — `QuoteDocumentRowBuilder` never emits them, there is no declarative config path to any of them, and no active table definition ships with one attached today. **Discount** is a counted row (usually tied to the `Quote_Line__c` it discounts) — the same leaf-contribution treatment as Detail. **Rounding** is a whole-table adjustment (`Group_Level__c = 0`, no `Quote_Line__c`) that counts toward the grand total only, never a subtotal — `Rounding_Row_Shape` enforces the shape declaratively, and `QuoteDocumentGenerator.verify()` refuses to let one onto a table checked against the Quote's own Net Amount, because CPQ has no idea the adjustment exists. **Note** is unconstrained the same way Informational is — no amount, no total impact, free text only. See `QuoteDocumentRoundingAdjustmentRowCustomizer` for a full worked example of Rounding.

### 2.1 Why Quote is a lookup and Table is master-detail

The two relationships in the hierarchy are deliberately different types.

**`Quote_Document_Row__c` → `Quote_Document_Table__c` is master-detail.** The generator's rebuild is `delete [tables]` and lets the rows go with them. Without the cascade that becomes a two-step delete with a window where rows are orphaned. Rows are also `ControlledByParent`, so they inherit whatever visibility the table has.

**`Quote_Document_Table__c` → `SBQQ__Quote__c` is a lookup**, configured to behave as closely to master-detail as a lookup can:

| Setting | Value | Why |
|---|---|---|
| `required` | `true` | A table with no quote is meaningless. The platform enforces it, so no validation rule is needed. |
| `deleteConstraint` | `Cascade` | Deleting a Quote still removes its tables, and the rows follow through their own master-detail. **Verified:** deleting a quote removed 6 tables and 21 rows, and they land in the recycle bin, so undeleting the Quote restores them. |
| `relationshipName` | `DocumentTables` | Unchanged from the master-detail version, so the report type, both reports, and any DocuSign template keep working. |

**What the lookup costs you, and it is exactly one thing: sharing.**

Master-detail made the object `ControlledByParent` — you could not see a table unless you could see its Quote. A lookup cannot do that, so the object's OWD is now **Public Read/Write**. Anyone granted the object through `CPQ_Document_Totals` can see and edit every quote's generated totals, regardless of whether they can see the quote itself.

That is a real reduction in confidentiality for commercially sensitive numbers. It is acceptable because the permission set is the gate and generated data is a projection of data the user can usually already see — but if quote visibility is genuinely restricted in your org, tighten the OWD to Private and add sharing rules. Note that Private also means the generator cannot delete tables another user created, which breaks regeneration; you would need `modifyAllRecords` on the permission set to compensate.

Everything else master-detail was providing is preserved by the settings above.

### 2.2 Why `Include_In_Subtotal__c` and `Include_In_Grand_Total__c` stay separate

`QuoteDocumentLine.countsIn` returns a single boolean, and the builder path (`QuoteDocumentRowBuilder`) sets both flags equal from it — [`specs/quote-docusign-totals/spec.md`](../specs/quote-docusign-totals/spec.md) §2 category C records this as a deliberate v1 constraint. Reading that code in isolation, a reasonable conclusion is that the second flag is dead and the two should collapse into one `Contributes_To_Total__c`. **Do not do this.**

The customizer path already exercises the divergence the builder path hasn't needed yet. A Rounding row is a whole-table adjustment: `Group_Level__c = 0`, it must count toward the grand total, and it must **never** count toward a subtotal — there is no subtotal it belongs to. That is only expressible with two independent flags. Collapsing them breaks the Rounding customizer today and forecloses any future row type with the same shape.

The hidden-row invariant stays conceptual, not mechanical: *a hidden row must contribute to at least one arithmetic total* — not "must have one generic contribution flag set". The declarative rule `Hidden_Row_Must_Count` already encodes the former; do not "simplify" it into checking a single collapsed flag.

### The 13 measures, and why there are two families

Identical API names on both objects. That is deliberate — `Measures.writeTo(SObject)` writes to a row or a table with the same code.

**Price waterfall** — what quote documents actually print:

| Field | From |
|---|---|
| `Amount_List__c` | `SBQQ__ListTotal__c` |
| `Amount_Regular__c` | `SBQQ__RegularTotal__c` |
| `Amount_Discount__c` | `SBQQ__TotalDiscountAmount__c` |
| `Amount_Net__c` | `SBQQ__NetTotal__c` |
| `Amount_Customer__c` | `SBQQ__CustomerTotal__c` |
| `Quantity__c` | `SBQQ__Quantity__c` |

**Change measures** — the amendment story. Removals always negative:

`Amount_Net_New__c` · `Amount_Cancellation__c` · `Amount_Replacement_Removed__c` · `Amount_Replacement_Added__c` · `Amount_Termination__c` · `Amount_Net_Change__c` (sum of the five) · `Amount_Final__c`

A table declares one family and leaves the other **null**. Null means "this table does not speak that language" — not zero. Do not `NVL` it away in a template; print the columns named by `Measure_Set__c`.

> **Do not expect `List − Discount = Net`.** On Q-00053 the laptop has List 60,000, Discount 0, Net 54,000. `SBQQ__TotalDiscountAmount__c` does not capture the partner/net adjustment. The five columns are independent sums, not a derivable chain.

### Why measures are properties, not a `Map<String, Decimal>`

A typo in a map key silently returns zero, and a silent zero in a total is exactly the failure this system exists to prevent. Explicit properties give a compile error instead. The cost is that adding a measure touches two methods in `Measures` — that is the intended trade.

### Why the table duplicates the grand total row

So a template can print a total outside a repeating block, and so the generator has a cheap reconciliation assertion. The table's measures are **copied from** the grand total row, never recalculated — two independent calculations could disagree; a copy cannot.

### Why the measures are not roll-up summaries

Rows include subtotal and grand-total records. A roll-up would add the details *and* the subtotals *and* the grand total, roughly tripling every figure.

---

## 3. The commercial rules

These are the rules a document is wrong without. They live in `QuoteDocumentLine`, and nowhere else.

### What counts — verified against Q-00053

| Line | CPQ flags | Net Total | Displayed | Counted |
|---|---|---|---|---|
| 15" Laptop | `Bundle__c = true` | 54,000 | yes | yes |
| CPU / RAM / SSD | `Bundled__c = true`, `OptionLevel = 1` | 0 | yes | **no** |
| Smartphone Activation, Case | option, `Bundled__c = false` | 50 / 800 | yes | yes |
| 10" Tablet | `Optional__c = true` | 6,000 | yes | **no** |

Counted lines sum to exactly **102,910**, which is `SBQQ__NetAmount__c` on the Quote. That equality is asserted at generation time and is the single most valuable check in the codebase.

```apex
public Boolean countsIn(String lineFilter) {
    if (isBundledComponent) return false;                    // price is in the package
    if (isOptional) return FILTER_OPTIONAL_ONLY.equals(lineFilter);
    return true;
}
```

**Counting is table-relative, not a property of the line.** An optional product must not count in an ordinary summary — CPQ's own roll-up excludes it and the document has to agree with the Quote. But it must count in the Optional Products table, whose entire subject is those lines; a zero total there would be absurd. This was a real bug during development: making `isOptional` a blanket exclusion produced an Optional Products table totalling zero.

### Transaction classification — PROVISIONAL, read this before trusting it

`classify()` decides which change measure a line feeds. **It has never been validated against real data**, because `gkCPQDev` contains no amendment or renewal quotes — every live line classifies as Net New. The branches are covered by tests only.

Current rules:

| Condition | Result |
|---|---|
| `UpgradedSubscription__c` or `RenewedSubscription__c` populated, and quantity 0 or net < 0 | Replacement Removed, valued at `−(PriorQuantity × NetPrice)` |
| Either populated otherwise | Replacement Added, valued at Net Total |
| `Existing__c` and quantity 0 | Cancellation, valued at `−(PriorQuantity × NetPrice)` |
| `Existing__c` and net < 0 | Termination |
| otherwise | Net New |

Two things a maintainer must know:

1. **A cancelled amendment line ends at quantity zero, so its own Net Total is zero.** The value leaving the deal is the prior quantity at the current price. That is why the code reads `SBQQ__PriorQuantity__c` rather than the line total. Using the line total would silently report every cancellation as £0.
2. **CPQ will not store a negative Net Total from a negative Net Price** in a plain quote — discovered while writing the test. Do not build a rule on "the removed side is negative"; use quantity going to zero.

Before this feature is used on amendment quotes, build a real amendment in a sandbox and check these five branches by hand.

**Every table that consumes these measures is deactivated until that happens.** `classify()` runs for every line regardless of table, but only `Measure_Set__c = CHANGE` tables publish its output as totals. All four are `Is_Active__c = false`:

| Table | Why it is exposed |
|---|---|
| `TRANSACTION_SUMMARY` | CHANGE measures, and the only table grouping by `TRANSACTION_TYPE` |
| `PRODUCT_SUMMARY` | CHANGE measures |
| `BUNDLE_SUMMARY` | CHANGE measures |
| `BUNDLE_PRODUCT_GRID` | CHANGE measures |

Deactivating only `TRANSACTION_SUMMARY` is not sufficient — the other three publish the same unvalidated numbers under different groupings. Reactivate all four together, and only after the five branches above are confirmed against a real amendment.

Deactivation closes this completely for generated data. `classify()` still runs in memory for every line, but `QuoteDocumentRowBuilder` writes `Transaction_Type__c` only when `definition.usesChangeMeasures()` — so with all four tables off, no provisional classification reaches a row, a report, or a template.

---

## 4. Architecture and control flow

### The pipeline

```
query quote + lines  →  normalize  →  filter  →  group  →  total  →  build rows  →  persist  →  verify
```

Core classes, each with one job:

| Class | Responsibility |
|---|---|
| `QuoteDocumentTableDefinition` | What tables exist, read from Custom Metadata |
| `QuoteDocumentLine` | One CPQ line, normalized. **All commercial rules live here** |
| `QuoteDocumentRowBuilder` | Recursive grouping, totalling, row emission |
| `QuoteDocumentGenerator` | Orchestration, persistence, verification, entry points |
| `QuoteDocumentGenerateJob` | One quote, one transaction |
| `QuoteDocumentStaleness` | Marks quotes whose tables no longer match |
| `QuoteDocumentFingerprint` | Canonicalizes and hashes everything that can change output, so generation can be skipped when nothing did |

### Runtime flow

```
User edits a Quote Line
   └─ QuoteDocumentQuoteLineTrigger (after insert/update/delete/undelete)
        └─ QuoteDocumentStaleness.markStale(quoteIds)
             └─ @future applyStaleAsync   ──►  Quote.Document_Data_Status__c = 'Stale'

User presses "Generate Document Tables"
   └─ Screen flow  ──►  QuoteDocumentGenerator.generateFromFlow (@InvocableMethod)
        └─ generate(Set<Id>)
             └─ generateOne(quote)   [savepoint]
                  ├─ delete existing tables      (master-detail cascades the rows)
                  ├─ build + insert tables
                  ├─ build + insert rows
                  ├─ stamp table measures from the grand total row
                  ├─ verify()  ← throws and rolls back on any mismatch
                  └─ Quote.Document_Data_Status__c = 'Ready'   [staleness suppressed]

DocuSign action
   └─ allowed only when Document_Data_Status__c = 'Ready'
```

### Invariant S1 — the stale write from a Quote Line trigger must be deferred

A synchronous `update` of `SBQQ__Quote__c` from inside the Quote Line trigger **does not survive**. CPQ's own `QuoteLineAfter` handler reads the quote, calculates, and writes it back later in the same cascade using the copy it read *before* our write. Our `Stale` value is silently overwritten and the quote reads `Ready` with out-of-date tables behind it.

This was observed, not assumed. Instrumentation showed the trigger firing, the update executing, and the committed value still reading `Ready`. Deferring to `@future` puts the write after the cascade commits, where nothing can clobber it.

**If you ever move this back to a synchronous write, you will reintroduce a bug that silently produces wrong signed documents.** The test `editingALineMarksTheQuoteStale` is the guard; do not weaken it.

### Invariant S2 — generator-owned writes to the Quote must suppress staleness

`markQuote()` wraps its update in `QuoteDocumentStaleness.suppress()` / `resume()`. Without it, the generator's write to `Document_Data_Status__c = 'Ready'` fires the Quote trigger, which marks the quote stale as a nested update inside the generator's own DML. The outer write wins, so the quote reads `Ready` — but the quote is now in the "already handled" set, so **the next genuine edit is silently skipped**. Same failure mode, different route.

Every Quote write the generator makes — including the fingerprint reuse check below — goes through `markQuote` or an equivalent wrapped in `suppress()`/`resume()`. No new code should add a bare `update SBQQ__Quote__c`.

### Fingerprint reuse — closing the gap trigger-based staleness cannot see

Invariants S1/S2 keep `Document_Data_Status__c` honest for anything that fires a Quote or Quote Line trigger. They cannot see a change to a field with no trigger of its own — principally a `Product2` field referenced by a grouping `Field_Path__c` (e.g. `Family`). `QuoteDocumentFingerprint` closes that gap: on every `generate()` call, before any DML, it canonicalizes everything that can change a table's output (active table definitions, groupings, required field paths, quote-level values including `CurrencyIsoCode` where multi-currency is on, and every line's typed values plus its resolved field-path values) and hashes it with SHA-256 into `Document_Data_Fingerprint__c`.

Generation is skipped — reused — only when **all** hold: the quote is `Ready`, the stored fingerprint matches the freshly computed one, every active table's `Table_Code__c` exists under the quote, and every one of those tables has a Grand Total row. The last two exist because `Quote_Document_Table__c`'s OWD is Public Read/Write (§2.1) — a matching fingerprint cannot see that someone deleted a row out from under a `Ready` quote.

Reuse is not free: the check still does definition loading, path validation, the dynamic Quote Line query, canonicalization, and the digest itself. It only saves the expensive half — the delete, both inserts, and the stamp/`markQuote` write.

### Why generation is on-demand rather than automatic

CPQ writes a quote several times during one calculation. Generating on every save would rebuild three to five times per user action and discard most of it. Marking stale is cheap; generating is not.

The failure mode is also the right way round: if nobody ever regenerates, the quote stays `Stale` and the document action stays closed. **A blocked document beats a wrong one.**

### If you later want fully automatic generation

The pieces are in place. Add a platform event published by `QuoteDocumentStaleness`, subscribe with a trigger, and enqueue `new QuoteDocumentGenerateJob(quoteId)` — the one-argument constructor, which **skips unless stale**. That skip is the debounce: several events arrive per user action, the first regenerates and clears `Stale`, the rest exit after one SOQL. Do not build a timer-based debounce; this is cheaper and cannot get stuck.

Use a platform event rather than `System.enqueueJob` directly, because CPQ's calculation runs in its own async contexts where enqueueing hits chain-depth limits and throws.

### Verification — the five assertions

In `QuoteDocumentGenerator.verify()`, run before a table is marked Complete. A failure rolls back to the savepoint and records `Failed` on the Quote.

0. Every `Row_Key__c` within the table is unique. Added under `specs/quote-docusign-totals/phases/phase-4-test-matrix-reconciliation.md` — the field is `externalId` but not `unique` (it can't be; the same key text like `GRAND_TOTAL` is legitimately reused across different Quotes' tables), so nothing else stops two different group values that sanitize to the same key (`buildGroupKey` uppercases and strips to `[A-Z0-9_]`, so `"R&D"` and `"R D"` both become `"R_D"`) from silently colliding. Caught here instead.
1. Grand total equals the sum of included **detail** rows (tables showing details).
2. Grand total equals the sum of **level-1 subtotals**. Two independent paths to one number; disagreement means grouping dropped or duplicated a line.
3. The table's measures equal its grand total row.
4. For any `PRICE_WATERFALL` + `EXCLUDE_OPTIONAL` table, `Amount_Net__c` equals the Quote's `SBQQ__NetAmount__c`.

Assertion 4 is the one that stops a signed document carrying a wrong number, and it is checkable against live data today. **Never disable these to make a deployment pass.** A failing assertion means the numbers are wrong, which is the whole point.

**Assertions 1 and 2 generalize beyond Detail and Subtotal.** Any row type that is not itself an aggregation output (`AGGREGATE_ROW_TYPES` in `QuoteDocumentGenerator` — Group Header, Subtotal, Section Total, Grand Total) and has `Include_In_Grand_Total__c = true` is a **leaf contribution**, and is folded into both reconciliation paths automatically — that is what lets a `QuoteDocumentRowCustomizer` introduce a genuinely new counted row type (Discount, Rounding, or one you invent) without touching `verify()`. A leaf that belongs to no group (`Group_Level__c = 0`, the shape a Rounding row is required to have) feeds both paths directly, since there is no Subtotal row to carry it through the second path. A leaf nested inside a group (a Discount tied to one line, say) relies on the customizer having folded its value into that group's own Subtotal row, the same discipline `QuoteDocumentIndustryRowCustomizer` already follows when it rebuilds subtotals after re-bucketing.

**Assertion 4 additionally rejects any synthetic counted row outright**, before comparing amounts at all — a Discount, Rounding, or other customizer-added leaf on a `PRICE_WATERFALL` + `EXCLUDE_OPTIONAL` table fails generation immediately, because CPQ's `SBQQ__NetAmount__c` cannot possibly reflect money it never saw. Attach that kind of customizer to a different table instead — one that doesn't carry the Quote Net Amount reconciliation obligation.

### Declarative validation rules

Five, on `Quote_Document_Row__c`: `Aggregate_Excluded_From_Totals`, `Aggregate_Has_No_Quote_Line`, `Grand_Total_Level_Zero`, `Removal_Signs_Negative`, `Hidden_Row_Must_Count`. They catch what a single record can see. Anything involving siblings has to be Apex — a validation rule cannot compare a subtotal to its children.

---

## 5. Configuration — adding a slice without writing an algorithm

Table definitions live in **Custom Metadata**, not Apex:

- `Quote_Document_Table_Def__mdt` — one record per table
- `Quote_Document_Grouping__mdt` — one record per grouping dimension, with `Sequence__c`

**Why a child object rather than a comma-separated field:** Custom Metadata has no ordered list. Nesting order is meaning — `QUOTE_LINE_GROUP > PRODUCT_FAMILY` is a different document from `PRODUCT_FAMILY > QUOTE_LINE_GROUP`. A child record with a sequence carries that; a delimited string needs parsing code you would rather not own.

### 5.1 Nesting vs composite, and where a grouping value comes from

Grouping is a list of **levels**, outermost first. Each level is a list of **parts**. Two fields on the `Quote_Document_Grouping__mdt` record decide the shape:

| | `Level__c` | `Sequence__c` |
|---|---|---|
| Meaning | nesting depth | order of parts *within* a level |

- **Different `Level__c` → nesting.** `Phase 1 → Hardware → detail rows`, subtotals at both depths.
- **Same `Level__c` → composite.** One bucket labelled `Hardware / Recurring`, at a single depth.

Those are genuinely different documents from the same two dimensions. `GROUP_FAMILY_DETAIL` demonstrates nesting; `FAMILY_BILLING_COMPOSITE` demonstrates the composite.

Each part is **either** a named dimension **or** a field path — exactly one, never both:

| | Use when | Cost |
|---|---|---|
| `Dimension__c` | the value is *computed*, not read — `BUNDLE` and `TRANSACTION_TYPE` have no single field behind them | needs a `when` clause in Apex |
| `Field_Path__c` | the value is a plain field — `SBQQ__Product__r.Family`, `SBQQ__Group__r.SBQQ__BillingFrequency__c` | none, config only |

**Why dynamic paths are acceptable here when a dynamic measure map is not.** A wrong measure key is *silent* — it returns zero and a total is quietly wrong. A wrong grouping is *visible*: the row lands under an obviously wrong header, or the path fails validation. The compile-time-safety argument that drives the explicit measure properties does not transfer to grouping, so configuration wins.

Three guard rails, all of which fail generation rather than producing something misleading:

1. **Paths are schema-validated** in `QuoteDocumentGenerator.validateFieldPath` when the query is built, naming the bad segment: *"no field Nonexistent__c on Product2"*.
2. **The query runs `WITH USER_MODE`**, so a configured path cannot read a field the running user has no access to.
3. **`Max_Groups__c`** (default 50) caps the group count, checked as the tree is built rather than after. A composite multiplies its parts, so this is the one that stops a two-dimension composite emitting a 300-row table.

### 5.2 The trap: a field from the Quote yields exactly one group

**Every table is scoped to one quote.** So any field on the Quote — or on anything it looks up to, like `Account.Industry` or `Opportunity.Type` — has a single value across every line in that table. Grouping by it produces one group containing everything. Measured on the seeded data:

| Quote | Lines | Product Families | Account Industries |
|---|---|---|---|
| Q-00063 | 12 | 5 | **1** |
| Q-00067 | 9 | 4 | **1** |

It resolves correctly and the test `aFieldPathOnTheQuoteYieldsExactlyOneGroup` pins the behaviour — it simply cannot discriminate. The shipped `INDUSTRY` dimension has the same property, which is why no table leads with it.

Quote-level fields are still useful, just not as groupings: as a **filter**, as **table context**, or as part of a **composite label**. What actually discriminates within a quote: fields on the **line**, the **product**, the **quote line group**, and MDQ **segment** fields.

The six shipped definitions:

| Table Code | Grouping | Filter | Measures | Details |
|---|---|---|---|---|
| `PRODUCT_FAMILY_SUMMARY` | PRODUCT_FAMILY | EXCLUDE_OPTIONAL | waterfall | no (+ section totals) |
| `CHARGE_TYPE_SUMMARY` | CHARGE_TYPE | EXCLUDE_OPTIONAL | waterfall | no |
| `BUNDLE_DETAIL` | BUNDLE | EXCLUDE_OPTIONAL | waterfall | yes |
| `GROUP_FAMILY_DETAIL` | QUOTE_LINE_GROUP → PRODUCT_FAMILY | EXCLUDE_OPTIONAL | waterfall | yes |
| `OPTIONAL_PRODUCTS` | PRODUCT_FAMILY | OPTIONAL_ONLY | waterfall | yes |
| `TRANSACTION_SUMMARY` | TRANSACTION_TYPE | EXCLUDE_OPTIONAL | change | no |

### Dimensions (`QuoteDocumentLine.getGroupingValue`)

| Dimension | Source |
|---|---|
| `PRODUCT_FAMILY` | `Product2.Family` |
| `CHARGE_TYPE` | `SBQQ__ChargeType__c`, blank → `One-Time` |
| `QUOTE_LINE_GROUP` | `SBQQ__Group__r.Name` |
| `BUNDLE` | `SBQQ__RequiredBy__r.SBQQ__ProductName__c`, else own name, else `Standalone Products` |
| `TRANSACTION_TYPE` | the classified value |
| `INDUSTRY` | `SBQQ__Quote__c.AccountIndustry__c` |

### Filters (`QuoteDocumentLine.matchesFilter`)

`ALL` · `EXCLUDE_OPTIONAL` · `OPTIONAL_ONLY` · `RECURRING_ONLY` · `ONE_TIME_ONLY` · `BUNDLE_PARENTS_ONLY`

An unrecognised dimension or filter **throws**. It does not fall through to "include everything" — a silently over-inclusive total is worse than a failed generation.

### When to change the shape rather than the config

- **A switch passing ~15 cases** — extract a dimension interface with a registry. Not before; six `when` clauses are easier to read than six classes.
- **Definitions needing per-table logic** — if a new table needs its own Apex branch, config has stopped paying for itself. You now maintain a record *and* a code path.

---

## 6. Running it

### For one quote, from the UI

The **Generate Document Tables** quick action runs the `Generate_Quote_Document_Tables` screen flow, which calls the invocable and shows a confirmation. The action is deployed but **must be added to the Quote page layout by hand** — it is a managed-package layout and is not source-controlled here.

### For one quote, from anonymous Apex

```apex
Id quoteId = [SELECT Id FROM SBQQ__Quote__c WHERE Name = 'Q-00053' LIMIT 1].Id;
QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
```

### For old data — backfill

```bash
sf apex run --target-org gkCPQDev --file scripts/apex/quote-document-backfill.apex
```

It selects quotes with lines and no tables, then calls `generateAsync` — **one Queueable per quote**. Re-run until it reports zero remaining. A synchronous context can queue only 50 jobs, hence the cap.

**Use `generateAsync`, never `generate`, for bulk.** `generate(Set<Id>)` processes every quote in one transaction: a hundred quotes at a few hundred rows each blows the 10,000 DML row limit. `generateAsync` scales with the largest single quote instead.

Note `generateAsync` generates **unconditionally** — a backfill would do nothing if it skipped quotes that are merely `Not Generated`. The skip-unless-stale behaviour is in `new QuoteDocumentGenerateJob(quoteId)`, the one-argument constructor.

### For new data — the normal path

1. Rep edits the quote → trigger marks it `Stale` (via `@future`).
2. Rep presses **Generate Document Tables** → `Ready`.
3. DocuSign action, gated on `Ready`.

### Retention

```apex
System.schedule('Quote Document Retention', '0 0 2 * * ?', new QuoteDocumentRetention());
```

Deletes tables for quotes that are Rejected/Denied, or older than `retentionDays` (90) and not Accepted, and resets the Quote to `Not Generated`. **Accepted quotes are never purged automatically** — their numbers may sit behind a signed document, and that is not a scheduled job's judgement to make.

### Reviewing the output

- **Report:** *Quote Document - Rendered View* — every row in render order, grouped by quote and table. No column sums, deliberately: the rows already contain subtotals and grand totals.
- **Report:** *Quote Document - Totals by Family* — detail rows only, real sums, grand total equals the Quote Net Amount (£102,910 on Q-00053).
- **Sample data:** `scripts/apex/quote-document-sample.apex` builds a hand-written example on Q-00053, including cancellation and termination amounts that no quote in this org can produce.

---

## 7. Scale, limits, and known constraints

| Concern | Reality | What to do |
|---|---|---|
| Rows per quote | tables × (headers + details + subtotals). Measured on a 500-line quote against all **15** active definitions (`specs/quote-docusign-launch/spec.md` §6.4): 3,122 rows, 5 DML statements, 3,153 DML rows (31% of the 10k cap), 2,985 ms CPU (30% of the 10k limit), 2 SOQL queries, 539 SOQL rows. Comfortably inside every synchronous limit with real headroom — not the "plausibly already outside a comfortable envelope" the definition count alone suggested. | Still chunk per table well above 500 lines; re-measure before raising any synchronous threshold, since bundle/grouping complexity (not covered by this flat-line measurement) can push CPU and row count higher than line count alone predicts. |
| Bulk generation | `generate()` is one transaction for all quotes | Always `generateAsync` for more than one. |
| Queueable chaining | 50 jobs from a synchronous context | The backfill script caps at 50; re-run. |
| Future calls | 50 per transaction | `QuoteDocumentStaleness.canDefer()` checks before deferring, and falls back to inline. |
| Storage | Rows live until the quote is deleted | Schedule `QuoteDocumentRetention`. |
| Visibility | Table OWD is Public Read/Write, not inherited from the Quote | See §2.1 before assuming quote-level restrictions apply. |
| Definition count | Every definition is generated for every quote | Deactivate unused ones with `Is_Active__c`. |

### Field-level security will bite you

Three separate failures during development came from FLS, and the error messages are actively misleading:

- A missing field on an object gives **`Variable does not exist: tmpVar1`** from a SOQL bind — nothing to do with variables.
- A formula field with `editable=true` in a permission set is **rejected**; formula fields must be `readable` only.
- Master-detail and universally-required fields **cannot** appear in `fieldPermissions` at all.

**Every new field must be added to `CPQ_Document_Totals.permissionset-meta.xml`.** Also note the permission set schema wants all `<fieldPermissions>` in one block and all `<objectPermissions>` in another — interleaving them fails with "Element objectPermissions is duplicated".

### Multi-currency

`CurrencyIsoCode` is added by the platform only when multi-currency is enabled, and **Apex naming it statically will not compile in a single-currency org**. `gkCPQDev` is single-currency; scratch orgs get `MultiCurrency` from `config/project-scratch-def.json`. Hence:

```apex
if (UserInfo.isMultiCurrencyOrganization()) {
    target.put('CurrencyIsoCode', quote.get('CurrencyIsoCode'));
}
```

One codebase, deployable to both. Do not "tidy" this into a direct reference.

**This already covers customizer-added rows, including Discount/Rounding/Note, with no extra code.** `copyCurrency` runs once, in `QuoteDocumentGenerator.generateOne()`, over every row in the final per-table row list — and that list is captured *after* `applyRowCustomizer` runs, not before. Any row a `QuoteDocumentRowCustomizer` adds gets the same `CurrencyIsoCode` stamp as every row `QuoteDocumentRowBuilder` produced, in the same loop, with the same call. A customizer never needs to know whether the org is multi-currency or set the field itself.

### Deployment order

CMDT **types** and CMDT **records** must be deployed separately. Together they fail with `UNKNOWN_EXCEPTION`, which tells you nothing.

CMDT record files also need `xmlns:xsd="http://www.w3.org/2001/XMLSchema"` declared, or you get the same useless error.

### Other traps found the hard way

- **CPQ line totals are formula fields.** `SBQQ__NetTotal__c`, `ListTotal`, `RegularTotal`, `CustomerTotal`, `TotalDiscountAmount` are all read-only. Tests must set `SBQQ__ListPrice__c` / `SBQQ__NetPrice__c` / `SBQQ__Quantity__c` and let CPQ compute — then derive expectations from what CPQ actually produced rather than hardcoding.
- **A recurring line needs `SBQQ__BillingType__c`** or CPQ rejects the insert.
- **A non-updateable field carried into an `update` fails** with the unhelpful "fields being inaccessible on Sobject". This bit when `Quote__c` was a master-detail with reparenting off. It is a lookup now and updateable, but the generator still stamps fresh `Quote_Document_Table__c` records holding only Id and the measures — sending only what changed keeps the update independent of the relationship type.
- **`Group` is a reserved word** in Apex (the standard `Group` object). The grouping node class is `GroupNode`. So is `override`; the test hook is `useDefinitions`.
- **Custom report types are referenced with a `__c` suffix** — `Quote_Document_Tables_and_Rows__c` — and report column names use the full relationship path with `$` before the field: `SBQQ__Quote__c.DocumentTables__r.Rows__r$Amount_Net__c`. The Analytics REST API uses dots for the same thing; the Metadata API does not.
- **Report `<name>` maxes at 40 characters** and `<description>` at 255.
- **A Custom Metadata deploy only writes the fields present in the file.** Deleting a `<values>` block does *not* clear the value in the org — it leaves whatever was there. To blank a field you must deploy it explicitly as `<value xsi:nil="true"/>`.
- **Salesforce trims leading and trailing spaces from stored text values.** A `Composite_Separator__c` of `" / "` arrives as `"/"`, giving `Hardware/Recurring`. Leave it blank to get the code default with real spaces.

---

## 8. Data-quality caveats in this org

Do not read these as bugs.

1. **`INDUSTRY` is quote-level.** The only source is `SBQQ__Quote__c.AccountIndustry__c`, so grouping by Industry yields exactly one node per quote. The dimension works; it just cannot nest meaningfully until there is a line-level or product-level source.
2. **`SBQQ__ChargeType__c` is blank on 76 of 78 lines.** `CHARGE_TYPE_SUMMARY` renders almost entirely as one "One-Time" group. The table is correct; the catalogue is incomplete.
3. **No amendment quotes exist.** `TRANSACTION_SUMMARY` is all Net New, and the change-measure classification is unvalidated (see §3).

---

## 9. "I need to…" index

| Task | Do this |
|---|---|
| Add a new table | New `Quote_Document_Table_Def__mdt` record + one `Quote_Document_Grouping__mdt` per part. No Apex. |
| Reorder nesting | Swap `Level__c` on the grouping records. No Apex. |
| Turn nesting into a composite | Give both groupings the **same** `Level__c`. No Apex. |
| Group by any plain field | Set `Field_Path__c` (e.g. `SBQQ__Group__r.SBQQ__BillingFrequency__c`). No Apex. |
| Turn a table off | `Is_Active__c = false`. Existing tables clear on next generation. |
| Turn a **change-measure** table back on | Not a config change — validate `classify()` first. See §3. |
| Add a *computed* dimension | One `when` in `QuoteDocumentLine.getGroupingValue(String)`, then reference it as `Dimension__c`. Only needed when no field holds the value. |
| Add a filter | One `when` in `QuoteDocumentLine.matchesFilter`. |
| Add a measure | Two fields per object, two lines in `Measures.add`/`writeTo`, one entry in `measureFields()`, **and the permission set**. |
| Change what counts | `QuoteDocumentLine.countsIn`. Expect `grandTotalReconcilesToTheQuoteNetAmount` to fail if you get it wrong — that is the test doing its job. |
| Generate for one quote | Quick action, or `QuoteDocumentGenerator.generate`. |
| Backfill history | `scripts/apex/quote-document-backfill.apex`, repeatedly. |
| Show someone the output | The two reports in the **CPQ Document Totals** folder. |
| Debug a failed generation | `Document_Data_Error__c` on the Quote; `Status__c = 'Failed'` on the table; Setup → Apex Jobs for async runs. |
| Run the tests | `sf apex run test --class-names QuoteDocumentGeneratorTest --class-names QuoteDocumentLifecycleTest` |

---

## 10. Rules for whoever maintains this

1. **Never disable a `verify()` assertion to unblock a deployment.** It is telling you the numbers are wrong.
2. **Never make the stale write synchronous.** CPQ overwrites it. See §4.
3. **Never rename or delete a field a DocuSign template references.** After a template ships, these API names are an integration contract; additive changes only.
4. **Never treat a null measure as zero.** Null means the table uses the other measure family.
5. **Put new commercial logic in `QuoteDocumentLine`.** If a rule about what counts ends up in `QuoteDocumentRowBuilder` or the generator, the next person will not find it.
6. **Add every new field to the permission set**, in the right block, with `editable=false` for formulas.
7. **Validate the change measures against a real amendment** before reactivating any of the four CHANGE tables — `TRANSACTION_SUMMARY`, `PRODUCT_SUMMARY`, `BUNDLE_SUMMARY`, `BUNDLE_PRODUCT_GRID`. See §3.
8. **Staleness marking from a Quote Line trigger must stay deferred, and generator-owned Quote writes must stay wrapped in `suppress()`/`resume()`.** Both prevent a quote reading `Ready` over stale tables. See Invariants S1 and S2 in §4.

---

## Appendix — file map

```
force-app/main/default/
├── classes/
│   ├── QuoteDocumentTableDefinition.cls     what tables exist (from CMDT)
│   ├── QuoteDocumentLine.cls                commercial rules — read first
│   ├── QuoteDocumentRowBuilder.cls          grouping, totalling, row emission
│   ├── QuoteDocumentGenerator.cls           orchestration, persistence, verification
│   ├── QuoteDocumentGenerateJob.cls         one quote, one transaction
│   ├── QuoteDocumentStaleness.cls           stale marking (async — see §4)
│   ├── QuoteDocumentRetention.cls           scheduled purge
│   ├── QuoteDocumentGeneratorTest.cls       arithmetic and classification
│   └── QuoteDocumentLifecycleTest.cls       gate, staleness, async, CMDT, retention
├── triggers/
│   ├── QuoteDocumentQuoteLineTrigger.trigger
│   └── QuoteDocumentQuoteTrigger.trigger
├── objects/
│   ├── Quote_Document_Table__c/
│   ├── Quote_Document_Row__c/
│   ├── Quote_Document_Table_Def__mdt/
│   ├── Quote_Document_Grouping__mdt/
│   └── SBQQ__Quote__c/fields/               Document_Data_Status__c and friends
├── customMetadata/                          the six definitions + groupings
├── permissionsets/CPQ_Document_Totals.permissionset-meta.xml
├── reportTypes/Quote_Document_Tables_and_Rows.reportType-meta.xml
├── reports/CPQ_Document_Totals/
├── flows/Generate_Quote_Document_Tables.flow-meta.xml
└── quickActions/SBQQ__Quote__c.Generate_Document_Tables.quickAction-meta.xml

scripts/apex/
├── quote-document-sample.apex               hand-built example on Q-00053
└── quote-document-backfill.apex             historical quotes

specs/quote-docusign-totals/research/        the design conversation this came from
```
