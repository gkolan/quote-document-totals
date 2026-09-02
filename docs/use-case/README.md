# Quote document use cases

This catalog contains 43 self-contained Salesforce CPQ runbooks and 57 additional design patterns. Each numbered runbook states exactly what is included, what must be created, when to stop, the Salesforce Setup steps, a worked example, checks, troubleshooting, rollback, and a production checklist. The additional patterns are ideas for future setup; they do not claim that working Salesforce records are already included.

## Architecture diagrams

Read [Quote document architecture — simple view](architecture-and-flow.md) for three diagrams:

- how the Quote and Custom Metadata become document-ready Salesforce records;
- the simple Quote → Table → Row data model; and
- what happens after **Generate Document Tables** is selected.

Each diagram includes Mermaid source and a text-only fallback.

For the common order-form layout with Hardware, Software, Services, Row notes, subtotals, tax, and amount due, use [Build an order form with only the Tables it needs](../dynamic-order-form-composition.md). It explains condition-based and Apex/Flow whole-document composition without template suppression.

## How complete the runbooks are

Every numbered guide can be followed on its own for the scope stated in **Status and scope**. A guide does not assume that an example, field, report, Flow, or table definition exists when it is not included. In that case, the guide names what must be created and identifies the point at which approval or a Salesforce review is required.

The [architecture and call-flow guide](architecture-and-flow.md) is optional background. Use it when you want to understand how the records connect; it is not a missing prerequisite for the numbered runbooks.

Organization-specific choices still require an owner. Examples include legal wording, pricing policy, forecast values, access, page assignments, and document-tool mapping. The runbooks identify these decisions explicitly and do not invent an answer for the organization.

## Start here

1. Find the business question in **Choose an existing guide**. Use **Additional patterns worth building** when no full guide is an exact match.
2. Prefer the smallest pattern that answers the question. Combine patterns only when the readiness note explicitly calls out the combination for validation.
3. Read **Status and scope** and **Before you start** before changing Salesforce. If the guide says **Stop here if**, resolve that condition first.
4. Build and test the configuration in a sandbox.
5. Keep **Active** cleared while the Custom Metadata is being prepared.
6. Select **Active** for a controlled sandbox test, then generate document data from a representative Quote.
7. Confirm the Quote's **Document Data Status** is **Ready** and each generated table's **Status** is **Complete**.
8. Review the Quote Document Table and Quote Document Row records.
9. Review the matching report in **Reports → CPQ Document Totals**, when available.
10. If the output is wrong, clear **Active** before correcting it. Leave the table active for general use only after its saved output agrees with the Quote.

## What the Salesforce records mean

- **Quote Document Table Definition** Custom Metadata describes one document table.
- **Quote Document Grouping** Custom Metadata controls how Quote Lines are grouped into sections or rows.
- **Quote Document Schedule** Custom Metadata defines named periods, milestones, departments, deliveries, or phases and their relative weights.
- **Quote Document Column Definition** Custom Metadata controls the columns and how each column is totaled.
- **Quote Document Content** Custom Metadata stores approved headings, notices, assumptions, clauses, and instructions by language.
- **Quote Document Table** is the saved result for one generated table.
- **Quote Document Row** is one saved heading, detail line, subtotal, or total inside that table.
- **Quote Document Block** is the saved copy of one active Quote Document Content record. Reports and the final document read this copy; administrators do not edit it by hand.
- **Document Data Status** on the Quote shows whether generation completed, is out of date, or failed.
- **Document Data Error** on the Quote explains a failed generation.

Codes such as `PRICE_WATERFALL`, `PERIOD`, and `EXPANSION` are values entered in Custom Metadata. They are shown exactly as Salesforce expects them.

### Quote Document Block examples included here

Use [Document content blocks](34-document-content-blocks.md) for the complete setup and test instructions. The repository supplies these ready-to-test examples:

| Block                  | English example                                       | French example                                         | Position |
| ---------------------- | ----------------------------------------------------- | ------------------------------------------------------ | -------: |
| Quote validity         | `QUOTE_VALIDITY` / “Validity”                         | `QUOTE_VALIDITY` / “Validité”                          |   `2000` |
| Signature instructions | `SIGNATURE_INSTRUCTIONS` / “How to accept this quote” | `SIGNATURE_INSTRUCTIONS` / “Comment accepter ce devis” |   `2100` |

