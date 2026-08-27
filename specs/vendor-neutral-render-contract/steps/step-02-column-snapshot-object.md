# Step 02 — Column snapshot object

**Status: PLANNED**
**Blocked by:** [step 01](step-01-table-presentation-fields.md)
**Blocks:** 03, 06, 07, 08

---

## 1. Goal

Every generated table states which columns it prints, in what order, bound to which field, with what data type and what heading — as records, not as template tags.

## 2. Why this step exists

Audit rows 2 and 3. Today the column set is whatever `<Value Select="..."/>` tags the template author dragged in, and the headings exist only inside a `.docx`. That is the single largest reason a second renderer is expensive: the column layout has to be rebuilt by hand and can silently diverge from the first.

## 3. Scope

1. New object `Quote_Document_Column__c`, master-detail to `Quote_Document_Table__c`:

   | Field | Type | Notes |
   |---|---|---|
   | `Column_Code__c` | Text(40) | Semantic key: `COL_LIST`, `COL_NET`, `COL_NET_CHANGE`, `COL_LABEL`. Never an English phrase. |
   | `Display_Label__c` | Text(255) | The printed heading, already localized. |
   | `Display_Order__c` | Number(3,0) | |
   | `Value_Field__c` | Text(80) | The `Quote_Document_Row__c` API name this column binds, e.g. `Amount_Net__c`. |
   | `Data_Type__c` | Picklist | `Currency`, `Number`, `Text`, `Percent`, `Date`, `DateTime`, `Boolean`. Tells the renderer how to format without inspecting values or the schema. Must agree with the bound field's real type — see scope item 6. |
   | `Is_Displayed__c` | Checkbox, default true | |

   Name field: AutoNumber `QDC-{0000000000}`, matching `Quote_Document_Row__c`.

