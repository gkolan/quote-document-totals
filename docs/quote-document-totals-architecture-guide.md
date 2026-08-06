# Quote Document Totals — architecture guide for admins

**Who this is for:** a Salesforce admin who is new to this project. No coding background assumed. Every Salesforce term used here (object, field, record, flow, permission set, custom metadata, validation rule, report) is explained the first time it comes up, or is standard Salesforce vocabulary you already know from Setup.

**Single source of truth, self-contained.** You should not need to open any other document to understand what this feature is, how it works, how to configure it, and when you need to bring in a developer.

**Status:** Every object, field, class, and record named in this guide is deployed and active in the org `gkCPQDev` today. Where this guide shows real numbers, they came from actually running the feature in that org, not from a made-up example.

---

## 1. What this is, in one paragraph

When a Sales rep sends a Quote out for signature, the document needs to show totals — subtotals by product family, a grand total, maybe a breakdown of discounts. The Quote itself (the `SBQQ__Quote__c` record, part of the CPQ — Configure, Price, Quote — managed package) knows its own grand total, but a printed document usually needs *many* different totals: one table broken out by product family, another by bundle, another showing only optional products, another showing what changed on a renewal. **Quote Document Totals** is the part of this Salesforce org that builds all of those tables, as real Salesforce records, before the document is generated — so that when DocuSign builds the actual PDF, all it has to do is print records in order. It never has to do any arithmetic itself.

---

## 2. Why it exists (the problem it solves)

DocuSign (the e-signature tool this org uses to generate and send the Quote document — either the "Gen" or "CLM" product; confirm which one your org uses before configuring a template) is good at pulling field values onto a document and repeating a list of records in a table. It is **not** good at deciding things like:

- "Is this line's price already included inside its parent bundle's price, so it shouldn't be counted again?"
- "Should this optional product be included in the total, or not?"
- "What's the subtotal for just the Hardware family?"

If you tried to make DocuSign work these things out on the fly, you would eventually get a signed document with a wrong number on it — and a wrong number on a document a customer has signed is a serious problem, not a minor bug.

So instead, **all of that math happens in Salesforce first**, using Apex (Salesforce's programming language — think of it as "the code that runs behind buttons, automation, and calculations that a Flow or a formula field can't handle by itself"). The math produces plain Salesforce records that already contain the right numbers. DocuSign's only job is to print those records in the order it's told to.

---

## 3. The building blocks — a map before the details

Everything in this feature is one of these seven kinds of thing. If you remember this table, the rest of the guide is just filling in detail.

| Kind of thing | What it is, in Salesforce terms | Who normally touches it |
|---|---|---|
| **Custom Objects** | Two new tables of data live under each Quote: one for each printed table, one for each row in those tables. | Nobody edits these directly — they're built automatically. |
| **Custom Metadata Types** | Reusable "settings records" that define *what tables exist* and *how each one groups its data* — deployable configuration, not regular data. | Admins/developers, when adding or changing a table — no code needed for most changes. |
| **Apex Classes** | The actual code that reads the Quote's line items, works out the totals, and writes the two custom objects above. | Developers only. |
| **Apex Triggers** | Small pieces of code that watch for a Quote or Quote Line being changed, and flag the Quote's totals as out of date when that happens. | Developers only (you'll never need to touch these). |
| **Flow + Quick Action** | The button a rep actually clicks. | Admins can add the button to a page layout; a developer maintains the Flow itself. |
| **Permission Set** | Grants access to the two custom objects and their fields. | Admins — assign it to any user who needs to generate or view document tables. |
| **Validation Rules, Reports, Report Type** | Declarative safety checks and ways to view the data without opening individual records. | Admins can view/extend the reports; the validation rules are part of the deployed design and shouldn't be edited casually (see §9). |

---

## 4. The two custom objects — where the numbers actually live

```
SBQQ__Quote__c   (the Quote itself)
└── Quote_Document_Table__c        (one record per printed table — e.g. "Product Family Summary")
    └── Quote_Document_Row__c      (one record per printed row inside that table)
```

