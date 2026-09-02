# Show generation status and errors on the Quote

## Status and scope

**Repository status:** Quote status/error fields, permission-set access, lifecycle behavior, and **Quote Document Generation Failures** report ship.

**Org verification status:** Status changes are tested. Page-layout placement and user access require organization setup.

## Use case scenario

Sales users and support staff need to know whether document data is safe to use and, when it is not, what action to take.

## What this produces

A visible readiness gate on each Quote plus an actionable stored error when generation fails.

## Before you start

Identify the Quote layouts used by sales and support, and decide which technical identity fields only support staff should see.

**Stop here if** users can create a document without checking Ready, technical fields are editable on the page, or access requirements are undecided.

## Terms in plain language

| Term          | Meaning                                                          |
| ------------- | ---------------------------------------------------------------- |
| Not Generated | No saved document data exists.                                   |
| Stale         | Relevant Quote data changed after the last successful run.       |
| Generating    | A run is currently building the result.                          |
| Ready         | Complete current result passed verification.                     |
| Failed        | No valid current result was published; read Document Data Error. |

## Configure in Salesforce

### Add the operational fields

In **Setup → Object Manager → Quote → Page Layouts**, add these fields to a clearly labeled **Document Data** section:

| Field                          | Show to           | Purpose                                              |
| ------------------------------ | ----------------- | ---------------------------------------------------- |
| **Document Data Status**       | Sales and support | The readiness gate                                   |
| **Document Data Generated On** | Sales and support | When the current saved result completed              |
| **Document Data Error**        | Sales and support | Actionable failure message                           |
| **Document Data Started At**   | Support/admin     | Diagnoses a request apparently stuck on `Generating` |
| **Document Data Request Id**   | Support/admin     | Identifies one generation attempt                    |
| `Document Data Fingerprint`    | Support/admin     | Saved change check for source records and setup      |
| `Document Payload Hash`        | Support/admin     | Saved check that identifies an unexpected data edit  |

Assign `CPQ_Document_Totals` to users who operate or troubleshoot the feature. Consider making system-managed fields read-only on layouts even though the packaged permission set allows the package to update them.

### Quote status meanings

| Quote status    | Meaning                                           | User action                                                         |
| --------------- | ------------------------------------------------- | ------------------------------------------------------------------- |
| `Not Generated` | No saved document result has been built           | Select **Generate Document Tables**                                 |
| `Stale`         | Relevant Quote data changed after generation      | Generate again                                                      |
| `Generating`    | A request owns the Quote and is building a result | Wait; escalate only if it exceeds the configured abandonment window |
| `Ready`         | The complete saved result passed verification     | Preview or create the document                                      |
| `Failed`        | Generation could not publish a valid saved result | Read **Document Data Error**, fix the cause, and generate again     |

The Quote-level success status is `Ready`. Individual `Quote_Document_Table__c` records use `Complete`. Do not interchange the two terms.

## Worked example

Use one test Quote to observe Not Generated → Generating → Ready. Edit a payable Quantity and confirm Stale. Temporarily remove a required setup record and confirm Failed plus a readable error; then restore it and return to Ready.

## Generate and verify

1. Generate the worked-example Quote and confirm the status transitions.
2. Confirm a generated Table uses status **Complete**, while the Quote uses **Ready**.
3. Open **Reports → CPQ Document Totals → Quote Document Generation Failures** and confirm the controlled failed Quote appears.
4. Confirm sales users see the business fields and support users see the additional identity fields.

## Troubleshooting

| Problem                   | What it means                            | What to do                                                    |
| ------------------------- | ---------------------------------------- | ------------------------------------------------------------- |
| Status is Stale           | Relevant data changed.                   | Calculate the Quote if needed, then generate again.           |
| Status remains Generating | Run may still be live or abandoned.      | Check Started At and **Setup → Apex Jobs** before escalation. |
| Status is Failed          | Current result was rejected.             | Read Document Data Error in full and correct the named cause. |
| Failure report is empty   | Filters/access do not include the Quote. | Verify status, report folder access, and filters.             |

Troubleshooting order:

1. Read **Document Data Error** in full.
2. Correct the named Quote data, configuration, translated content, custom adjustment, or access problem.
3. Generate again; do not bypass reconciliation or integrity checks.
4. For multiple failures, open **Reports → CPQ Document Totals → Quote Document Generation Failures**.
5. For background failures without a clear Quote message, inspect **Setup → Apex Jobs** using the request time.

## Deactivate or roll back

Remove fields from a layout only through an approved layout change; do not clear status or error values manually. Restore the prior layout assignment if the new section exposes too much information.

## Production checklist

- [ ] Every status was observed in a sandbox.
- [ ] Only Ready permits document creation.
- [ ] Quote Ready and Table Complete are not confused.
- [ ] Failure report and Apex Jobs path were tested.
- [ ] Technical identity fields are read-only and appropriately limited.
