# Quote Document Totals extension recipes

**Repository status:** These recipes match the current extension interfaces, closed registries, metadata fields, version rules, and verification path.

**Org verification status:** Shipped implementations are covered by repository tests. A new extension is not production-ready until its own Apex tests and representative Salesforce CPQ sandbox generation pass.

## Choose the smallest supported change

Use this order:

1. table, grouping, column, label, content, alias, or schedule Custom Metadata;
2. a Flow row adjustment for a small declarative row change;
3. a registered Apex row adjustment for logic that Flow cannot maintain safely;
4. a registered expander or comparison source only when the existing registries do not cover the required row shape.

Stop if a template formula, direct generated-record edit, dynamic class name, or unregistered extension appears to be the shortcut. Those approaches bypass the saved contract or its deployment checks.

## Rules shared by every extension

- Run inside the generation transaction and expect the whole attempt to roll back on failure.
- Use `with sharing` for Apex implementations.
- Return deterministic output for the same declared inputs.
- Never calculate or approve a business value that belongs to CPQ, tax, billing, legal, or another source system.
- Use the resolved locale and label dictionary for customer-facing words.
- Give every new row a stable key, allowed type, unique order, visibility decision, and total-inclusion decision.
- Declare every output-changing dependency.
- Change the extension version token with every behavior change.
- Test through `QuoteDocumentGenerator`, not only by invoking the extension directly.
- Let `QuoteDocumentVerification` reject invalid totals or structure.

## Recipe 1: adjust rows with Flow

Use an **Autolaunched Flow (No Trigger)** with these exact variables:

| API name          | Type                      | Collection | Input | Output |
| ----------------- | ------------------------- | ---------- | ----- | ------ |
| `rows`            | Quote Document Row record | Yes        | Yes   | Yes    |
| `quoteId`         | Text                      | No         | Yes   | No     |
| `tableCode`       | Text                      | No         | Yes   | No     |
| `locale`          | Text                      | No         | Yes   | No     |
| `currencyIsoCode` | Text                      | No         | Yes   | No     |

Build a second row collection, add every processed loop item to it, and assign it back to `rows` after the loop. A Flow loop item is a copy; changing it without rebuilding the collection returns unchanged rows.

Configure the Table Definition:

| Field                       | Required value                                           |
| --------------------------- | -------------------------------------------------------- |
| Row Customizer Flow         | Active Flow API name                                     |
| Row Customizer Flow Version | New token for every active behavior change               |
| Cache Policy                | `STANDARD`, `DECLARED_DEPENDENCIES`, or `ALWAYS_REBUILD` |
| Contributor Dependency Set  | Required field paths when using `DECLARED_DEPENDENCIES`  |

Follow [Add a Flow-based row adjustment](use-case/42-flow-row-adjustment.md) for the complete setup, example, failure tests, and rollback.

## Recipe 2: adjust rows with Apex

Create a class that implements:

```apex
public interface QuoteDocumentRowCustomizer {
  List<Quote_Document_Row__c> customize(
    QuoteDocumentRowCustomizerContext context
  );
}
```

Use `context.rows` for the normal built rows, `context.lines` for filtered normalized source lines, `context.labels` for translated text, and `context.newRow(...)` for a new row with framework defaults.

Register a stable code in `QuoteDocumentRowCustomizerRegistry.resolve`. Metadata stores the code, not a class name. This makes an unknown implementation fail clearly and makes class renames compile-time changes.

Configure:

| Field                      | Required value                                                 |
| -------------------------- | -------------------------------------------------------------- |
| Row Customizer Code        | Registered code                                                |
| Row Customizer Version     | New token for every behavior change                            |
| Cache Policy               | Policy that matches what the class reads                       |
| Contributor Dependency Set | Every additional field path read under `DECLARED_DEPENDENCIES` |

Follow [Add a registered Apex-based row adjustment](use-case/43-registered-apex-row-adjustment.md) for the full class, registry, metadata, test, deployment, and rollback procedure.

## Recipe 3: add an informational row

Use row type `Informational` when the document needs an amount that must not change any total, such as an estimate owned by another system.

Required shape:

| Field                  | Decision                             |
| ---------------------- | ------------------------------------ |
| Row Type               | `Informational`                      |
| Include in Subtotal    | False                                |
| Include in Grand Total | False                                |
| Is Displayed           | True when every renderer may show it |
| Row Key                | Stable and unique within the Table   |

Do not describe an amount as calculated tax, approved tax, or final tax unless the authoritative tax system supplied and approved that value.

## Recipe 4: add a counted discount or rounding row

