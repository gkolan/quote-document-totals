# How Quote Document Totals records get created — Part 2: Apex (the builder)

**Who this is for:** anyone — a business admin with no coding background, a junior Salesforce admin, or a junior developer. You don't need to write or read Apex code to follow this file — you just need to understand what it does, step by step, in plain English, so you can recognize what's happening when a quote gets regenerated and know where to look if something goes wrong. If a term feels unfamiliar, check the [shared glossary](00-glossary.md).

**Read [01-custom-metadata-the-blueprint.md](01-custom-metadata-the-blueprint.md) first.** Everything in this file assumes the Custom Metadata records described there already exist. This file is about the code that reads those settings and actually saves records.

> **In one sentence:** Apex is the part of the system that actually reads the settings from file 1, does the real work of building and saving the table and row records, and runs five safety checks to make sure the numbers are right before letting anyone treat the quote as ready.

> **A count correction, up front.** This project does not have "3 Apex classes that each independently create these records." It has **one pipeline** made of several Apex classes that each do one job, handing off to the next. There is exactly **one** starting point a person or a Flow ever calls: `QuoteDocumentGenerator`. Everything else listed below is a helper that `QuoteDocumentGenerator` calls internally — you would never call them directly, and a junior admin never needs to open them to use this framework day to day.

---

## 1. What "Apex" means, in plain terms

Apex is Salesforce's own programming language. Unlike a Flow (covered in the next file), which an admin builds by dragging boxes and arrows on a screen, Apex is written as text by a developer and then deployed into the org, the same way the Custom Metadata records from file 1 were deployed. Once it's deployed, Apex can do anything a Flow can do, plus things a Flow cannot — like the recursive "keep grouping inside of groups inside of groups, however many levels there are" logic this framework needs.

You do not need to read or understand Apex syntax to use this framework as an admin. This file explains **what the code does**, in the order it does it, using plain English and real field names, not a walkthrough of the code itself.

---

## 2. The one entry point: `QuoteDocumentGenerator`

Every single time these records get created — whether triggered by a person clicking a button, by an automated background job, or (in a future phase, not yet built — see §9 of [`docs/quote-document-totals.md`](../quote-document-totals.md)) by an automatic system event — it goes through this one Apex class. Think of `QuoteDocumentGenerator` as the head chef: it doesn't chop every vegetable itself, but it directs every other class involved and is the only one anyone outside the kitchen ever talks to.

Here are the helper classes it calls, and the one job each one has:

