# Quote Document Totals configuration and maintenance guide

**Repository status:** This guide describes the objects, Custom Metadata, Flow, Apex, reports, permissions, and operating rules present in the current repository.

**Org verification status:** Repository tests verify the framework behavior. Page layouts, user assignments, CPQ pricing rules, document-tool mappings, and customer wording must be verified in the target Salesforce org.

## What the feature does

Quote Document Totals reads a calculated Salesforce CPQ Quote and saves complete document-ready data in Salesforce. A user or automation can inspect that saved result before a document tool uses it.

The feature prepares data. It does not calculate CPQ prices, approve wording, send a document, or collect signatures.

```text
Calculated Quote and Quote Lines
              |
              v
Generate Document Tables action
              |
              v
Current Custom Metadata settings
              |
              v
Saved Tables, Columns, Rows, and Blocks
              |
              v
Salesforce Reports or a document adapter
```

## Before you configure anything

You need:

- Salesforce CPQ installed and configured;
- this project deployed to a sandbox;
- the `CPQ_Document_Totals` permission set;
- permission to manage Custom Metadata when changing definitions;
- a calculated Quote with representative Quote Lines; and
- an agreed result that can be checked against Salesforce.

Stop if the business meaning of a table, optional-line policy, amount source, wording, language, or owner is undecided. Configuration should record a decision, not make one silently.

## What users see on a Quote

Add these fields to a **Document Data** section on the Quote page:

| Field                      | Meaning                                 | Typical visibility |
| -------------------------- | --------------------------------------- | ------------------ |
| Document Data Status       | Whether the saved result is safe to use | Sales and support  |
| Document Data Generated On | When the current result completed       | Sales and support  |
| Document Data Error        | Why the last attempt failed             | Sales and support  |
| Document Data Started At   | When the active attempt began           | Support            |
| Document Data Request Id   | Identifier for one attempt              | Support            |
| Document Data Fingerprint  | Identifier for the current inputs       | Support            |
| Document Payload Hash      | Integrity check for saved output        | Support            |

Quote status values have exact meanings:

| Status        | Meaning                                                | Action                                                          |
| ------------- | ------------------------------------------------------ | --------------------------------------------------------------- |
| Not Generated | No saved result has been created                       | Generate                                                        |
| Stale         | Relevant data changed after the last successful result | Calculate if needed, then generate                              |
| Generating    | A request currently owns generation                    | Wait unless it exceeds the abandonment window                   |
| Ready         | The complete current result passed every check         | Review or create the document                                   |
| Failed        | No valid current result was published                  | Read Document Data Error, correct the cause, and generate again |

The Quote uses **Ready**. Each generated Table uses **Complete**. Those values are not interchangeable.

## What Salesforce saves

### Quote Document Table

One record represents one generated table. It stores:

- the Quote and stable Table Code;
- customer-facing title, subtitle, introduction, and footer;
- language, currency, display order, and display decision;
- row count and copied grand totals;
- request Id, input fingerprint, and output integrity information; and
- status for that table.

### Quote Document Column

One record represents one displayed column. It stores the column code, translated heading, order, data type, alignment, and the generated-row field that supplies its value.

### Quote Document Row

One record represents a heading, detail, subtotal, section total, grand total, informational value, discount, rounding adjustment, or note. It stores stable identity, label, order, visibility, grouping, amount fields, and explicit total-inclusion decisions.

### Quote Document Block

One record represents document-level prose such as a heading, paragraph, clause, notice, validity statement, or signature instruction. Blocks and Tables share one document-wide display order.

Generated records are snapshots. Do not correct them by hand. Correct the Quote or configuration and generate again.

### Quote Document Fact

One record stores a typed document value such as Customer, Billing Address, Quote Number, or Quote Expiration Date. Facts are generated and checked with the rest of the document data. See [Dynamic order form composition](dynamic-order-form-composition.md) for the complete document structure.

## What controls the result

The project has nine Custom Metadata Types:

| Custom Metadata Type             | Purpose                                                                    |
| -------------------------------- | -------------------------------------------------------------------------- |
| Quote Document Table Definition  | One table's filter, measures, presentation, order, and optional extensions |
| Quote Document Grouping          | How Quote Lines become groups or nested groups                             |
| Quote Document Column Definition | Which columns every renderer receives and their order                      |
| Quote Document Content           | Translated document-level prose and its order                              |
| Quote Document Key Value         | Label dictionaries and named configuration values                          |
| Quote Document Product Alias     | Customer-facing product-number or product-name mappings                    |
| Quote Document Schedule          | Named periods or milestones and their allocation weights                   |
| Quote Document Condition         | Typed rules that select the Quote Lines included in a Table                |
| Quote Document Composer          | Approved Apex or Flow that can add complete Tables, Rows, Blocks, or Facts |

Custom Metadata describes the result. It does not itself create generated records.

## Configure one table safely

Use the closest numbered [use-case runbook](use-case/README.md). Each runbook supplies the exact values, example, report, checks, and rollback steps for that case.

For a new table:

1. Work in a sandbox.
2. Create the Table Definition as inactive.
3. Give it a permanent, unique Table Code.
4. Give it a unique document-wide Display Order.
5. Enter a customer-facing Display Title.
6. Choose the line filter and amount source deliberately.
7. Add at least one Grouping unless an approved contributor builds all rows.
8. Add every displayed Column Definition.
9. Add every required translated label and content block.
10. Activate the definition only after configuration is complete.
11. Generate representative Quotes.
12. Compare saved rows, the named report, and the final document preview.

