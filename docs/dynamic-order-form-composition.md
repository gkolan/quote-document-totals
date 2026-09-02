# Build an order form with only the Tables it needs

This guide explains how to create an order form with separate Hardware, Software, and Services Tables. Salesforce decides which Tables belong in the document before the document tool runs. The template does not contain hidden duplicate Tables and does not need suppression rules.

## What Salesforce creates

One generation creates all applicable records for the same Quote:

- typed header Facts, such as Customer, Billing Address, Quote Number, and Quote Expiration Date;
- zero or more Tables, such as Hardware, Software Subscriptions, and Services Schedule;
- Columns and Rows inside each Table;
- payable, subtotal, tax, charge, allowance, and information-only total roles;
- governed Blocks before or after a Table; and
- governed Blocks before or after an individual Row.

An empty category creates no **Quote Document Table** record. The document tool therefore has nothing to hide.

## Before you start

You need a sandbox, the **CPQ Document Totals** permission set, access to **Setup → Custom Metadata Types**, and a calculated Quote containing representative products.

Stop if Product Family values are not maintained consistently. For this example, products must use `Hardware`, `Software`, or `Services` exactly. Correct product data before creating document rules.

## The easiest setup: conditions on Table Definitions

Use this method when an administrator can state the rule using Quote Line fields. It covers most order forms.

Create three inactive **Quote Document Table Definition** records:

| Table Code       | Display Title          | Display Order | Line Filter | Amount Basis  | Measure Set       |
| ---------------- | ---------------------- | ------------: | ----------- | ------------- | ----------------- |
| `ORDER_HARDWARE` | Hardware               |         `100` | `ALL`       | `Final Value` | `PRICE_WATERFALL` |
| `ORDER_SOFTWARE` | Software Subscriptions |         `200` | `ALL`       | `Final Value` | `PRICE_WATERFALL` |
| `ORDER_SERVICES` | Services Schedule      |         `300` | `ALL`       | `Final Value` | `PRICE_WATERFALL` |

For each Table, create one active **Quote Document Condition** record:

| Table            | Condition Set | Sequence | Quote Line Field Path     | Operator | Compare Value | Data Type |
| ---------------- | ------------: | -------: | ------------------------- | -------- | ------------- | --------- |
| `ORDER_HARDWARE` |           `1` |     `10` | `SBQQ__Product__r.Family` | `Equals` | `Hardware`    | `Text`    |
| `ORDER_SOFTWARE` |           `1` |     `10` | `SBQQ__Product__r.Family` | `Equals` | `Software`    | `Text`    |
| `ORDER_SERVICES` |           `1` |     `10` | `SBQQ__Product__r.Family` | `Equals` | `Services`    | `Text`    |

Rules in the same Condition Set must all be true. Different Condition Sets are alternatives. For example, a Services Table can include either Services products or any line whose Quote Line Group is Implementation:

| Condition Set | Sequence | Field Path                | Operator | Compare Value    | Data Type |
| ------------: | -------: | ------------------------- | -------- | ---------------- | --------- |
|           `1` |     `10` | `SBQQ__Product__r.Family` | `Equals` | `Services`       | `Text`    |
|           `2` |     `10` | `SBQQ__Group__r.Name`     | `Equals` | `Implementation` | `Text`    |

Activate the Table Definitions only after their conditions, groupings, and Columns are complete.

## Add the Columns people expect

Create active **Quote Document Column Definition** records for each Table. Reuse a Column Code when it has the same meaning.

| Column Code    | Label          | Value Field              | Data Type  | Format Role   | Total Rule | Order |
| -------------- | -------------- | ------------------------ | ---------- | ------------- | ---------- | ----: |
| `PRODUCT_CODE` | Product Code   | `Product_Code__c`        | `Text`     | `Identifier`  | `None`     |  `10` |
| `PRODUCT_NAME` | Product Name   | `Product_Name__c`        | `Text`     | `Product`     | `None`     |  `20` |
| `DESCRIPTION`  | Description    | `Product_Description__c` | `Text`     | `Description` | `None`     |  `30` |
| `START_DATE`   | Start Date     | `Start_Date__c`          | `Date`     | `Start Date`  | `None`     |  `40` |
| `END_DATE`     | End Date       | `End_Date__c`            | `Date`     | `End Date`    | `None`     |  `50` |
| `QUANTITY`     | Quantity       | `Quantity__c`            | `Number`   | `Quantity`    | `Sum`      |  `60` |
| `UNIT_PRICE`   | Unit Price     | `Unit_Price__c`          | `Currency` | `Unit Price`  | `None`     |  `70` |
| `LINE_TOTAL`   | Customer Price | `Amount_Net__c`          | `Currency` | `Line Total`  | `Payable`  |  `80` |

