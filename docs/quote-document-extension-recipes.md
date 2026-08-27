# Extension recipes

Two copyable recipes for changing what a table's rows contain, plus the error codes they can raise.

Neither requires reading generator internals, and neither changes a core class. If you find yourself
editing `QuoteDocumentGenerator`, `QuoteDocumentRowBuilder`, `QuoteDocumentFingerprint`, or
`QuoteDocumentVerification` to make one of these work, stop — the seam is missing something, and adding
it there is the fix.

**Read this first:** [the render contract](quote-document-totals.md#the-render-contract).

---

## Before either recipe: contributors are trusted, not sandboxed

State this plainly, because a spec that overstates its guarantees is how those guarantees stop being
checked.

Core owns publication, validates what a contributor returns, and rolls the whole attempt back on
failure. Core **cannot** stop a contributor running its own SOQL, performing DML, enqueuing async work,
or making callouts. Apex offers no such sandbox and neither does Flow.

| Guarantee | Real? |
|---|---|
| Core alone writes the snapshot rows | yes — contributors receive an in-memory list |
| Publication follows verification | yes, as a lifecycle rule — trusted Apex could still issue its own `update` |
| Invalid contributor **output** is rejected | yes |
| The whole attempt rolls back on failure | yes, for DML in the same transaction |
| A contributor performs no DML, SOQL, or callouts | **no.** Not enforced, not enforceable |

---

## Recipe 1 — add your own Apex customizer

### 1. Write the class

```apex
public with sharing class MyOrgTaxRowCustomizer implements QuoteDocumentRowCustomizer {

    public List<Quote_Document_Row__c> customize(QuoteDocumentRowCustomizerContext context) {
        Decimal net = 0;
        for (Quote_Document_Row__c row : context.rows) {
            if (row.Include_In_Grand_Total__c == true && row.Amount_Net__c != null) {
                net += row.Amount_Net__c;
            }
        }

        // newRow() gives the same defaults the builder uses, so your row cannot
        // drift from the framework's idea of what a row is.
        Quote_Document_Row__c tax = context.newRow(
            'Informational', 0, 'ESTIMATED_TAX',
            context.labels.resolve('ESTIMATED_TAX')
        );
        tax.Label_Key__c = 'ESTIMATED_TAX';
        tax.Amount_Net__c = (net * 0.08).setScale(2);

        // Informational rows count toward nothing. Setting either inclusion
        // flag true would make verify() fold this into reconciliation, and the
        // table would stop matching the Quote's own Net Amount.
        tax.Include_In_Subtotal__c = false;
        tax.Include_In_Grand_Total__c = false;

        return context.rows;
    }
}
```

**Resolve every string from `context.labels`.** Do not concatenate English. A contributor is a
generation stage and is held to the same rule as core — a shipped customizer broke this once and had to
be fixed.

### 2. Register the code

One line in `QuoteDocumentRowCustomizerRegistry`:

```apex
when 'MY_ORG_TAX' { return new MyOrgTaxRowCustomizer(); }
```

The registry is closed on purpose. `Type.forName` on a free-text field was the earlier design and was
rejected: a rename then surfaced as a runtime "class not found" instead of a compile error.

### 3. Add the metadata

On the `Quote_Document_Table_Def__mdt` record for your table:

| Field | Value |
|---|---|
| `Row_Customizer_Code__c` | `MY_ORG_TAX` |
| `Row_Customizer_Version__c` | `1` |
| `Cache_Policy__c` | `STANDARD` |

**`Row_Customizer_Version__c` is content identity, not documentation.** Reuse is decided from a
fingerprint computed *before* customization runs, and that fingerprint hashes the customizer *code
string* — not the behaviour behind it. Deploy changed Apex without bumping this and quotes stay `Ready`
on a snapshot your new logic would never have produced. Bump it in the same deployment as the code, then
run the invalidation job.

`Cache_Policy__c` has no default, deliberately. Choose:

- **`STANDARD`** — reads only the quote and its lines.
- **`DECLARED_DEPENDENCIES`** — also reads the field paths in `Contributor_Dependency_Set__c`, which are
  hashed. Use this if you read an Account field, a custom object, anything outside the quote.
- **`ALWAYS_REBUILD`** — reads data it cannot enumerate. Note this skips reuse for the **whole quote**,
  not just your table.

Reading external data under `STANDARD` is prohibited, and core cannot detect it. It is a declaration you
are trusted to make honestly, and the failure mode is a confidently wrong document.

### 4. Test it locally

```apex
@IsTest
static void taxRowDoesNotMoveTheGrandTotal() {
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });

    Quote_Document_Row__c tax = [
        SELECT Amount_Net__c, Include_In_Grand_Total__c FROM Quote_Document_Row__c
        WHERE Row_Key__c = 'ESTIMATED_TAX' AND Quote_Document_Table__r.Quote__c = :quoteId
    ];
    Assert.isFalse(tax.Include_In_Grand_Total__c, 'An informational row counts toward nothing.');
}
```

### 5. Deploy and verify

```bash
sf project deploy start --source-dir force-app
```

```sql
SELECT Row_Key__c, Row_Type__c, Display_Label__c, Amount_Net__c, Include_In_Grand_Total__c
FROM Quote_Document_Row__c
WHERE Quote_Document_Table__r.Quote__c = :quoteId
ORDER BY Display_Order__c
```

### 6. Switch it off

Clear `Row_Customizer_Code__c`. No code change, no deployment of Apex. Bump the version token so
existing quotes regenerate.

---

## Recipe 2 — add your own autolaunched Flow customizer

No Apex at all.

### THE MISTAKE TO AVOID, FIRST

**A Flow loop variable is a COPY.** Editing it inside the loop changes nothing, the Flow reports
success, and your document comes out unchanged. This is the single most likely authoring error and it
fails *silently*.

Collect edited rows into a second collection and assign that back to `rows` at the end. Always.

### 1. Build the Flow

An autolaunched Flow with these variables — plain Salesforce types, no Apex-defined types, no JSON:

| Direction | Variable | Type |
|---|---|---|
| in **and** out | `rows` | record collection, `Quote_Document_Row__c` |
| in | `quoteId` | Text |
| in | `tableCode` | Text |
| in | `locale` | Text |
| in | `currencyIsoCode` | Text |

`rows` **must** be marked *Available for Output*. A Flow that returns nothing fails with
`CONTRIBUTOR_NO_OUTPUT` rather than being read as "unchanged" — because "unchanged" is almost never what
the author meant, and shipping a document missing every intended edit is worse than failing.

Copy [`QuoteDocumentSampleFlowContributor`](../force-app/main/default/flows/QuoteDocumentSampleFlowContributor.flow-meta.xml).
It renames the Grand Total and appends a Note row, and shows the collect-into-a-second-collection shape.

### 2. Add the metadata

| Field | Value |
|---|---|
| `Row_Customizer_Flow__c` | your Flow's API name |
| `Row_Customizer_Flow_Version__c` | `1` |
| `Cache_Policy__c` | as above |

Same rule as Apex: **editing a Flow does not change its API name**, so without bumping the version token
the fingerprint cannot see your change and quotes reuse a stale snapshot.

### 3. Order, when both exist

**Apex first, then Flow.** The Flow sees the Apex customizer's rows and can overwrite them; the Apex
customizer never sees the Flow's. Last writer wins on the same field of the same row — deliberately, so
a Flow can undo an Apex customizer without touching its code.

### 4. Switch it off

Clear `Row_Customizer_Flow__c`.

---

## Error codes

Every code below is a stable string. Grep for it; do not parse the message.

### Contributor output

| Code | Means |
|---|---|
| `CONTRIBUTOR_MULTIPLE_GRAND_TOTALS` | Two Grand Total rows. Reconciliation only ever checks the first, so the others would print unverified |
| `CONTRIBUTOR_DUPLICATE_DISPLAY_ORDER` | Two rows share an order, or one has none. Printed order would depend on query order |
| `ROW_ORDER_INVALID` | A **Detail** row prints below the Grand Total. Adjustment rows may; a line item may not |
| `CONTRIBUTOR_FOREIGN_TABLE` | A returned row already names a parent table |
| `ROW_MEASURE_MISMATCH` | A row sets a measure outside the table's measure set — it would be stored and silently ignored |
| `CONTRIBUTOR_RETURNED_PERSISTED_ROW` | A returned row carries an Id, so it is already saved and outside the rollback |

### Flow bridge

| Code | Means |
|---|---|
| `CONTRIBUTOR_NO_OUTPUT` | The Flow returned no `rows` collection. Usually the loop-variable-is-a-copy mistake |
| `CONTRIBUTOR_FLOW_FAULT` | The Flow faulted. Nothing was saved |
| `CONTRIBUTOR_FLOW_UNAVAILABLE` | Missing, inactive, or misnamed Flow |

### Configuration

| Code | Means |
|---|---|
| `CONTRIBUTOR_VERSION_UNDECLARED` | A contributor with no version token |
| `CONTRIBUTOR_DEPENDENCY_UNDECLARED` | Blank `Cache_Policy__c`, or `DECLARED_DEPENDENCIES` with nothing declared |
| `DEPENDENCY_UNREADABLE` | A declared dependency path does not resolve |
| `COLUMN_FIELD_UNKNOWN` | A column binds a field that is not on `Quote_Document_Row__c` |
| `COLUMN_TYPE_UNSUPPORTED` | A column binds a type no renderer can print — lookup, multi-select, rich text, encrypted, blob, compound |
| `COLUMN_TYPE_DECLARATION_MISMATCH` | `Data_Type__c` disagrees with the field's real type |
| `COLUMN_MEASURE_MISMATCH` | A column binds a measure from the other measure set |
| `LABEL_KEY_MISSING` | Required text with no dictionary entry |
| `LABEL_KEY_DUPLICATE` | One category defines a key twice |
| `LABEL_ARGUMENT_MISSING` | A template references `{0}` or `{1}` with nothing supplied |
| `LOCALE_UNSUPPORTED` | No dictionary for the requested locale. Never falls through to English |
| `BLOCK_BODY_MARKUP` | A narrative block contains a tag or merge-field syntax |
| `TABLE_TITLE_MISSING` / `TABLE_LOCALE_MISSING` | A table cannot be published incomplete |

### Retrieval

| Code | Means |
|---|---|
| `SNAPSHOT_NOT_READY` | The quote is not `Ready`; the status is named |
| `SNAPSHOT_MOVED` | Regenerated between launch and retrieval. Re-run generate-or-reuse; never retry with the old expectations |
| `LAUNCH_CONTRACT_BYPASSED` | Retrieval with no expectations — the launch contract was skipped |
| `PAYLOAD_INTEGRITY_MISMATCH` | The snapshot was edited after publication. Regenerate; never repair |
| `TABLE_NOT_COMPLETE` / `TABLE_ROW_COUNT_MISMATCH` | Rows belong to a generation that never finished |
| `COLUMN_VALUE_NOT_QUERIED` | A configured column's field was not selected. A null must mean "no value", never "nobody selected it" |

### Lifecycle

| Code | Means |
|---|---|
| `REQUEST_SUPERSEDED` | A taken-over attempt tried to publish after a newer one claimed the quote |
| `GENERATION_LOCK_TIMEOUT` | Lock not acquired. **No snapshot changed and no status moved** — nothing about the existing document is wrong |