### Core table choices

| Setting             | Decision                                                                                    |
| ------------------- | ------------------------------------------------------------------------------------------- |
| Line Filter         | All, exclude optional, optional only, recurring only, one-time only, or bundle parents only |
| Amount Basis        | Which calculated CPQ amount family the table summarizes                                     |
| Measure Set         | Price waterfall values or Quote-change values                                               |
| Show Details        | Whether individual Quote Lines appear                                                       |
| Show Section Totals | Whether Recurring and One-Time totals appear                                                |
| Sort Groups By      | Alphabetical label or first Quote Line sequence                                             |
| Max Groups          | Maximum allowed grouping buckets before generation fails                                    |
| Display Order       | Position shared by every Table and Block                                                    |
| Active              | Whether generation includes the definition                                                  |

Do not type permanent titles, headings, notices, translations, formulas, or visibility rules only into a document template. Those decisions belong in the saved Salesforce result.

## Grouping, expansion, comparison, and partitioning

These terms describe different jobs:

| Feature            | What it does                                                                | Example                               |
| ------------------ | --------------------------------------------------------------------------- | ------------------------------------- |
| Grouping           | Places lines into sections inside one table                                 | Product Family                        |
| Nested grouping    | Places one group inside another                                             | Quote Line Group, then Product Family |
| Composite grouping | Combines values at the same level                                           | Product Family plus Billing Frequency |
| Expansion          | Turns one Quote Line into several time, tier, alias, or schedule rows       | One row per month                     |
| Allocation         | Divides additive amounts across expanded rows                               | Annual amount across months           |
| Comparison         | Matches current lines to a declared baseline                                | Current Quote versus Source Quote     |
| Partitioning       | Creates separate tables per value                                           | One table per purchasing entity       |
| Row adjustment     | Changes the built rows through a registered Apex class or autolaunched Flow | Add a rounding row                    |

Use only combinations accepted by configuration validation. A rejected combination is a deliberate safety boundary, not a prompt to bypass the check in a template.

## Language and customer wording

Generation resolves one language for the entire saved result. It uses the Quote field configured by `DOCUMENT_CONFIG / LOCALE_FIELD_PATH`; if that field is blank, it uses `DOCUMENT_CONFIG / DEFAULT_LOCALE`, then the repository default `en_US`.

The running user's language is ignored so two users cannot create different results from the same Quote by accident.

Use:

- Table Definition presentation fields for words attached to one table;
- Column Definitions and the label dictionary for headings;
- semantic label keys for row labels; and
- Quote Document Content for standalone paragraphs, clauses, and notices.

Increase the content or contributor version whenever behavior or wording changes. Deploying metadata does not update every existing Ready Quote; run the documented invalidation job when a release changes output.

## Generation and safe reuse

The **Generate Document Tables** action always performs a fresh change check.

- If current inputs and saved output still match, Salesforce reuses the result.
- If output-relevant data or configuration changed, Salesforce rebuilds it.
- If generation fails, Salesforce rolls back partial changes and marks the Quote Failed.
- A concurrent live request is rejected without taking ownership from the active request.
- A document adapter must request the exact Ready result using the returned request Id and fingerprint.

Never let a document tool query arbitrary generated rows without first running generate-or-reuse.

## Reports and related lists

Use **Reports → CPQ Document Totals** for routine review. The repository includes a rendered-view report, generation-failure report, and table-specific reports for shipped views.

Use related lists for record-level troubleshooting:

1. Quote → Quote Document Tables
2. Table → Quote Document Columns
3. Table → Quote Document Rows
4. Quote → Quote Document Blocks

Reports do not calculate document totals. They display the saved result.

## Access and ownership

Assign `CPQ_Document_Totals` to users who generate or support document data. Limit Custom Metadata changes, Flow activation, Apex deployment, and legal wording changes through the organization's normal release controls.

| Change                                              | Required owner                                   |
| --------------------------------------------------- | ------------------------------------------------ |
| Page layout, action visibility, related lists       | Salesforce administrator                         |
| Table, grouping, column, label, or content metadata | Salesforce administrator plus business owner     |
| Legal clauses or signature instructions             | Legal or designated content owner                |
| Translation                                         | Qualified language reviewer                      |
| Flow row adjustment                                 | Salesforce administrator with Flow review        |
| Apex row adjustment or registry change              | Salesforce developer and code reviewer           |
| Document adapter mapping                            | Document-tool administrator and Salesforce owner |

## Troubleshooting order

1. Confirm the Quote is calculated.
2. Read **Document Data Status**.
3. If Failed, read **Document Data Error** in full.
4. Correct the named Quote data, metadata, access, language, or extension problem.
5. Generate again.
6. Compare the generated records and named report.
7. Inspect **Setup → Apex Jobs** only for asynchronous or invalidation work.
8. Retain the Request Id when escalating.

Do not delete generated records, clear status fields, disable verification, or add template calculations to make an error disappear.

## Production checklist

- [ ] Salesforce CPQ and package prerequisites were validated in a sandbox.
- [ ] Quote action, status fields, related lists, reports, and permissions are configured.
- [ ] Every active table has a unique code, title, order, valid grouping or contributor, and displayed columns.
- [ ] Every active language has complete labels and content.
- [ ] Every custom contributor has a version token and correct cache policy.
- [ ] Representative happy-path and failure-path Quotes were tested.
- [ ] Saved records, reports, and final document previews agree.
- [ ] Only Ready results can reach the document launch.
- [ ] Rollback and invalidation procedures were tested.
