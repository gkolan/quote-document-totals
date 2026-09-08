# Configuration diagnostics

Run configuration diagnostics after deployment, after changing Custom Metadata or registered extensions, and before enabling generation for users. The check reads configuration and Salesforce schema only. It does not query a Quote or write generated document data.

## Access

Assign `CPQ_Document_Totals_Generator_Admin` to the administrator or release operator running the check. This small permission set grants access only to the diagnostic Apex class; the operator still needs the organization's normal access to CPQ and project metadata. Do not assign this administrative check merely to let a user generate documents; generation uses `CPQ_Document_Totals_Generator`.

## Run from Salesforce CLI

```bash
sf org assign permset --target-org qdt-test --name CPQ_Document_Totals_Generator_Admin
sf apex run --target-org qdt-test --file scripts/apex/quote-document-configuration-diagnostics.apex
```

Find the log entry beginning `QDTD_CONFIGURATION_DIAGNOSTICS`. A healthy result has `"ready": true` and an empty `issues` list. Record the timestamp and counts with release evidence.

The current check validates:

- active Table Definition structure through the same loader generation uses;
- resolved and validated Columns for every active table;
- Quote Line grouping field paths;
- Quote dependency, comparison-source, and configured locale field paths;
- registered Apex row customizers, expanders, comparison sources, and document composers;
- active composer type, version, order, and dependency declarations; and
- that at least one active Table Definition exists.

Failures return stable `code`, `severity`, and `message` fields. `CONFIGURATION_INVALID` means the existing validator or registry rejected a specific setting; the message names the field, code, or relationship to repair. `NO_ACTIVE_TABLE_DEFINITIONS` means deployment succeeded but no document table can be generated.

## Current limits

This first diagnostic entry point does not prove that a configured Flow exists and returns its required Apex-defined values, validate a document tool, inspect page layouts, or test a representative user's field and record access. Those require the Flow contract tests, install preflight, protected deployment validation, and representative-user smoke test. Diagnostics success must not be presented as complete installation proof.

After repairing configuration, rerun diagnostics and generate a controlled Quote. Do not edit generated Table, Row, Column, Block, or Fact records to work around a diagnostic failure.
