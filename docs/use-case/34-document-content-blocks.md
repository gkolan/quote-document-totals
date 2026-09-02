# Assumptions, quote validity, and signature instructions

## Status and scope

**Repository status:** Document Content metadata, generated Block records, integrity checks, and English/French examples ship.

**Org verification status:** The feature is tested. Organization-specific legal wording is not approved by this repository.

## Use case scenario

A document needs reviewed prose that is independent of any one pricing table: assumptions, a validity notice, acceptance instructions, terms, or another clause.

## What this produces

One ordered, versioned **Quote Document Block** record per active **Quote Document Content** record for the selected language. The Content record is setup. The Block record is the saved result for one Quote. Reports and the final document use the saved Block.

## Before you start

You need:

- this package deployed to a sandbox;
- the `CPQ_Document_Totals` permission set;
- access to **Setup → Custom Metadata Types**;
- a calculated test Quote with the **Generate Document Tables** action;
- the language that the test Quote will use; and
- approved plain text, block type, and document position for any new production wording.

**Stop here if** legal or business approval is missing, wording contains HTML or document tags, or another active table/block already uses the intended display order.

## Terms in plain language

| Term          | Meaning                                                                               |
| ------------- | ------------------------------------------------------------------------------------- |
| Block Code    | Permanent identifier shared by translations.                                          |
| Locale        | Language code such as `en_US` or `fr`.                                                |
| Block Type    | Styling hint: Heading, Paragraph, Clause, or Notice.                                  |
| Version       | Change identity; increase it whenever approved wording changes.                       |
| Display Order | Whole-document position shared by tables and content. A lower number appears earlier. |

### Content model

Create one **Quote Document Content** record per block code and locale. Generation copies each active record to a versioned **Quote Document Block** saved record and checks it before a document tool can retrieve it.

| Field              | Purpose                                                                                |
| ------------------ | -------------------------------------------------------------------------------------- |
| `Block_Code__c`    | Stable code, such as `QUOTE_VALIDITY` or `SIGNATURE_INSTRUCTIONS`                      |
| `Locale__c`        | Normalized locale such as `en_US` or `fr`                                              |
| `Block_Type__c`    | `Heading`, `Paragraph`, `Clause`, or `Notice`; the document tool uses this for styling |
| `Display_Order__c` | Position in the document-wide sequence shared with tables                              |
| `Heading__c`       | Optional heading                                                                       |
| `Body__c`          | Required plain text body                                                               |
| `Version__c`       | Content identity; change it whenever approved wording changes                          |
| `Is_Active__c`     | Whether generation includes the block                                                  |

## Configure in Salesforce

### Confirm the examples that ship

1. Open **Setup**.
2. In **Quick Find**, enter **Custom Metadata Types**.
3. Select **Custom Metadata Types**.
4. Beside **Quote Document Content**, select **Manage Records**.
5. Confirm the four records below. Do not create duplicates.

| Record label                           | Block Code               | Locale  | Type      |  Order | Heading                     | Version | Active   |
| -------------------------------------- | ------------------------ | ------- | --------- | -----: | --------------------------- | ------- | -------- |
| Content en_US - QUOTE_VALIDITY         | `QUOTE_VALIDITY`         | `en_US` | Notice    | `2000` | `Validity`                  | `1`     | Selected |
| Content en_US - SIGNATURE_INSTRUCTIONS | `SIGNATURE_INSTRUCTIONS` | `en_US` | Paragraph | `2100` | `How to accept this quote`  | `1`     | Selected |
| Content fr - QUOTE_VALIDITY            | `QUOTE_VALIDITY`         | `fr`    | Notice    | `2000` | `Validité`                  | `1`     | Selected |
| Content fr - SIGNATURE_INSTRUCTIONS    | `SIGNATURE_INSTRUCTIONS` | `fr`    | Paragraph | `2100` | `Comment accepter ce devis` | `1`     | Selected |

6. Open each record and confirm its Body is not blank. The exact supplied text appears in the worked examples below.
7. Select **Save** only if a deployed value does not match the table.

### Create a new block

1. Obtain approved wording and choose a Block Code that will not change when the wording changes. Use capital letters and underscores, such as `DELIVERY_ASSUMPTIONS`.
2. Open **Setup → Custom Metadata Types → Quote Document Content → Manage Records** and select **New**.
3. Enter a descriptive record label. Set **Block Code**, **Locale**, **Block Type**, **Display Order**, **Heading**, **Body**, **Version**, and **Active**.
4. Choose a Display Order not used by another active table or content record. Tables and blocks share one sequence; a duplicate number stops generation.
5. Enter plain text only. Do not enter HTML, DocuSign tags, or merge-field marks such as `«Account_Name»`. The final document controls fonts and styling.
6. Start with Version `1`. Increase it to `2`, `3`, and so on whenever approved wording changes.
7. Create one record for every supported language. Use the same Block Code for its translations.
8. For a table that must never publish without its assumptions, open its **Quote Document Table Definition** record and set **Assumptions Block Code** to the Block Code created above.
9. Select **Active** only when the sandbox test is ready, then save.

