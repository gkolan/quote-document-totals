# How each row gets built — Part 3: Flow (and why it has no row-level role)

**Who this is for:** anyone — a business admin with no coding background, a junior Salesforce admin, or a junior developer. If a term feels unfamiliar anywhere in this file, check the [shared glossary](../quote-document-totals-creation-pipeline/00-glossary.md).

**Read [01-custom-metadata-shapes-each-row.md](01-custom-metadata-shapes-each-row.md) and [02-apex-builds-each-row.md](02-apex-builds-each-row.md) first.** This file is short and exists to answer one specific question directly, rather than to pad this folder out to match the other two: **what does the Flow from the first folder actually do at the individual-row level?**

The honest answer is: **nothing.** And that's worth explaining properly rather than leaving as an assumption, because it's an easy thing to guess wrong about.

---

## 1. What the Flow can see, and what it can't

Go back to [`../quote-document-totals-creation-pipeline/03-flow-the-trigger.md`](../quote-document-totals-creation-pipeline/03-flow-the-trigger.md) and look again at the four pieces of information the Apex action hands back to the Flow:

| Field | What it tells the Flow |
|---|---|
| `success` | Did generation complete and pass every check |
| `tableCount` | How many tables now exist |
| `rowCount` | How many rows now exist, **in total, across every table** |
| `message` | A plain-English summary sentence |

Notice `rowCount` is a single number for the *whole quote* — it doesn't say which table each row belongs to, what `Row_Type__c` any of them are, what `Group_Level__c` they sit at, or what any individual row's dollar figures are. The Flow genuinely has no visibility into any of that. It isn't that this information is hidden from the Flow on purpose — it's that the Flow never asked for it, because a confirmation screen showing "42 rows were created" is all a person clicking a button actually needs to see. Anyone who needs to look at individual rows — their `Row_Type__c`, their `Group_Level__c`, their dollar amounts — does that afterward, by opening the `Quote_Document_Row__c` records directly or through a report (see `docs/quote-document-totals.md` §10 for the reports built for exactly this).

## 2. Why this is the correct design, not a missing feature

If you find yourself wanting the Flow to do something row-specific — say, show a different message depending on how many Group Header rows were created, or list out every Subtotal on the confirmation screen — resist the urge to build that into the Flow. Here's why:

- **All of the actual row-shaping logic already lives in one well-tested place** (`QuoteDocumentRowBuilder`, from file 2), which is exactly where a developer would need to make a change anyway if the row logic itself needed to change. Duplicating any of that logic into the Flow would mean two different places could disagree with each other about what a row should look like.
- **The Flow's only real job is to be a button with a result screen.** Every extra thing a Flow is asked to know about makes it more fragile and harder for a future admin to safely modify without breaking something. Keeping it this narrow is what let file 3 of the previous folder describe the entire Flow in a few short tables.
- **If you need a genuinely different row-level report or screen,** the right tool is a **Report** (built against the custom report type already covering `Quote_Document_Table__c` and its `Quote_Document_Row__c` children — see `docs/quote-document-totals.md` §10) or a **Lightning page component reading the rows directly**, not more logic stuffed into this one Flow.

## 3. The full picture, one more time

Put together, all six files across both folders describe **exactly one generation pipeline**, viewed from two different distances:

```
Quote_Document_Table_Def__mdt  ─┐
                                  ├─► QuoteDocumentTableDefinition ─► QuoteDocumentGenerator
Quote_Document_Grouping__mdt   ─┘         (reads the metadata)      (the one entry point,
                                                                      called by the Flow)
                                                                            │
                                                                            ▼
                                                                  QuoteDocumentRowBuilder
                                                                  (builds every row, per
                                                                   the metadata's grouping
                                                                   and measure settings)
                                                                            │
                                                                            ▼
                                                        Quote_Document_Table__c + Quote_Document_Row__c
                                                                    (saved records)
```

There is one Flow, calling one Apex entry point, which itself calls a small, fixed set of helper Apex classes, all of them reading the same two Custom Metadata Types. Nothing in this framework requires — or currently has — three interchangeable creation methods or four independent triggers. It's one pipeline, and every file in these two folders has been a closer look at one part of it.
