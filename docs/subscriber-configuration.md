# Subscriber-safe configuration

An organization can declare additional direct Quote fields that affect document output without editing the stock staleness, query, or fingerprint classes. Create a **Quote Document Watched Field** Custom Metadata record for each field.

This layer is append-only. Core dependencies always remain active, and subscriber records can only add fields. An inactive subscriber record has no effect. When no subscriber records exist, generation follows the stock field set exactly.

## Add a watched Quote field

1. Confirm the field is a direct field on `SBQQ__Quote__c`, the generation user can read it, and a supported contributor or composer actually uses it.
2. Create a Quote Document Watched Field record. Start its **Developer Name** with `SUB_`, such as `SUB_PURCHASE_ORDER_CLASS`.
3. Set **Field API Name** to the exact direct field name, such as `Purchase_Order_Class__c`. Relationship paths are rejected because changing the related record would not run the Quote trigger.
4. Set **Version** to a stable value such as `1`. Increase it whenever subscriber logic changes how the field affects output, even if the field value itself is unchanged.
5. Select **Active**, then run [configuration diagnostics](configuration-diagnostics.md). A missing field, duplicate path, relationship path, blank version, wrong prefix, or generation lifecycle field fails diagnostics and generation instead of silently narrowing freshness checks.
6. Generate a test Quote, change only the watched field, and confirm the Quote becomes `Stale`. Generate again and confirm the request ID and fingerprint change and the intended output changes.

An active record participates in three places through one implementation:

- the Quote trigger compares its old and new values and closes the Ready gate;
- the generation query selects it in user mode, which enforces field access; and
- the input fingerprint includes the record name, version, field path, and typed Salesforce value.

This prevents a field from being watched without being hashed, or hashed without being selected.

## Ownership and upgrade rules

`QDTD_` is reserved for future stock records. Subscriber records must use `SUB_`. The loader rejects two active records for the same field even when their letter case differs, so precedence cannot depend on query order. Stock watched fields cannot be disabled through subscriber metadata.

Keep subscriber records in the organization's own source directory or package. Do not add them to a vendor release archive. Capture them immediately before and after every upgrade:

```console
npm run snapshot:subscriber-config -- --target-org my-org --output artifacts/subscriber-upgrade/before.json
# Install the release candidate through the chosen package or source process.
npm run snapshot:subscriber-config -- --target-org my-org --output artifacts/subscriber-upgrade/after.json
npm run compare:subscriber-config -- --before artifacts/subscriber-upgrade/before.json --after artifacts/subscriber-upgrade/after.json --output artifacts/subscriber-upgrade/comparison.json
```

Capture queries only `SUB_` custom metadata records and records no Quote or customer field values. Comparison exits unsuccessfully if a previous record was removed or its label, field, active state, or version changed. New subscriber records are allowed. Retain all three JSON files with release evidence.

After the comparison passes, run diagnostics and the field-only change test again. A source deployment does not prove that a managed or unlocked package upgrade will preserve records; rehearse the chosen package model before claiming upgrade support.

## Limits

This first subscriber layer supports direct Quote fields only. Quote Line changes already mark their Quote stale, while declared composer line dependencies are selected and fingerprinted. Related Account fields require the existing Account staleness trigger or a future validated related-object extension; placing `SBQQ__Account__r.Name` in this metadata is rejected.

The watched-field record does not itself place a value in the payload. Use the validated Flow bridge, a registered stock Apex extension, or a supported composer to produce the output. Continue to version that extension through its existing contributor version field.