Use `Discount` for a counted adjustment tied to a specific commercial basis. Use `Rounding` for a whole-table adjustment.

For a Rounding row:

- Group Level is `0`;
- Include in Subtotal is false;
- Include in Grand Total is true;
- the Grand Total row is updated by the same delta; and
- the table must not claim direct reconciliation to a CPQ source total that the adjustment intentionally changes.

For a Discount row, decide whether it contributes to both subtotal and grand total based on its placement and update the affected aggregate rows consistently.

Generation will reject an adjustment that causes reconciliation to fail.

## Recipe 5: add a note row

Use row type `Note` for table-row prose that needs row ordering and visibility. Use Quote Document Content instead when the prose belongs between Tables or applies to the whole document.

A Note normally has:

- no amount values;
- Include in Subtotal false;
- Include in Grand Total false;
- a translated Semantic Key or resolved label; and
- a unique Display Order.

## Recipe 6: turn one source line into several rows

Use an expander when one Quote Line must appear in several periods, milestones, tiers, aliases, or other placements.

Configure:

| Field                     | Meaning                                                                      |
| ------------------------- | ---------------------------------------------------------------------------- |
| Expander Code             | Registered implementation code                                               |
| Expander Version          | Change token for expander behavior                                           |
| Allocation Basis          | How additive amounts are preserved across placements                         |
| Suppress Amounts          | Explicitly allows an expanded result with no money                           |
| Period Months             | Period size for the PERIOD expander                                          |
| Period One-Time Placement | Where one-time amounts belong on a period axis                               |
| Schedule Code             | Named schedule for the SCHEDULE expander                                     |
| Schedule Divides Quantity | Whether the schedule represents different units or repeated payment coverage |

An expanded table cannot silently repeat the full amount in every placement. Allocate additive amounts or explicitly suppress them.

## Recipe 7: declare a non-additive measure

Use `context.nonAdditiveMeasures` when repeated rows describe the same quantity across time and summing them would be wrong.

Example: 100 licenses active in each of 12 months represent 100 licenses, not 1,200. Declare the quantity field as non-additive so verification applies the supported group-and-maximum rule.

Never leave a measure unverified. Choose an implemented aggregation rule or do not publish the measure.

## Recipe 8: compare with a baseline

Use a registered comparison source and configure:

| Field                     | Meaning                                           |
| ------------------------- | ------------------------------------------------- |
| Comparison Source Code    | Registry code for the baseline source             |
| Comparison Source Version | Change token for matching behavior                |
| Comparison Source Field   | Field used to identify the baseline when required |
| Comparison Match Path     | Stable current-to-baseline matching value         |

Ambiguous matches fail. Do not select an arbitrary baseline line when more than one record matches.

## Recipe 9: create separate Tables by value

Set **Partition Dimension** when one definition must create independent Tables, such as one per purchasing entity or scenario.

Also decide **Cross-Partition Total** explicitly. A partitioned result cannot leave the reader guessing whether a total across all Tables exists.

Partitioning is different from grouping: grouping creates sections under one Grand Total; partitioning creates several Tables with their own totals.

## Cache-policy decision

| Extension reads                                                                                                        | Policy                                        |
| ---------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| Only supplied rows, normalized lines, definition, locale, currency, and labels already covered by the core fingerprint | `STANDARD`                                    |
| Additional Quote or Quote Line fields that can all be listed                                                           | `DECLARED_DEPENDENCIES` plus every field path |
| Custom Metadata, custom settings, external data, time, user state, or other inputs that cannot be fully declared       | `ALWAYS_REBUILD`                              |

If uncertain, use `ALWAYS_REBUILD` until the dependency set is proven complete. Reuse is an optimization; a current document is the requirement.

## Required tests

Every new extension test suite must cover:

- expected output from representative inputs;
- empty and null inputs;
- row key and order uniqueness;
- allowed row types;
- visibility and total-inclusion flags;
- subtotal and grand-total reconciliation;
- translation behavior;
- permission and sharing behavior;
- extension failure and full generation rollback;
- unknown registry code or inactive Flow;
- cache-policy behavior;
- version-token change causing rebuild; and
- end-to-end generation and retrieval.

## Deployment and rollback

Deploy implementation, registry, tests, metadata, version tokens, and dependency policy together.

After an output-changing release:

```apex
Database.executeBatch(new QuoteDocumentInvalidationJob(), 200);
```

Review **Setup → Apex Jobs**, regenerate representative Quotes, and compare generated records, reports, and final output.

To roll back, remove the Table Definition's Flow name or registered code, restore the prior configuration and version identity, invalidate affected Ready Quotes, and generate again. Do not edit generated rows or bypass verification.
