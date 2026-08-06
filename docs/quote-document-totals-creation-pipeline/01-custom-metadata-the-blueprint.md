# How Quote Document Totals records get created — Part 1: Custom Metadata (the blueprint)

**Who this is for:** anyone — a business admin with no coding background, a junior Salesforce admin, or a junior developer — who has never touched this part of the org before. Nothing in this file assumes you already know Salesforce configuration terms. If a word feels unfamiliar, check the [glossary](00-glossary.md) — every file in this series links back to it.

**What this file covers:** the two Custom Metadata Types that describe *what* should be built. Think of this file as "the settings," the next file as "the worker who reads the settings and does the work," and the third file as "the button a person presses to ask the worker to start." This file does **not** cover what actually creates records — that's [02-apex-the-builder.md](02-apex-the-builder.md). Read this file first, because the code in file 2 reads these settings before it does anything else — nothing in file 2 makes sense without knowing what's described here.

> **In one sentence:** the two Custom Metadata Types described in this file are where someone writes down *which document tables should exist and how each one should be organized* — nothing on this page, by itself, ever creates a table or a row on an actual quote.

> **A quick correction before we start.** If you came here expecting "3 independent ways to create these records — Flow, or Apex, or Custom Metadata, pick one" — that's not how this project actually works, and this series is written to correct that instead of repeating it. There is exactly **one** creation pipeline. Custom Metadata is the recipe card. Apex is the cook who reads the recipe card and does the actual work. Flow is the doorbell a person presses to tell the cook to start. You cannot get a finished meal by ringing the doorbell with no cook in the kitchen, and you cannot get a finished meal by writing a recipe card and never cooking it. All three files in this folder describe **the same one pipeline**, each from a different angle.

---

## 1. What "Custom Metadata" even means, in plain terms

In Salesforce, most of the records you're used to working with — a Quote, an Account, an Opportunity — are **data** that reflects the real world of your business. A salesperson creates a new Quote every time they quote a new deal; that's genuinely new information, and it keeps growing every day. People create this kind of record by clicking "New," filling in fields, and saving, the same way you'd fill out a paper form.

