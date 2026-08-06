# How Quote Document Totals records get created — Part 3: Flow (the trigger)

**Who this is for:** anyone — a business admin with no coding background, a junior Salesforce admin, or a junior developer. If a term feels unfamiliar, check the [shared glossary](00-glossary.md).

**Read [01-custom-metadata-the-blueprint.md](01-custom-metadata-the-blueprint.md) and [02-apex-the-builder.md](02-apex-the-builder.md) first.** This file is the shortest of the three, on purpose — Flow's actual job in this framework is small.

> **In one sentence:** Flow's whole role is to be the clickable button on a Quote that a person presses, and the screen that tells them whether it worked — it doesn't decide what gets built (file 1) or do the actual building (file 2).

> **A count correction, up front.** This project has exactly **one** Flow involved in creating these records, not four. Read on and you'll see why that's not a gap — Custom Metadata (file 1) and Apex (file 2) don't each need their own separate Flow. There is one job left for Flow to do — give a person a button to press — and one Flow does it. If a future need genuinely called for more Flows (for example: one screen-flow button, plus a separate record-triggered Flow, plus a separate scheduled Flow, plus a separate Flow reacting to a system event), those would be four *different kinds* of triggers for the *same* underlying Apex — not four parallel paths to creating the records independently of Apex. As it stands today, only the screen-flow button exists; a fully automatic, event-driven trigger is a documented but not-yet-built future phase (see `docs/quote-document-totals.md` §9, "what Phase 6 would add").

---

## 1. What "Flow" means, in plain terms

A Flow is Salesforce's point-and-click automation tool. An admin builds one visually — screens, decision boxes, actions — without writing code, and Salesforce runs it exactly the same way every time. Where file 2's Apex is what actually *does* the work of creating records, a Flow is usually just the thing that decides *when* that work should start, and what the person who started it sees on their screen while it happens.

In this framework, Flow's entire job is: **be a button on the Quote record page that a person can click, then show them whether it worked.** It does not build any table or row logic itself — it hands off to the one Apex entry point from file 2 and waits for an answer.

---

## 2. The one Flow: `Generate Quote Document Tables`

This is a **Screen Flow** — the kind of Flow meant to be run by a real person, one step at a time, with actual screens in between (as opposed to a Flow that runs silently in the background). Here is exactly what it contains, and what a user sees at each point.

### What it needs to start

The Flow expects one piece of information handed to it before it starts: `recordId` — the Salesforce ID of the Quote the person is currently looking at. In practice, this Flow is placed as a button on the Quote record page, and Salesforce automatically fills in `recordId` with whichever quote the person has open — nobody has to type an ID in by hand.

### Step 1 — Call the Apex action

The very first thing the Flow does (there's no screen shown yet) is call an **Apex Action** named `Generate_Tables`. This is a Flow-native trigger: it invokes the exact `@InvocableMethod` documented in file 2, `QuoteDocumentGenerator.generateFromFlow`. The Flow passes it exactly one input, mapped like this:

| Flow input name | What it's set to |
|---|---|
| `quoteId` | The `recordId` the Flow started with — i.e., the quote the person had open |

Everything described in file 2 — reading the quote, running through every active table definition, saving tables and rows, running the five safety checks, marking the quote `Ready` or `Failed` — happens **inside this one action call**. The Flow itself has no idea any of that is happening; from the Flow's point of view, it asked a question and is waiting for an answer.

### Step 2 — Show the person what happened

The Apex action always sends back a result with four pieces of information, and the Flow uses them to decide what to show:

| Field the Apex sends back | What it means |
|---|---|
| `success` | `true` if generation completed and passed every check, `false` if anything failed |
| `tableCount` | How many `Quote_Document_Table__c` records now exist for this quote |
| `rowCount` | How many `Quote_Document_Row__c` records now exist for this quote |
| `message` | A plain-English sentence describing the outcome |

**If the action succeeds** (this includes both "generation ran and everything checked out" *and* "nothing needed to change because it was already correct" — both count as success), the Flow shows a screen called **Document Tables Generated**, displaying that `message` text. For our Quote Q-00123 example from file 2, the person would see something like:

> *Generated 1 tables and 3 rows. This quote is ready for document generation.*

**If the action throws an unexpected error** (something the Apex itself didn't cleanly catch and turn into a `Failed` result), the Flow's fault path shows a screen called **Generation Failed**, with this fixed text plus whatever Salesforce's own fault message says:

> *The document tables could not be generated. Nothing was changed on this Quote.*
> *(followed by the technical fault message)*

Either way, the person sees a real answer on their screen — never a blank page, and never silence while something might or might not be happening in the background.

---

## 3. Why the Flow itself has almost nothing to configure

If you open this Flow expecting to find decision elements, loops, or logic about tables and rows, you won't — and that's intentional, not incomplete. Every actual decision about *what* gets built (file 1) and *how* it gets built and checked (file 2) lives outside the Flow entirely. The Flow's description field says this directly:

> *"Rebuilds the document tables and rows for this Quote, then reports what was generated. The Apex records success or failure on the Quote itself, so this screen only has to show the outcome."*

This is a deliberate design choice, not a missing feature: keeping all of the real logic in Apex (where it can be tested automatically, and where it's the same whether it's triggered by this Flow, by a bulk background job, or by any future automatic trigger) means the Flow can stay this simple. If the business rules ever need to change — a new table, a new check, a new filter — a developer only has to touch the Apex from file 2. Nobody has to open and re-test this Flow at the same time.

---

## 4. If you genuinely need more than one trigger someday

To be clear about what *would* actually justify more than one Flow — since the request that prompted this document asked about "4 Flows" — here is what that would really mean, so it's not confused with what exists today:

| Trigger you might add | What it would do differently | Does it exist today? |
|---|---|---|
| Screen Flow button (covered above) | A person clicks a button and waits for a result on screen | **Yes** — this is `Generate Quote Document Tables` |
| Record-Triggered Flow | Automatically fires generation the moment a quote field changes, with no button click | No — not built |
| Scheduled Flow | Regenerates a batch of quotes on a timer (e.g., nightly) | No — not built. The equivalent exists today as a **background Apex job** (`QuoteDocumentGenerateJob`, mentioned in file 2), not a Flow |
| Platform-Event-Triggered Flow (or an Apex trigger doing the same job) | Reacts automatically the instant `QuoteDocumentStaleness` marks a quote out of date, with no person involved at all | No — documented as a future phase in `docs/quote-document-totals.md` §9, not built |

Every one of those, if built, would still call the exact same `QuoteDocumentGenerator` Apex from file 2 — they'd just be different doorbells ringing the same one cook. None of them would be an alternative to Apex or to Custom Metadata; they'd all still depend on both.

**This completes the creation pipeline series.** For a deeper look at exactly how each individual row (not just each table) gets its shape, see the companion folder [`../quote-document-totals-row-by-row/`](../quote-document-totals-row-by-row/01-custom-metadata-shapes-each-row.md).