The Services Table can show dates while Hardware leaves those Columns out. Every renderer receives the saved Column list and does not guess the layout.

## Blocks and totals together

A Block can be **Document Level**, **Before Section**, **After Section**, **Before Row**, **After Row**, or **Full Width After Row**. Use Row placement for a product note, service scope, or delivery instruction.

For a Table Block, populate **Related Table Key**. For a Row Block, populate both **Related Table Key** and **Related Row Key**. Salesforce resolves those keys to the saved records during generation. Each Block also carries its placement, source version, and approval identity.

```text
Hardware
  HW-100  Branch Gateway       2 × $1,500        $3,000
          Delivery note: Ships to the Chicago office.
  HW-200  Rack Mount Kit       2 ×    $75          $150
  Hardware subtotal                                $3,150

Software Subscriptions
  SW-500  Analytics Platform   25 ×   $40/mo     $12,000
          Term: January 1 through December 31.
  Software subtotal                               $12,000

Services Schedule
  SV-100  Implementation       Jan 5–Feb 28        $8,000
          Scope note: Includes discovery, setup, and administrator training.
  Services subtotal                                $8,000

Payable total                                     $23,150
```

The notes are Row Blocks. Subtotal and payable Rows use **Total Role** values. Nothing is inferred from bold text or cell position.

## Common real-world arrangements

### Only one category is present

If a Quote contains only Services, Salesforce creates only the Services Table. Hardware and Software create no empty records.

### Optional products

Place optional products in their own Table. Use an informational total role and clear **Include in Grand Total**. The option remains visible without increasing the amount due.

### Packages and included components

Print the package parent and components as related Rows. Count the package price once. Included components can show zero or an allocated informational amount but must not add the package price again.

### Discounts, charges, tax, and amount due

```text
Line extensions                         $25,000
Discount                                ($2,000)  Allowance
Implementation fee                       $1,500   Charge
Subtotal before tax                     $24,500   Tax Exclusive
Sales tax                                $1,715   Tax
Total including tax                     $26,215   Tax Inclusive
Deposit already paid                    ($5,000)  Prepaid
Amount due                              $21,215   Payable
```

Salesforce must receive tax values from the approved tax source. This framework carries tax but does not calculate tax law.

### Several sites, buyers, phases, or delivery locations

Use a separate Table when each site, buyer, phase, or delivery location needs its own Rows and subtotal. Add a combined payable total only when the business has approved one.

### Amendments and renewals

Set **Document Type**, **Document Revision**, and **Prior Document Reference** on the Quote. Distinguish additions, removals, replacements, and unchanged items. A change amount is not automatically the new payable total.

## When Apex is appropriate

Use an approved Apex document composer when the Table shape cannot be expressed safely as field conditions. Registered code `ORDER_FORM_FAMILIES` is a working example. It creates one Table for each payable Product Family actually present. Hardware and Software receive their own Product Code, Product Name, Description, Quantity, List Price, Discount, and Customer Price Columns. Services receives those Columns plus Start Date and End Date. Each Table ends with its own explicit Payable total Row. Optional lines are not included in these payable Tables.

Create an inactive **Quote Document Composer** Custom Metadata record, enter the registered **Composer Code**, Version, and Display Order, test it, and then select **Active**. Version must be a positive whole number. Increase it whenever the composer rules change.

If the composer reads another Quote or Quote Line field, list its API path in **Quote Dependency Paths** or **Line Dependency Paths**. Separate several paths with commas, semicolons, or new lines. Generation checks each path, loads it with the other source data, and includes its value in the change check. A misspelled or unreadable path stops generation with a clear error instead of reusing an old document.

The composer returns unsaved vendor-neutral Salesforce records. It does not call a document vendor or insert records itself. Main generation validates and saves everything together.

## When Flow is appropriate