### Make existing generated Quotes out of date after wording changes

Deploying a Content change does not rebuild existing Quotes automatically. Ask a Salesforce developer or an administrator with **Execute Anonymous** access to run the following command. Then review the result in **Setup → Apex Jobs**.

```apex
Database.executeBatch(new QuoteDocumentInvalidationJob(), 200);
```

## Worked examples

### Example 1: supplied English blocks

Generate an `en_US` Quote with the supplied records active. Salesforce must save these two Quote Document Blocks in this order:

```text
2000  Validity
      This quote is valid for 30 days from the date of issue. Pricing is subject to change after that date.

2100  How to accept this quote
      To accept, sign and return this document. An authorised signatory must sign on behalf of the customer.
```

The first saved Block must be type Notice and the second must be type Paragraph. Both must show Source Version `1` and Locale `en_US`.

### Example 2: supplied French blocks

Generate the same Quote with locale `fr`. Salesforce must save:

```text
2000  Validité
      Ce devis est valable 30 jours à compter de sa date d'émission. Les prix peuvent changer après cette date.

2100  Comment accepter ce devis
      Pour accepter, signez et retournez ce document. Un signataire autorisé doit signer au nom du client.
```

Amounts and table rows must remain unchanged. Only governed labels and Block text change language.

### Example 3: consumption assumptions created for a sandbox

This record is a complete test example; it does not ship. Replace the sample volumes, date, owner, and wording with approved values before production.

| Field         | Sandbox example value                                                                                                                                                                                                         |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Record Label  | `Content en_US - CONSUMPTION_SCENARIO_ASSUMPTIONS`                                                                                                                                                                            |
| Block Code    | `CONSUMPTION_SCENARIO_ASSUMPTIONS`                                                                                                                                                                                            |
| Locale        | `en_US`                                                                                                                                                                                                                       |
| Block Type    | Notice                                                                                                                                                                                                                        |
| Display Order | `250`                                                                                                                                                                                                                         |
| Heading       | `Consumption assumptions`                                                                                                                                                                                                     |
| Body          | `Illustration only. Low assumes 1,000,000 API calls per year, Expected assumes 2,000,000, and High assumes 3,000,000. Sample source: Revenue Operations forecast dated August 15, 2026. Actual usage and charges may differ.` |
| Version       | `1`                                                                                                                                                                                                                           |
| Active        | Selected for the controlled sandbox test                                                                                                                                                                                      |

Set **Assumptions Block Code** on the `CONSUMPTION_SCENARIOS` table definition to `CONSUMPTION_SCENARIO_ASSUMPTIONS`. Generation must stop if that required Block cannot be found for the Quote language.

## Combine Blocks and totals in one document

You do not run Blocks separately from totals. Selecting **Generate Document Tables** once creates all active Tables and all active Content Blocks for the same Quote and language. Salesforce places both types into one list using **Display Order**.

Two settings have different jobs:

| Setting                                        | What it controls                                                                            |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Display Order on the Table and Content records | Where each Table or Block appears in the document.                                          |
| Assumptions Block Code on a Table Definition   | Stops generation when that required Block is missing. It does not move or attach the Block. |

Every active Table and Block for one language must have a different Display Order. Use gaps between numbers so another section can be inserted later.

### Combined example A: totals followed by validity and signature text

This is the most common supplied arrangement. Keep `PRODUCT_FAMILY_SUMMARY` active at order `10` and keep the supplied English Blocks active at `2000` and `2100`.

```text
10    TABLE — Summary by Product Family
      Software                     $10,800
      Services                      $5,000
      Grand Total                  $15,800

2000  BLOCK — Validity
      This quote is valid for 30 days from the date of issue. Pricing is subject to change after that date.

2100  BLOCK — How to accept this quote
      To accept, sign and return this document. An authorised signatory must sign on behalf of the customer.
```

Other active pricing Tables at orders `20` through `80` may appear between the Product Family Summary and the validity Block. That is expected. Each payable Table must reconcile independently; Block text never changes a total.

### Combined example B: assumptions immediately before estimated totals

Use this arrangement with [Estimated Consumption Scenarios](26-estimated-consumption-scenarios.md):

| Section                   | Code                               | Display Order |
| ------------------------- | ---------------------------------- | ------------: |
| Assumptions Block         | `CONSUMPTION_SCENARIO_ASSUMPTIONS` |         `250` |
| Scenario Table Definition | `CONSUMPTION_SCENARIOS`            |         `260` |

