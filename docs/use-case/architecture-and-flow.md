# Quote document architecture — simple view

This feature does one simple job:

> It reads a Salesforce CPQ Quote, organizes the Quote Lines using Custom Metadata, checks the totals, and saves document-ready records.

The document and Salesforce Reports use those saved records. They do not calculate the Quote again.

## 1. The whole process

### Mermaid diagram

```mermaid
%%{init: {"flowchart": {"nodeSpacing": 80, "rankSpacing": 70}} }%%
flowchart LR
    Quote["Salesforce CPQ Quote"]
    Setup["Custom Metadata setup"]
    Generate["Generate document data"]
    Saved["Checked Salesforce records"]
    Output["Reports and final document"]

    Quote --> Generate
    Setup --> Generate
    Generate --> Saved
    Saved --> Output

    style Quote fill:#bae6fd,stroke:#0369a1,color:#1f2937
    style Setup fill:#a5f3fc,stroke:#0e7490,color:#1f2937
    style Generate fill:#c7d2fe,stroke:#4338ca,color:#1f2937
    style Saved fill:#fed7aa,stroke:#c2410c,color:#1f2937
    style Output fill:#a7f3d0,stroke:#047857,color:#1f2937
```

### Text-only version

```text
Salesforce CPQ Quote ───┐
                        ├──> Generate ──> Checked records ──> Reports/document
Custom Metadata setup ──┘
```

- The **Quote** supplies products, quantities, prices, dates, and Quote Line Groups.
- **Custom Metadata** says which tables to create and how to organize them.
- **Generate** builds the tables and checks their totals.
- The checked records become the source for Reports and the final document.

## 2. The saved data model

### Mermaid diagram

```mermaid
%%{init: {"flowchart": {"nodeSpacing": 80, "rankSpacing": 70}} }%%
flowchart TB
    Quote["Quote"]
    Table["Quote Document Table"]
    Row["Quote Document Row"]
    Column["Quote Document Column"]
    Block["Quote Document Block"]

    Quote -->|"has tables"| Table
    Table -->|"has rows"| Row
    Table -->|"has columns"| Column
    Quote -->|"has text blocks"| Block

    style Quote fill:#bae6fd,stroke:#0369a1,color:#1f2937
    style Table fill:#fed7aa,stroke:#c2410c,color:#1f2937
    style Row fill:#fed7aa,stroke:#c2410c,color:#1f2937
    style Column fill:#fed7aa,stroke:#c2410c,color:#1f2937
    style Block fill:#fed7aa,stroke:#c2410c,color:#1f2937
```

### Text-only version

```text
Quote
├── Quote Document Table
│   ├── Quote Document Rows
│   └── Quote Document Columns
└── Quote Document Blocks
```

The easiest way to remember the model is:

- A **Quote Document Table** is one complete table, such as Product Family Summary.
- A **Quote Document Row** is one heading, product line, subtotal, or grand total.
- A **Quote Document Column** says which saved columns the table displays.
- A **Quote Document Block** is document text, such as assumptions or signature instructions.

## 3. What happens after Generate is selected

### Mermaid diagram

```mermaid
%%{init: {"flowchart": {"nodeSpacing": 80, "rankSpacing": 70}} }%%
flowchart TB
    Start([Select Generate Document Tables])
    Flow["Salesforce Flow starts"]
    Read["Read Quote and active Custom Metadata"]
    Build["Build tables and rows"]
    Check{"Do all checks pass?"}
    Ready["Set Quote status to Ready"]
    Failed["Set Quote status to Failed"]
    Use["View in Reports or create document"]
    Fix["Read Document Data Error and correct the issue"]

    Start --> Flow
    Flow --> Read
    Read --> Build
    Build --> Check
    Check -->|"Yes"| Ready
    Ready --> Use
    Check -->|"No"| Failed
    Failed --> Fix
    Fix --> Start

    style Start fill:#a7f3d0,stroke:#047857,color:#1f2937
    style Flow fill:#c7d2fe,stroke:#4338ca,color:#1f2937
    style Read fill:#c7d2fe,stroke:#4338ca,color:#1f2937
    style Build fill:#c7d2fe,stroke:#4338ca,color:#1f2937
    style Check fill:#fde68a,stroke:#b45309,color:#1f2937
    style Ready fill:#a7f3d0,stroke:#047857,color:#1f2937
    style Failed fill:#fecaca,stroke:#b91c1c,color:#1f2937
    style Use fill:#a7f3d0,stroke:#047857,color:#1f2937
    style Fix fill:#fde68a,stroke:#b45309,color:#1f2937
```

### Text-only version

```text
Select Generate
      │
      ▼
Flow reads the Quote and Custom Metadata
      │
      ▼
Salesforce builds and checks the tables
      │
      ├── Checks pass ──> Ready ──> Reports or final document
      │
      └── Check fails ──> Failed ──> Correct the error and try again
```

Nothing is ready for a document until all checks pass.

## Quote status meanings

| Status            | Meaning                                              | What to do                                                           |
| ----------------- | ---------------------------------------------------- | -------------------------------------------------------------------- |
| **Not Generated** | No saved document data exists yet.                   | Select **Generate Document Tables**.                                 |
| **Stale**         | The Quote changed after document data was generated. | Generate again.                                                      |
| **Generating**    | Salesforce is currently building the records.        | Wait for completion.                                                 |
| **Ready**         | The records were created and all checks passed.      | Review or create the document.                                       |
| **Failed**        | Salesforce could not create a valid result.          | Read **Document Data Error**, correct the cause, and generate again. |

## Simple example

A Quote contains:

- Software: $10,000
- Services: $5,000

The Product Family Summary setup tells Salesforce to group the Quote Lines by Product Family.

After Generate is selected, Salesforce saves:

```text
Quote Document Table: Product Family Summary
├── Row: Software       $10,000
├── Row: Services        $5,000
└── Row: Grand Total    $15,000
```

The related list, Salesforce Report, and final document all read the same saved $15,000 total.

## Exact Salesforce component names

These names are provided only when the exact component must be found in Setup or source control.

| Plain name       | Salesforce component               |
| ---------------- | ---------------------------------- |
| Quote            | `SBQQ__Quote__c`                   |
| Quote Line       | `SBQQ__QuoteLine__c`               |
| Table setup      | `Quote_Document_Table_Def__mdt`    |
| Grouping setup   | `Quote_Document_Grouping__mdt`     |
| Column setup     | `Quote_Document_Column_Def__mdt`   |
| Saved table      | `Quote_Document_Table__c`          |
| Saved row        | `Quote_Document_Row__c`            |
| Saved column     | `Quote_Document_Column__c`         |
| Saved text block | `Quote_Document_Block__c`          |
| Generate Flow    | **Generate Quote Document Tables** |
| Quote action     | **Generate Document Tables**       |

## Key rule

The final document prints saved Salesforce values. It must not calculate prices, discounts, subtotals, or grand totals on its own.

Live-org page layouts and document-tool screens are not shown because they vary by Salesforce org. The numbered runbooks give the exact Salesforce configuration and verification steps for each supported use case.