**`Quote_Document_Table__c`** — one record exists for every table that will appear on the document, for that Quote. Important fields:

| Field | Plain-English meaning |
|---|---|
| `Quote__c` | Which Quote this table belongs to. |
| `Table_Code__c` | A short code like `PRODUCT_FAMILY_SUMMARY` — the stable name the document template looks for. |
| `Display_Order__c` | What order the tables print in. |
| `Status__c` | `Generating`, `Complete`, or `Failed` — whether this table's numbers are trustworthy right now. |
| A set of Amount and Quantity fields | The grand total for this table (List price, Net price, Discount, etc.) — copied from that table's own Grand Total row (see below), so a template can print a total without having to add up every row itself. |

**`Quote_Document_Row__c`** — one record per printed row: a group heading, a detail line, a subtotal, or the grand total. Important fields:

| Field | Plain-English meaning |
|---|---|
| `Quote_Document_Table__c` | Which table this row belongs to. |
| `Row_Type__c` | What kind of row this is — see the table just below. |
| `Group_Level__c` | How far in from the left this row should be indented (0 = the very top, e.g. the grand total). |
| `Display_Order__c` | The exact print order — the document template always sorts by this field and nothing else. |
| `Display_Label__c` | The text to print in the left-hand column — a product name, a group name, or "Total". |
| Amount fields (`Amount_List__c`, `Amount_Net__c`, etc.) | The dollar figures for this one row. |
| `Include_In_Subtotal__c` / `Include_In_Grand_Total__c` | Whether this row's dollar amount is meant to be added into the totals above it, or whether it's just descriptive (a heading has nothing to add, so both are unchecked on a heading row). |

**Why two separate checkboxes instead of one?** For every table built from plain configuration, they're always set the same way, which can make the second one look pointless. It isn't: a Rounding adjustment (§7.4, only reachable through a plug-in) has to count toward the whole table's grand total but must **never** be folded into any one group's subtotal — there's no group it belongs to. That's only possible to express with two independent checkboxes. Don't collapse them into one, even though today's standard tables never need the difference.

### The nine kinds of row (`Row_Type__c`)

| Row Type | What it means | Where it comes from |
|---|---|---|
| **Group Header** | A heading row, e.g. "Hardware" | Built automatically whenever a table is set up to group its lines |
| **Detail** | One actual line from the Quote | Built automatically |
| **Subtotal** | The total for one heading's group of lines | Built automatically |
| **Section Total** | A total that cuts across the groups a different way — e.g. "Total Recurring" next to a family breakdown | Built automatically, only if that table is configured to show it |
| **Grand Total** | The one total for the whole table, always the last row | Built automatically, every table has exactly one |
| **Informational** | A row that's printed but never added into any total — e.g. an estimated tax line | Only added by a developer-written "plug-in" (see §11) |
| **Discount** | A row for a discount tied to one specific product line, and *is* added into the totals | Only added by a plug-in |
| **Rounding** | A whole-table adjustment that rounds the printed grand total to a cleaner figure, and *is* added into the totals | Only added by a plug-in |
| **Note** | Free text with no dollar amount at all, e.g. a disclaimer | Only added by a plug-in |

The last four only ever appear if a developer has written and attached a small plug-in class for that specific table — a plain configuration record can never produce them. §11 explains what that means in practice.

---

## 5. How it works, step by step — from a rep's click to a signed document

```
1. Rep edits a Quote Line (adds a product, changes a quantity, etc.)
        │
        ▼
2. Behind the scenes, the Quote gets flagged "Stale" —
   meaning "the printed tables no longer match what's on the Quote now."
   The rep doesn't see anything happen; this is silent bookkeeping.
        │
        ▼
3. Rep clicks the "Generate Document Tables" button on the Quote.
        │
        ▼
4. All of that Quote's existing table/row records are deleted
   and rebuilt from scratch, based on the Quote's current line items.
        │
        ▼
5. The rebuild checks its own math (see §8) before it's allowed to finish.
   If the numbers don't add up correctly, NOTHING is saved — the Quote's
   previous tables (if any) are left exactly as they were.
        │
        ▼
6. If everything checks out, the Quote's status becomes "Ready."
        │
        ▼
7. The DocuSign button is only usable when the Quote's status is "Ready."
   DocuSign then simply prints the rows in order — no calculations of its own.
```