A **Custom Metadata Type** holds something fundamentally different: **configuration**, not business data. It looks identical on the surface — it's still "a list of records, each with fields you fill in" — but the records don't represent real-world events like a sale happening. They represent a *decision someone made about how the system should behave*, made once, and then left alone. These records are set up as part of building or changing the system (the technical term is "deployed," the same word used when a developer ships a code change — see the [glossary](00-glossary.md) if that's unfamiliar), not typed in day-to-day by your sales team. A salesperson browsing their quotes will never see these records, never needs to know they exist, and never edits them.

A close everyday comparison: think of the settings menu on a phone versus the photos in your camera roll. Your photos are data — a new one appears every time you take a picture, and the total keeps growing forever. Your settings (screen brightness, Wi-Fi password, whether notifications are silenced) are metadata — you set each one up once, rarely touch it again, and the phone quietly checks those settings every single time it needs to decide how to behave, without you noticing it happening.

This project has **exactly two** Custom Metadata Types, and together they are the entire "recipe" for what a document table should look like. Nothing else in the system decides what a table contains — if you want to change what a document prints, these two places are where that decision actually lives:

| Custom Metadata Type | What it describes |
|---|---|
| `Quote_Document_Table_Def__mdt` | One record per **table** you want to appear in a document — its name, which quote lines it starts from, and what kind of dollar columns it shows. |
| `Quote_Document_Grouping__mdt` | One record per **grouping instruction** — how the lines inside a table get bucketed into headings and subtotals. Several of these records belong to one table definition. |

Neither of these two Custom Metadata Types can, by itself, put a single record into `Quote_Document_Table__c` or `Quote_Document_Row__c` (the two objects that actually hold the generated numbers a document prints). **Custom Metadata only describes intent.** Something else — Apex, covered in the next file — has to read that intent and act on it.

---

## 2. `Quote_Document_Table_Def__mdt` — one record per table

Every table that can ever appear on a document (an "Optional Products" table, a "Bundle Detail" table, a "Discount Summary" table, and so on) starts life as exactly one record of this type. Here is every field on it, in plain language, with a realistic example value.

> **A precision note before the table below, because getting this wrong causes real confusion.** A few of these fields (`Line_Filter__c`, `Measure_Set__c`, `Amount_Basis__c`, `Sort_Groups_By__c`) are **plain text fields**, not true Salesforce **picklists** (see the [glossary](00-glossary.md) if that distinction is new to you). That means Salesforce itself will *not* stop you from typing something misspelled or made up into one of them — there is no dropdown physically preventing a typo. The list of genuinely valid values for each one is enforced by Apex instead, at the moment a quote is regenerated, and an invalid value produces a clear error message at that point rather than being blocked at save time. In practice: **type these values exactly as shown, in capital letters, with no extra spaces**, and don't assume a typo will be caught the instant you save the metadata record — it will only be caught the next time someone clicks "Generate."

| Field API Name | Field Type | What it means in plain English | Example value |
|---|---|---|---|
| `Table_Code__c` | Text | A short, unique, all-caps code used purely as an internal identifier — everything else in the system (the generated `Quote_Document_Table__c` record, reports, templates) uses this code, not the human-readable name, to identify this table. Pick this once and don't change it later — other configuration and templates will come to depend on it staying the same. | `DISCOUNT_SUMMARY` |
| `Table_Name__c` | Text | The human-readable name a person would actually recognize. This is what shows up in the generated table's `Name` field, combined with the quote number, e.g. "Q-00123 - Discount Summary". | `Discount Summary` |
| `Is_Active__c` | Checkbox | Whether this table should be built at all, the next time a quote is regenerated. This is the on/off switch for a whole table. Unchecking it is how you turn a table off without deleting anything — the next time someone regenerates a quote, that table's old records simply disappear (because every regeneration starts by clearing out the old tables — see file 2) and no new one takes its place. | `true` |
| `Line_Filter__c` | Text, with a fixed set of valid values enforced by Apex (not a true picklist) | Which quote lines this table is allowed to include, decided *before* any grouping or totaling happens — a line that doesn't pass this filter is treated as if it doesn't exist for this one table, even though it's still a completely normal line on the quote itself. See the full list of valid values below. | `EXCLUDE_OPTIONAL` |
| `Measure_Set__c` | Text, with a fixed set of valid values enforced by Apex (not a true picklist) | Which family of dollar columns get filled in on this table's rows. Either `PRICE_WATERFALL` (five columns: List, Regular, Discount, Net, Customer — the usual "here's how we arrived at this price, step by step" columns most tables use) or `CHANGE` (seven columns: Net New, Cancellation, Replacement Removed, Replacement Added, Termination, Net Change, Final — used specifically for a renewal or amendment document, where the point of the table is to show what changed compared to before, not just what the price is now). | `PRICE_WATERFALL` |
| `Amount_Basis__c` | Text | A free-text label describing which quote-line pricing basis these dollar figures are calculated from. Mainly informational — it's copied straight through onto the generated table and isn't itself checked against a fixed list of values. | `Final Value` |
| `Show_Details__c` | Checkbox | Whether individual quote lines are printed one by one as their own rows, or whether the document only shows the group headings and subtotals with no line-by-line detail (useful for a short "at a glance" summary table where the reader doesn't need to see every single item). | `true` |
| `Show_Section_Totals__c` | Checkbox | Whether to add a *second, different* cut of totals on top of the normal grouping — for example, showing "Total Recurring Charges" and "Total One-Time Charges" as extra rows, even though the table is otherwise organized by product family rather than by recurring-vs-one-time. | `false` |
| `Display_Order__c` | Number | Where this table sits relative to the other tables generated for the same quote, when there's more than one table on a document. Lower numbers print first — think of it like page-ordering a stack of printouts. | `10` |
| `Composite_Separator__c` | Text | Only relevant if two grouping records share the same `Level__c` value (fully explained below) — the exact text used to join their two values into one combined label, for example the `" / "` between "Hardware" and "Recurring" in "Hardware / Recurring". If you leave this blank, the system quietly falls back to `" / "` on its own — you never have to set it unless you want something different, like a comma or a dash instead. | `/` |
| `Max_Groups__c` | Number | A safety limit on how many distinct buckets your grouping settings are allowed to produce for one table. If your actual settings would create more buckets than this number allows, generation deliberately stops and shows a clear error, rather than silently building an enormous, unreadable table with hundreds of tiny headings. If you leave this blank, the system automatically uses a built-in safety limit of 50 — you don't have to set this field at all unless you specifically expect more than 50 buckets and want to raise the limit on purpose. | `50` |
| `Sort_Groups_By__c` | Text, with a fixed set of valid values enforced by Apex (not a true picklist) | Controls the order the buckets print in. `ALPHABETICAL` (the default if you leave this blank) sorts buckets by their own label, A to Z. `LINE_SEQUENCE` instead sorts buckets by whichever quote line inside that bucket was added to the quote earliest, so the very first bundle or product a salesperson added prints first, regardless of what it's named. | `ALPHABETICAL` |
| `Row_Customizer_Code__c` | Text | An advanced, developer-only setting. A tiny number of tables need a row that a plain grouping configuration genuinely cannot produce on its own — for example, a rounding adjustment line, or an estimated tax line that isn't tied to any single quote line. For those specific cases, a developer writes a small piece of custom Apex logic and gives it a short code name; putting that exact code name here tells the system to run that extra logic for this table. As a business admin, you should never need to fill this in yourself — leave it blank unless a developer has explicitly told you a specific code to enter. | *(blank for most tables)* |

### A worked example

Say you want a new table called "Recurring Charges Only" that shows just the recurring lines on a quote, with the usual List/Regular/Discount/Net/Customer columns, printing third in the document. You would create one `Quote_Document_Table_Def__mdt` record like this:

```xml
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" label="Recurring Charges Only">
    <protected>false</protected>
    <values><field>Table_Code__c</field><value xsi:type="xsd:string">RECURRING_ONLY</value></values>
    <values><field>Table_Name__c</field><value xsi:type="xsd:string">Recurring Charges Only</value></values>
    <values><field>Is_Active__c</field><value xsi:type="xsd:boolean">true</value></values>
    <values><field>Line_Filter__c</field><value xsi:type="xsd:string">RECURRING_ONLY</value></values>
    <values><field>Measure_Set__c</field><value xsi:type="xsd:string">PRICE_WATERFALL</value></values>
    <values><field>Amount_Basis__c</field><value xsi:type="xsd:string">Final Value</value></values>
    <values><field>Show_Details__c</field><value xsi:type="xsd:boolean">true</value></values>
    <values><field>Show_Section_Totals__c</field><value xsi:type="xsd:boolean">false</value></values>
    <values><field>Display_Order__c</field><value xsi:type="xsd:double">30</value></values>
</CustomMetadata>
```

That record, on its own, does **nothing visible yet**. No `Quote_Document_Table__c` record appears anywhere just because you deployed this. Keep reading.

### The valid `Line_Filter__c` values

| Value | Which quote lines it keeps |
|---|---|
| `ALL` | Every line on the quote. |
| `EXCLUDE_OPTIONAL` | Everything except optional products. This is the filter used for the one table that has to match the Quote's own official total exactly. |
| `OPTIONAL_ONLY` | Only optional products. |
| `RECURRING_ONLY` | Only recurring (subscription-style) charges. |
| `ONE_TIME_ONLY` | Only one-time charges. |
| `BUNDLE_PARENTS_ONLY` | Only the "parent" line of each bundle, not its components. |

---

## 3. `Quote_Document_Grouping__mdt` — one or more records per table

A table definition on its own doesn't say *how* to organize the lines it keeps — it only says which lines are eligible and what kind of numbers to show. Deciding how to sort those lines into headings, sub-groups, and subtotals is this second Custom Metadata Type's entire job. Every `Quote_Document_Grouping__mdt` record belongs to exactly one `Quote_Document_Table_Def__mdt` record (they're linked by matching the table code, explained in the first row below), and each individual grouping record describes **one single grouping instruction** — never a whole table's worth of organization by itself. A table usually needs more than one of these records working together — for example, "group by Product Family, and then, inside each family, group again by Charge Type" is accomplished with **two** separate grouping records, not one.

| Field API Name | Field Type | What it means in plain English | Example value |
|---|---|---|---|
| `Table_Definition__c` | Text | Which table this one grouping instruction belongs to. The value here must exactly match a `Table_Code__c` value from a `Quote_Document_Table_Def__mdt` record in the previous section — that matching text is the only thing linking a grouping instruction back to its table. A typo here (extra space, wrong capitalization) means this grouping instruction silently belongs to no table at all, rather than producing a visible error, so double-check it matches exactly. | `RECURRING_ONLY` |
| `Dimension__c` | Text, with a fixed set of valid values enforced by Apex (not a true picklist) | Use this field when you want to group by one of six groupings the system already knows how to work out on its own, with no need to point at a specific field. You must set **either** this field **or** `Field_Path__c` below on any one grouping record — never both at once, and never leave both blank. The six valid options are: `PRODUCT_FAMILY`, `CHARGE_TYPE`, `QUOTE_LINE_GROUP`, `BUNDLE`, `TRANSACTION_TYPE`, `INDUSTRY`. Two of these — `BUNDLE` and `TRANSACTION_TYPE` — genuinely have no single field on the quote line that holds that value directly; the system works them out through its own logic, which is exactly why they can only be reached through this field and never through `Field_Path__c`. | `PRODUCT_FAMILY` |
| `Field_Path__c` | Text | Use this field, instead of `Dimension__c`, when the grouping you want is a specific field that already exists on the quote line (or on something the quote line is related to), and isn't one of the six built-in options above. Write it exactly the way you'd type a field into a Salesforce report's "group by" box: a straightforward field like `SBQQ__ProductName__c`, or — to reach across to a related record's field — a dotted path like `SBQQ__Product__r.Family` (the product's own Family field) or `SBQQ__Group__r.SBQQ__BillingFrequency__c` (the billing frequency of the quote line group this line belongs to). This is the escape hatch that lets a business admin add a brand-new kind of grouping without needing a developer to write any code — as long as the field you want already exists somewhere reachable from the quote line. | `SBQQ__Group__r.SBQQ__BillingFrequency__c` |
| `Level__c` | Number | **This is the field that controls how many levels of nesting your table has, and it's very likely the exact field you're thinking of when you say "we used to group by 5 levels."** It's explained in full, with a worked example, in its own section immediately below — read that section before creating any grouping records, since getting this field wrong is the single easiest way to accidentally combine two groupings into one bucket when you meant to nest them, or vice versa. | `1` |
| `Sequence__c` | Number | Only matters when two or more grouping records share the exact same `Level__c` value (which, as explained below, means they combine into one single bucket rather than nesting). In that specific case, `Sequence__c` decides which of those combined values is written first in the combined label — lower numbers come first. If every grouping record on a table has its own distinct `Level__c`, this field has no visible effect at all. | `1` |

### `Level__c` — this is your "how many levels" answer

This is very likely the field you're thinking of when you say "we used to be able to group by 5 levels." Here is exactly how it works, because it is easy to get backwards:

- **Two grouping records with *different* `Level__c` numbers → nesting.** Level 1 is the outermost bucket; Level 2 sits inside every Level 1 bucket; Level 3 sits inside every Level 2 bucket, and so on. There is **no maximum number of levels written anywhere in the code or on the field** — `Level__c` is a plain Number field with no upper limit set on it. You can absolutely have five levels (or more) today, in this exact version of the framework, by creating five grouping records with `Level__c` values `1`, `2`, `3`, `4`, `5`. Nothing needs to change in Apex, the object, or the field for that to work.
- **Two grouping records with the *same* `Level__c` number → a composite, not nesting.** They combine into a single bucket whose label joins both values together (using `Composite_Separator__c` from the table definition) — for example, one heading that reads "Hardware / Recurring" instead of a Hardware heading with a Recurring heading inside it. `Sequence__c` decides the order the parts are joined in.

### A worked 5-level example

Say you want a table that groups, from outermost to innermost: Industry, then Product Family, then Charge Type, then Billing Frequency, then Bundle. That is five *nested* levels, so you'd create five grouping records, each on its own `Level__c`, all belonging to the same table:

| `Table_Definition__c` | `Dimension__c` | `Field_Path__c` | `Level__c` | `Sequence__c` |
|---|---|---|---|---|
| `FIVE_LEVEL_EXAMPLE` | `INDUSTRY` | *(blank)* | `1` | `1` |
| `FIVE_LEVEL_EXAMPLE` | `PRODUCT_FAMILY` | *(blank)* | `2` | `1` |
| `FIVE_LEVEL_EXAMPLE` | `CHARGE_TYPE` | *(blank)* | `3` | `1` |
| `FIVE_LEVEL_EXAMPLE` | *(blank)* | `SBQQ__Group__r.SBQQ__BillingFrequency__c` | `4` | `1` |
| `FIVE_LEVEL_EXAMPLE` | `BUNDLE` | *(blank)* | `5` | `1` |

Deploy those five records alongside a `Quote_Document_Table_Def__mdt` record with `Table_Code__c = FIVE_LEVEL_EXAMPLE`, and you have a genuine 5-level nested table — no code change required. (One real-world caution, explained fully in [`docs/quote-document-totals-architecture-guide.md`](../quote-document-totals-architecture-guide.md) §12: `INDUSTRY` is a quote-level field, meaning every line on the quote has the *same* value for it, so it only ever makes sense as the outermost level. Putting it anywhere else in the nesting order won't error, but it won't split anything into meaningful sub-groups either.)

One raw XML example of a single grouping record, so you can see the exact shape:

```xml
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" label="FIVE_LEVEL_EXAMPLE - Level 2 Product Family">
    <protected>false</protected>
    <values><field>Table_Definition__c</field><value xsi:type="xsd:string">FIVE_LEVEL_EXAMPLE</value></values>
    <values><field>Dimension__c</field><value xsi:type="xsd:string">PRODUCT_FAMILY</value></values>
    <values><field>Level__c</field><value xsi:type="xsd:double">2</value></values>
    <values><field>Sequence__c</field><value xsi:type="xsd:double">1</value></values>
</CustomMetadata>
```

---

## 4. What Custom Metadata does **not** do

To be completely unambiguous, because this is the single most common source of confusion for a junior admin looking at this framework for the first time:

- Creating, editing, or deploying `Quote_Document_Table_Def__mdt` and `Quote_Document_Grouping__mdt` records **never** creates a single `Quote_Document_Table__c` or `Quote_Document_Row__c` record.
- These metadata records only take effect the **next time Apex runs the generation logic** for a given quote (covered in [02-apex-the-builder.md](02-apex-the-builder.md)).
- If a table's numbers look wrong or a table is entirely missing, the very first thing to check is not "did the metadata save correctly" in isolation — it's "has this quote actually been regenerated since the metadata changed." A stale, already-`Ready` quote will keep showing its old numbers until someone (or the Flow covered in [03-flow-the-trigger.md](03-flow-the-trigger.md)) triggers a fresh generation.

**Where these records actually live and how they're organized:** [`docs/quote-document-totals.md`](../quote-document-totals.md) §4 and §5 cover the same two Custom Metadata Types for a developer audience, including edge cases like `INDUSTRY` grouping and reordering nesting without Apex changes.

**Next:** [02-apex-the-builder.md](02-apex-the-builder.md) — how these settings actually turn into saved records.
