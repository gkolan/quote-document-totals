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

## Recipe 3 — expand one line into several rows

Use when one quote line must become several document rows: a month, a year, a
milestone, a delivery. Grouping cannot express this — grouping puts each line in
exactly one bucket, expansion multiplies it.

**Most period cases need no code at all.** Set these on the table definition:

| Field | Value |
|---|---|
| `Expander_Code__c` | `PERIOD` |
| `Expander_Version__c` | `1` (bump whenever the expander's behaviour changes) |
| `Period_Months__c` | `1` monthly, `3` quarterly, `12` annual |
| `Allocation_Basis__c` | `EVEN` |
| `Period_One_Time_Placement__c` | `FIRST_PERIOD` (default), `EFFECTIVE_DATE`, or `SPREAD` |
| `Sort_Groups_By__c` | `EXPANSION_ORDER` — without it "Month 10" prints before "Month 2" |

Then add one `Quote_Document_Grouping__mdt` record with `Dimension__c = EXPANSION`.
Put it at level 1 for period-then-product, or level 2 for product-then-period; both
work, and that is the point of the design.

**For milestones, departments, phases or promotional periods, use `SCHEDULE`
instead** — also no code. The sections and their relative weights are authored
as `Quote_Document_Schedule__mdt` rows, and the definition names the schedule:

| Field | Value |
|---|---|
| `Expander_Code__c` | `SCHEDULE` |
| `Schedule_Code__c` | the code your schedule rows share |
| `Schedule_Divides_Quantity__c` | tick for a department or delivery split (different units per section); leave clear for a payment schedule (the same products covered by every instalment) |

Each schedule row carries a `Bucket_Code__c`, a `Label_Key__c` resolved from the
dictionary, an optional `Label_Arg_1__c` for a parameterised key, a `Weight__c`,
and a `Display_Order__c`. Weights are **relative**: 30/40/30 and 3/4/3 split
identically, and a weight of `0` is a genuinely free section that receives
exactly zero and never the rounding residual.

For a different axis again, implement `QuoteDocumentLineExpander` and register it:

```apex
public with sharing class MyDeliveryExpander implements QuoteDocumentLineExpander {

    public List<QuoteDocumentExpansion.Bucket> buckets(QuoteDocumentExpansion.Request request) {
        // Every bucket the table prints, in order, occupied or not.
        // Throw QuoteDocumentContributorError rather than guessing an axis.
    }

    public List<QuoteDocumentExpansion.Placement> placements(
        QuoteDocumentLine line, QuoteDocumentExpansion.Request request
    ) {
        // Which buckets this line occupies, and its RELATIVE weight in each.
        // Weight 1 everywhere is an even split. Weight 0 is a genuinely free
        // period - it receives exactly zero and never the rounding residual.
        // Returning an empty list for a counted line is an error: its money
        // would vanish from a table that still claimed to reconcile.
    }

    public Boolean dividesQuantity() {
        // TRUE where each bucket is a different set of physical things
        // (1,000 devices across three deliveries is 200/300/500).
        // FALSE where it is the same things present in every bucket
        // (100 licences in each of twelve months is 100, not 8.33).
        return true;
    }
}
```

Register it in `QuoteDocumentExpanderRegistry.resolve`, then name the code on the
definition. Allocation, reconciliation and ordering are handled for you.

**Three things the framework does on your behalf, so do not reimplement them:**
every allocated measure uses the same weights; each line's shares are checked
against its own value at zero tolerance before insert; and a repeated measure is
declared non-additive so its grand total is the peak bucket rather than the sum.

## Recipe 4 — a measure that must not be summed

A percentage, a blended rate, a peak or a running balance is wrong the moment it
is added up. Declare the rule on the column definition:

| `Aggregation_Rule__c` | Aggregate value |
|---|---|
| `SUM` | Default, and blank means this |
| `RATIO` | `Aggregation_Numerator__c` / `Aggregation_Denominator__c`, recomputed at every level |
| `MAX` | The largest contributing row |
| `SUM_THEN_MAX` | Sum within each group, then the largest group — peak active licences |
| `LAST` | The final row in display order — an ending balance |
| `NONE` | Blank on aggregate rows |

A 60% discount on \$1,000 beside a 10% discount on \$100,000 blends to 10.50%.
Summed it reads 70%; averaged, 35%. Only `RATIO` gets it right, and only because
it divides the aggregated numerator by the aggregated denominator rather than
combining the children's percentages.

Two ready-made fields exist for ratios — `Effective_Discount_Percent__c` and
`Blended_Unit_Price__c`. For anything else, add your own numeric field to
`Quote_Document_Row__c` and bind a column to it; that is additive and
upgrade-safe.

## Recipe 5 — a before-and-after table

Set `Comparison_Source_Code__c = SOURCE_QUOTE`, `Comparison_Source_Version__c`,
and `Measure_Set__c = CHANGE`. The baseline is the quote named by
`SBQQ__Source__c`, which CPQ populates on a revision; point elsewhere with
`Comparison_Source_Field__c`.

Each position produces exactly one row carrying `Amount_Baseline__c` (before),
`Amount_Final__c` (after) and `Amount_Net_Change__c` (the difference), with
`Transaction_Type__c` saying which of the four outcomes it is: `Net New`,
`Cancellation`, `Amended`, `Unchanged`. Unchanged positions are printed by
default — a customer scanning for what moved is entitled to see what did not.

For a different baseline, implement `QuoteDocumentComparisonSource`. Choose the
match key carefully: product alone pairs two lines that are really two positions
on different terms. Where the key is genuinely ambiguous the framework refuses
rather than guessing, because the difference column is the number a customer
trusts most.

## Recipe 6 — separate tables per scenario or entity

Set `Partition_Dimension__c` to any dimension a grouping accepts, and
`Cross_Partition_Total__c` to `NONE` or `SUM`. There is no default, on purpose:

- `NONE` for alternatives, scenarios and contingent amounts — things that are
  mutually exclusive. Summing them states a number the customer is not being
  asked to pay.
- `SUM` for departments and purchasing entities — complementary parts of one
  whole. Generation then checks that they actually add to the quote.

Each partition becomes its own `Quote_Document_Table__c`, with its own grand
total and its own three-segment `Table_Key__c`. At most nine partitions: table
order is a whole number and definitions are spaced by ten.

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

### Row production — expansion, allocation, aggregation, comparison, partitioning

| Code | Means |
|---|---|
| `EXPANSION_AXIS_UNRESOLVED` | A period table has no term to divide. Neither the quote nor any line carries usable dates — an axis guessed from nothing puts every product in a period nobody chose |
| `EXPANSION_WINDOW_INVALID` | A line ends before it starts. There is no set of periods to spread it over |
| `EXPANSION_LINE_OUTSIDE_AXIS` | A line runs entirely outside the term. Including it would leave the printed periods short of the quote total, and dropping it silently would do the same |
| `EXPANSION_TOO_MANY_BUCKETS` | More than 120 buckets. A data error, not a document |
| `EXPANSION_BUCKET_UNKNOWN` | An expander placed a line in a bucket it never published — a row in a section nobody would see |
| `ALLOCATION_WEIGHTS_INVALID` | Empty, all-zero, or negative weights. There is deliberately no "fall back to even": silently changing the basis is how a document becomes wrong without failing |
| `ALLOCATION_SOURCE_UNRECONCILED` | One line's allocated shares do not sum back to its own value, **at zero tolerance**. The table total can still reconcile while every printed row is wrong |
| `AGGREGATION_RULE_UNKNOWN` | An `Aggregation_Rule__c` that is not `SUM`, `RATIO`, `MAX`, `SUM_THEN_MAX`, `LAST` or `NONE`, or a `RATIO` missing an operand |
| `AGGREGATION_RULE_CYCLIC` | A `RATIO` whose numerator or denominator is its own field |
| `AGGREGATION_RESULT_UNVERIFIED` | An aggregate row disagrees with the rule that produced it. Non-additive measures are re-checked, never merely excused |
| `SUM_THEN_MAX_REQUIRES_EXPANSION` | A peak declared on a table with no expansion to peak across. Across product families that is not a peak of anything |
| `COMPARISON_MATCH_AMBIGUOUS` | Two lines on one side share a match key. Pairing one arbitrarily prints a confidently wrong difference |
| `COMPARISON_MATCH_KEY_BLANK` | A position with no identity can only ever appear as both added and removed |
| `COMPARISON_MEASURE_SET_UNSUPPORTED` | A comparison on the price waterfall. Every difference would be silently zero |
| `ENRICHMENT_SOURCE_MISSING` | The baseline could not be read, or the source lookup is blank. An empty baseline prints "everything is new" — a confident statement built on a missing input |
| `PARTITION_TOTAL_UNRECONCILED` | A `SUM` partition set does not add to the quote. A line reached no partition, or reached two |
| `PARTITION_NOT_FOUND` | A partition was requested from a snapshot that has none by that name. Returning the remainder would hand a signer a document with their own products missing |
| `SCENARIO_ASSUMPTIONS_MISSING` | A table that states estimates requires a narrative block that no active content supplies for this locale |
| `SCHEDULE_CODE_UNDECLARED` / `SCHEDULE_NOT_FOUND` | A `SCHEDULE` table names no schedule, or one with no active rows |
| `SCHEDULE_WEIGHTS_INVALID` | Every weight in a schedule is zero — there is nowhere for the money to land |
| `SCHEDULE_LABEL_ARGUMENT_MISSING` | A schedule section uses a parameterised dictionary key with no `Label_Arg_1__c`, so every section would print and key identically |

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