**Why step 5 matters so much:** this is the single most important design decision in the whole feature. It would be easy to build a version of this that just writes whatever numbers it calculates and hopes they're right. Instead, every single generation run is required to prove its own arithmetic is internally consistent before anything is allowed to count as done. If it can't prove that, the whole thing is thrown away and the Quote is marked `Failed` instead — a document that refuses to generate is a much smaller problem than a signed document with a wrong number on it.

**Two things worth knowing, even though you'll never touch the Apex behind them:**

- **The "Stale" flag can't be set the instant a line changes — it has to happen in a small delayed step.** CPQ recalculates a Quote several times right after an edit, and if the flag were set immediately, CPQ's own recalculation would silently overwrite it a moment later, leaving the Quote reading "Ready" over tables that are actually out of date. This was found by watching it happen, not guessed at — treat it as a hard rule, not a style choice.
- **When the generator itself writes "Ready" back onto the Quote, it deliberately tells the system not to react to that write as if it were a real edit.** Without that, the generator's own save would immediately (and wrongly) re-flag the Quote it just finished as "Stale," and the *next* genuine edit after that would be silently ignored.
- **Step 4 doesn't always actually happen.** If nothing that could change the printed numbers has changed since the last successful build — not just the Quote and its lines, but anything the configuration reads from, like a Product's Family — clicking "Generate Document Tables" recognizes that and reuses the existing tables instead of tearing them down and rebuilding them. This is invisible to the rep; it just makes the button faster when there was nothing to do.

---

## 6. What a rep sees, and what each status means

| Quote status (`Document_Data_Status__c`) | What it means | What the rep should do |
|---|---|---|
| **Not Generated** | Tables have never been built for this Quote | Click "Generate Document Tables" before trying to send for signature |
| **Stale** | Something on the Quote changed since the tables were last built | Click "Generate Document Tables" again to refresh |
| **Ready** | The tables match the Quote's current lines and passed every check | Safe to generate the DocuSign document |
| **Failed** | The last attempt to build the tables found a problem and stopped | Do not proceed — see §12 (Troubleshooting) |

**The single rule to remember: never send a document from a Quote that isn't `Ready`.** `Stale` or `Failed` both mean "what's on screen may not match what's about to print."

---

## 7. Configuring it — the admin's job, no code required

Almost everything about *what tables exist* and *how they're grouped* is controlled by two Custom Metadata Types — reusable configuration records, deployed like any other metadata, but readable and editable through Setup like data.

### 7.1 `Quote_Document_Table_Def__mdt` — one record per table

This defines one printed table: what it's called, which lines it includes, and what family of dollar figures it shows.

| Field | What you set it to |
|---|---|
| `Table_Code__c` | A short, stable code the document template will reference — never change this once a template uses it |
| `Table_Name__c` | The human-readable name |
| `Line_Filter__c` | Which lines from the Quote this table starts from — e.g. `ALL`, `EXCLUDE_OPTIONAL` (skip optional products), `OPTIONAL_ONLY`, `RECURRING_ONLY`, `ONE_TIME_ONLY` |
| `Measure_Set__c` | `PRICE_WATERFALL` (List/Regular/Discount/Net/Customer/Quantity — what most tables show) or `CHANGE` (Net New/Cancellation/etc. — for renewal and amendment documents) |
| `Show_Details__c` | Whether individual line items are printed, or only the headings and subtotals |
| `Show_Section_Totals__c` | Whether to also show a secondary cut of totals, e.g. "Total Recurring" |
| `Display_Order__c` | Where this table sits relative to the others |
| `Is_Active__c` | Turn a table off without deleting it — existing generated tables of that type disappear on the next regeneration |
| `Row_Customizer_Code__c` | Leave blank for a normal table. Only filled in when a developer has registered a plug-in for this specific table (§11) |

