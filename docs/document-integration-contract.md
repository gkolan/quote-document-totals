# Renderer contract and reference document

Renderer developers can consume the v2 document payload without reading Apex. The public contract consists of:

- [`quote-document-payload.schema.json`](../contracts/v2/quote-document-payload.schema.json), the strict JSON shape for contract version `2.0`;
- canonical table-only, block-only, and mixed fixtures under [`contracts/v2/fixtures/valid`](../contracts/v2/fixtures/valid);
- intentionally rejected fixtures under [`contracts/v2/fixtures/invalid`](../contracts/v2/fixtures/invalid);
- independent expected commercial values under [`contracts/v2/fixtures/expectations`](../contracts/v2/fixtures/expectations); and
- [`reference-html-capabilities.json`](../contracts/v2/reference-html-capabilities.json), an explicit capability and limitation declaration.
- the reviewed [`mixed.html`](../contracts/v2/golden/mixed.html) output and its [`mixed.manifest.json`](../contracts/v2/golden/mixed.manifest.json) identity evidence.

Run the conformance checks from a clean checkout:

```bash
npm ci
npm run test:renderer-contract
node --test scripts/qdtd/renderer-contract.test.js scripts/qdtd/render-reference-document.test.js
```

The valid fixtures must pass with no errors, and every invalid fixture must fail. The runner checks the published schema and semantic rules that JSON Schema alone cannot express clearly: section and column ordering, unique section keys, table/block shape, complete row values, declared value types, and optional expected request/fingerprint bindings.

## Produce the reference document

This command renders the mixed fixture and writes HTML plus a machine-readable manifest:

```bash
npm run render:reference-document -- \
  --input contracts/v2/fixtures/valid/mixed.json \
  --output-dir artifacts/reference-document \
  --expected-request-id REQ-MIXED-001 \
  --expected-fingerprint fixture-mixed-v1
```

Open `artifacts/reference-document/quote-document.html` in a browser or print it to PDF for evaluation. The output manifest records the Quote, generation request, source fingerprint, contract and renderer versions, media type, byte count, canonical input hash, and output hash. Repeating the command with the same payload produces the same HTML and hashes.

The checked fixture deliberately includes `<`, `>`, and `&` in source values. Tests require those values to be escaped. Currency remains a JSON number in the payload and is formatted only by the renderer using the payload locale and ISO currency code. The renderer does not calculate totals; `table-only.expected.json` independently states that the Product Family Summary grand total must be `102910`.

## Bind retrieval to the generated snapshot

Assign `CPQ_Document_Totals_Retrieval` to the integration principal. It grants read-only generated-data access plus the `QuoteDocumentJsonAdapter` and `QuoteDocumentRestResource` retrieval paths, without the generation Flow, Run Flows, output editing, tabs, diagnostics, or recovery. The principal must also have access to the source Quote and to its generated records under the organization's sharing model. Do not assign the Generator role merely to make retrieval work.

In Salesforce, call `QuoteDocumentJsonAdapter.render(quoteId, expectedRequestId, expectedFingerprint)` only with the request ID and fingerprint returned by the preceding generation or reuse operation. `QuoteDocumentRenderService` checks readiness, both identities, sharing, and payload integrity before the adapter receives data. A renderer must reject a missing or mismatched identity before writing output. The local reference command requires the same two expectations to prevent a substituted fixture from appearing valid.

Do not retrieve by Quote ID alone, query generated rows directly, recompute totals, accept an unknown major contract version, or copy a mutable debug description into a customer document.

## Export a live generated document

The repository includes one complete reference path from an authenticated Salesforce session to validated HTML. Use a synthetic Quote in a CPQ test org first.

1. Generate the Quote with **Generate Document Tables** and confirm **Document Data Status** is `Ready`.
2. Read the Quote's `Id`, `Document_Data_Request_Id__c`, and `Document_Data_Fingerprint__c`. Keep these operational values out of issues, commits, and release artifacts.
3. Authenticate Salesforce CLI as the retrieval principal. The principal needs `CPQ_Document_Totals_Retrieval` and the record-sharing access described above.
4. Run the exporter with all three values from the same generation:

```bash
npm run export:live-document -- \
  --target-org qdt-test \
  --quote-id 0Q0REPLACE_WITH_TEST_QUOTE_ID \
  --request-id REPLACE_WITH_GENERATION_REQUEST_ID \
  --fingerprint REPLACE_WITH_GENERATION_FINGERPRINT
```

The command calls `GET /services/apexrest/quote-document-totals/v2/quotes/{quoteId}` with the `X-QDTD-Request-Id` and `X-QDTD-Fingerprint` headers. It uses the existing CLI session in memory, rejects responses larger than 20 MiB, validates the v2 schema and semantic contract, and writes three ignored local files:

- `artifacts/live-document/quote-document.payload.json`
- `artifacts/live-document/quote-document.html`
- `artifacts/live-document/quote-document.manifest.json`

Open the HTML file in a browser and compare its sections, rows, and totals with the generated Salesforce records and the approved Quote. Repeating an export of the same snapshot must produce the same source and output hashes.

A `409 SNAPSHOT_MOVED` response means another generation replaced the snapshot. Generate again and use the new request ID and fingerprint. A `409 SNAPSHOT_NOT_READY` response means generation has not published a complete snapshot. Endpoint error bodies do not reflect record IDs, fingerprints, hashes, customer values, or raw Apex exceptions.

The exporter restricts output to the ignored `artifacts/` tree because a live payload can contain customer and record data. Keep that restriction in derived tooling.

## Supported boundary

The reference renderer is a deterministic semantic HTML integration and conformance example. Its capability file declares unsupported features such as pagination, signatures, right-to-left layout, images, accessible tagged PDF, and password protection. The live exporter applies a 20 MiB local safety ceiling; that ceiling is not a supported Salesforce capacity claim.

The source ships an identity-bound Apex REST endpoint, a strict client, and the deterministic HTML adapter as one reproducible implementation path. Release evidence still requires compiling and testing the endpoint in the release-candidate org, exporting an actual generated payload, comparing it with independently approved expected totals, and rehearsing the complete flow with a representative user. Organizations that need PDF generation, signatures, or delivery must qualify a document product against the same contract and declared capabilities.

## Version changes

Additive fields require a reviewed contract decision because the v2.0 schema rejects unknown properties instead of silently losing them. An incompatible shape requires a new major contract directory, fixtures, capability declaration, and version negotiation tests. Keep the old contract and conformance corpus for every still-supported major version.
