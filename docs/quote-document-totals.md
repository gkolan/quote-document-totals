# Quote Document Totals technical reference

**Repository status:** This reference describes the current source tree. It contains no deployment history, retired phase status, or org-specific sample claims.

**Org verification status:** Automated repository tests cover the contracts described here. Salesforce limits, sharing, CPQ behavior, and adapter behavior must also be verified in the target org.

## Product boundary

The framework owns four jobs:

1. interpret calculated Salesforce CPQ Quote and Quote Line data;
2. build deterministic document Tables, Columns, Rows, and Blocks;
3. verify and publish one complete saved result; and
4. return a result that a renderer can bind by Quote, request Id, and fingerprint.

It does not own CPQ pricing, legal approval, translation approval, document delivery, signatures, or renderer styling.

## Supported launch contract

Every document launch must:

1. call generation or safe reuse;
2. require Quote status `Ready`;
3. keep the returned request Id and fingerprint;
4. request the payload for that exact identity; and
5. render only the returned payload.

Reading generated objects directly without the fresh generation check can use an old result after related data or configuration changed.

`QuoteDocumentGenerator.Result` exposes:

| Value         | Meaning                                    |
| ------------- | ------------------------------------------ |
| `success`     | Whether the Flow-facing request succeeded  |
| `tableCount`  | Number of generated Tables                 |
| `rowCount`    | Number of generated Rows                   |
| `message`     | User-facing generation or reuse result     |
| `requestId`   | Identity of the published attempt          |
| `fingerprint` | Identity of the output-relevant inputs     |
| `reused`      | Whether the existing Ready result was kept |

## Data model

```text
SBQQ__Quote__c
├── Quote_Document_Table__c
│   ├── Quote_Document_Column__c
│   └── Quote_Document_Row__c
└── Quote_Document_Block__c
```

Table to Quote is a lookup with controlled cascade behavior. Row and Column to Table are master-detail relationships. Blocks relate directly to the Quote because they occupy document-level positions between Tables.

### Table invariants

- one Quote can have many generated Tables;
- active definitions must use unique Table Codes;
- every active definition has a printable title;
- Tables and Blocks share unique document-wide display orders;
- a published Table has status `Complete`;
- copied table totals match the generated Grand Total row; and
- request Id, locale, and fingerprint agree across one saved result.

### Row invariants

Allowed row types are:

- Group Header
- Detail
- Subtotal
- Section Total
- Grand Total
- Informational
- Discount
- Rounding
- Note

Every row has a unique Row Key within its Table and an unambiguous Display Order. Exactly one Grand Total exists per Table. Visibility is stored in `Is_Displayed__c`; adapters may not invent content-selection rules.

`Include_In_Subtotal__c` and `Include_In_Grand_Total__c` are separate because some legitimate adjustments affect only one reconciliation level.

### Column invariants

Generated Columns are the renderer's column contract. A Column Definition supplies:

- stable Column Code;
- display order;
- translated heading key;
- bound generated-row field;
- data type; and
- alignment.

An adapter may format a value, but it may not choose an unconfigured field or calculate a replacement amount.

### Block invariants

Each active content record resolves by Block Code and locale. Generated Blocks contain plain text, block type, optional heading, order, source version, and locale. HTML, document tags, and merge-field markup are rejected from content data.

## Custom Metadata model