### 7.2 `Quote_Document_Grouping__mdt` — one or more child records per table

This says how a table's lines are grouped into headings and subtotals. Each record is one "part" of the grouping.

| Field | What you set it to |
|---|---|
| `Table_Definition__c` | Which table this grouping belongs to (matches the `Table_Code__c` above) |
| `Dimension__c` | A built-in grouping the system already knows how to compute — `PRODUCT_FAMILY`, `CHARGE_TYPE`, `QUOTE_LINE_GROUP`, `BUNDLE`, `TRANSACTION_TYPE`, or `INDUSTRY` |
| `Field_Path__c` | *Instead of* `Dimension__c` — a plain field to group by directly, e.g. `SBQQ__Product__r.Family` or `SBQQ__Group__r.SBQQ__BillingFrequency__c` |
| `Level__c` | The nesting depth. Two grouping records with **different** `Level__c` values nest inside each other (e.g. Phase, then Hardware inside each Phase). Two records with the **same** `Level__c` combine into one single bucket instead (e.g. "Hardware / Recurring" as one heading, not two levels) |
| `Sequence__c` | Which order the parts of one level combine in, when there's more than one |

Set exactly one of `Dimension__c` or `Field_Path__c` on each record — never both, never neither.

### 7.3 Things you can do with zero Apex changes

| What you want to do | How |
|---|---|
| Add a brand new table | One new `Quote_Document_Table_Def__mdt` record, plus one `Quote_Document_Grouping__mdt` record for each grouping level/part |
| Change the order tables nest | Swap the `Level__c` values on the grouping records |
| Turn a nested breakdown into one combined bucket | Give the two grouping records the same `Level__c` |
| Group by a different plain field | Set `Field_Path__c` |
| Turn a table off | Set `Is_Active__c` to false |

### 7.4 Two guardrails worth knowing about

- **Every field a table can group by has to be one the running user is allowed to see.** If you configure a `Field_Path__c` to a field that doesn't exist, or one the current user's permissions don't allow, the generation fails immediately with a message naming exactly which field and table caused it — it will never fail silently or show a blank number.
- **A table can only produce so many groups before something has gone wrong.** There's a configurable ceiling (`Max_Groups__c`, defaulting to 50) — if a grouping choice would create far more groups than expected (a common mistake: combining two dimensions that multiply out to hundreds of buckets), generation stops with a clear explanation rather than quietly producing an enormous, unreadable table.

---

## 8. The safety checks — what "Complete" actually promises

Before any table is allowed to finish generating, five checks run automatically. If any one of them fails, that specific table (and, because everything for one Quote happens together, every table for that Quote) is rolled back to whatever existed before — nothing half-finished is ever left behind.

1. **No two rows in the same table can carry the same internal key.** This stops two different groups from accidentally colliding into one row.
2. **The grand total must equal the sum of the individual line rows.** (Only checked on tables that show individual lines.)
3. **The grand total must also equal the sum of the top-level subtotal rows** — a second, completely independent way of adding up to the same number. If these two ways of adding up disagree, something in the grouping went wrong.
4. **The table's own stored total must match its Grand Total row.** These are always meant to be identical.
5. **For the table that's meant to match CPQ's own Quote total exactly** (the standard "everything except optional products" table), the grand total must equal the number CPQ itself calculated on the Quote. This is the single most important check in the whole feature — it's the one that actually stops a signed document from carrying a wrong number, because it's checked against a number CPQ computed completely independently.

**Nobody should ever turn off one of these checks to "get a deployment to pass."** A failing check means the numbers really are wrong; disabling the check doesn't fix that, it just hides it until a customer notices.