Use an autolaunched Flow for controlled rules that conditions cannot express and do not justify Apex. The Flow builds unsaved Salesforce records. The main generation process checks them, links them to the Quote, and saves them together. Do not use **Create Records** in the composer Flow.

Create these Flow resources with the names and letter case shown below. **Available for input** and **Available for output** are Flow Builder checkboxes.

| Resource name     | Flow data type                    | Collection | Available for input | Available for output | What it contains                                   |
| ----------------- | --------------------------------- | ---------- | ------------------- | -------------------- | -------------------------------------------------- |
| `quoteId`         | Text                              | No         | Yes                 | No                   | The Salesforce Quote record ID.                    |
| `locale`          | Text                              | No         | Yes                 | No                   | The document language, such as `en_US`.            |
| `currencyIsoCode` | Text                              | No         | Yes                 | No                   | The Quote currency, such as `USD`.                 |
| `documentType`    | Text                              | No         | Yes                 | No                   | Quote, Order Form, Amendment, or another type.     |
| `revision`        | Number, zero decimal places       | No         | Yes                 | No                   | The positive document revision number.             |
| `quoteLineIds`    | Text                              | Yes        | Yes                 | No                   | IDs of the Quote Lines supplied to the composer.   |
| `sourceLines`     | Record: Salesforce CPQ Quote Line | Yes        | Yes                 | No                   | The queried Quote Lines and their approved fields. |
| `documentFacts`   | Record: Quote Document Fact       | Yes        | Yes                 | No                   | Header facts already prepared for this document.   |
| `tables`          | Record: Quote Document Table      | Yes        | No                  | Yes                  | Every Table the Flow wants to add.                 |
| `columns`         | Record: Quote Document Column     | Yes        | No                  | Yes                  | The Columns belonging to those Tables.             |
| `rows`            | Record: Quote Document Row        | Yes        | No                  | Yes                  | Detail, note, subtotal, and payable Rows.          |
| `blocks`          | Record: Quote Document Block      | Yes        | No                  | Yes                  | Approved wording for the document, Table, or Row.  |
| `facts`           | Record: Quote Document Fact       | Yes        | No                  | Yes                  | Additional typed header facts made by this Flow.   |

Build the Flow in this order:

1. In Setup, open **Flows**, select **New Flow**, and choose **Autolaunched Flow (No Trigger)**.
2. Create the eight input resources and five output collections from the table above.
3. Create one temporary Record variable for each kind of record the Flow will return.
4. Use **Assignment** elements to set the temporary record fields.
5. In the same or a following Assignment, add the temporary record to its matching output collection.
6. Return no Table when no section applies. Do not add a blank or hidden Table.
7. Save and activate the Flow. Copy its API Name exactly.
8. Create a **Quote Document Composer** Custom Metadata record. Enter the Flow API Name, a positive whole-number Version, a unique Display Order, and every extra Quote or Quote Line field the Flow reads.
9. Leave the Composer inactive while testing. Activate it only after the checks below pass.

At minimum, every returned Table needs **Table Key**, **Table Name**, **Table Code**, **Display Title**, and **Display Order**. Every returned Column needs the same **Table Key**, plus **Column Code**, **Display Label**, **Data Type**, **Display Order**, and a supported **Value Field**. Every returned Row needs the same **Table Key**, plus a unique **Row Key**, **Row Type**, **Display Label**, **Group Level**, and **Display Order**.

If a Table includes a Row with **Total Role = Payable**, that Row's net amount must equal the displayed Rows marked **Include in Grand Total**. Keep optional, alternative, note, and informational Rows out of that calculation. A Flow must not calculate tax law; it may carry a tax amount supplied by the approved tax source.

For a Block, set **Block Code**, **Block Type**, **Display Order**, **Body**, **Locale**, **Source Version**, **Approval Identity**, and **Placement**. For Table placement, also set **Related Table Key**. For Row placement, set both **Related Table Key** and **Related Row Key**. The related keys must exactly match the Table and Row returned by this run.

For a Fact, set **Fact Code**, **Data Type**, **Display Order**, and exactly one matching value field. For example, a Date fact uses **Date Value** and leaves Text, Number, Currency, Date/Time, and Checkbox values empty. A false Checkbox is a valid Boolean value.

