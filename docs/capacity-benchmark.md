# Measure generation capacity

Use this harness in a disposable Salesforce CPQ test org to measure the current release candidate at 10, 100, 500, and 1,000 Quote Lines. It creates synthetic records and replaces their generated snapshots. It is not a read-only command.

## Before you run it

Deploy the exact candidate source and assign the required administrative test access. Use an org with no customer data. The fixture builder owns only an Account, Opportunity, Product, and Quotes carrying the exact `QDTD Capacity Fixture`, `QDTD-CAPACITY-1`, and `QDTD-CAP-*` markers.

**Stop here if** the org contains business data using any of those reserved markers, the candidate source is not deployed, CPQ calculation automation has not settled, or deletion and recreation of the synthetic Quotes is not acceptable.

## Prepare the fixtures

```bash
npm run prepare:capacity-fixtures -- --target-org qdt-capacity
```

Each tier runs in a separate anonymous-Apex transaction so the 1,610 total fixture lines do not share one transaction limit. The default tiers are fixed in source as 10, 100, 500, and 1,000 lines. The command writes Quote IDs to `artifacts/capacity/fixtures.json`. That file is ignored and must never be attached to a public issue or committed.

To rerun a smaller diagnostic subset:

```bash
npm run prepare:capacity-fixtures -- --target-org qdt-capacity --tiers 10,100
```

## Measure generation and retrieval

```bash
npm run benchmark:capacity -- --target-org qdt-capacity
```

For each tier, the harness marks the synthetic Quote stale outside the measurement window, then calls the synchronous generator. It records:

- generation CPU time and limit;
- heap at the start and end observation points and the heap limit;
- SOQL statements and queried rows;
- DML statements and rows;
- generated Tables, Columns, Rows, Blocks, and Facts;
- identity-bound JSON payload bytes; and
- retrieval CPU and heap endpoint.

The sanitized report is written to `artifacts/capacity/benchmark.json`. It omits Quote IDs and customer field values. Both commands mutate the disposable org and replace prior capacity fixtures with the same marker.

## Interpret the result

`observedHeadroomAtLeast25Percent` is true only when every measured ratio is at or below 75% of its transaction limit. This is one observation, not a supported capacity claim. Apex exposes current heap at an observation point rather than peak heap, so `supportedEnvelopeEstablished` remains false by design.

Before publishing a supported S, M, or L tier:

1. repeat the measurement on the exact release candidate in the supported CPQ org shape;
2. capture peak heap with reviewed phase instrumentation;
3. include representative contributor, grouping, bundle, period, description-length, and optional-line density;
4. repeat enough runs to disclose variation rather than one best result;
5. compare semantic totals and payload hashes with the smaller baseline;
6. keep at least 25% CPU and heap headroom; and
7. attach the sanitized evidence to the protected release run rather than Git.

A failed or over-limit tier remains useful evidence. Do not reduce document detail silently, increase a published ceiling from one run, or describe a Salesforce platform limit as this project's supported capacity.

## Remove the fixtures

Delete only Quotes whose **Quote Key** starts with `QDTD-CAP-`, then delete the Account, Opportunity, and Product with the exact reserved capacity markers if no longer needed. Review the selected records before deletion. Removing local `artifacts/capacity` files does not remove Salesforce records.
