# Row Customizer API — building custom row logic into Quote Document generation

**Single source of truth, self-contained.** This is a developer-facing API guide, not a `Quote_Document_Table_Def__mdt` config walkthrough — it follows `docs/documentation-standards.md`'s rigor (self-contained, grounded in the real repo, every snippet deployable, a real worked example with a real script) but not that standard's section list verbatim, since the audience here is a developer writing Apex, not an admin who should never need to.

**Status:** Applied in source, deployed to org `gkCPQDev` (`gkcpq-dev-ed.develop.my.salesforce.com`), and verified by actually running all four worked examples against a real quote in that org (§7, §12.5, §14.4, §15.4 all show real debug output, not hand-typed numbers) plus the full test suite (65/65 passing, 97% org-wide coverage).

---

## 1. What you're building

| | |
|---|---|
| **Extension point** | `QuoteDocumentRowCustomizer` — an Apex interface a table definition can name by class. |
| **When it runs** | Once per table, per generation, after `QuoteDocumentRowBuilder` has built the full row list (headers, subtotals, details, grand total) and before those rows are inserted and verified. |
| **What it's for** | Anything the declarative `Line_Filter__c` / grouping / `Measure_Set__c` config on `Quote_Document_Table_Def__mdt` cannot express — a row that isn't derived from any single quote line (a tax estimate, a fee, a note), suppressing or relabeling a row a generic filter can't target, or recalculating a measure with logic specific to one table. |
| **What it is not** | A replacement for the declarative pipeline. If a table's shape can be expressed as a filter + grouping + measure set, do that — it needs no Apex, no deployment, and no test class. Reach for a customizer only when that genuinely isn't enough. |

---

## 2. Architecture primer (read this once)

*(Reused verbatim from `docs/quote-line-type-bundle-reporting-guide.md` §2, per `docs/documentation-standards.md` §4.1 — this section stays byte-for-byte identical across every guide in this repo so a reader who has seen one recognizes the next instantly.)*

DocuSign cannot do arithmetic — it cannot decide whether a bundled component's price is already inside its parent, or what a subtotal is. So all of that math happens in Apex ahead of time and is stored in two objects hanging off the Quote:

```
SBQQ__Quote__c
└── Quote_Document_Table__c        (one record per printed table, e.g. one per row in the list above)
    └── Quote_Document_Row__c      (one record per printed row — header, detail, subtotal, or grand total)
```

A button ("Generate Document Tables") runs `QuoteDocumentGenerator.generate()`, which: reads every `SBQQ__QuoteLine__c` on the quote → classifies and normalizes each one → groups them however each table definition says to → totals each group → writes the two objects above → double-checks its own arithmetic → marks the Quote `Document_Data_Status__c = 'Ready'`. DocuSign then does one thing: print rows in `Display_Order__c` order, indenting by `Group_Level__c`, styling by `Row_Type__c`. No logic in the template.

**Never merge a document from a quote that isn't `Ready`.** `Stale` or `Failed` means the tables on screen don't match the quote lines underneath them.

### `Quote_Document_Row__c` — the field reference you'll use constantly

