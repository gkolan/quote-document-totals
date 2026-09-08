"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const {
  validateFixtureDirectory,
  validatePayload
} = require("./renderer-contract");

const contractRoot = path.resolve("contracts/v2");
const schema = JSON.parse(
  fs.readFileSync(
    path.join(contractRoot, "quote-document-payload.schema.json"),
    "utf8"
  )
);

test("all canonical valid and invalid fixtures have the expected result", () => {
  const outcomes = validateFixtureDirectory(contractRoot);
  assert.equal(outcomes.filter((item) => item.expected === "valid").length, 4);
  assert.equal(
    outcomes.filter((item) => item.expected === "invalid").length,
    2
  );
  for (const outcome of outcomes) {
    assert.equal(
      outcome.errors.length === 0,
      outcome.expected === "valid",
      `${outcome.file}: ${outcome.errors.join("; ")}`
    );
  }
});

test("request and fingerprint expectations are mandatory integration bindings", () => {
  const payload = JSON.parse(
    fs.readFileSync(
      path.join(contractRoot, "fixtures/valid/table-only.json"),
      "utf8"
    )
  );
  assert.deepEqual(
    validatePayload(payload, schema, {
      requestId: payload.requestId,
      fingerprint: payload.fingerprint
    }),
    []
  );
  const errors = validatePayload(payload, schema, {
    requestId: "a newer request",
    fingerprint: "a different fingerprint"
  });
  assert.equal(errors.length, 2);
  assert.match(errors.join("\n"), /expected generation request/);
  assert.match(errors.join("\n"), /expected snapshot fingerprint/);
});

test("typed currency values cannot arrive as formatted text", () => {
  const payload = JSON.parse(
    fs.readFileSync(
      path.join(contractRoot, "fixtures/valid/table-only.json"),
      "utf8"
    )
  );
  payload.sections[0].rows[0].values.COL_NET = "$54,000.00";
  const errors = validatePayload(payload, schema);
  assert.match(errors.join("\n"), /Currency requires a JSON number or null/);
});

test("unknown payload fields fail instead of disappearing silently", () => {
  const payload = JSON.parse(
    fs.readFileSync(
      path.join(contractRoot, "fixtures/valid/block-only.json"),
      "utf8"
    )
  );
  payload.unreviewedVendorField = "must not be ignored";
  const errors = validatePayload(payload, schema);
  assert.match(errors.join("\n"), /additional property is not allowed/);
});