| Type                                | Runtime reader                                                           | Responsibility                                                                                             |
| ----------------------------------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| `Quote_Document_Table_Def__mdt`     | `QuoteDocumentTableDefinition`                                           | Table filter, measures, presentation, expansion, comparison, partitioning, contributor, caching, and order |
| `Quote_Document_Grouping__mdt`      | `QuoteDocumentTableDefinition`                                           | Named dimensions or schema-validated Quote Line field paths arranged by level and sequence                 |
| `Quote_Document_Column_Def__mdt`    | `QuoteDocumentColumnDefinition`                                          | Displayed columns and field bindings                                                                       |
| `Quote_Document_Content__mdt`       | `QuoteDocumentBlockBuilder`                                              | Localized document-level prose                                                                             |
| `Quote_Document_Key_Value__mdt`     | `QuoteDocumentKeyValueMap`, `QuoteDocumentLabels`, `QuoteDocumentLocale` | Label dictionaries, locale configuration, and named maps                                                   |
| `Quote_Document_Product_Alias__mdt` | Alias expander                                                           | Customer-facing product aliases                                                                            |
| `Quote_Document_Schedule__mdt`      | Schedule expander                                                        | Named schedule sections and weights                                                                        |

Configuration loading fails loudly for ambiguous, incomplete, unsupported, or unsafe combinations.

## Generation pipeline

The current pipeline is:

1. lock and query the Quote;
2. load active definitions and supporting metadata;
3. resolve locale and translated content;
4. normalize Quote Lines into `QuoteDocumentLine` values;
5. compute the input fingerprint;
6. reuse only when status, identity, structure, payload integrity, and cache policy all allow it;
7. claim generation ownership with a new request Id;
8. delete the prior generated result inside a savepoint;
9. filter, group, expand, allocate, compare, partition, and customize rows;
10. build Tables, Columns, Rows, and Blocks;
11. verify reconciliation, presentation, ordering, identity, and contract completeness;
12. insert the complete result;
13. compute and save the payload hash; and
14. mark the Quote `Ready`.

On a non-retryable failure, the transaction rolls back to the savepoint, then records `Failed` and a safe error on the Quote. A lock conflict or non-owning lifecycle rejection does not overwrite the live attempt.

## Freshness and integrity

The framework uses two different hashes:

| Check             | Answers                                        | Used for                  |
| ----------------- | ---------------------------------------------- | ------------------------- |
| Input fingerprint | Did anything that can change output change?    | Safe reuse versus rebuild |
| Payload hash      | Did the saved output change after publication? | Retrieval integrity       |

Trigger-based staleness gives users an immediate warning for watched Quote and Quote Line edits. The fingerprint is the final authority during generate-or-reuse because it also covers configured related fields, active metadata, presentation, locale, content versions, columns, and declared extension dependencies.

Metadata deployment does not update existing Quotes. Releases that change output must update the relevant version token and run:

```apex
Database.executeBatch(new QuoteDocumentInvalidationJob(), 200);
```

Review completion in **Setup → Apex Jobs**, then regenerate affected Quotes.

## Row production features

### Grouping

Different grouping levels create nesting. Multiple parts at the same level create one composite key. Named dimensions are resolved by `QuoteDocumentLine`; field paths are validated and queried in bulk.

### Expansion and allocation

An expander can turn one source line into multiple placed lines. Additive measures must be allocated so the placements reconcile with the source. A no-money expansion must explicitly set Suppress Amounts.

### Non-additive measures

A contributor can declare measures that must not be summed across repeated periods. Verification then applies the configured non-additive rule instead of leaving the value unchecked.

### Comparison

Comparison sources are closed-registry implementations with stable matching. Ambiguous matches fail. Current shipped sources are documented by the relevant numbered use-case runbooks.

### Partitioning

Partitioning emits separate Tables per dimension value. Cross-partition total behavior must be declared. Unsafe combinations, including unsupported expansion or comparison combinations, fail configuration validation.

### Contributors

Core builds normal rows first. A registered Apex customizer runs next. A configured Flow customizer runs after Apex. All returned rows pass the same verification and persistence path.

Every contributor declares:

- an implementation code or Flow API name;
- a version token;
- a cache policy; and
- dependency field paths when the policy is `DECLARED_DEPENDENCIES`.

Supported cache policies are:

