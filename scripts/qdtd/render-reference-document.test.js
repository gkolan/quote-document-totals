"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  canonicalJson,
  createManifest,
  renderValidated
} = require("./render-reference-document");

const root = path.resolve("contracts/v2");
const schema = JSON.parse(
  fs.readFileSync(path.join(root, "quote-document-payload.schema.json"), "utf8")
);
const mixed = JSON.parse(
  fs.readFileSync(path.join(root, "fixtures/valid/mixed.json"), "utf8")
);

test("reference renderer preserves binding identity and escapes source text", () => {
  const { html } = renderValidated(mixed, schema, {
    requestId: mixed.requestId,
    fingerprint: mixed.fingerprint
  });
  assert.match(html, /data-contract-version="2\.0"/);
  assert.match(html, new RegExp(`data-request-id="${mixed.requestId}"`));
  assert.match(html, /Secure &lt;Gateway&gt;/);
  assert.match(html, /Includes setup &amp; validation\./);
  assert.doesNotMatch(html, /Secure <Gateway>/);
  assert.match(html, /GBP[^<]*1,250\.50/);
});

test("manifest makes output and source identity reproducible", () => {
  const first = renderValidated(mixed, schema, {
    requestId: mixed.requestId,
    fingerprint: mixed.fingerprint
  });
  const second = createManifest(mixed, first.html);
  assert.deepEqual(first.manifest, second);
  assert.equal(first.manifest.output.sha256.length, 64);
  assert.equal(first.manifest.sourcePayloadSha256.length, 64);
  assert.equal(first.manifest.requestId, mixed.requestId);
  assert.equal(first.manifest.fingerprint, mixed.fingerprint);
  assert.equal(first.manifest.output.bytes, Buffer.byteLength(first.html));
});

test("source hash uses canonical property ordering", () => {
  const reversed = Object.fromEntries(Object.entries(mixed).reverse());
  assert.equal(canonicalJson(mixed), canonicalJson(reversed));
  assert.equal(
    createManifest(mixed, "same output").sourcePayloadSha256,
    createManifest(reversed, "same output").sourcePayloadSha256
  );
});

test("mixed fixture matches the reviewed golden document and manifest", () => {
  const result = renderValidated(mixed, schema, {
    requestId: mixed.requestId,
    fingerprint: mixed.fingerprint
  });
  const goldenHtml = fs
    .readFileSync(path.join(root, "golden/mixed.html"), "utf8")
    .trimEnd();
  const goldenManifest = JSON.parse(
    fs.readFileSync(path.join(root, "golden/mixed.manifest.json"), "utf8")
  );
  assert.equal(result.html, goldenHtml);
  assert.deepEqual(result.manifest, goldenManifest);
});

test("renderer rejects a stale or substituted invocation", () => {
  assert.throws(
    () =>
      renderValidated(mixed, schema, {
        requestId: "REQ-OLDER",
        fingerprint: mixed.fingerprint
      }),
    /expected generation request/
  );
});

test("renderer refuses unsupported payload versions before output", () => {
  const unsupported = { ...mixed, contractVersion: "3.0" };
  assert.throws(
    () =>
      renderValidated(unsupported, schema, {
        requestId: unsupported.requestId,
        fingerprint: unsupported.fingerprint
      }),
    /expected constant "2\.0"/
  );
});
