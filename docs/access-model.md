# Access roles

Quote Document Totals separates ordinary generation, document retrieval, configuration diagnostics, and operational recovery. Assign only the role required for the action a user or integration performs.

These permission sets supplement Salesforce CPQ licenses, CPQ object and field permissions, Quote sharing, report-folder sharing, page layout assignment, and the organization's existing security controls. They do not grant access to every Quote.

## Supplied permission sets

| Permission set                   | Assign to                                   | Grants                                                                                                           | Does not grant                                                                                          |
| -------------------------------- | ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `CPQ_Document_Totals_Generator`  | People who run **Generate Document Tables** | Generation Flow, Run Flows, `QuoteDocumentGenerator`, read-only lifecycle fields, and read-only generated output | JSON retrieval adapter, output editing, diagnostics, recovery, CPQ entitlements, or Quote record access |
| `CPQ_Document_Totals_Retrieval`  | The document integration principal          | JSON adapter, REST retrieval endpoint, and read-only lifecycle and generated-output fields                       | Generation Flow, Run Flows, output tabs, editing, diagnostics, or recovery                              |
| `CPQ_Document_Totals_Admin`      | Release and configuration administrators    | Read-only configuration diagnostics and the diagnostic Apex service                                              | Generation, document retrieval, output editing, or recovery                                             |
| `CPQ_Document_Totals_Operations` | Staff responsible for invalidation recovery | Private run/failure records and guarded invalidation retry                                                       | Generation, document retrieval, or configuration maintenance                                            |
| `CPQ_Document_Totals`            | Existing installations during migration     | Generator, JSON/REST retrieval entry paths, and read-only review                                                 | Diagnostics, recovery, generated-output editing, CPQ entitlements, or Quote record access               |

The compatibility role remains so upgrades do not remove an existing assignment. It no longer grants create, edit, or delete access to generated records or edit access to lifecycle fields. New installations should use the smaller Generator and Retrieval roles.

## Generated-record sharing

Quote Document Tables, Blocks, and Facts use private sharing. Columns and Rows inherit access from their parent Table. The generator writes system-managed output, but retrieval runs with sharing and user-mode queries. A retrieval principal therefore needs record access to the source Quote and the generated records it is allowed to render.

Choose and test an organization-specific sharing mechanism when generation and retrieval use different principals. For example, use a criteria-based sharing rule, Apex managed sharing reviewed for this data model, or run retrieval as the same owning principal. Do not make generated objects publicly readable to avoid designing the sharing boundary.

## Assign roles for a new installation

Assign generation access:

```bash
sf org assign permset --target-org qdt-test --name CPQ_Document_Totals_Generator
```

Assign `CPQ_Document_Totals_Retrieval` to the integration user through **Setup -> Users -> Permission Set Assignments** or the organization's approved user-management automation. Record the assignee by internal role, without copying a username into release evidence.

## Migrate an existing installation

1. Inventory every assignment of `CPQ_Document_Totals` and identify whether each assignee generates, retrieves, or only reviews output.
2. Assign `CPQ_Document_Totals_Generator` to generators and `CPQ_Document_Totals_Retrieval` to document integration principals.
3. Configure the minimum record-sharing path needed between generators and retrieval principals.
4. Complete the positive and negative checks below.
5. Remove the compatibility permission set from migrated users. Keep it available until all assignments are verified.

Removing a permission-set assignment does not delete generated data or stop a job already queued. Restore the previous assignment if a pilot user loses an approved action, then correct the smaller role or sharing rule before retrying the migration.

## Required sandbox checks

Use synthetic Quotes and users derived from the organization's normal sales and integration profiles.

- A generator can see and run **Generate Document Tables** on an accessible Quote.
- The generator can review saved output but cannot edit or delete Tables, Columns, Rows, Blocks, or Facts.
- A retrieval principal can call the REST endpoint and render only when Quote, request ID, fingerprint, and record sharing all match.
- The retrieval principal cannot see or run the generation Flow and cannot edit generated output.
- A user without access to the Quote cannot retrieve its payload.
- A user with Quote access but without the Retrieval role cannot call the JSON adapter.
- Diagnostics and operations users can perform only the actions in their respective guides.
- Removing each role causes a clear access denial without changing existing generated data.

Record the profile or baseline permission-set group, CPQ entitlement, assigned Quote owner, sharing rule, role assignment, action attempted, and result. Do not commit usernames, org URLs, record IDs, or screenshots containing customer data.

## Automated boundary

`npm run test:ci-gate` checks that the Generator role contains only the generation entry path, the Retrieval role contains only the JSON and REST retrieval paths, all three user-facing roles keep generated data read-only, and top-level generated objects use private sharing. This source check prevents accidental permission expansion. It does not replace the sandbox checks above.
