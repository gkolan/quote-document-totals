# Quote Document Totals documentation

Start with the question you need to answer. You do not need to read every guide.

**New installation? Start with [Install and generate your first table](quick-start.md).** It covers downloading the source, deploying to a CPQ test org, adding the Quote action, and checking the first result.

Use [Build an order form with only the Tables it needs](dynamic-order-form-composition.md) when the document must combine dynamic category Tables, Row wording, and totals without template suppression.

## I want to understand the feature

1. [How the Quote tables are built](how-quote-document-totals-works.md) explains the full process in Salesforce terms.
2. [Simple architecture view](use-case/architecture-and-flow.md) shows how the Quote, action, Flow, Apex, Custom Metadata, and saved records work together.
3. [Feature and use-case overview](use-cases.md) explains the supported building blocks and safe operating rules.
4. [Available use cases](use-case/README.md) lists the table examples and their current status.

## I want to install or configure it

- [Quick start](quick-start.md) gets the first Product Family Summary working and explains common installation problems.
- [Configuration and maintenance guide](quote-document-totals-architecture-guide.md) explains objects, fields, Custom Metadata, access, checks, and support steps.
- [Testing guide](testing-guide.md) explains the local checks, Salesforce checks, and evidence to record before release.
- [Product Family Summary](use-case/01-product-family-summary.md)
- [Charge Type Summary](use-case/02-charge-type-summary.md)
- [Discount Summary](use-case/03-discount-summary.md)
- [Bundle Detail](use-case/04-bundle-detail.md)
- [Quote Group and Family Detail](use-case/05-quote-group-family-detail.md)
- [Family and Billing Frequency Summary](use-case/06-family-billing-frequency-summary.md)
- [Optional Products](use-case/07-optional-products.md)
- [Monthly Subscription Breakdown](use-case/08-monthly-subscription-breakdown.md)
- [Multi-Year Schedule](use-case/09-multi-year-schedule.md)
- [All 43 step-by-step guides](use-case/README.md)

Each configuration guide states what is already in the source, what must still be deployed, and what was tested in a Salesforce org.

## I want to understand one part of the process

- [How Quote Document Totals works](how-quote-document-totals-works.md)
- [Simple architecture and Flow view](use-case/architecture-and-flow.md)
- [Generate or refresh from a Quote](use-case/37-generate-or-refresh-from-quote.md)
- [Generation status and errors](use-case/38-quote-generation-status-and-errors.md)
- [Review saved output with Salesforce Reports](use-case/40-review-output-with-salesforce-reports.md)
- [Regenerate only after relevant changes](use-case/41-regenerate-only-for-relevant-changes.md)

## I need to change behavior

- [Extension recipes](quote-document-extension-recipes.md) gives short examples for supported changes.
- [Apex row adjustment guide](use-case/43-registered-apex-row-adjustment.md) explains changes that cannot be made with Custom Metadata alone.
- [Detailed maintenance reference](quote-document-totals.md) records the full rules and test expectations.
- [Documentation standard](documentation-standard.md) defines the required structure and evidence for every guide.
- [Roadmap](roadmap.md) lists only work that is not yet implemented.

## Words used in these guides

| Term                    | Meaning here                                                                       |
| ----------------------- | ---------------------------------------------------------------------------------- |
| **Generate**            | Build and save document tables from the current Quote Lines                        |
| **Table definition**    | A Custom Metadata record that controls one table                                   |
| **Saved document data** | The Quote Document Table, Column, Row, Block, and Fact records created for a Quote |
| **Document tool**       | DocuSign CLM or another product that turns the saved data into a document          |
| **Row adjustment**      | An approved Flow or Apex step that changes rows before Salesforce saves them       |
| **Change check**        | The stored value Salesforce uses to tell whether relevant Quote data changed       |

Salesforce object names, field names, and menu labels appear exactly as they do in the org. Code names appear only when they are needed to deploy, configure, test, or troubleshoot the feature.