Set **Table Key** on every returned Column and Row. A Row Block must set **Related Table Key** and **Related Row Key**. A Flow may return no sections when none apply. A missing or failed Flow stops generation rather than publishing an incomplete document. If every configured source returns no Table or document-level Block, generation stops because the document would be empty.

Create and activate the Flow through supported Salesforce metadata tools. Do not hand-edit Flow XML.

Before activating the Composer, run it with a calculated sandbox Quote and confirm all five output collections in Flow Debug. Then generate the Quote normally and confirm the same records were saved under the Quote. A debug result alone is not enough because the shared validation and save step runs after the Flow returns.

## Generate and check the result

1. Open a calculated sandbox Quote containing every category being tested.
2. Select **Generate Document Tables** once.
3. Wait for **Document Data Status** to become **Ready**.
4. Check **Quote Document Facts** for Customer, Billing Address, Quote Number, and Quote Expiration Date.
5. Check **Quote Document Tables** and confirm only applicable Tables exist.
6. Check each Table's Columns and Rows, saved values, Total Roles, and payable total.
7. Check each Block's Placement and related Table or Row.
8. Remove all products from one category, calculate, and generate again.
9. Confirm that category's Table record no longer exists. A hidden empty Table is not a pass.
10. Compare the final document preview with the saved Salesforce records.

## Move an existing document integration to contract 2.0

Contract `2.0` adds document type, revision, prior-document reference, typed Facts, source identities, Column format and total rules, Row total roles, and Row Blocks. Existing saved snapshots should be regenerated after deployment.

Before production:

1. Make the document integration reject an unknown contract version with a readable error.
2. Map header values from `facts` by Fact Code instead of reading Salesforce field API names.
3. Build each Table from its supplied Columns and Rows. Do not keep a fixed Hardware, Software, or Services grid in the template.
4. Print each Row's nested Blocks using its Placement.
5. Use Total Role to style and reconcile subtotal, allowance, charge, tax, prepaid, and payable Rows.
6. Test Quotes containing every category, only one category, no optional products, Row Blocks, and tax or prepaid Rows.
7. Mark existing Ready Quotes Stale and generate new snapshots before users create customer documents.

The old Table Definition Line Filter remains supported for existing setup. New category decisions should use Quote Document Conditions. This avoids forcing an immediate rewrite while keeping new templates free of suppression rules.

## Troubleshooting

| Problem                     | What it means                                                      | What to do                                                                                        |
| --------------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| An empty Table appears      | Old fixed-table logic is still running.                            | Confirm generation uses current conditions and the document tool reads only saved Tables.         |
| A category is missing       | No Quote Line met its condition.                                   | Check Product Family spelling and the condition field, operator, value, and data type.            |
| A Row cannot find its Table | Its Table Key is blank or different.                               | Use the exact stable Table Key on the Table, Column, and Row.                                     |
| A Row Block fails           | Its related key or Placement is incomplete.                        | For Row placement, provide both Related Table Key and Related Row Key.                            |
| The amount due is wrong     | A Row has the wrong Total Role or inclusion setting.               | Reconcile line extensions, allowances, charges, tax, prepaid amounts, and payable total in order. |
| Generation always rebuilds  | An active composer can read data outside the standard fingerprint. | This is deliberate protection against stale composed content.                                     |
| Flow returns no output      | The Flow did not assign its output collections.                    | Make the collections available for output and assign them before the Flow ends.                   |

## Roll back safely

Clear **Active** on the new Table Definition, Condition, or Composer records. Generate the test Quote again. Confirm the removed Tables, Rows, and related Blocks no longer exist. Do not repair generated snapshots by hand.

## Production checklist

- [ ] Product Family and other condition fields are maintained consistently.
- [ ] Every Table has a permanent unique Table Key and Display Order.
- [ ] Every Column has a clear data type, format role, and total rule.
- [ ] Every payable Table reconciles to its included Rows.
- [ ] Optional and informational Rows do not increase the payable total.
- [ ] Every Block has reviewed wording, source version, approval identity, and placement.
- [ ] Row Blocks resolve to the intended Table and Row.
- [ ] Missing categories produce no empty Tables.
- [ ] Header Facts, amendment references, language, and currency are correct.
- [ ] The final document matches saved Salesforce records without template suppression.