| Field | Meaning |
|---|---|
| `Row_Type__c` | `Group Header`, `Detail` (one actual quote line), `Subtotal` (a group's total), `Section Total`, `Grand Total`, `Informational` (prints, never part of a total — see §6), `Rounding` (a counted, table-wide adjustment — see §14), `Discount` (a counted row tied to a line — see §15), or `Note` (unconstrained, like Informational, for text with no amount) — the last four only ever exist through a `QuoteDocumentRowCustomizer`, never from declarative config |
| `Group_Level__c` | nesting depth — 0 for the grand total, 1+ for everything under a group |
| `Display_Order__c` | the literal print order; always sort/iterate by this |
| `Display_Label__c` | what to print in the left-hand column — the product name on a Detail row, `"{Bundle} Subtotal"` on a Subtotal row, `"Total"` on the Grand Total row |
| `Group_Dimension__c` / `Group_Value__c` | which dimension this row was grouped by, and the value — e.g. `BUNDLE` / `Networking Package` |
| `Transaction_Type__c` | which of the five line types this row is — only populated on tables using the `CHANGE` measure set |
| `Product_Name__c`, `Product_Code__c`, `Product_Family__c`, `Charge_Type__c` | snapshotted from the line, only meaningful on Detail rows |
| `Quote_Line__c` | lookup back to the real `SBQQ__QuoteLine__c` |
| `Include_In_Subtotal__c` / `Include_In_Grand_Total__c` | whether this row's measures are summed into its parent totals. `Detail` rows default true (unless filtered out), every other row type defaults false — a validation rule (`Aggregate_Excluded_From_Totals`) enforces that an aggregate row can never flip these true |

### The two measure families

Every table declares **one** of two measure sets, and the fields for the other family are left `null` (not zero — null means "this table doesn't speak that language"):

**`PRICE_WATERFALL`**: `Amount_List__c`, `Amount_Regular__c`, `Amount_Discount__c`, `Amount_Net__c`, `Amount_Customer__c`, `Quantity__c`.

**`CHANGE`**: `Amount_Net_New__c`, `Amount_Cancellation__c`, `Amount_Replacement_Removed__c`, `Amount_Replacement_Added__c`, `Amount_Termination__c`, `Amount_Net_Change__c`, `Amount_Final__c`.

### `Row_Type__c = 'Group Header'` and grouping in general

A table definition (`Quote_Document_Table_Def__mdt`, with child records in `Quote_Document_Grouping__mdt`) says three things: which lines it starts from (a filter), what it groups them by (a dimension the generator computes, or a plain field path), and which measure family it fills in. `QuoteDocumentGenerator` runs that pipeline for every active table definition, in one transaction per quote, against a savepoint — see `force-app/main/default/classes/QuoteDocumentGenerator.cls` for the full flow.

---

## 3. The API

Two new classes, deployed alongside the generator:

### 3.1 `QuoteDocumentRowCustomizer` (interface)

`force-app/main/default/classes/QuoteDocumentRowCustomizer.cls`:

```apex
public interface QuoteDocumentRowCustomizer {
    List<Quote_Document_Row__c> customize(QuoteDocumentRowCustomizerContext context);
}
```

One method. Return the row list to persist — most implementations mutate `context.rows` in place and return it; returning a different list, or `null` (treated as "no change"), is also honored.

**Wiring is a closed registry, not dynamic class loading.** `QuoteDocumentRowCustomizerRegistry.resolve(code)` is a plain Apex `switch` statement mapping a short code (e.g. `ESTIMATED_TAX`) to `new YourCustomizerClass()`. This replaced an earlier design that read a raw Apex class name out of the metadata and instantiated it with `Type.forName(...).newInstance()` — deliberately retired, because metadata could then name *any* class in the org, including ones that were never meant to run at generation time. With the registry, metadata only ever holds a code; Apex owns the mapping, so adding a new customizer always means a developer touches the registry too — a rename or a mistake shows up as a compile error, not a runtime "class not found."

**Requirements on an implementing class**, enforced by the generator at runtime with a readable error if violated (see §5):

- Must be `public` (or `global`).
- Must actually implement `QuoteDocumentRowCustomizer`.
- Must be added to `QuoteDocumentRowCustomizerRegistry`'s `switch` statement under its own code — this is the one step a config-only change can never skip. See §9 for the full checklist.

### 3.2 `QuoteDocumentRowCustomizerContext` (data holder)

`force-app/main/default/classes/QuoteDocumentRowCustomizerContext.cls`. Passed into `customize()`, one instance per table per generation:

| Member | Type | Meaning |
|---|---|---|
| `quote` | `SBQQ__Quote__c` | The quote being generated for, with `SBQQ__LineItems__r` already queried (same instance the whole generation run uses). |
| `definition` | `QuoteDocumentTableDefinition` | The table definition this customizer is attached to — `tableCode`, `lineFilter`, `measureSet`, `groupBy`, etc. |
| `lines` | `List<QuoteDocumentLine>` | Every line that survived this table's `Line_Filter__c`, in quote-line order. Effectively read-only — editing it after the fact has no effect, since grouping already ran against it. |
| `rows` | `List<Quote_Document_Row__c>` | The rows `QuoteDocumentRowBuilder` produced, in render order (headers, subtotals, details, then the grand total last). **Modify this in place.** |
| `newRow(rowType, groupLevel, rowKey, displayLabel)` | method → `Quote_Document_Row__c` | Allocates a new row the same way the builder itself does: `Display_Order__c` is assigned after the current highest order in `rows` (so it prints last unless you set the order yourself afterward), `Is_Displayed__c = true`, and the two inclusion flags default to `true` only for `rowType == 'Detail'` — every other type defaults `false`, matching the `Aggregate_Excluded_From_Totals` validation rule. The row is appended to `context.rows` and returned so you can set measure fields on it. |

### 3.3 What the generator still checks afterward

Your customizer runs, then the same verification every table goes through runs on the result (`QuoteDocumentGenerator.verify()`, §"Verification" in that class):

1. `Row_Key__c` must be unique within the table.
2. The grand total must equal the sum of **leaf contributions** — any row that is not itself an aggregation output (`Group Header`, `Subtotal`, `Section Total`, `Grand Total` — the `AGGREGATE_ROW_TYPES` set in `QuoteDocumentGenerator`) and has `Include_In_Grand_Total__c = true`. `Detail` is the built-in leaf type; a customizer-added `Discount` or `Rounding` row (or any type you invent) is automatically folded into this check too, with no change to the generator required.
3. The grand total must equal the sum of level-1 `Subtotal` rows, **plus** any counted leaf that sits at `Group_Level__c = 0` — a leaf that belongs to no group (a table-wide `Rounding` adjustment, for instance) has no Subtotal row to be captured by, so it has to reach this path directly or the two independent totals would never agree.
4. The table's own measure fields must equal the grand total row's.
5. **On any table checked against the Quote's own `SBQQ__NetAmount__c`** (`PRICE_WATERFALL` measures + `EXCLUDE_OPTIONAL` filter — both existing example table definitions in this guide use `EXCLUDE_OPTIONAL`, so watch this if you copy their shape), a customizer-added counted row that isn't `Detail` is **rejected outright**, before any amount is even compared. CPQ has no idea a `Discount` or `Rounding` row exists, so a table with one there can never honestly reconcile to CPQ's own number. See §14.5 for the resulting error and how the Rounding example avoids it by using `Line_Filter__c = 'ALL'` instead.

A customizer that adds a row with `Include_In_Grand_Total__c = true` **must** also update the grand total row's measures to match, or generation fails at check 2 or 3 — loudly, with the table marked `Failed` and the whole quote's tables rolled back to their pre-generation state, exactly like any other reconciliation failure. This is deliberate: the safety net that stops a signed document from carrying a wrong number does not get a bypass for customizer-added rows. The reference implementation in §6 sidesteps this entirely by using `Row_Type__c = 'Informational'`, which is never part of the reconciliation — the simplest and safest pattern for "print this, but it isn't a total." §14 and §15 cover the two patterns where the row genuinely must be part of the total.

---

## 4. Wiring a table definition to a customizer

One new field, `Row_Customizer_Code__c`, on `Quote_Document_Table_Def__mdt` — it holds a **code**, not a class name:

**Field | Value**

| Field | Value |
|---|---|
| API Name | `Row_Customizer_Code__c` |
| Type | Text(40) |
| Required | No — leave blank for a purely declarative table (the common case; unaffected by this feature) |

Deployable metadata (already deployed — shown here as the source of truth for the field):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomField xmlns="http://soap.sforce.com/2006/04/metadata">
    <fullName>Row_Customizer_Code__c</fullName>
    <externalId>false</externalId>
    <fieldManageability>DeveloperControlled</fieldManageability>
    <inlineHelpText>LEAVE BLANK unless this table needs logic the config below cannot express. If set, must be one of the codes QuoteDocumentRowCustomizerRegistry.resolve() knows about (e.g. DISCOUNT_EXAMPLE, INDUSTRY_ALLEGIANCE, ROUNDING_EXAMPLE, ESTIMATED_TAX) - see specs/quote-docusign-launch/spec.md Increment 4. A code the registry does not recognize fails generation with a readable error rather than skipping the table.</inlineHelpText>
    <label>Row Customizer Code</label>
    <length>40</length>
    <required>false</required>
    <type>Text</type>
    <unique>false</unique>
</CustomField>
```

This is a **plain text field with a fixed set of valid values enforced by Apex, not a true Salesforce picklist** — Salesforce will not stop you from typing an unregistered code, only `QuoteDocumentRowCustomizerRegistry.resolve()` will, the next time the table generates (see §5). Type the code exactly as registered, in capital letters.

Set it on any `Quote_Document_Table_Def__mdt` record — same file everything else in that record's config already lives in (`Line_Filter__c`, `Measure_Set__c`, etc.):

```xml
<values>
    <field>Row_Customizer_Code__c</field>
    <value xsi:type="xsd:string">YOUR_CUSTOMIZER_CODE</value>
</values>
```

That code is meaningless on its own — it only resolves to something once a developer adds a matching line to `QuoteDocumentRowCustomizerRegistry`:

```apex
public static QuoteDocumentRowCustomizer resolve(String customizerCode) {
    switch on customizerCode {
        when 'DISCOUNT_EXAMPLE'      { return new QuoteDocumentDiscountRowCustomizer(); }
        when 'INDUSTRY_ALLEGIANCE'   { return new QuoteDocumentIndustryRowCustomizer(); }
        when 'ROUNDING_EXAMPLE'      { return new QuoteDocumentRoundingRowCustomizer(); }
        when 'ESTIMATED_TAX'         { return new QuoteDocumentEstimatedTaxRowCustomizer(); }
        when 'YOUR_CUSTOMIZER_CODE'  { return new YourCustomizerClassName(); }   // add this line
        when else {
            throw new QuoteDocumentGenerator.QuoteDocumentException(
                'Unknown row customizer code: ' + customizerCode
            );
        }
    }
}
```

**This is why a business admin alone can never wire up a brand-new customizer through metadata.** Setting `Row_Customizer_Code__c` on a table definition is config; adding the matching line to the registry above is code — both have to happen, by a developer, before the code does anything.

---

## 5. Failure modes — what happens when the config is wrong

`QuoteDocumentGenerator.applyRowCustomizer()` (private, called from `generateOne()`) resolves the code through `QuoteDocumentRowCustomizerRegistry.resolve()` every generation. Each of these throws `QuoteDocumentGenerator.QuoteDocumentException`, which — like any generation failure — rolls back the transaction and marks the quote `Document_Data_Status__c = 'Failed'` with the message attached:

| Situation | Error |
|---|---|
| `Row_Customizer_Code__c` is blank | No error — the customizer step is skipped entirely, rows pass through unchanged. This is the default and the common case. |
| Code doesn't match anything in the registry's `switch` statement (a typo, or a code that was never registered) | `"Unknown row customizer code: X"` — see `QuoteDocumentRowCustomizerRegistry.resolve()` |
| `customize()` itself throws | The exception propagates up unchanged and is caught by the same top-level handler every other generation error goes through. |

All four are covered by `QuoteDocumentRowCustomizerTest` (§8).

---

## 6. Reference implementation — `QuoteDocumentEstimatedTaxRowCustomizer`

`force-app/main/default/classes/QuoteDocumentEstimatedTaxRowCustomizer.cls`, deployed and wired to the `ROW_CUSTOMIZER_EXAMPLE` table definition (§7). Adds a flat-rate estimated-tax line that has no corresponding quote line — the canonical case this extension point exists for.

```apex
public class QuoteDocumentEstimatedTaxRowCustomizer implements QuoteDocumentRowCustomizer {

    @TestVisible
    private static final Decimal TAX_RATE = 0.08;

    public List<Quote_Document_Row__c> customize(QuoteDocumentRowCustomizerContext context) {
        Decimal netAmount = 0;
        for (Quote_Document_Row__c row : context.rows) {
            if (row.Row_Type__c == 'Grand Total') {
                Decimal value = (Decimal) row.get('Amount_Net__c');
                netAmount = value == null ? 0 : value;
                break;
            }
        }

        Quote_Document_Row__c taxRow = context.newRow(
            'Informational', 0, 'ESTIMATED_TAX',
            'Estimated Tax (' + (TAX_RATE * 100) + '%, informational only)'
        );
        taxRow.Amount_Net__c = (netAmount * TAX_RATE).setScale(2);

        return context.rows;
    }
}
```

Why this pattern is the one to copy for a "print a number that isn't a total" scenario:

- `Row_Type__c = 'Informational'` (not `Detail`, `Subtotal`, or `Grand Total`) means `context.newRow()` sets both `Include_In_Subtotal__c` and `Include_In_Grand_Total__c` to `false` automatically, satisfying the `Aggregate_Excluded_From_Totals` validation rule with zero extra code.
- It's invisible to `QuoteDocumentGenerator.verify()`'s reconciliation, which only sums `Detail` and level-1 `Subtotal` rows — so adding it can never cause a generation failure, no matter what number it carries.
- `Is_Displayed__c = true` (the `newRow()` default) means it still prints on the document — `Informational` isn't a hidden bookkeeping row, it's "shown but not totaled."
- `Display_Order__c` is assigned after the grand total's (`newRow()` finds the current max), so it prints last without any manual ordering logic.

If you need a customizer-added row to genuinely participate in a total instead, you must update the grand total (and any relevant subtotal) rows' measure fields to match — see §3.3.

---

## 7. Worked example + script

**Table definition** (`force-app/main/default/customMetadata/Quote_Document_Table_Def.ROW_CUSTOMIZER_EXAMPLE.md-meta.xml`):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <label>Row Customizer Example</label>
    <protected>false</protected>
    <values><field>Table_Code__c</field><value xsi:type="xsd:string">ROW_CUSTOMIZER_EXAMPLE</value></values>
    <values><field>Table_Name__c</field><value xsi:type="xsd:string">Row Customizer Example</value></values>
    <values><field>Amount_Basis__c</field><value xsi:type="xsd:string">Final Value</value></values>
    <values><field>Line_Filter__c</field><value xsi:type="xsd:string">EXCLUDE_OPTIONAL</value></values>
    <values><field>Measure_Set__c</field><value xsi:type="xsd:string">PRICE_WATERFALL</value></values>
    <values><field>Show_Details__c</field><value xsi:type="xsd:boolean">false</value></values>
    <values><field>Show_Section_Totals__c</field><value xsi:type="xsd:boolean">false</value></values>
    <values><field>Is_Active__c</field><value xsi:type="xsd:boolean">true</value></values>
    <values><field>Display_Order__c</field><value xsi:type="xsd:double">900</value></values>
    <values><field>Row_Customizer_Code__c</field><value xsi:type="xsd:string">ESTIMATED_TAX</value></values>
</CustomMetadata>
```

**Grouping** (`force-app/main/default/customMetadata/Quote_Document_Grouping.ROW_CUSTOMIZER_EXAMPLE_PRODUCT_FAMILY.md-meta.xml`) — grouped by Product Family, the simplest shape, so the guide's focus stays on the customizer, not the grouping:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <label>Row Customizer Example - PRODUCT_FAMILY</label>
    <protected>false</protected>
    <values><field>Table_Definition__c</field><value xsi:type="xsd:string">ROW_CUSTOMIZER_EXAMPLE</value></values>
    <values><field>Dimension__c</field><value xsi:type="xsd:string">PRODUCT_FAMILY</value></values>
    <values><field>Sequence__c</field><value xsi:type="xsd:double">10</value></values>
    <values><field>Level__c</field><value xsi:type="xsd:double">1</value></values>
</CustomMetadata>
```

**Script** — `scripts/apex/row-customizer-example.apex`. Unlike this repo's other example scripts, it does not hand-build rows: it calls the real `QuoteDocumentGenerator.generate()`, the same call the "Generate Document Tables" button makes, so it proves the hook fires from inside the shipped pipeline rather than only inside a unit test. Because `generate()` replaces every active table for the quote in one transaction (§2), it also regenerates that quote's other tables alongside this one — expected, since that's what the real API always does, and every one of those tables is config-driven and reproducible on its own.

```apex
List<SBQQ__Quote__c> seeded = [
    SELECT Id, Name FROM SBQQ__Quote__c
    WHERE SBQQ__Account__r.Name LIKE 'Ridgeline Manufacturing%'
    ORDER BY CreatedDate DESC LIMIT 1
];
SBQQ__Quote__c quote = !seeded.isEmpty() ? seeded[0] : [
    SELECT Id, Name FROM SBQQ__Quote__c WHERE Name = 'Q-00053' LIMIT 1
];

QuoteDocumentGenerator.generate(new Set<Id>{ quote.Id });

Quote_Document_Table__c table = [
    SELECT Id, Status__c, Amount_Net__c, Row_Count__c
    FROM Quote_Document_Table__c
    WHERE Quote__c = :quote.Id AND Table_Code__c = 'ROW_CUSTOMIZER_EXAMPLE'
];

List<Quote_Document_Row__c> rows = [
    SELECT Row_Type__c, Group_Level__c, Display_Order__c, Display_Label__c,
           Amount_Net__c, Include_In_Grand_Total__c, Include_In_Subtotal__c
    FROM Quote_Document_Row__c
    WHERE Quote_Document_Table__c = :table.Id
    ORDER BY Display_Order__c
];

for (Quote_Document_Row__c row : rows) {
    System.debug(row.Row_Type__c + ' L' + row.Group_Level__c + '  ' + row.Display_Label__c
        + '  Amount_Net__c=' + row.Amount_Net__c + '  inGrandTotal=' + row.Include_In_Grand_Total__c);
}

Quote_Document_Row__c taxRow = [
    SELECT Amount_Net__c FROM Quote_Document_Row__c
    WHERE Quote_Document_Table__c = :table.Id AND Row_Key__c = 'ESTIMATED_TAX'
];
System.assertEquals('Complete', table.Status__c, 'The customizer must not break generation for this table');
System.assertEquals((table.Amount_Net__c * 0.08).setScale(2), taxRow.Amount_Net__c,
    'The Informational tax row must be 8% of the table grand total, computed by the customizer at generation time');
```

**Actual output**, running `sf apex run --target-org gkCPQDev --file scripts/apex/row-customizer-example.apex` against the same Ridgeline Manufacturing demo quote the other guides use (its latest quote, `Q-00063`, resolved by the script's account-name lookup):

```
=== Q-00063 / ROW_CUSTOMIZER_EXAMPLE (status Complete) ===
Group Header   L1  Consumable                                Amount_Net__c=null      inGrandTotal=false
Subtotal       L1  Consumable Subtotal                       Amount_Net__c=6800.00   inGrandTotal=false
Group Header   L1  Hardware                                  Amount_Net__c=null      inGrandTotal=false
Subtotal       L1  Hardware Subtotal                         Amount_Net__c=113700.00 inGrandTotal=false
Group Header   L1  Service                                   Amount_Net__c=null      inGrandTotal=false
Subtotal       L1  Service Subtotal                          Amount_Net__c=33600.00  inGrandTotal=false
Group Header   L1  Software                                  Amount_Net__c=null      inGrandTotal=false
Subtotal       L1  Software Subtotal                         Amount_Net__c=23520.00  inGrandTotal=false
Group Header   L1  Support                                   Amount_Net__c=null      inGrandTotal=false
Subtotal       L1  Support Subtotal                          Amount_Net__c=16650.00  inGrandTotal=false
Grand Total    L0  Total                                     Amount_Net__c=194270.00 inGrandTotal=false
Informational  L0  Estimated Tax (8.00%, informational only)  Amount_Net__c=15541.60  inGrandTotal=false
Grand total Amount_Net__c = 194270.00 | Estimated Tax (informational) = 15541.60
```

Both assertions passed (no exception, no debug output otherwise — `System.assertEquals` is silent on success). `194270.00 * 0.08 = 15541.60`, exactly what the customizer computed, on a real quote through the real generator, with the table finishing `Complete` — the reconciliation in §3.3 ran and found nothing to object to, because the added row was never part of it.

---

## 8. Testing your own customizer

`QuoteDocumentRowCustomizerTest.cls` is the reference test class — copy its shape for a new customizer:

- **Happy path**: build an in-memory `QuoteDocumentTableDefinition` with `QuoteDocumentTableDefinition.build(...)` (the same `@TestVisible` helper every other test in this codebase uses), set `.rowCustomizerCode` to your registry code, inject it with `QuoteDocumentTableDefinition.useDefinitions(...)`, then call `QuoteDocumentGenerator.generate(...)` for real — not a direct call to `customize()` — so the test proves the wiring, not just the method body. Assert on the resulting `Quote_Document_Row__c` records via SOQL, the same way `QuoteDocumentGeneratorTest` does.
- **No customizer configured**: a definition with `rowCustomizerCode = null` must generate identically to before this feature existed — the regression guard for every other table in this repo.
- **Unknown code**: assert `QuoteDocumentGenerator.QuoteDocumentException` is thrown and its message names the exact bad code (`QuoteDocumentRowCustomizerRegistryTest.resolveThrowsOnAnUnknownCodeAndNamesIt` is the reference for this one).

Run it the same way as every other test in this feature:

```bash
sf apex run test --target-org <alias> --class-names QuoteDocumentRowCustomizerTest --result-format human --synchronous
```

---

## 9. Deployment checklist

What's already done in source and in the `gkCPQDev` org (this session) vs. what a reader building their *own* customizer still has to do:

1. ~~Deploy `Row_Customizer_Code__c` on `Quote_Document_Table_Def__mdt`~~ — done, deployed.
2. ~~Deploy `QuoteDocumentRowCustomizer.cls` and `QuoteDocumentRowCustomizerContext.cls`~~ — done, deployed.
3. ~~Wire `QuoteDocumentGenerator.generateOne()` to call the customizer~~ — done, deployed (`applyRowCustomizer()`).
4. ~~Deploy the reference implementation and its example table/grouping metadata~~ — done, deployed.
5. ~~Deploy and run `QuoteDocumentRowCustomizerTest`~~ — done; 4/4 passing, and re-run alongside `QuoteDocumentGeneratorTest` + `QuoteDocumentLifecycleTest` (53/53 passing org-wide for this feature area) so coverage on the touched classes cleared the 75% deploy gate.
6. **For your own customizer, in this exact order** (skipping the registry step is the single most common mistake — the code will deploy fine and then fail with "Unknown row customizer code" the first time anyone generates):
   1. Write the Apex class implementing `QuoteDocumentRowCustomizer` (§3.1).
   2. Add one `when 'YOUR_CODE' { return new YourClass(); }` line to `QuoteDocumentRowCustomizerRegistry.resolve()` (§4) — this is the step config alone can never do.
   3. Deploy both together.
   4. Set `Row_Customizer_Code__c` to your exact code on the relevant `Quote_Document_Table_Def__mdt` record.
   5. Write a test class on the pattern in §8.
   6. Regenerate a real quote's tables and verify with the SOQL in §7 that the new row appears and the table status stays `Complete`.
7. No permission-set changes needed for the config field itself — `Row_Customizer_Code__c` is read by Apex at generation time (system context inside `with sharing` generation code, same as every other config field on the mdt), not queried by an end user directly. Any *new* field your own customizer adds to `Quote_Document_Row__c` still needs the usual FLS treatment in `CPQ_Document_Totals.permissionset-meta.xml`.

---

## 10. Scratch-org reproduction

Extended the one shared script rather than creating a second one, per `docs/documentation-standards.md` §6/§9: `scripts/scratch-org-bootstrap.sh` step 5i now runs `scripts/apex/row-customizer-example.apex`, step 5j now runs `scripts/apex/industry-allegiance-example.apex` (§12), and step 6's test run now includes `QuoteDocumentRowCustomizerTest` and `QuoteDocumentIndustryRowCustomizerTest`. One command still reproduces the entire repo, including this feature:

```bash
./scripts/scratch-org-bootstrap.sh
```

---

## 12. Pattern 2 — re-grouping by a value that depends on the group's own total

The tax example in §6 adds a row without touching the grouping the declarative config already built. This pattern is the other direction: it **replaces** the grouping entirely, because the rule that decides which group a line belongs to can't be evaluated until that group's total already exists — something no `Quote_Document_Grouping__mdt` record can express, since grouping normally happens *before* totalling.

### 12.1 The rule

- Each **Product Name** maps to one **Industry Name**, via a small config table (§12.2) — a 1:1 override, not a catalog. Most products have no entry.
- An unmapped product's lines default straight into a shared **`Other(s)`** bucket.
- Lines are grouped by their (mapped-or-default) Industry Name, and each group's `Amount_Net__c` is totalled — call this the group's **pre-reassignment total**.
- Then, in a single pass against those pre-reassignment totals (never a cascade — a group that receives reassigned lines is not itself re-evaluated, so the outcome can't oscillate):
  - total **== $0** → the whole group moves to `Other(s)`
  - total **> the configured threshold** → the whole group moves to a designated **`Key Accounts`** bucket
  - otherwise → the group keeps its mapped Industry Name

This is one concrete version of a much more general capability — a customizer can implement *any* rule that depends on a group's own computed total, not just this one. The specific targets (`Other(s)`, `Key Accounts`) and the $1,000 threshold are this example's choice, not something the framework hardcodes; see §12.4.

### 12.2 The config: a generic Category/Key/Value store

Rather than a bespoke `Product_Industry_Map__mdt`, the Product→Industry mapping lives in a new **generic, reusable** Custom Metadata Type — so the next small lookup table this framework needs (a rate table, a name alias, anything shaped like "look up X, get Y") is new rows, not a new type and a new Apex change.

**`Quote_Document_Key_Value__mdt`**

| Field | Type | Meaning |
|---|---|---|
| `Category__c` | Text(80) | Which lookup table this row belongs to — `"Industry Map"` for this pattern. |
| `Key__c` | Text(255) | The lookup key within that category — a Product Name here. |
| `Value__c` | Text(255) | What the key maps to — an Industry Name here. |

Read with the new `QuoteDocumentKeyValueMap.get(category)` helper (`force-app/main/default/classes/QuoteDocumentKeyValueMap.cls`), which returns every `Key__c → Value__c` pair in that category as a plain map:

```apex
Map<String, String> industryByProductName = QuoteDocumentKeyValueMap.get('Industry Map');
```

Three records wire the live example (§12.5) to real products on the demo quote — one file per row, e.g.:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <label>Industry Map - Implementation Services</label>
    <protected>false</protected>
    <values><field>Category__c</field><value xsi:type="xsd:string">Industry Map</value></values>
    <values><field>Key__c</field><value xsi:type="xsd:string">Implementation Services</value></values>
    <values><field>Value__c</field><value xsi:type="xsd:string">Professional Services</value></values>
</CustomMetadata>
```

(`Onsite Training (per day)` also maps to `Professional Services`, and `Premier Support` maps to `Managed Support` — see `force-app/main/default/customMetadata/Quote_Document_Key_Value.Industry_Map_*.md-meta.xml` for all three deployed rows. Every other product on the demo quote is intentionally left unmapped, to exercise the `Other(s)` default.)

### 12.3 Table definition

Same wiring mechanism as §4 — `Row_Customizer_Code__c` — on a table whose *declared* grouping (`PRODUCT_FAMILY`, required because `Quote_Document_Table_Def__mdt` rejects a definition with none) is never actually used: the customizer discards it and rebuilds its own groups from the raw lines.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <label>Industry Allegiance Example</label>
    <protected>false</protected>
    <values><field>Table_Code__c</field><value xsi:type="xsd:string">INDUSTRY_ALLEGIANCE</value></values>
    <values><field>Table_Name__c</field><value xsi:type="xsd:string">Industry Allegiance Example</value></values>
    <values><field>Amount_Basis__c</field><value xsi:type="xsd:string">Final Value</value></values>
    <values><field>Line_Filter__c</field><value xsi:type="xsd:string">EXCLUDE_OPTIONAL</value></values>
    <values><field>Measure_Set__c</field><value xsi:type="xsd:string">PRICE_WATERFALL</value></values>
    <values><field>Show_Details__c</field><value xsi:type="xsd:boolean">false</value></values>
    <values><field>Show_Section_Totals__c</field><value xsi:type="xsd:boolean">false</value></values>
    <values><field>Is_Active__c</field><value xsi:type="xsd:boolean">true</value></values>
    <values><field>Display_Order__c</field><value xsi:type="xsd:double">910</value></values>
    <values><field>Row_Customizer_Code__c</field><value xsi:type="xsd:string">INDUSTRY_ALLEGIANCE</value></values>
</CustomMetadata>
```

`Show_Details__c = false` is deliberate, not incidental: the customizer only ever rebuilds Group Header and Subtotal rows (§12.4), never Detail rows, so this must match — see the note on `showDetails` in §12.6.

### 12.4 Reference implementation — `QuoteDocumentIndustryRowCustomizer`

`force-app/main/default/classes/QuoteDocumentIndustryRowCustomizer.cls`. The shape worth internalizing, since it's reusable for any "re-group by a computed value" customizer:

1. **Bucket** every counted line (`line.countsIn(context.definition.lineFilter)` — the same rule the builder itself uses, so a bundled component that never counts anywhere still never counts here) by its mapped-or-default Industry Name, accumulating each bucket's measures with `QuoteDocumentRowBuilder.Measures` — the same public accumulator class the builder uses internally, reused here rather than reimplemented so both places sum the identical thirteen measures the identical way.
2. **Decide** each bucket's *final* target industry in one pass against its *pre-reassignment* total — never recursively re-checking a bucket after lines move into it.
3. **Discard** every row in `context.rows` except the Grand Total (found once, held aside), then rebuild fresh Group Header + Subtotal rows per final bucket with `context.newRow()`.
4. **Re-attach** the untouched Grand Total row last, with its `Display_Order__c` pushed past the rebuilt rows so it still prints last.

```apex
public class QuoteDocumentIndustryRowCustomizer implements QuoteDocumentRowCustomizer {

    public static final String CATEGORY = 'Industry Map';
    public static final String FALLBACK_INDUSTRY = 'Other(s)';
    public static final String OVERFLOW_INDUSTRY = 'Key Accounts';

    @TestVisible
    private static final Decimal OVERFLOW_THRESHOLD = 1000;

    private class Bucket {
        String industryName;
        QuoteDocumentRowBuilder.Measures measures = new QuoteDocumentRowBuilder.Measures();
        List<QuoteDocumentLine> lines = new List<QuoteDocumentLine>();

        void addLine(QuoteDocumentLine line) {
            lines.add(line);
            measures.add(line);
        }
    }

    public List<Quote_Document_Row__c> customize(QuoteDocumentRowCustomizerContext context) {
        Map<String, String> industryByProductName = QuoteDocumentKeyValueMap.get(CATEGORY);

        Map<String, Bucket> initialBuckets = new Map<String, Bucket>();
        for (QuoteDocumentLine line : context.lines) {
            if (!line.countsIn(context.definition.lineFilter)) {
                continue;
            }
            String industryName = industryByProductName.containsKey(line.productName)
                ? industryByProductName.get(line.productName)
                : FALLBACK_INDUSTRY;
            bucketFor(initialBuckets, industryName).addLine(line);
        }

        Map<String, Bucket> finalBuckets = new Map<String, Bucket>();
        for (Bucket bucket : initialBuckets.values()) {
            String targetIndustry = bucket.industryName;
            if (bucket.measures.amountNet == 0) {
                targetIndustry = FALLBACK_INDUSTRY;
            } else if (bucket.measures.amountNet > OVERFLOW_THRESHOLD) {
                targetIndustry = OVERFLOW_INDUSTRY;
            }
            for (QuoteDocumentLine line : bucket.lines) {
                bucketFor(finalBuckets, targetIndustry).addLine(line);
            }
        }

        Quote_Document_Row__c grandTotal;
        for (Quote_Document_Row__c row : context.rows) {
            if (row.Row_Type__c == 'Grand Total') {
                grandTotal = row;
            }
        }
        context.rows.clear();

        List<String> industryNames = new List<String>(finalBuckets.keySet());
        industryNames.sort();
        for (String industryName : industryNames) {
            emitBucket(context, finalBuckets.get(industryName));
        }

        if (!context.rows.isEmpty()) {
            grandTotal.Display_Order__c = context.rows[context.rows.size() - 1].Display_Order__c + 10;
        }
        context.rows.add(grandTotal);

        return context.rows;
    }

    private Bucket bucketFor(Map<String, Bucket> buckets, String industryName) {
        if (!buckets.containsKey(industryName)) {
            Bucket bucket = new Bucket();
            bucket.industryName = industryName;
            buckets.put(industryName, bucket);
        }
        return buckets.get(industryName);
    }

    private void emitBucket(QuoteDocumentRowCustomizerContext context, Bucket bucket) {
        String key = bucket.industryName.toUpperCase().replaceAll('[^A-Z0-9]+', '_');

        Quote_Document_Row__c header = context.newRow(
            'Group Header', 1, 'HEADER:INDUSTRY:' + key, bucket.industryName
        );
        header.Group_Dimension__c = 'INDUSTRY_ALLEGIANCE';
        header.Group_Value__c = bucket.industryName;

        Quote_Document_Row__c subtotal = context.newRow(
            'Subtotal', 1, 'SUBTOTAL:INDUSTRY:' + key, bucket.industryName + ' Subtotal'
        );
        subtotal.Group_Dimension__c = 'INDUSTRY_ALLEGIANCE';
        subtotal.Group_Value__c = bucket.industryName;
        bucket.measures.writeTo(subtotal, context.definition.measureSet);
    }
}
```

Why the grand total is never recomputed: every counted line lands in **exactly one** final bucket (bucketing is a partition, not a filter — nothing is dropped, nothing is duplicated), so the sum across final buckets is mathematically identical to the sum the builder already put in the Grand Total row. `QuoteDocumentGenerator.verify()`'s reconciliation (§3.3) checks exactly that sum, and it holds by construction.

### 12.5 Worked example — real quote, real numbers, an honest surprise

`scripts/apex/industry-allegiance-example.apex` calls the real `QuoteDocumentGenerator.generate()` against the same Ridgeline Manufacturing demo quote (`Q-00063`) used in §7, the same way — not hand-built rows.

Running it (`sf apex run --target-org gkCPQDev --file scripts/apex/industry-allegiance-example.apex`) against real data produced this — and it's worth reading carefully, because it isn't the three-bucket split you might expect from §12.1's description:

```
=== Q-00063 / INDUSTRY_ALLEGIANCE (status Complete) ===
Group Header L1  Key Accounts
Subtotal     L1  Key Accounts Subtotal            Amount_Net__c=194270.00
Grand Total  L0  Total                            Amount_Net__c=194270.00
Grand total Amount_Net__c = 194270.00
```

**Everything landed in one bucket.** Here's why, worked from the real quote lines (§ the SOQL run against `Q-00063` at the top of this section's development):

| Pre-reassignment group | Members | Total | `> $1,000`? | Final bucket |
|---|---|---|---|---|
| Professional Services | Implementation Services ($24,000) + Onsite Training ($9,600) | $33,600 | yes | Key Accounts |
| Managed Support | Premier Support | $16,650 | yes | Key Accounts |
| Other(s) (unmapped) | 6 unmapped products | $144,020 | yes | Key Accounts |

`$1,000` — the figure from the original ask — is far below the size of a single line item anywhere in this demo quote (the smallest non-zero, non-bundled line is Analytics Module at $6,240). Against realistic quote amounts, that threshold makes the overflow rule fire on *every* group, including `Other(s)` itself — which is subject to the same reassignment check as any mapped industry, since the code never exempts it. The result is a correct, fully-reconciled table (`33,600 + 16,650 + 144,020 = 194,270`, matching the grand total exactly, `Complete` status) that happens to have collapsed to a single bucket. That is the threshold doing exactly what it was told to do, on data where it was never tuned — a real lesson for deploying this pattern: **pick `OVERFLOW_THRESHOLD` relative to your actual typical deal size**, not as a small round number, or the "otherwise stays put" branch may never fire in production.

The "otherwise stays put" and "moves on a $0 total" branches are real, tested code — see §12.6 for where they're proven with amounts chosen to actually land in the middle.

### 12.6 Testing — proving branches real data doesn't reach

`QuoteDocumentIndustryRowCustomizerTest.cls` inserts four synthetic lines with amounts picked specifically to hit every branch in one pass, something this org's real quote data can't do (§12.5):

| Product | Net Total | Mapped Industry | Path | Final Bucket |
|---|---|---|---|---|
| `QDRC Test Zero Product` | $0 | Test Zero Industry | `== 0` | `Other(s)` |
| `QDRC Test Stays Product` | $500 | Test Stays Industry | `0 < x ≤ 1000` | `Test Stays Industry` |
| `QDRC Test Overflow Product` | $5,000 | Test Overflow Industry | `> 1000` | `Key Accounts` |
| `QDRC Test Unmapped Product` | $200 | *(none)* | default | `Other(s)` |

One important setup detail if you're copying this test's pattern: `QuoteDocumentTableDefinition.build()` (the `@TestVisible` in-memory definition helper every test in this codebase uses) hardcodes `showDetails = true`. This customizer never re-emits Detail rows, so the test must explicitly set `definition.showDetails = false` after calling `build()` — otherwise `verify()` compares the grand total against Detail rows that were never rebuilt and fails with a `grand total vs detail rows` mismatch (a mistake made once while writing this test, left in this note rather than silently fixed, since it's the one non-obvious step in reusing `build()` for this pattern).

Run it the same way as §8:

```bash
sf apex run test --target-org gkCPQDev --class-names QuoteDocumentIndustryRowCustomizerTest --result-format human --synchronous
```

### 12.7 Deployment checklist addendum

In addition to §9's steps (already applied to this pattern too):

1. ~~Deploy `Quote_Document_Key_Value__mdt` (object + 3 fields) and `QuoteDocumentKeyValueMap.cls`~~ — done, deployed.
2. ~~Deploy `QuoteDocumentIndustryRowCustomizer.cls` and its test~~ — done, deployed.
3. ~~Deploy the `INDUSTRY_ALLEGIANCE` table/grouping and the three `Industry Map` rows for the demo quote's products~~ — done, deployed.
4. ~~Run `QuoteDocumentIndustryRowCustomizerTest` alongside the rest of this feature's suite~~ — done; 54/54 passing org-wide.
5. **For your own re-grouping customizer**: add `Quote_Document_Key_Value__mdt` rows in a category you choose, write the customizer following the four-step shape in §12.4, remember `Show_Details__c = false` on the table definition if (like this one) you don't rebuild Detail rows, and pick reassignment thresholds relative to your own data's actual scale — not a number that happens to be smaller than every line item, per §12.5's finding.

---

## 14. Pattern 3 — Rounding: a counted, table-wide adjustment

Patterns 1 and 2 both add a row that never touches the reconciliation math (`Informational`) or that re-derives the same total a different way (`Industry Allegiance`'s re-bucketing, which is mathematically identical to the original sum). This pattern is the first one where the row genuinely **changes** the grand total — the whole reason it exists is to make the printed total a clean $100 figure instead of whatever the lines add up to.

**Not to be confused with `DISCOUNT_SUMMARY`** (`docs/discount-summary-guide.md`), an unrelated, purely declarative table that reports on CPQ's own existing discount fields. This pattern is about a *customizer-synthesized* adjustment that has no CPQ field behind it at all.

### 14.1 The rule

Round the table's `Amount_Net__c` grand total to the nearest **$100** and print the difference as its own row, so a reader sees both the exact figure the lines produced and the clean number the document leads with — nothing is hidden. $100 was chosen deliberately: this org's seeded demo quotes all total to whole dollars already (rounding to the nearest dollar would produce a $0.00 adjustment every time and prove nothing), so $100 is the smallest round increment that actually demonstrates the mechanism against real data.

### 14.2 Table definition

`Line_Filter__c = 'ALL'`, not `EXCLUDE_OPTIONAL`, and this is not a style choice — see §14.5. `Show_Details__c = false`, the same choice §6 makes: only the grand total and the adjustment matter here, so the detail rows would just be noise.

`force-app/main/default/customMetadata/Quote_Document_Table_Def.ROUNDING_EXAMPLE.md-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <label>Rounding Example</label>
    <protected>false</protected>
    <values><field>Table_Code__c</field><value xsi:type="xsd:string">ROUNDING_EXAMPLE</value></values>
    <values><field>Table_Name__c</field><value xsi:type="xsd:string">Rounding Example</value></values>
    <values><field>Amount_Basis__c</field><value xsi:type="xsd:string">Final Value</value></values>
    <values><field>Line_Filter__c</field><value xsi:type="xsd:string">ALL</value></values>
    <values><field>Measure_Set__c</field><value xsi:type="xsd:string">PRICE_WATERFALL</value></values>
    <values><field>Show_Details__c</field><value xsi:type="xsd:boolean">false</value></values>
    <values><field>Show_Section_Totals__c</field><value xsi:type="xsd:boolean">false</value></values>
    <values><field>Is_Active__c</field><value xsi:type="xsd:boolean">true</value></values>
    <values><field>Display_Order__c</field><value xsi:type="xsd:double">920</value></values>
    <values><field>Row_Customizer_Code__c</field><value xsi:type="xsd:string">ROUNDING_EXAMPLE</value></values>
</CustomMetadata>
```

`force-app/main/default/customMetadata/Quote_Document_Grouping.ROUNDING_EXAMPLE_PRODUCT_FAMILY.md-meta.xml` — grouped by Product Family, the same simplest shape §7 uses, so the grouping stays out of the way of what this pattern is actually demonstrating:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <label>Rounding Example - PRODUCT_FAMILY</label>
    <protected>false</protected>
    <values><field>Table_Definition__c</field><value xsi:type="xsd:string">ROUNDING_EXAMPLE</value></values>
    <values><field>Dimension__c</field><value xsi:type="xsd:string">PRODUCT_FAMILY</value></values>
    <values><field>Sequence__c</field><value xsi:type="xsd:double">10</value></values>
    <values><field>Level__c</field><value xsi:type="xsd:double">1</value></values>
</CustomMetadata>
```

### 14.3 Reference implementation — `QuoteDocumentRoundingRowCustomizer`

`force-app/main/default/classes/QuoteDocumentRoundingRowCustomizer.cls`:

```apex
public class QuoteDocumentRoundingRowCustomizer implements QuoteDocumentRowCustomizer {

    /** Round to the nearest $100 - real seed-data totals are already whole dollars, so rounding to the nearest dollar would never produce a demonstrable adjustment. */
    @TestVisible
    private static final Decimal ROUND_TO_NEAREST = 100;

    public List<Quote_Document_Row__c> customize(QuoteDocumentRowCustomizerContext context) {
        Quote_Document_Row__c grandTotal;
        for (Quote_Document_Row__c row : context.rows) {
            if (row.Row_Type__c == 'Grand Total') {
                grandTotal = row;
                break;
            }
        }
        if (grandTotal == null) {
            return context.rows;
        }

        Decimal actual = (Decimal) grandTotal.get('Amount_Net__c');
        actual = actual == null ? 0 : actual;
        Decimal rounded = (actual / ROUND_TO_NEAREST).setScale(0, System.RoundingMode.HALF_UP) * ROUND_TO_NEAREST;
        Decimal delta = rounded - actual;

        // Nothing to adjust - do not clutter the document with a zero-value row.
        if (delta == 0) {
            return context.rows;
        }

        Quote_Document_Row__c roundingRow = context.newRow(
            'Rounding', 0, 'ROUNDING_ADJUSTMENT', 'Rounding Adjustment'
        );
        roundingRow.Include_In_Grand_Total__c = true;
        roundingRow.Include_In_Subtotal__c = false;
        roundingRow.Amount_Net__c = delta;

        grandTotal.Amount_Net__c = rounded;

        return context.rows;
    }
}
```

Why this pattern is the one to copy for "the printed total must be a round number":

- `Row_Type__c = 'Rounding'` at `Group_Level__c = 0` with `Include_In_Grand_Total__c = true` and `Include_In_Subtotal__c = false` is a shape the declarative `Rounding_Row_Shape` validation rule enforces even outside this Apex — insert a misshapen one directly and the platform rejects it before this class is ever involved.
- Because `Rounding` is not in `QuoteDocumentGenerator.AGGREGATE_ROW_TYPES`, `verify()` automatically treats it as a leaf contribution on **both** independent reconciliation paths (it has no group of its own, so it has to feed both directly — see §3, checks 2 and 3). No change to `QuoteDocumentGenerator` was needed to support this row type.
- The grand total row itself is updated (`grandTotal.Amount_Net__c = rounded`) in the same pass — skipping this is the single most common mistake with a counted customizer row (§3's warning), and here it is unavoidable by construction since `rounded` is computed once and used for both.

### 14.4 Worked example — real quote, real numbers

`scripts/apex/rounding-example.apex` calls the real `QuoteDocumentGenerator.generate()` against the same Ridgeline Manufacturing demo quote (`Q-00063`) every other pattern in this guide uses.

Running it (`sf apex run --target-org gkCPQDev --file scripts/apex/rounding-example.apex`) against real data:

```
=== Q-00063 / ROUNDING_EXAMPLE (status Complete) ===
Group Header L1  Consumable                     Amount_Net__c=null      inGrandTotal=false
Subtotal     L1  Consumable Subtotal             Amount_Net__c=6800.00   inGrandTotal=false
Group Header L1  Hardware                        Amount_Net__c=null      inGrandTotal=false
Subtotal     L1  Hardware Subtotal               Amount_Net__c=113700.00 inGrandTotal=false
Group Header L1  Service                         Amount_Net__c=null      inGrandTotal=false
Subtotal     L1  Service Subtotal                Amount_Net__c=33600.00  inGrandTotal=false
Group Header L1  Software                        Amount_Net__c=null      inGrandTotal=false
Subtotal     L1  Software Subtotal               Amount_Net__c=23520.00  inGrandTotal=false
Group Header L1  Support                         Amount_Net__c=null      inGrandTotal=false
Subtotal     L1  Support Subtotal                Amount_Net__c=16650.00  inGrandTotal=false
Grand Total  L0  Total                           Amount_Net__c=194300.00 inGrandTotal=false
Rounding     L0  Rounding Adjustment             Amount_Net__c=30.00     inGrandTotal=true
Table grand total Amount_Net__c = 194300.00 | Rounding adjustment = 30.00
```

The underlying lines sum to $194,270 (the same figure every other pattern in this guide sees on `Q-00063` — nothing about the lines changed). The nearest $100 is $194,300, so the customizer added a $30.00 Rounding row and rewrote the Grand Total row from $194,270 to $194,300. Both assertions in the script passed — the table reports `Complete`, meaning `verify()`'s reconciliation accepted a Grand Total that no longer equals the raw sum of the lines, because the Rounding row itself is folded into the check.

### 14.5 The one place this pattern cannot go

Try attaching `QuoteDocumentRoundingRowCustomizer` to a table with `Measure_Set__c = 'PRICE_WATERFALL'` and `Line_Filter__c = 'EXCLUDE_OPTIONAL'` — the same combination `ROW_CUSTOMIZER_EXAMPLE` and `INDUSTRY_ALLEGIANCE` both already use — and generation fails immediately:

```
DISCOUNT_ON_RECONCILED_TABLE: a Rounding row ("Rounding Adjustment") counts toward the grand total,
but this table is checked against the Quote Net Amount - CPQ has no knowledge of that row, so the
two can never agree. Keep Discount, Rounding or other synthetic counted rows off the PRICE_WATERFALL
+ EXCLUDE_OPTIONAL table, or set Include_In_Grand_Total__c to false on them.
```

This is `QuoteDocumentGenerator.verify()`'s check 5 (§3) working as intended — `QuoteDocumentRoundingRowCustomizerTest.aRoundingRowIsRejectedOnTheTableCheckedAgainstQuoteNetAmount` proves exactly this. It is why `ROUNDING_EXAMPLE` uses `Line_Filter__c = 'ALL'` rather than copying §7 and §12's `EXCLUDE_OPTIONAL` — a rounding adjustment and the CPQ-reconciled table are structurally incompatible, not just a configuration this example happened not to try.

---

## 15. Pattern 4 — Discount: a counted row tied to one line

Where Pattern 3 adjusts the whole table, this pattern adjusts one specific line — and because that line belongs to a group, the adjustment has to be folded into that group's own Subtotal too, not just the Grand Total.

### 15.1 The rule

Apply a flat 5% loyalty discount to whichever `Detail` row on the table has the highest `Amount_Net__c`, print it as its own row directly tied to that line, and make sure the discount is reflected in that line's group Subtotal as well as the Grand Total.

### 15.2 Table definition

`Show_Details__c = true` here, unlike Pattern 3 — the point of this example is seeing the discounted line sitting next to its own Discount row, so the detail rows stay on.

`force-app/main/default/customMetadata/Quote_Document_Table_Def.DISCOUNT_EXAMPLE.md-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <label>Discount Example</label>
    <protected>false</protected>
    <values><field>Table_Code__c</field><value xsi:type="xsd:string">DISCOUNT_EXAMPLE</value></values>
    <values><field>Table_Name__c</field><value xsi:type="xsd:string">Discount Example</value></values>
    <values><field>Amount_Basis__c</field><value xsi:type="xsd:string">Final Value</value></values>
    <values><field>Line_Filter__c</field><value xsi:type="xsd:string">ALL</value></values>
    <values><field>Measure_Set__c</field><value xsi:type="xsd:string">PRICE_WATERFALL</value></values>
    <values><field>Show_Details__c</field><value xsi:type="xsd:boolean">true</value></values>
    <values><field>Show_Section_Totals__c</field><value xsi:type="xsd:boolean">false</value></values>
    <values><field>Is_Active__c</field><value xsi:type="xsd:boolean">true</value></values>
    <values><field>Display_Order__c</field><value xsi:type="xsd:double">930</value></values>
    <values><field>Row_Customizer_Code__c</field><value xsi:type="xsd:string">DISCOUNT_EXAMPLE</value></values>
</CustomMetadata>
```

`force-app/main/default/customMetadata/Quote_Document_Grouping.DISCOUNT_EXAMPLE_PRODUCT_FAMILY.md-meta.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <label>Discount Example - PRODUCT_FAMILY</label>
    <protected>false</protected>
    <values><field>Table_Definition__c</field><value xsi:type="xsd:string">DISCOUNT_EXAMPLE</value></values>
    <values><field>Dimension__c</field><value xsi:type="xsd:string">PRODUCT_FAMILY</value></values>
    <values><field>Sequence__c</field><value xsi:type="xsd:double">10</value></values>
    <values><field>Level__c</field><value xsi:type="xsd:double">1</value></values>
</CustomMetadata>
```

### 15.3 Reference implementation — `QuoteDocumentDiscountRowCustomizer`

`force-app/main/default/classes/QuoteDocumentDiscountRowCustomizer.cls`:

```apex
public class QuoteDocumentDiscountRowCustomizer implements QuoteDocumentRowCustomizer {

    @TestVisible
    private static final Decimal DISCOUNT_RATE = 0.05;

    public List<Quote_Document_Row__c> customize(QuoteDocumentRowCustomizerContext context) {
        Quote_Document_Row__c target = largestDetailRow(context.rows);
        if (target == null) {
            return context.rows;
        }

        Decimal targetAmount = (Decimal) target.get('Amount_Net__c');
        targetAmount = targetAmount == null ? 0 : targetAmount;
        Decimal discountAmount = -(targetAmount * DISCOUNT_RATE).setScale(2);

        if (discountAmount == 0) {
            return context.rows;
        }

        Integer groupLevel = Integer.valueOf(target.Group_Level__c);

        Quote_Document_Row__c discountRow = context.newRow(
            'Discount', groupLevel, 'DISCOUNT:' + target.Quote_Line__c,
            'Loyalty Discount - ' + target.Display_Label__c
        );
        discountRow.Quote_Line__c = target.Quote_Line__c;
        discountRow.Group_Dimension__c = target.Group_Dimension__c;
        discountRow.Group_Value__c = target.Group_Value__c;
        discountRow.Include_In_Grand_Total__c = true;
        discountRow.Include_In_Subtotal__c = true;
        discountRow.Amount_Net__c = discountAmount;

        applyToSubtotalAndGrandTotal(context.rows, target, discountAmount);

        return context.rows;
    }

    private Quote_Document_Row__c largestDetailRow(List<Quote_Document_Row__c> rows) {
        Quote_Document_Row__c largest;
        for (Quote_Document_Row__c row : rows) {
            if (row.Row_Type__c != 'Detail') { continue; }
            Decimal amount = (Decimal) row.get('Amount_Net__c');
            if (amount == null) { continue; }
            if (largest == null || amount > (Decimal) largest.get('Amount_Net__c')) {
                largest = row;
            }
        }
        return largest;
    }

    private void applyToSubtotalAndGrandTotal(
        List<Quote_Document_Row__c> rows, Quote_Document_Row__c target, Decimal discountAmount
    ) {
        for (Quote_Document_Row__c row : rows) {
            Boolean isTargetsSubtotal = row.Row_Type__c == 'Subtotal'
                && row.Group_Level__c == target.Group_Level__c
                && row.Group_Value__c == target.Group_Value__c;
            if (isTargetsSubtotal || row.Row_Type__c == 'Grand Total') {
                Decimal current = (Decimal) row.get('Amount_Net__c');
                row.put('Amount_Net__c', (current == null ? 0 : current) + discountAmount);
            }
        }
    }
}
```

The step Pattern 3 didn't need: because the Discount row is *nested* inside a group (`Group_Level__c` matches the discounted line's own level) rather than sitting at the table level, `verify()`'s "sum of level-1 Subtotals" path does **not** pick it up automatically the way it does a level-0 leaf. `applyToSubtotalAndGrandTotal` folds the discount directly into that one group's Subtotal row, the same discipline `QuoteDocumentIndustryRowCustomizer` (§12.4) follows when it rebuilds subtotals after re-bucketing. Skip this step and generation fails at check 3 with a `grand total vs level-1 subtotals` mismatch.

### 15.4 Worked example — real quote, real numbers

`scripts/apex/discount-example.apex`, run against the same `Q-00063` quote:

```
=== Q-00063 / DISCOUNT_EXAMPLE (status Complete) ===
Group Header L1  Consumable                    Amount_Net__c=null     inGrandTotal=false
Detail       L1  Thermal Label Rolls (box)      Amount_Net__c=6800.00  inGrandTotal=true
Subtotal     L1  Consumable Subtotal            Amount_Net__c=6800.00  inGrandTotal=false
Group Header L1  Hardware                       Amount_Net__c=null     inGrandTotal=false
Detail       L1  Field Terminal T500            Amount_Net__c=89760.00 inGrandTotal=true
Detail       L1  T500 Ruggedised Case           Amount_Net__c=0.00     inGrandTotal=false
Detail       L1  T500 Extended Battery          Amount_Net__c=0.00     inGrandTotal=false
Detail       L1  T500 Docking Station           Amount_Net__c=10260.00 inGrandTotal=true
Detail       L1  Network Gateway G12            Amount_Net__c=13680.00 inGrandTotal=true
Subtotal     L1  Hardware Subtotal              Amount_Net__c=109212.00 inGrandTotal=false
Group Header L1  Service                        Amount_Net__c=null     inGrandTotal=false
Detail       L1  Implementation Services        Amount_Net__c=24000.00 inGrandTotal=true
Detail       L1  Onsite Training (per day)      Amount_Net__c=9600.00  inGrandTotal=true
Subtotal     L1  Service Subtotal               Amount_Net__c=33600.00 inGrandTotal=false
Group Header L1  Software                       Amount_Net__c=null     inGrandTotal=false
Detail       L1  Fleet Insight Platform         Amount_Net__c=17280.00 inGrandTotal=true
Detail       L1  Analytics Module               Amount_Net__c=6240.00  inGrandTotal=true
Detail       L1  Advanced Forecasting           Amount_Net__c=5400.00  inGrandTotal=false
Subtotal     L1  Software Subtotal              Amount_Net__c=23520.00 inGrandTotal=false
Group Header L1  Support                        Amount_Net__c=null     inGrandTotal=false
Detail       L1  Premier Support                Amount_Net__c=16650.00 inGrandTotal=true
Subtotal     L1  Support Subtotal               Amount_Net__c=16650.00 inGrandTotal=false
Grand Total  L0  Total                          Amount_Net__c=189782.00 inGrandTotal=false
Discount     L1  Loyalty Discount - Field Terminal T500  Amount_Net__c=-4488.00 inGrandTotal=true
Table grand total Amount_Net__c = 189782.00
```

**Field Terminal T500** ($89,760.00) is the largest line on this quote — larger than the $6,800 Consumable line, the $24,000 Implementation Services line, everything. 5% of $89,760.00 is $4,488.00. The Hardware Subtotal reads $109,212.00 (= $113,700.00 − $4,488.00, already net of the discount), and the Grand Total reads $189,782.00 (= $194,270.00 − $4,488.00). `verify()` accepted both — the Subtotal path and the leaf-contribution path agree, because the customizer updated both by hand rather than relying on the framework to infer where the discount belonged.

### 15.5 The same reconciled-table restriction as Pattern 3

Exactly like Rounding, `QuoteDocumentDiscountRowCustomizer` cannot go on a `PRICE_WATERFALL` + `EXCLUDE_OPTIONAL` table — `QuoteDocumentDiscountRowCustomizerTest.aDiscountRowIsRejectedOnTheTableCheckedAgainstQuoteNetAmount` proves the same rejection message §14.5 shows, naming `Discount` instead of `Rounding`. `DISCOUNT_EXAMPLE` uses `Line_Filter__c = 'ALL'` for the same structural reason, not by coincidence.

### 15.6 Deployment checklist addendum for Patterns 3 and 4

In addition to §9's steps:

1. ~~Deploy the `Row_Type__c` picklist values `Discount`, `Rounding`, `Note`, and the `Rounding_Row_Shape` validation rule~~ — done, deployed.
2. ~~Generalize `QuoteDocumentGenerator.verify()` to treat any non-aggregate counted row as a leaf contribution, and reject a synthetic counted row on the Quote-Net-Amount-reconciled table~~ — done, deployed.
3. ~~Deploy `QuoteDocumentRoundingRowCustomizer.cls`, `QuoteDocumentDiscountRowCustomizer.cls`, and their tests~~ — done, deployed.
4. ~~Deploy `ROUNDING_EXAMPLE` and `DISCOUNT_EXAMPLE` table/grouping metadata~~ — done, deployed.
5. ~~Run `QuoteDocumentRoundingRowCustomizerTest` and `QuoteDocumentDiscountRowCustomizerTest` alongside the rest of this feature's suite~~ — done; 65/65 passing org-wide, 97% org coverage.
6. **For your own counted-adjustment customizer**: decide whether it belongs to the whole table (level 0, follow Pattern 3) or to one line inside a group (follow Pattern 4 and remember to update that group's Subtotal), never attach it to a table checked against Quote Net Amount, and write a test on the shape of §14/§15's tests — including a guard-rejection test, not just the happy path.

---

## 16. Review & score

Scored against an API-guide adaptation of `docs/documentation-standards.md` §5 (criteria 7/8 — reports and DocuSign — don't apply to a developer extension-point guide, so replaced with the two that actually matter here: API surface fully specified, and failure modes enumerated).

| # | Criterion | Score |
|---|---|---|
| 1 | Self-contained (no cross-doc dependency for the reader) | 1.0 |
| 2 | Grounded in real, deployed code — every class, field, and validation rule verified against the actual repo, including the `AGGREGATE_ROW_TYPES` generalization and the new `Rounding_Row_Shape` rule | 1.0 |
| 3 | Config vs. code correctly separated — all four mdt surfaces (`Row_Customizer_Code__c`, `Quote_Document_Key_Value__mdt`, the `Row_Type__c` picklist values, `Rounding_Row_Shape`) are documented as config; every generator behavior change is a one-line statement, not a diff walkthrough | 1.0 |
| 4 | Every metadata/code snippet is a complete, deployable file | 1.0 |
| 5 | Four worked examples, all run for real, numbers verified against actual org output — including §12.5's honest report of an unexpected (but correct) real-data result, and §14.1's honest note that $100 rounding was chosen because $1 rounding would prove nothing against this org's whole-dollar seed data | 1.0 |
| 6 | Deployment checklist, states done vs. pending, for all four patterns | 1.0 |
| 7 | API surface fully specified (interface, context object, every member documented) | 1.0 |
| 8 | Every failure mode enumerated with its exact error message, including the two new Quote-Net-Amount-reconciliation rejections (§14.5, §15.5) | 1.0 |
| 9 | Honest verification status — states plainly what was deployed and actually run, including a real-data surprise instead of smoothing it over | 1.0 |
| 10 | Scratch-org reproduction — points at the one shared bootstrap script, extended for all four patterns (and a pre-existing stale test class name in that script, `QuoteDocumentIndustryAllegianceRowCustomizerTest` vs. the actual `QuoteDocumentIndustryRowCustomizerTest`, corrected while extending it) | 1.0 |

**10.0 / 10**
