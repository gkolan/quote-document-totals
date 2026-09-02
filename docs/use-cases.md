# What Quote Document Totals can do

Quote Document Totals turns Salesforce CPQ Quote Lines into saved, checked tables for customer documents.

Start with the [use-case catalog](use-case/README.md). It contains 43 step-by-step guides with:

- the business result;
- the Salesforce Setup steps;
- a numeric example;
- an honest statement of what ships and what still needs org testing;
- troubleshooting steps; and
- a production checklist.

## Common starting points

| Need                                                         | Guide                                                                                                                                        |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Summarize amounts by Product Family                          | [Product Family Summary](use-case/01-product-family-summary.md)                                                                              |
| Separate one-time and recurring charges                      | [Charge Type Summary](use-case/02-charge-type-summary.md)                                                                                    |
| Show discounts clearly                                       | [Discount Summary](use-case/03-discount-summary.md)                                                                                          |
| Show a bundle and its products                               | [Bundle Detail](use-case/04-bundle-detail.md)                                                                                                |
| List optional products without adding them to the deal total | [Optional Products](use-case/07-optional-products.md)                                                                                        |
| Show monthly or yearly amounts                               | [Monthly Subscription Breakdown](use-case/08-monthly-subscription-breakdown.md) or [Multi-Year Schedule](use-case/09-multi-year-schedule.md) |
| Start generation from a Quote                                | [Generate or refresh document data](use-case/37-generate-or-refresh-from-quote.md)                                                           |
| Understand Ready, Stale, or Failed                           | [Generation status and errors](use-case/38-quote-generation-status-and-errors.md)                                                            |
| Review the result before creating a document                 | [Review output with Salesforce Reports](use-case/40-review-output-with-salesforce-reports.md)                                                |

## Safe use

Test new settings in a Salesforce CPQ sandbox. Keep a new table inactive while preparing it, generate from representative Quotes, and enable it broadly only after the saved report agrees with the Quote and test document.

The package displays approved Salesforce data. It must not silently become the system that calculates or approves tax, rebates, forecasts, usage, or other values owned elsewhere.