The guide also gives complete sandbox records for consumption assumptions, a minimum-commitment explanation, and rebate conditions. Those three records do not ship and their sample wording is not legal or commercial approval.

The usual document combines both record types in one generation:

```text
10    Product Family Summary table and totals
20-80 Other active pricing tables
2000  Quote validity Block
2100  Signature instructions Block
```

No second generation or template calculation is required. Salesforce creates the Tables, Rows, Columns, and Blocks for the same Quote, then the document tool reads them in Display Order. See [Combine Blocks and totals in one document](34-document-content-blocks.md#combine-blocks-and-totals-in-one-document) for complete examples, including assumptions immediately before an estimated table.

## Choose an existing guide

The sample result is deliberately small. It shows the question the table answers; the linked guide contains the complete setup, a larger output example, and the checks that protect the total.

### Summaries and product structure

|   # | Guide                                                                                  | Use it when                                                                           | Small example of the result                                    | Availability |
| --: | -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- | -------------------------------------------------------------- | ------------ |
|   1 | [Product Family Summary](01-product-family-summary.md)                                 | An executive needs one amount per family instead of individual SKUs.                  | Software $10,800; Services $5,000; total $15,800.              | Ready to use |
|   2 | [Charge Type Summary](02-charge-type-summary.md)                                       | The document must separate one-time, recurring, and usage charges.                    | One-time $5,000; Recurring $12,000; total $17,000.             | Ready to use |
|   3 | [Discount Summary](03-discount-summary.md)                                             | A buyer needs a concise list-to-net explanation.                                      | List $20,000; discount ($2,000); net $18,000.                  | Ready to use |
|   4 | [Bundle Detail](04-bundle-detail.md)                                                   | Package parents and their included or priced components must remain visually related. | Security Suite → Gateway, Monitoring, Support.                 | Ready to use |
|   5 | [Quote Line Group and Product Family Detail](05-quote-group-family-detail.md)          | CPQ Quote Line Groups are customer-facing work packages, sites, or phases.            | Headquarters → Software $8,000; Services $2,000.               | Ready to use |
|   6 | [Product Family and Billing Frequency Summary](06-family-billing-frequency-summary.md) | Family alone is too broad and monthly versus annual billing matters.                  | Software / Annual $12,000; Software / Monthly $1,200.          | Ready to use |
|   7 | [Optional Products](07-optional-products.md)                                           | Optional add-ons must be shown without inflating the payable Quote total.             | Base total $15,000; optional training $2,000 shown separately. | Ready to use |

### Schedules and allocations

|   # | Guide                                                                                   | Use it when                                                                               | Small example of the result                                    | Availability                           |
| --: | --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | -------------------------------------------------------------- | -------------------------------------- |
|   8 | [Monthly Subscription Breakdown](08-monthly-subscription-breakdown.md)                  | A term total needs to be explained month by month.                                        | Jan–Dec $1,000 each; total $12,000.                            | Built and tested; metadata is inactive |
|   9 | [Multi-Year Schedule](09-multi-year-schedule.md)                                        | A multi-year deal needs annual totals, including ramps.                                   | Year 1 $12,000; Year 2 $18,000; Year 3 $24,000.                | Built and tested; example is inactive  |
|  10 | [Payment Installments and Milestones](10-payment-installments.md)                       | Commercial terms split one amount across signing, delivery, and acceptance.               | 30/40/30 of $60,000 → $18,000 / $24,000 / $18,000.             | Built and tested                       |
|  11 | [Free Periods and Promotional Pricing](11-free-period-promotional-pricing.md)           | Zero-price or reduced-price periods must be explicit rather than omitted.                 | Months 1–2 $0; months 3–6 $75; months 7–12 $150.               | Built and tested                       |
|  12 | [One-Time and Recurring Charges in One Schedule](12-one-time-and-recurring-schedule.md) | A schedule contains both a recurring subscription and a fee incurred once.                | Month 1 $6,000; months 2–12 $1,000; total $17,000.             | Built and tested                       |
|  13 | [Delivery Schedule by Units](13-delivery-schedule-by-units.md)                          | Goods or licenses are delivered in planned quantities.                                    | April 40 units; June 35; August 25; total 100.                 | Built and tested                       |
|  14 | [Project Phase Breakdown](14-project-phase-breakdown.md)                                | Services are priced by discovery, implementation, and launch phases.                      | Discovery $10,000; Build $35,000; Launch $5,000.               | Built and tested                       |
|  15 | [Cost Allocation by Department or Location](15-cost-allocation.md)                      | One payable Quote must be apportioned across cost owners.                                 | HQ 50%; West 30%; East 20%; allocations equal the Quote total. | Built and tested                       |
|  16 | [Bundle Price Allocation](16-bundle-price-allocation.md)                                | A package price must be distributed across components without double counting the parent. | $10,000 package → Platform $7,000; Support $3,000.             | Built and tested                       |

### Comparisons and Quote changes

|   # | Guide                                                                  | Use it when                                                                     | Small example of the result                           | Availability                                      |
| --: | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ----------------------------------------------------- | ------------------------------------------------- |
|  17 | [Amendment Before-and-After](17-amendment-before-after.md)             | A customer needs the contracted amount, amended amount, and delta.              | Before $20,000; after $24,000; increase $4,000.       | Provisional for real CPQ amendments               |
|  18 | [Renewal and Co-Term Schedule](18-renewal-coterm-schedule.md)          | Renewed and newly co-termed subscriptions must be explained together.           | Existing renewal $18,000; six-month add-on $3,000.    | Provisional for real CPQ renewals                 |
|  19 | [Previous Quote Comparison](19-previous-quote-comparison.md)           | Sales needs to compare the current proposal with a selected earlier Quote.      | Previous $50,000; current $46,000; decrease $4,000.   | Built and tested                                  |
|  20 | [Transaction Change Summary](20-transaction-change-summary.md)         | Changes should be summarized as add, remove, upgrade, downgrade, or unchanged.  | Adds +$8,000; removals ($3,000); net change +$5,000.  | Inactive; amendment classification is provisional |
|  21 | [Product Change Summary](21-product-change-summary.md)                 | A change document needs one delta per product rather than transaction category. | Analytics +$3,000; Support +$2,000.                   | Inactive; amendment classification is provisional |
|  22 | [Bundle Change Summary](22-bundle-change-summary.md)                   | The commercial impact should roll up to bundle parents.                         | Security Suite +$4,000; Data Suite ($1,000).          | Inactive; amendment classification is provisional |
|  23 | [Bundle and Product Change Detail](23-bundle-product-change-detail.md) | Reviewers need bundle context and the changed component beneath it.             | Security Suite → Monitoring +$2,500; Gateway +$1,500. | Inactive; amendment classification is provisional |

### Usage and customer-specific output

|   # | Guide                                                                    | Use it when                                                            | Small example of the result                      | Availability                              |
| --: | ------------------------------------------------------------------------ | ---------------------------------------------------------------------- | ------------------------------------------------ | ----------------------------------------- |
|  24 | [Usage Pricing Tier Breakdown](24-usage-tier-breakdown.md)               | Existing CPQ consumption tiers and rates must be printed clearly.      | 0–10k units at $0.10; 10k–50k at $0.08.          | Built and tested; displays CPQ rates only |
|  25 | [Customer Product Numbers](25-customer-product-numbers.md)               | The buyer orders by its own material or catalog numbers.               | Customer part ACME-1049 → seller SKU SW-ENT.     | Built and tested; mappings are required   |
|  26 | [Estimated Consumption Scenarios](26-estimated-consumption-scenarios.md) | Approved usage assumptions need low, expected, and high illustrations. | 1M / 2M / 3M calls → $8,000 / $14,000 / $20,000. | Value must be supplied                    |

### Proposals and financial illustrations

|   # | Guide                                                                          | Use it when                                                                       | Small example of the result                              | Availability                              |
| --: | ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------- | -------------------------------------------------------- | ----------------------------------------- |
|  27 | [Alternative Proposals](27-alternative-proposals.md)                           | Basic, recommended, and premium choices must be presented without summing them.   | Basic $25,000; Recommended $34,000; Premium $48,000.     | Built and tested                          |
|  28 | [Minimum Commitment and Shortfall](28-minimum-commitment-shortfall.md)         | A sourced forecast must be compared with a contractual minimum.                   | Minimum $100,000; forecast $82,000; shortfall $18,000.   | Commitment value must be supplied         |
|  29 | [Rebate or Incentive Illustration](29-rebate-incentive-illustration.md)        | An approved external rebate result needs a transparent illustration.              | Eligible spend $200,000; 3% incentive $6,000.            | Rebate rule and value must be supplied    |
|  30 | [Averages, Percentages, Peaks, and Ending Balances](30-non-additive-values.md) | A column total is a maximum, ratio, last value, or no total—not a sum.            | 100 licenses repeated monthly → peak 100, not 1,200.     | Built and tested                          |
|  31 | [Separate Purchasing Entities](31-separate-purchasing-entities.md)             | One Quote funds several legal buyers that each need a separate table or document. | US entity $70,000; UK entity $30,000; combined $100,000. | Built and tested; entity data is required |

### Document presentation and administration

These guides support every pricing scenario. They keep reusable document and operating controls separate from the commercial table guides.

|   # | Guide                                                                                | Use it when                                                                                 | Availability                                                 |
| --: | ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
|  32 | [Product-only list without amounts](32-product-only-list.md)                         | Included products must print without prices or totals.                                      | Supported pattern; no stock definition or dedicated fixture  |
|  33 | [Table presentation text](33-table-presentation-text.md)                             | Titles, subtitles, introductions, or footers need administration.                           | Ready to use                                                 |
|  34 | [Document content blocks](34-document-content-blocks.md)                             | Assumptions, validity, signature instructions, or clauses must be governed.                 | Ready to use; wording requires approval                      |
|  35 | [Translated content and labels](35-translated-content-and-labels.md)                 | Complete saved document data is needed in another language.                                 | `en_US` and `fr` examples ship                               |
|  36 | [Row, totals, and table order](36-row-totals-and-table-order.md)                     | Detail visibility, section totals, or print sequence needs control.                         | Ready to use                                                 |
|  37 | [Generate or refresh from a Quote](37-generate-or-refresh-from-quote.md)             | Users need the Quote action or an automation entry point.                                   | Ready to use; page-layout placement is manual                |
|  38 | [Quote generation status and errors](38-quote-generation-status-and-errors.md)       | Users need a clear readiness gate and support diagnostics.                                  | Fields and lifecycle ship; layout placement is manual        |
|  39 | [Related-list administration](39-related-list-administration.md)                     | Administrators need record-level Table and Row inspection.                                  | Relationships ship; layout placement is manual               |
|  40 | [Review output with Salesforce Reports](40-review-output-with-salesforce-reports.md) | Saved output needs a readable pre-document review.                                          | Reports ship; one-click Quote links are planned              |
|  41 | [Regenerate only for relevant changes](41-regenerate-only-for-relevant-changes.md)   | Saved document data should be reused until relevant Quote data changes.                     | Ready to use                                                 |
|  42 | [Flow-based row adjustment](42-flow-row-adjustment.md)                               | An experienced Flow builder needs to change or add generated rows without Apex.             | Advanced configuration; bridge and sample Flow ship          |
|  43 | [Registered Apex-based row adjustment](43-registered-apex-row-adjustment.md)         | A Salesforce developer must implement a controlled row change that settings cannot provide. | Apex extension; approved-code list, examples, and tests ship |

## Additional patterns worth building

These are not claims that 43 more active table definitions already ship. They show ways to combine filtering, grouping, schedules, allocations, comparisons, separate table sections, row adjustments, translations, and totals. Start with the named guide, supply the listed source data, and create inactive Custom Metadata for sandbox testing. A pattern marked **Validate first** needs proof with the org's own CPQ data before production use.

### Commercial catalog and price presentation

|   # | Pattern                                               | Start with               | Concrete result                                                     | Readiness                                   |
| --: | ----------------------------------------------------- | ------------------------ | ------------------------------------------------------------------- | ------------------------------------------- |
|  44 | Region and product-family summary                     | Product Family Summary   | North America / Software $40,000; EMEA / Software $25,000.          | Configuration pattern                       |
|  45 | Sales channel or partner summary                      | Quote Line Group Detail  | Direct $30,000; Reseller $18,000; Marketplace $7,000.               | Source channel required                     |
|  46 | SKU, quantity, unit price, and extended price catalog | Bundle Detail            | SKU A-100 × 25 at $80 = $2,000.                                     | Configuration pattern                       |
|  47 | Customer and seller part numbers side by side         | Customer Product Numbers | ACME-1049 / SW-ENT / 20 seats / $12,000.                            | Mapping required                            |
|  48 | Reseller buy price and customer sell price            | Discount Summary         | Partner buy $80,000; customer sell $92,000; spread $12,000.         | Approved fields required; protect access    |
|  49 | Zero-dollar included items                            | Bundle Detail            | Platform $15,000; SSO included $0; Standard Support included $0.    | Configuration pattern                       |
|  50 | Credits and negative lines                            | Charge Type Summary      | Subscription $12,000; service credit ($1,500); net $10,500.         | Validate sign and total rules first         |
|  51 | Freight, tax, or regulatory fee presentation          | Charge Type Summary      | Products $20,000; freight $500; sourced tax $1,640.                 | Values must be supplied; no tax calculation |
|  52 | Discount exception reasons                            | Discount Summary         | Volume discount ($2,000), competitive match ($1,000).               | Approved reason field required              |
|  53 | Service scope and responsibility matrix               | Quote Line Group Detail  | Implementation: Seller; data migration: Customer; training: Seller. | Contributor or mapped field required        |

### Time, ramp, delivery, and payment

|   # | Pattern                                        | Start with                           | Concrete result                                                     | Readiness                                  |
| --: | ---------------------------------------------- | ------------------------------------ | ------------------------------------------------------------------- | ------------------------------------------ |
|  54 | Ramped subscription quantities                 | Multi-Year Schedule                  | Year 1: 100 seats; Year 2: 150; Year 3: 225; peak 225.              | Configuration pattern                      |
|  55 | Prorated first or final period                 | Monthly Subscription Breakdown       | Partial January $387.10; February–December $1,000.                  | Validate against CPQ proration first       |
|  56 | Quarterly or semiannual billing calendar       | Payment Installments                 | Q1 $15,000; Q2 $15,000; Q3 $15,000; Q4 $15,000.                     | Configuration pattern                      |
|  57 | Deposit, progress payments, and final balance  | Payment Installments                 | Deposit $10,000; progress payment $25,000; acceptance $15,000.      | Configuration pattern                      |
|  58 | Billing in advance versus arrears              | One-Time and Recurring Schedule      | Annual platform due at signing; usage billed monthly in arrears.    | Labels and source terms required           |
|  59 | Hardware delivery with subscription activation | Delivery Schedule by Units           | 50 devices ship Apr 1; subscriptions begin on activation Apr 15.    | Validate dates and separate measures first |
|  60 | Service hours by sprint or workstream          | Project Phase Breakdown              | Design 80h; Build 240h; Test 120h; total 440h.                      | Configuration pattern                      |
|  61 | Deferred onboarding after a free period        | Free Periods and Promotional Pricing | Months 1–2 free; onboarding in month 3; recurring fee from month 4. | Configuration pattern                      |
|  62 | Renewal uplift by product family               | Renewal and Co-Term Schedule         | Software $100,000 → $105,000; 5% uplift.                            | Validate against a real renewal first      |
|  63 | Amendment effective-date schedule              | Amendment Before-and-After           | Existing amount through Jun 14; amended amount from Jun 15.         | Validate CPQ segment boundaries first      |

### Allocation, ownership, and document splitting

|   # | Pattern                                            | Start with                                     | Concrete result                                                   | Readiness                                               |
| --: | -------------------------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------- |
|  64 | Cost center and general-ledger allocation          | Cost Allocation                                | CC-4100 / Software $24,000; CC-4200 / Services $6,000.            | Allocation source required                              |
|  65 | Site, branch, or ship-to allocation                | Cost Allocation                                | Chicago 60 units / $30,000; Austin 40 / $20,000.                  | Allocation source required                              |
|  66 | Purchase-order line mapping                        | Customer Product Numbers                       | PO line 10 → 25 licenses; PO line 20 → implementation.            | Customer PO mapping required                            |
|  67 | Separate documents by country or legal entity      | Separate Purchasing Entities                   | US buyer in USD table; Canadian buyer in CAD table.               | Validate currency handling; never add unlike currencies |
|  68 | Buyer, bill-to, and ship-to sections               | Separate Purchasing Entities                   | Buyer ACME Corp; bill-to HQ; ship-to Plant 3.                     | Source account/address roles required                   |
|  69 | Department allocation inside each legal entity     | Separate Purchasing Entities + Cost Allocation | US / IT $40,000; US / HR $10,000; UK / IT $25,000.                | Validate partition-plus-allocation combination first    |
|  70 | Quote Line Group as project, site, or work package | Quote Line Group Detail                        | Site A / Hardware $20,000; Site B / Hardware $15,000.             | Configuration pattern                                   |
|  71 | Phased bundle rollout                              | Bundle Detail + Project Phase Breakdown        | Pilot / Security Suite $10,000; Rollout / Security Suite $40,000. | Validate expansion-plus-bundle grouping first           |

### Usage, commitments, and scenarios

|   # | Pattern                                          | Start with                            | Concrete result                                                          | Readiness                                              |
| --: | ------------------------------------------------ | ------------------------------------- | ------------------------------------------------------------------------ | ------------------------------------------------------ |
|  72 | Committed versus forecast usage                  | Minimum Commitment                    | Commitment 2M units; forecast 1.6M; gap 400k.                            | Forecast value must be supplied                        |
|  73 | Overage illustration                             | Usage Tier Breakdown                  | 2M committed; 250k estimated overage at $0.06 = $15,000.                 | Estimate must be supplied; no live billing calculation |
|  74 | Selected tier highlighted with adjacent tiers    | Usage Tier Breakdown                  | Selected 10k–50k tier at $0.08; neighboring tiers shown for context.     | Contributor or display flag required                   |
|  75 | Conservative, expected, and growth cases by year | Estimated Consumption Scenarios       | Year 1 expected $14,000; Year 2 expected $19,000.                        | Assumptions must be supplied                           |
|  76 | Commitment drawdown or remaining balance         | Non-Additive Values                   | Opening 1M units; used 200k; ending balance 800k.                        | Balances must be supplied; use `LAST`, not `SUM`       |
|  77 | Peak capacity by location                        | Non-Additive Values + Cost Allocation | Chicago peak 120; Austin peak 80; enterprise peak is defined explicitly. | Aggregation rule requires business approval            |

### Change communication and document experience

|   # | Pattern                                               | Start with                                | Concrete result                                                                      | Readiness                                                 |
| --: | ----------------------------------------------------- | ----------------------------------------- | ------------------------------------------------------------------------------------ | --------------------------------------------------------- |
|  78 | Adds, removals, and replacements with effective dates | Transaction Change Summary                | Add Premium Support Jul 1; remove Standard Support Jun 30.                           | Provisional amendment classification                      |
|  79 | Cancellation or downsell credit                       | Product Change Summary                    | Remove 25 seats; remaining-term credit ($3,250).                                     | Validate CPQ amendment amounts first                      |
|  80 | Bundle upgrade path                                   | Bundle Change Summary                     | Standard Suite removed; Enterprise Suite added; net +$8,000.                         | Provisional amendment classification                      |
|  81 | Executive summary plus detailed appendix              | Product Family Summary + Bundle Detail    | Page 1 family totals; appendix contains SKU-level detail; both reconcile.            | Configuration pattern                                     |
|  82 | Mandatory base and optional upgrades side by side     | Optional Products + Alternative Proposals | Base $20,000; optional SSO $2,000; upgrade package $5,000.                           | Keep alternatives outside the payable total               |
|  83 | Localized labels and narrative                        | Any guide                                 | English “Grand Total”; French “Total général”; identical saved amounts.              | Translation records required                              |
|  84 | Internal review and customer-facing versions          | Discount Summary                          | Internal table includes approval reason; customer table shows only approved pricing. | Separate definitions and field access required            |
|  85 | Assumptions and exclusions beside the priced table    | Estimated Consumption Scenarios           | “Assumes 2M API calls/year; taxes excluded” stored with the document data.           | Content metadata required                                 |
|  86 | Signature or acceptance summary                       | Payment Installments                      | Accepted option, total commitment, payment milestones, and signer notice.            | Content metadata required; document tool only displays it |

### More practical combinations

|   # | Pattern                                       | Start with                                      | Concrete result                                                                     | Readiness                                                                  |
| --: | --------------------------------------------- | ----------------------------------------------- | ----------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
|  87 | Minimum order quantity explanation            | Product-only List + Table Presentation Text     | Ordered 75 units; minimum 100; 25-unit gap shown as information.                    | Minimum and ordered quantities must be supplied                            |
|  88 | Product warranty by line                      | Bundle Detail                                   | Gateway — 36-month warranty; sensor — 12-month warranty.                            | Warranty source field required                                             |
|  89 | Manufacturer and customer part numbers        | Customer Product Numbers                        | Manufacturer M-410 / seller HW-410 / customer PLANT-882.                            | Both mapping sources required                                              |
|  90 | Unit-price volume break explanation           | Usage Tier Breakdown                            | 1–99 units at $100; 100–249 at $90; selected quantity 120.                          | Display supplied CPQ tiers; do not recalculate price                       |
|  91 | Waived setup fee                              | Charge Type Summary                             | Setup fee $2,000; waiver ($2,000); setup net $0.                                    | Waiver must already exist in CPQ pricing                                   |
|  92 | Annual price escalation                       | Multi-Year Schedule                             | Year 1 $100,000; Year 2 $103,000; Year 3 $106,090.                                  | Validate the CPQ escalation source first                                   |
|  93 | Seats added by cohort                         | Monthly Subscription Breakdown                  | 100 seats Jan–Mar; 125 Apr–Jun; 150 Jul–Dec.                                        | Subscription dates and quantities must be supplied                         |
|  94 | Mid-term cancellation schedule                | Amendment Before-and-After                      | Service through Sep 30; cancellation credit ($6,000); new total $18,000.            | Validate dates and credit signs on a real amendment                        |
|  95 | Prepaid usage credit balance                  | Non-Additive Values                             | Opening credit $50,000; planned use $12,000; ending credit $38,000.                 | Balances must be supplied; use `LAST`, not `SUM`                           |
|  96 | Service-level credit illustration             | Rebate or Incentive Illustration                | Monthly fee $20,000; possible 5% service credit $1,000.                             | Eligibility and amount must come from the service process                  |
|  97 | Residual allocation owner                     | Cost Allocation                                 | Department shares $99,999.99; rounding residual $0.01 assigned to Finance.          | Residual owner requires business approval                                  |
|  98 | Internal pricing exception appendix           | Discount Summary                                | Standard discount 10%; approved exception 5%; approval reference APR-1042.          | Separate internal definition and restricted field access required          |
|  99 | Terms by proposal option                      | Alternative Proposals + Document Content Blocks | Basic: annual payment; Premium: quarterly payment and 24-month term.                | Each option needs approved content and must remain outside combined totals |
| 100 | Tax jurisdiction summary from supplied values | Separate Purchasing Entities                    | Illinois supplied tax $1,625; Texas supplied tax $800; no cross-jurisdiction total. | Tax engine or approved field must supply every value                       |

## Availability guide

- **Ready to use** means the repository contains an active table definition. It still needs sandbox testing after deployment.
- **Built and tested** means the underlying behavior has automated Salesforce tests, but use-case-specific Custom Metadata may still need to be created or activated.
- **Configuration pattern** means the result should be expressible with existing table, filter, grouping, schedule, column, or partition settings. It is not a promise that named metadata and a dedicated automated test already exist.
- **Provisional** or **Validate first** means the behavior crosses amendment, renewal, proration, currency, or feature-combination boundaries that require proof with representative data from the target org.
- **Value or source data must be supplied** means Salesforce can save, display, and total the result, but an approved field, Flow, contributor, or connected system owns the business value.

## Rules that apply to every use case

- The document must display the saved Quote Document Table and Quote Document Row values. It must not calculate pricing again.
- Printable titles, headings, notices, and assumptions belong in Salesforce Custom Metadata, not only in a document template.
- Optional Quote Lines must be deliberately included or excluded.
- A generated total must agree with the Salesforce CPQ Quote total when the table represents the payable Quote.
- Credits and negative lines must retain their intended sign and reconcile to the Quote; do not convert them to positive display values merely for presentation.
- Alternatives must not be added together.
- Purchasing entities or departments that divide one Quote must add back to the Quote total.
- Amounts in different currencies must remain in separate tables unless an approved source supplies the converted values and conversion basis.
- Taxes, rebates, forecasts, balances, and usage estimates may be displayed, but this package must not become the system that calculates or approves them.
- Averages, percentages, peaks, and ending balances must use the correct column total rule instead of a simple sum.
- A summary and its detailed appendix must use the same saved document data and agree with one another.
- If generation fails, correct the cause shown in **Document Data Error**. Do not bypass the total checks.