| Policy                  | Meaning                                                               |
| ----------------------- | --------------------------------------------------------------------- |
| `STANDARD`              | The contributor uses only supplied context and already-covered inputs |
| `DECLARED_DEPENDENCIES` | Additional Quote or Quote Line field paths are listed and hashed      |
| `ALWAYS_REBUILD`        | Dependencies cannot be exhaustively declared, so reuse is disabled    |

## Verification boundary

`QuoteDocumentVerification` checks, among other conditions:

- allowed row types and required row identity;
- one Grand Total per Table;
- unique row keys and unambiguous row ordering;
- subtotal and grand-total reconciliation;
- source-total reconciliation where the table contract requires it;
- column bindings and projected values;
- required presentation and locale data;
- content completeness and document-wide order;
- consistent request Id and fingerprint; and
- complete table status before retrieval.

`QuoteDocumentRenderService` adds retrieval-time checks for Quote readiness, requested identity, structure, field access, and payload integrity.

## Sharing and permissions

Production classes use sharing-aware access. The `CPQ_Document_Totals` permission set grants the packaged object, field, Flow, Apex, tab, report, and quick-action access required to operate the feature.

The package permission set is not an approval model. Organizations should control:

- who may run generation;
- who may review technical identity fields;
- who may edit Custom Metadata;
- who may activate contributor Flows;
- who may deploy registry or contributor Apex; and
- who may approve customer wording and translations.

## Entry points

| Need                                                  | Entry point                                                          |
| ----------------------------------------------------- | -------------------------------------------------------------------- |
| Quote user action                                     | `Generate_Quote_Document_Tables` Flow through the Quote quick action |
| Synchronous Apex                                      | `QuoteDocumentGenerator.generate(Set<Id>)`                           |
| Asynchronous Apex                                     | `QuoteDocumentGenerator.generateAsync`                               |
| One queued Quote                                      | `QuoteDocumentGenerateJob`                                           |
| Invalidate Ready Quotes after output-changing release | `QuoteDocumentInvalidationJob`                                       |
| Retrieve a bound payload                              | `QuoteDocumentRenderService`                                         |

Use the UI or asynchronous entry point for normal administration. Direct Apex calls are for controlled automation, tests, or support procedures.

## Testing and release checks

Before production deployment:

1. run formatting, JavaScript, documentation, and contributor-version checks;
2. deploy with Apex tests to a Salesforce CPQ test org;
3. run the full Apex suite required by the repository CI configuration;
4. generate representative Quotes for every changed definition or contributor;
5. verify failures, reuse, rebuilding, permissions, locale, and adapter binding;
6. run invalidation when output identity changed; and
7. compare saved records, reports, and final document previews.

Repository commands:

```bash
npm test
npm run lint
npm run prettier:verify
npm run test:docs
npm run test:ci-gate
```

## Current limits

- Salesforce CPQ is required and is not installed by this project.
- Target-org CPQ formulas, pricing rules, fields, sharing, and page layouts can change observed results.
- A custom document adapter is responsible for styling and delivery, but may not recalculate or select content independently.
- One-click Quote-scoped report links are planned and do not currently ship.
- Open defects and proposed improvements are listed only in the live `bugs/` and `enhancements/` indexes.

## File map

| Area                            | Path                                                                     |
| ------------------------------- | ------------------------------------------------------------------------ |
| Apex implementation and tests   | `force-app/main/default/classes/`                                        |
| Triggers                        | `force-app/main/default/triggers/`                                       |
| Objects and fields              | `force-app/main/default/objects/`                                        |
| Custom Metadata records         | `force-app/main/default/customMetadata/`                                 |
| Flow                            | `force-app/main/default/flows/`                                          |
| Quick action                    | `force-app/main/default/quickActions/`                                   |
| Permission set                  | `force-app/main/default/permissionsets/`                                 |
| Reports and report types        | `force-app/main/default/reports/`, `force-app/main/default/reportTypes/` |
| Operational and use-case guides | `docs/`                                                                  |
| Reproducible scripts            | `scripts/`                                                               |
