# Regenerate only when relevant Quote data changes

## Status and scope

**Repository status:** Stale marking, current-input comparison, declared Flow/Apex dependencies, generate-or-reuse, invalidation batch, and tests ship.

**Org verification status:** Core behavior is tested. Every custom Flow/Apex adjustment must declare its own changing inputs and version correctly.

## Use case scenario

Document data must stay current without rebuilding after every Salesforce CPQ save or reusing saved data after a document value changed.

## What this produces

Unchanged Quotes reuse current saved document data; relevant changes make it Stale or cause the next launch to rebuild before document creation.

## Before you start

You need:

- this repository's current Quote and Quote Line triggers, generation classes, and Custom Metadata deployed;
- the `CPQ_Document_Totals` permission set;
- one calculated sandbox Quote with a successful generated result;
- the API name of every field read by an active custom Flow or Apex row adjustment; and
- a developer for Execute Anonymous and Apex-owned changes.

**Stop here if** a custom adjustment reads changing data that is neither declared nor configured to always rebuild, or a document launch reads Ready rows without first calling generate-or-reuse.

## Terms in plain language

| Term                  | Meaning                                                                        |
| --------------------- | ------------------------------------------------------------------------------ |
| Stale                 | Saved result is no longer safe because relevant data changed.                  |
| Change check          | Stored comparison value representing the inputs that can affect the output.    |
| Customizer version    | Value on a table definition that must change when custom behavior changes.     |
| Declared dependencies | Comma-separated field paths that a custom adjustment reads in related records. |
| Always rebuild        | Safe policy when changing inputs cannot be fully listed.                       |

## Configure in Salesforce

### How freshness works

Two controls work together:

1. Quote and Quote Line automation marks existing saved data `Stale` after relevant edits. The Quote Line update runs after CPQ calculation so CPQ does not overwrite the status.
2. Every **Generate Document Tables** run creates a new change check from relevant Quote data, Quote Lines, configured field paths, active setup, presentation text, language, content versions, columns, and custom-adjustment details.

The change check also catches items that record automation cannot see directly, such as a Product field reached through a configured field path or a Custom Metadata change.

### Reuse requirements

The existing saved data is reused only when all required conditions hold, including:

- Quote status is `Ready`;
- the stored and freshly computed change checks match;
- every applicable active table exists;
- required table structure, including Grand Total rows, is intact;
- no custom adjustment uses `ALWAYS_REBUILD`.

If any condition fails, generation replaces the saved result as one complete operation.

### Configure a custom adjustment

1. In **Setup**, open **Custom Metadata Types**.
2. Find **Quote Document Table Definition** and select **Manage Records**.
3. Open the table that uses the Flow or registered Apex adjustment.
4. Set the matching version field:
   - use **Row Customizer Flow Version** for a Flow; or
   - use **Row Customizer Version** for registered Apex.
5. Use `1` for the first released behavior. Increase the whole number by one whenever the result can change, even when the Flow or Apex API name stays the same.
6. Set **Cache Policy** using this table:

   | Value                   | Use it when                                                                                                                                                                     |
   | ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
   | `STANDARD`              | The adjustment uses only values already represented by the standard Quote and Quote Line inputs. Leave **Contributor Dependency Set** blank.                                    |
   | `DECLARED_DEPENDENCIES` | The adjustment reads additional fields through the Quote, such as `SBQQ__Account__r.Customer_Tier__c`. Enter every path in **Contributor Dependency Set**, separated by commas. |
   | `ALWAYS_REBUILD`        | The changing inputs cannot be listed completely, such as a live response from another system. Leave **Contributor Dependency Set** blank.                                       |

7. For `DECLARED_DEPENDENCIES`, write each path relative to the Quote. Do not include `SBQQ__Quote__c.` at the start. Example: `SBQQ__Account__r.Customer_Tier__c,Contract_Tier__c`.
8. Save the table definition while it remains inactive, then test the cases below.

Changing Flow or Apex behavior without increasing its matching version can leave a Quote marked `Ready` with an older result. Deploy the behavior change, new version value, and any dependency change together.

After deploying a global metadata or custom-adjustment change that existing saved results cannot observe through triggers, ask a developer or administrator with Execute Anonymous access to run:

```apex
Database.executeBatch(new QuoteDocumentInvalidationJob(), 200);
```

The job selects only `Ready` Quotes and marks successfully processed records `Stale`. Running it again is safe. Confirm completion in **Setup → Apex Jobs**. For failed records, ask the developer to capture the batch user's debug log, find `Invalidation complete:`, correct the stated cause, and run the batch again.

## Worked example

1. Generate a calculated Quote. Confirm its Document Data Status becomes `Ready`.
2. Select **Generate Document Tables** again without editing anything. Confirm the Flow reports that the saved result was reused.
3. Change a Quote Line Quantity, calculate the Quote, and confirm Document Data Status becomes `Stale`. Generate again and confirm the changed quantity appears.
4. Change a field that no active table or custom adjustment reads. Generate again and confirm reuse.
5. Change an active table's Display Title. Generate again and confirm a rebuild contains the new title.

### Operational behavior

- Generation is request-driven, not automatic on every save. Salesforce CPQ may write a Quote several times for one user action.
- Irrelevant edits can leave the reusable saved data intact.
- A relevant edit blocks document use by producing `Stale`; the next generate action rebuilds.
- Every document launch must run the shipped generate-or-reuse operation first. Reading saved rows directly bypasses the fresh change check.

## Generate and verify

1. Complete all five worked-example tests and record the result.
2. For each custom adjustment, change one declared source value and confirm the next run rebuilds.
3. Increase its matching version and confirm the next run rebuilds.
4. If it reads a related Account or Product field, change that field and confirm the next run rebuilds even when the Quote status did not change immediately.
5. Change a translated label or Document Content version and confirm the next run rebuilds.
6. Temporarily deactivate an expected table or remove a Grand Total row only in a disposable test setup. Confirm the next run rebuilds or fails instead of reusing incomplete data, then restore the setup.
7. Confirm the final Quote is `Ready`, every expected table is `Complete`, and the visible values reflect the latest inputs.

## Troubleshooting

| Problem                          | What it means                                          | What to do                                                    |
| -------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------- |
| Old custom output is reused      | Version or dependency list was not changed.            | Correct both, run the invalidation batch, and generate again. |
| Every run rebuilds               | Policy is Always Rebuild or an input changes each run. | Confirm policy and identify unstable declared data.           |
| Relevant edit leaves Quote Ready | Trigger cannot see it and dependency is missing.       | Add the exact field path or use Always Rebuild.               |
| Invalidation batch fails records | Access or record-specific error occurred.              | Review Apex Jobs/debug summary, correct failures, and rerun.  |

## Deactivate or roll back

1. Edit the affected table definition.
2. Clear **Row Customizer Flow** or **Row Customizer Code**, whichever is populated.
3. Increase the matching Flow or Apex customizer version by one.
4. Save the table definition.
5. Run `Database.executeBatch(new QuoteDocumentInvalidationJob(), 200);` in Execute Anonymous.
6. Generate an affected test Quote and confirm the standard rows return.

Never set Document Data Status to `Ready` or edit the `Document Data Fingerprint` field by hand. That field is Salesforce's saved change-check value.

## Production checklist

- [ ] Every custom adjustment has a version and safe cache policy.
- [ ] All extra field dependencies are declared exactly.
- [ ] Unchanged run reuses; relevant edits rebuild.
- [ ] Presentation and translation changes rebuild.
- [ ] Every document launch calls generate-or-reuse first.
