# Retention inventory

Run the retention inventory before enabling or changing scheduled deletion in an established org. The tool executes aggregate-only SOQL, returns no Quote or customer field values, and makes no Salesforce data changes.

```bash
npm run inventory:retention -- --target-org qdt-test --output-dir artifacts/retention-inventory
```

The default policy matches `QuoteDocumentRetention`: rejected or denied Quotes with generated state are eligible, and generated snapshots older than 90 days are eligible unless the Quote is Accepted. Override the age only when reviewing a deliberate policy change:

```bash
npm run inventory:retention -- --target-org qdt-test --retention-days 120 --estimated-kb-per-record 2
```

The output directory contains JSON with the executed aggregate queries and CSV with portable metric/value rows. It reports:

- eligible Quotes and eligible Tables, Columns, Rows, Blocks, and Facts;
- eligible block-only, table-only, mixed, and facts-only Quote shapes;
- generated children attached to a Quote whose lifecycle says `Not Generated` or is blank; and
- a planning storage estimate based on the supplied kilobytes-per-record assumption.

The storage figure is an estimate, not a Salesforce invoice or measured byte count. Confirm the applicable storage behavior and pricing for the target org. Record the assumption with the inventory artifact.

## Review before deletion

1. Confirm the target alias identifies the intended sandbox or inventory org.
2. Compare the cutoff and retention days with the approved policy.
3. Investigate every facts-only or inconsistent-child count. Routine retention assumes the parent lifecycle is authoritative; historical repair requires a separate reviewed plan.
4. Export any accepted, signed, or historical artifact that cannot be regenerated from current Quote inputs.
5. Rehearse the batch with synthetic data and verify table-only, block-only, mixed, newly Accepted, and recently regenerated Quotes.
6. Enable or change the schedule only after the inventory owner records approval and rollback limits.

Disabling the schedule prevents future deletion but cannot restore purged records. Regeneration creates output from current inputs and is not recovery for a historical or signed document.