2. New CMDT `Quote_Document_Column_Def__mdt`, child of the table definition by `Table_Definition__c`, with the same fields minus `Display_Label__c` (which resolves from `Column_Code__c` in step 03). Same reasoning as `Quote_Document_Grouping__mdt`: Custom Metadata has no ordered list, so ordering needs a child record with a sequence.
3. Default when a table definition declares no columns: emit one `COL_LABEL` column plus one column per field in `QuoteDocumentTableDefinition.measureFields(measureSet)`. This keeps every current definition working with zero new CMDT authoring; never freeze the count in code or documentation. A table needs explicit column records when it wants a *subset* or a different order.
4. Author explicit column definitions for the tables whose guides show a narrower set — `PRODUCT_FAMILY_SUMMARY` (label, list, discount, net) and `CHARGE_TYPE_SUMMARY` — so the data matches the documented output rather than the full measure set.
5. Validate `Value_Field__c` as **any readable field on `Quote_Document_Row__c`**, schema-checked the same way as `validateFieldPath`, and read under whichever persona [step 00](step-00-audit-and-contract-principles.md) selected ([`spec.md`](../spec.md) §10 — under the requesting-user model this means `WITH USER_MODE`; under the service-context model, FLS is not the gate and access is authorized at the action instead). Deliberately *not* restricted to the table's measure set:

   - A subscriber adding their own custom field to `Quote_Document_Row__c` in their own org — additive and upgrade-safe — can bind a column to it with one CMDT row and no core change. That is the cheapest flexibility lever in the whole design ([`spec.md`](../spec.md) §7) and a measure-set allowlist would close it.
   - `Product_Code__c`, `Quantity__c`, `Charge_Type__c`, and `Transaction_Type__c` are legitimate columns today and are not measures.

   The failure this restriction was aimed at — a `CHANGE` table printing `Amount_List__c`, which is never populated for that measure set — is caught more precisely and without collateral damage: a column bound to a measure field that is *outside the table's measure set* fails with `COLUMN_MEASURE_MISMATCH`. A column bound to a non-measure field is always allowed.

   **Readable is not the same as render-safe.** Bind only these `DisplayType` values, and reject everything else at config load with `COLUMN_TYPE_UNSUPPORTED`, naming the field and its type:

   | Allowed | Rejected, and why |
   |---|---|
   | String, TextArea (within a declared maximum length) | **TextArea (rich)** — carries HTML, which no vendor-neutral payload may contain |
   | Boolean | **Base64 / Blob** — not printable |
   | Date, DateTime (kept distinct — a renderer formats them differently) | **Encrypted** — must never enter a snapshot |
   | Integer, Double, Currency, Percent | **Address / Location compound** — no single scalar value |
   | Picklist (the API value; the label comes from the dictionary, not from the picklist's own translation) | **Reference** — an Id is not printable; bind the resolved text field instead |
   | | **Long text beyond the declared maximum** — truncation is a renderer-specific behaviour and would break adapter equivalence |
   | | **Multi-select picklist** — the separator is a presentation decision, so resolve it in Apex into a text field first |

   A formula field is allowed if its return type is on the left-hand list; the same schema check applies to what it returns, not to how it is computed.

6. **`Data_Type__c` must agree with the field's actual `DisplayType`,** checked at config load, not trusted from the CMDT row. A `Currency` field declared as `Text` is exactly how two adapters start formatting the same value differently — `COLUMN_TYPE_DECLARATION_MISMATCH`. The field is not redundant with the schema: it is what the renderer reads so it never has to describe the schema itself.
7. **A valid column definition is not a populated value.** Binding a field is only half the contract — the value has to reach the DTO. Required alongside the validation above:

   - the row query that feeds [`QuoteDocumentRenderService`](step-07-render-service-dto.md) is **assembled dynamically from the union of every configured `Value_Field__c`**, not from a static SELECT list. A column whose field is absent from the queried row fails with `COLUMN_VALUE_NOT_QUERIED` rather than arriving as null — a null must mean "empty value", never "nobody selected it";
   - namespaced subscriber fields resolve, and are covered by a test;
   - **formula fields are read after insert.** A formula on `Quote_Document_Row__c` has no value on the pre-insert in-memory record, so a column bound to one must be re-queried post-insert, not read from the row the builder or a contributor held;
   - a contributor that is supposed to populate a bound custom field, and does not, produces a null the renderer prints as empty — so any column whose emptiness is a defect needs its own required-value check, declared per column rather than assumed;
   - a bound field that is later deleted, renamed, or retyped fails at config load, and the type change moves the fingerprint on its own.

8. Add the object and all fields to `CPQ_Document_Totals.permissionset-meta.xml`.

## 4. Out of scope

- Localizing `Display_Label__c` (step 03). Until then it holds the English label from the field's own label.
- Renderer consumption (steps 07–08).
- Per-row column overrides. If one row needs a different column set than its table, that is a different table.

## 5. Acceptance criteria

- [ ] Object, CMDT, and permission-set entries deployed.
- [ ] Every displayed table on a regenerated quote has at least one visible label/content column and the columns required by its definition, with non-null unique ascending `Display_Order__c` and no duplicate `Column_Code__c`. Orders may use gaps (10, 20, 30) for insertability.
- [ ] `PRODUCT_FAMILY_SUMMARY` produces exactly the four columns its guide documents, in that order.
- [ ] A `Quote_Document_Column_Def__mdt` pointing at a non-existent field fails generation with a message naming the field.
- [ ] A `CHANGE`-measure table referencing a `PRICE_WATERFALL` measure fails with `COLUMN_MEASURE_MISMATCH`.
- [ ] A column bound to a **non-measure** field (`Product_Code__c`, `Quantity__c`) generates normally.
- [ ] A column bound to a custom field added to `Quote_Document_Row__c` outside core generates normally, with no core change — the subscriber flexibility case from [`spec.md`](../spec.md) §7.
- [ ] A column bound to a Rich Text, encrypted, Blob, compound, reference, or multi-select field fails with `COLUMN_TYPE_UNSUPPORTED` naming the type.
- [ ] A `Currency` field declared as `Text` fails with `COLUMN_TYPE_DECLARATION_MISMATCH`.
- [ ] Field-level-security behaviour matches the generation persona chosen in [step 00](step-00-audit-and-contract-principles.md): under the requesting-user model, an unreadable bound field fails rather than printing blank; under the service-context model, the same document is produced for two users with different FLS. One test for whichever model was chosen.
- [ ] A column bound to a subscriber field is **selected, populated, and present in the DTO** — the value survives from contributor to payload, not just from CMDT to validation.
- [ ] A column bound to a formula field carries the post-insert value.
- [ ] Removing a bound field, or changing its type, fails at config load or changes the fingerprint.
- [ ] `Max_Groups__c`, totals, and `verify()` behaviour unchanged — existing tests pass untouched.

## 6. Verification method

```bash
sf project deploy start --source-dir force-app
sf apex run test --class-names QuoteDocumentGeneratorTest --class-names QuoteDocumentLifecycleTest --result-format human --wait 20
```

```sql
SELECT Quote_Document_Table__r.Table_Code__c, Column_Code__c, Display_Label__c,
       Display_Order__c, Value_Field__c, Data_Type__c
FROM Quote_Document_Column__c
WHERE Quote_Document_Table__r.Quote__c = :quoteId
ORDER BY Quote_Document_Table__r.Display_Order__c, Display_Order__c
```

Pass: the result reads as the printed table layout of every guide, with no gaps and no `Value_Field__c` that is not on `Quote_Document_Row__c`.

New test class `QuoteDocumentColumnTest`: `defaultColumnsMatchTheMeasureSet`, `explicitColumnDefinitionsWinOverDefaults`, `unknownValueFieldFailsGeneration`, `measureSetMismatchFailsGeneration`, `nonMeasureFieldIsAValidColumnSource`, `subscriberAddedFieldIsAValidColumnSource`, `unsupportedFieldTypeIsRejected`, `declaredTypeMustMatchSchema`, `fieldLevelSecurityFollowsTheChosenPersona`.

## 7. Close-out

- **Date:**
- **Notes:**
- **Next step:** [`step-03-semantic-keys-and-localization.md`](step-03-semantic-keys-and-localization.md)