**A related, quieter safeguard:** as noted in §5, a click on "Generate Document Tables" sometimes reuses the existing tables instead of rebuilding — but only when it can prove nothing changed, *and* the full set of expected tables and grand totals is actually still there. Because table and row records are broadly editable (anyone with the right permission set can see and change any Quote's generated totals, not just their own), it's possible for someone to delete a table record directly without touching the Quote at all. Reuse checks for exactly that before trusting what's already there, so a Quote can't end up "Ready" over a document that's silently missing a table.

---

## 9. Validation Rules — the checks that protect individual records

On top of the five checks in §8 (which compare *many* rows to each other, so they have to run in code), there are five plain Salesforce Validation Rules on `Quote_Document_Row__c` that catch mistakes a single record can be checked for on its own:

| Validation Rule | What it stops |
|---|---|
| `Aggregate_Excluded_From_Totals` | A heading, subtotal, section total, or grand total row from being wrongly marked as something that should be added into a total — those row types are the *result* of adding things up, not an input to it |
| `Aggregate_Has_No_Quote_Line` | Those same row types from being linked to one specific Quote Line — a total spans many lines, so pointing it at just one is always a mistake |
| `Grand_Total_Level_Zero` | A grand total row from being indented as if it belonged under some group heading |
| `Removal_Signs_Negative` | A cancellation, removal, or termination amount from being entered as a positive number, when it should always be zero or negative |
| `Hidden_Row_Must_Count` | A row from being created that's neither shown on the document nor counted in any total — a row like that serves no purpose |
| `Rounding_Row_Shape` | A Rounding-type row from being shaped incorrectly (must count toward the grand total only, not any subtotal, and must sit at the top level, not indented under a group) |

You'll never need to edit these unless you're deliberately changing how the feature behaves — treat them as part of the design, not a config option.

---

## 10. Reports — viewing the data without opening records

A dedicated Report Type, **Quote Document Tables and Rows**, lets you build reports across Quote → Table → Row without any code. Two general-purpose reports already exist, plus one per specific table view, all filed under the **CPQ Document Totals** report folder:

- **Quote Document - Rendered View** — every row, in print order, grouped by Quote and Table. Deliberately has no column totals, because the rows themselves already contain the subtotals and grand totals.
- **Quote Document - Totals by Family** — detail rows only, with real column sums, so you can check the grand total against the Quote's own net amount at a glance.
- One additional report per shipped table (Product Family Summary, Charge Type Summary, Bundle Detail, Group and Family Detail, Optional Products, Family and Billing Composite, Discount Summary, Bundle Totals, Product Totals, Transaction Type Totals), each filtered to that table's code.

If you add a new table (§7), the standard for this project is to add a matching report too, filtered to the new table's code, rather than expecting someone to build one from scratch.

---

## 11. When you need a developer — the plug-in point, explained simply

Sometimes a table needs something the plain configuration in §7 genuinely cannot express — a printed row that doesn't come from any one Quote Line at all (an estimated tax line, a loyalty discount, a rounding adjustment), or a grouping rule that depends on a number that doesn't exist yet at grouping time.

For those cases, a developer writes a small, separate piece of Apex code — think of it as **a plug-in**, in the same sense as a plug-in for any other piece of software: it slots into one specific, well-defined point in the process, does one focused job, and everything around it works exactly the same whether or not the plug-in is there.

**What you, as the admin, actually need to know:**

- A table either uses a plug-in or it doesn't — you can see this at a glance, because the `Row_Customizer_Code__c` field on that table's configuration record is either blank (no plug-in) or has a registered code in it.
- The plug-in runs *after* the normal grouping/subtotal/total-building described in §7–§8 has already happened, and *before* anything is saved. It's allowed to add, remove, or change rows.
- Whatever the plug-in does, the table still has to pass every check in §8 afterward — there is no special exception for plug-in-added rows. If a plug-in adds a row that should count toward the total, the developer has to make sure the totals still add up correctly, or generation fails with a clear error, exactly the same as any other mistake.
- **One specific rule worth knowing, because it will come up if your org ever asks for a Discount or Rounding table:** a plug-in-added row that counts toward the total is **never allowed** on the one table that's checked against CPQ's own Quote total (§8, check 5) — because CPQ has no way of knowing that extra row exists, so the two numbers could never honestly agree. If you're asked to configure a new Discount- or Rounding-style table, tell the developer building it that it needs its own table definition, separate from the standard "everything except optional products" one.

Four real, working examples of this plug-in mechanism are already deployed in this org, so a developer building a new one has something concrete to copy rather than starting from nothing — see `docs/quote-document-row-customizer-guide.md` for the full, developer-level detail. You don't need to read that document to use or configure this feature; it exists for whoever is asked to write a new plug-in.

---

## 12. Where Apex comes into play — a plain-English map of every piece of code

You will never need to write or edit any of this yourself, but knowing what each piece is for will help you have a useful conversation with a developer, or make sense of an error message.

| Apex Class | What it's for, in one sentence |
|---|---|
| `QuoteDocumentTableDefinition` | Reads the `Quote_Document_Table_Def__mdt` and `Quote_Document_Grouping__mdt` configuration records described in §7, and turns them into something the rest of the code can use. |
| `QuoteDocumentLine` | Looks at one Quote Line and works out everything about it that matters for a document — is it a bundled component, is it optional, what family is it in, does it count toward this particular table's total. All of the actual business rules about "what counts" live in exactly this one place. |
| `QuoteDocumentRowBuilder` | Takes the normalized lines and the grouping configuration, and produces the actual list of rows — headings, subtotals, details, grand total — in the exact order they should print. |
| `QuoteDocumentGenerator` | The conductor. This is what actually runs when a rep clicks the button: it reads the Quote, calls the other classes in order, saves the results, runs the five safety checks from §8, and either marks the Quote `Ready` or `Failed`. |
| `QuoteDocumentGenerateJob` | Handles generating tables for one Quote in the background — used for regenerating many historical Quotes at once without hitting Salesforce's per-transaction limits. |
| `QuoteDocumentStaleness` | The code behind the "Stale" status in §6 — watches for a Quote or Quote Line being edited and flags the Quote as out of date. |
| `QuoteDocumentRetention` | A scheduled cleanup job that deletes old generated tables for Quotes that were rejected, or are old and were never accepted — so this data doesn't build up forever. Quotes that were actually accepted are never automatically cleaned up. |
| `QuoteDocumentRowCustomizer` (and `QuoteDocumentRowCustomizerContext`) | The plug-in mechanism described in §11 — not a working example by itself, just the "socket" a developer's plug-in class plugs into. |
| `QuoteDocumentKeyValueMap` | A small, reusable lookup-table helper — for when a plug-in needs a simple "look up X, get Y" table (like mapping a product name to an industry name) without needing a brand-new Custom Metadata Type built just for it. |

**Apex Triggers** (`QuoteDocumentQuoteLineTrigger`, `QuoteDocumentQuoteTrigger`) simply watch for changes and call `QuoteDocumentStaleness` — they contain no logic of their own.

**The Flow** (`Generate_Quote_Document_Tables`) is what actually runs when the button is clicked. It is deliberately almost empty: it calls `QuoteDocumentGenerator`, then shows the success or failure message that Apex already worked out — the Flow itself makes no decisions and does no calculations. If you ever need to change what the confirmation screen looks like, that's a Flow edit an admin can make; if you need to change what gets generated, that's an Apex change only a developer can make.

---

## 13. The permission set

**`CPQ_Document_Totals`** grants access to both custom objects and every field on them. Assign it to:

- Any Sales rep who needs to click "Generate Document Tables" or view the generated tables.
- Any user who needs to run the reports in §10.

**One thing worth knowing:** the two custom objects are visible to anyone holding this permission set, for *any* Quote — visibility isn't automatically limited to Quotes that user could already see. This was a deliberate tradeoff (documented in `docs/quote-document-totals.md` §2.1) so that deleting a Quote automatically cleans up its generated tables. If your org has Quotes that must stay strictly private even from other users holding this permission set, talk to a developer before assigning it broadly.

---

## 14. Troubleshooting — what to do when something looks wrong

| Symptom | Likely cause | What to do |
|---|---|---|
| Quote status is stuck on `Failed` | The last generation attempt found a problem with the numbers, or a configuration mistake | Check the `Document_Data_Error__c` field on the Quote — it has a plain-English message naming exactly what went wrong. Do not attempt to send the document. |
| A table's `Status__c` is `Failed` but the Quote itself shows `Ready` | This shouldn't happen — the Quote can only be `Ready` if every one of its tables finished successfully | Treat this as a bug and involve a developer |
| Quote won't leave `Stale` even after clicking Generate | The click may not have actually run, or ran against different data than expected (a very rapid double-save) | Click Generate again; if it persists, check the Quote's Apex Jobs history in Setup for an error |
| A new table you configured doesn't appear | `Is_Active__c` may not be checked, or the table has no grouping records at all (a table needs at least one) | Check both on the `Quote_Document_Table_Def__mdt` record |
| A grouping produces a "too many groups" error | Two grouping dimensions were combined that multiply out to far more buckets than expected | Reduce to one dimension, or raise `Max_Groups__c` deliberately if the large number of groups is genuinely intended |
| A field path you configured fails with a message naming a field | A typo in `Field_Path__c`, or the field genuinely doesn't exist on that object | Fix the field path — the error names the exact bad segment |
| Numbers on the document don't match what you expected from the Quote | Check whether the table you're looking at was built with `EXCLUDE_OPTIONAL` — an optional product deliberately does not count in a normal table, even though it's still shown | This is very likely correct behavior, not a bug — compare against the **Quote Document - Totals by Family** report, which reconciles to the Quote's own net amount |

---

## 15. Glossary

| Term | Plain-English meaning |
|---|---|
| **Custom Object** | A brand-new kind of record, alongside Salesforce's built-in ones like Account or Opportunity. |
| **Custom Metadata Type** | A kind of record used for configuration rather than day-to-day data — deployable like code, but editable through Setup like a record. |
| **Apex** | Salesforce's programming language — the code behind buttons, automation, and calculations too complex for a Flow or a formula field. |
| **Apex Class** | One named unit of Apex code, roughly like one chapter of a manual, each responsible for one job. |
| **Apex Trigger** | Apex code that automatically runs when a record of a certain type is created, changed, or deleted. |
| **Flow** | Salesforce's point-and-click automation tool — used here just to run the button and show a confirmation message. |
| **Quick Action** | The actual button a user clicks on a record page. |
| **Permission Set** | A bundle of access grants (to objects, fields, etc.) that can be assigned to any user who needs it. |
| **Validation Rule** | A declarative (no-code) rule that stops a record from being saved if it doesn't meet a condition. |
| **Report Type** | A template that defines what objects and fields are available when building a report. |
| **Master-Detail vs. Lookup relationship** | Two ways one record can point to another. Master-Detail means the child is deleted automatically if the parent is, and inherits the parent's sharing. Lookup is more independent — this feature uses Lookup between Table and Quote (so deleting a Quote still cleans up its tables, without inheriting all of the Quote's own sharing rules) and Master-Detail between Row and Table. |
| **Picklist** | A field where the value must be chosen from a fixed list — `Row_Type__c` is one, and §4 lists every value it can hold. |
| **CPQ** | Configure, Price, Quote — the managed package (Salesforce Revenue Cloud / Salesforce CPQ) this whole feature is built on top of. Every field starting with `SBQQ__` belongs to that package, not to this project. |
| **DocuSign Gen / DocuSign CLM** | The e-signature and document-generation tool that actually turns these records into a PDF. Confirm which of the two your org uses before configuring a template — the setup steps differ. |