A partitioned Table can create several generated Tables beginning at order `260`. The assumptions remain immediately before that set.

```text
250  BLOCK — Consumption assumptions
     Illustration only. Low assumes 1,000,000 API calls per year...

260+ TABLES — Estimated Consumption Scenarios
     Low estimate               $18,000
     Expected estimate          $24,000
     High estimate              $32,000
     No combined payable total
```

Set **Assumptions Block Code** on `CONSUMPTION_SCENARIOS` to `CONSUMPTION_SCENARIO_ASSUMPTIONS`. If the Content record is inactive, missing, or unavailable in the Quote language, generation must fail instead of publishing the estimates without their explanation.

### Combined example C: explanation before each informational table

This layout supports both [Minimum Commitment](28-minimum-commitment-shortfall.md) and [Rebate Illustration](29-rebate-incentive-illustration.md):

```text
270  BLOCK — Minimum commitment assumptions
280  TABLE — Minimum Commitment
     Minimum commitment        $100,000
     Expected usage             $82,000
     Shortfall                  $18,000  information only

285  BLOCK — Rebate conditions
290  TABLE — Rebate Illustration
     Current price              $50,000
     Possible rebate             $5,000  conditional
     Current payable total      $50,000
```

The Block at `270` is required by the Table at `280`; the Block at `285` is required by the Table at `290`. The shortfall and contingent rebate rows remain excluded from payable totals.

### Verify a combined result

1. Generate once from the calculated sandbox Quote.
2. Confirm **Document Data Status** is **Ready**.
3. In **Quote Document Tables**, check each Table's Display Order, status, rows, and Grand Total.
4. In **Quote Document Blocks**, check each Block's Display Order, Block Code, language, version, heading, and body.
5. Preview the final document and read the sections from smallest Display Order to largest.
6. Confirm every Table total still matches its saved Salesforce rows.
7. Confirm removing a required assumptions Content record makes generation fail with `SCENARIO_ASSUMPTIONS_MISSING`.
8. Restore the Content record, generate again, and confirm the Quote returns to **Ready**.

### Safety rules

- A required assumptions block missing from the resolved locale fails generation with `SCENARIO_ASSUMPTIONS_MISSING`.
- Empty bodies, missing versions, duplicate block codes, body markup, and ambiguous document order fail rather than producing incomplete customer text.
- Deploying changed content does not itself update every Quote. Run the job above to mark existing results Stale, then generate again.

## Generate and verify

1. Open the calculated sandbox Quote.
2. Confirm the Quote language is `en_US` for Example 1 or `fr` for Example 2.
3. Select **Generate Document Tables**.
4. Wait until **Document Data Status** is **Ready**. If it becomes **Failed**, read **Document Data Error** before changing anything.
5. Open the **Quote Document Blocks** related list on the Quote. If the list is not present, add it by following [Related-list administration](39-related-list-administration.md).
6. Open each Block and compare Block Code, Type, Display Order, Locale, Heading, Body, Source Version, and Displayed with the example.
7. Confirm there is one Block per active content record for the selected locale and that **Is Displayed** is selected.
8. Preview the final document. Confirm the wording and order match the saved Blocks exactly.
9. Confirm no required paragraph exists only in the document template.

## Troubleshooting

| Problem                            | What it means                                                                                          | What to do                                                                                          |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------- |
| Duplicate-order error              | A table or block already uses that order.                                                              | Assign a unique number and generate again.                                                          |
| Missing assumptions error          | Required code has no active record for the language.                                                   | Add the matching active content record.                                                             |
| Markup rejected                    | Heading or body contains unsupported tags.                                                             | Store plain text and let the document control styling.                                              |
| Old wording appears                | Version update or regeneration was missed.                                                             | Increase Version, mark affected Ready Quotes Stale, and regenerate.                                 |
| No Blocks are generated            | No active Content records match the selected locale.                                                   | Confirm the Quote language, Content Locale, and Active checkbox.                                    |
| Only some translated Blocks appear | At least one exact locale record exists, so Salesforce does not combine it with base-language records. | Complete every required Block for the exact locale, or use only the reviewed base-language records. |

## Deactivate or roll back

Deactivate the content record, invalidate affected Ready Quotes, and generate again. To restore previous wording, restore its exact text with a new higher Version. Do not edit generated blocks manually.

## Production checklist

- [ ] Every production wording and translation has named approval.
- [ ] Code, locale, type, and order are unique and correct.
- [ ] Heading and body are plain text.
- [ ] Required table references resolve.
- [ ] Quote Document Blocks related list matches the active Content records.
- [ ] Generated block and final document match exactly.