| Apex Class | Its one job |
|---|---|
| `QuoteDocumentTableDefinition` | Reads the two Custom Metadata Types from file 1 and turns them into something the rest of the code can use — this is the class that actually queries `Quote_Document_Table_Def__mdt` and `Quote_Document_Grouping__mdt`. |
| `QuoteDocumentLine` | Looks at one quote line at a time and works out facts about it: is it optional, is it a bundle component, what family is it in, what dollar amounts does it carry. |
| `QuoteDocumentRowBuilder` | Takes the normalized lines from `QuoteDocumentLine` and the grouping instructions from `QuoteDocumentTableDefinition`, and produces the actual list of rows — headings, subtotals, detail lines, grand total — in the order a document should print them. (This class is covered in much more depth in the second folder of this series, [`../quote-document-totals-row-by-row/`](../quote-document-totals-row-by-row/02-apex-builds-each-row.md), since it's the piece that decides exactly how each individual row is shaped.) |
| `QuoteDocumentGenerateJob` | A background version of the same work, used when regenerating many quotes at once (a bulk backfill) rather than one quote from a button click. |
| `QuoteDocumentFingerprint` | Works out whether anything has actually changed since the last time this quote was generated, so a quote that's already correct doesn't get needlessly rebuilt. |
| `QuoteDocumentStaleness` | Watches for a quote or a quote line being edited, and marks the quote's readiness status as out of date when that happens (covered briefly at the end of this file, in full in `docs/quote-document-totals.md` §6). |

---

## 3. Step by step: what happens when generation runs, using a real example

Let's follow one concrete example all the way through. Say we have Quote **Q-00123**, and it has three quote lines:

| Line | Product | Quantity | List Price (each) | Net Price (each) | Optional? |
|---|---|---|---|---|---|
| 1 | Laptop | 2 | $1,000 | $900 | No |
| 2 | Extended Warranty | 2 | $150 | $150 | Yes |
| 3 | Docking Station | 1 | $80 | $72 | No |

Someone clicks the button that starts generation (that button is the Flow from file 3). Here, in order, is what `QuoteDocumentGenerator` does:

### Step 1 — Read the quote and its lines

It runs one query (see the [glossary](00-glossary.md) if "query" is a new term — it just means "a request asking Salesforce for a specific set of records") that pulls the quote itself (its name, its own official net total, its account's industry, its current readiness status) along with every one of its quote lines, in quote-line order.

It also temporarily locks the quote record for the rest of this one save — meaning: if a second person clicks the same "Generate" button on the very same quote at almost the exact same instant, Salesforce makes that second click wait until the first one has completely finished, rather than letting the two run at the same time and risk stepping on each other's work. Without this, two nearly-simultaneous clicks could each read the same starting information, then both try to save changes based on that same starting point — and whichever one finished second would silently overwrite the first one's work in a confusing way. The lock simply makes the two happen one after another instead, in the order they were clicked.

### Step 2 — Work out what's actually changed (the "fingerprint" check)

Before doing any real work, it calculates a short fingerprint — a kind of digital summary — of the quote's current lines and the current Custom Metadata settings. If that fingerprint matches the one already stored from the last successful generation, **and** the quote is currently `Ready`, **and** every expected table still exists with a Grand Total row, it stops here and does nothing further. This is a safety-and-performance step: it means clicking "Generate" twice in a row on an unchanged quote doesn't do unnecessary work.

For our example, assume nothing has been generated yet, so this check finds no match and generation continues.

### Step 3 — Delete the old tables (if any)

Any existing `Quote_Document_Table__c` records for Q-00123 — left over from a previous generation — are deleted. Their `Quote_Document_Row__c` child records are deleted automatically along with them, with no separate step needed, because of how the relationship between the two objects is built (a **master-detail relationship** — see the [glossary](00-glossary.md) — deleting the "master" record always automatically deletes every "detail" record that belongs to it, so it's not possible to accidentally end up with rows left behind pointing at a table that no longer exists).

This is a full rebuild every single time, not a small patch to the existing records — the framework's deliberate rule is that every generation throws away everything from the last run and builds it all fresh, rather than trying to figure out which specific old rows changed and update just those. This is simpler to reason about and guarantees a table can never end up as a strange mix of some old rows and some new ones.

### Step 4 — Build one table + its rows, for every active table definition

For **each** `Quote_Document_Table_Def__mdt` record that is `Is_Active__c = true` (from file 1), the code:

1. Filters the three lines above down to whichever ones match that table's `Line_Filter__c`.
2. Creates one new (not-yet-saved) `Quote_Document_Table__c` record, filling in `Table_Code__c`, `Table_Key__c` (built as `<the Quote's Id>:<the table code>`), `Display_Order__c`, `Amount_Basis__c`, `Line_Filter__c`, and `Measure_Set__c` straight from the table definition, plus `Status__c = Generating` as a temporary placeholder.
3. Hands the filtered lines to `QuoteDocumentRowBuilder`, which produces the full set of (not-yet-saved) `Quote_Document_Row__c` records for that table — this is the part covered in depth in [the row-by-row folder](../quote-document-totals-row-by-row/02-apex-builds-each-row.md).

Say our example table definition is `Table_Code__c = EXCLUDE_OPTIONAL_SUMMARY`, `Line_Filter__c = EXCLUDE_OPTIONAL`, grouped by nothing (one flat list). Line 2 (the Extended Warranty, which is optional) is filtered out, leaving Lines 1 and 3.

### Step 5 — Save the tables

All of the new `Quote_Document_Table__c` records for every active table definition are inserted **in a single save** (not one at a time). Saving them together, rather than one by one, is what lets the whole operation be rolled back cleanly as a single unit if anything later goes wrong.

### Step 6 — Attach and save the rows

Now that the tables have real Salesforce IDs, every row built in Step 4 gets its `Quote_Document_Table__c` lookup field pointed at the correct saved table, and every row across every table is inserted together, again as one single save.

For our example table, the rows would come out looking like this (the row-by-row folder explains exactly how these values are calculated):

| `Row_Type__c` | `Display_Label__c` | `Display_Order__c` | `Amount_List__c` | `Amount_Net__c` |
|---|---|---|---|---|
| Detail | Laptop | 10 | $2,000 | $1,800 |
| Detail | Docking Station | 20 | $80 | $72 |
| Grand Total | Total | 30 | $2,080 | $1,872 |

### Step 7 — Stamp the totals back onto the table, and double-check the math

Each `Quote_Document_Table__c` record gets its own `Amount_*` fields filled in by copying them straight from that table's Grand Total row (so a document template, or a report, can print a table's overall total without having to add up every row itself), plus `Row_Count__c` (a simple count of how many rows the table ended up with) and `Generated_On__c` (a timestamp).

Then, before anything is considered finished, **five independent safety checks** run against the data that was just saved. This is genuinely the single most important part of this whole process for a business admin to know about — not because you'll ever run these checks yourself, but because when a quote's document generation fails, it is almost always one of these five checks doing exactly its job: catching a real, specific problem *before* a wrong dollar figure could ever make it onto a document a customer signs.

1. **No two rows in the same table can share the same `Row_Key__c` (their unique internal identifier).** If this happened, it would mean two different groups accidentally produced an identical internal identifier — a sign that two different real-world values (say, two differently-spelled versions of the same product family) got treated as the same bucket by mistake.
2. **The Grand Total equals the sum of the individual detail rows.** In other words: add up every single line-item row by hand, and it should come out to exactly the number printed on the Grand Total row.
3. **The Grand Total also equals the sum of the outermost subtotal rows.** This is a *second, completely independent* way of arriving at the same number — instead of adding every individual line, add up just the handful of subtotals. If checks 2 and 3 land on two different numbers, that's proof something in the grouping logic dropped a line entirely or accidentally counted one twice — and the system treats that as a hard failure rather than quietly printing a table that's slightly wrong.
4. **The table's own copied-over totals match its Grand Total row exactly.** This confirms the copy performed at the start of this step was done faithfully, with no mismatch introduced along the way.
5. **For the one specific table shape that's supposed to match the Quote's own official total** (a table with `Measure_Set__c = PRICE_WATERFALL` and `Line_Filter__c = EXCLUDE_OPTIONAL`) — its Grand Total's `Amount_Net__c` has to equal the Quote's own `SBQQ__NetAmount__c` field, down to the exact penny. This is the single most important check in the entire framework: it's the one guarantee that a signed document's printed total will always match what Salesforce CPQ itself calculated as the deal's real value — the two numbers can never quietly drift apart.

If **any single one** of these five checks fails, the entire save is undone (a **rollback** — see the [glossary](00-glossary.md) — meaning everything is put back exactly as it was before Step 3 started, as if this attempt at generation had never happened at all). The specific table involved is marked `Status__c = Failed`, and the Quote's own `Document_Data_Status__c` field is set to `Failed`, along with a specific, readable error message explaining exactly which of the five checks failed and why. Nothing partially-correct, and nothing merely "probably fine," is ever left behind for a document to accidentally print from.

### Step 8 — Mark the quote ready

Only after every table for the quote has passed all five checks does the code update the Quote itself: `Document_Data_Status__c = Ready`, `Document_Data_Generated_On__c = right now`, and it stores the fingerprint from Step 2 so the next click on an unchanged quote can skip straight past Steps 3–8. **This is the field a document-generation button or DocuSign template should check before printing** — it's the one place that proves every table on the quote came from the same successful generation, rather than a mix of old and new.

---

## 4. What happens if something goes wrong

If any step throws an unexpected error — a bad Custom Metadata setting, a field the running user isn't allowed to see, anything at all — the whole save is rolled back to exactly how it was before Step 3 started, and the Quote's `Document_Data_Status__c` is set to `Failed` with the error message captured in `Document_Data_Error__c`. A quote is never left half-updated: either every table for that quote is `Complete` and consistent with each other, or nothing changed and the quote's previous state (whatever it was) is untouched.

---

## 5. One important background process, briefly

There's one more Apex-driven behavior worth knowing about even though it isn't part of the "create the records" pipeline itself: whenever someone edits a quote line, `QuoteDocumentStaleness` automatically flips the Quote's `Document_Data_Status__c` to `Stale`. This doesn't create any `Quote_Document_Table__c` or `Quote_Document_Row__c` records by itself — it's just a warning flag that says "the numbers currently on this quote no longer match its lines, someone needs to regenerate." The full detail on why this has to happen in a very specific, deliberate way (and the bug it prevents if done the naive way) is in [`docs/quote-document-totals.md`](../quote-document-totals.md) §6.

**Next:** [03-flow-the-trigger.md](03-flow-the-trigger.md) — how a person actually starts this whole process.
