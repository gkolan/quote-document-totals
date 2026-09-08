const test = require("node:test");
const assert = require("node:assert/strict");

const {
  normalize,
  secretContentFailures,
  trackedPathFailures
} = require("./check-publication-hygiene");

test("normalizes repository paths", () => {
  assert.equal(normalize(".\\reports\\audit.md"), "reports/audit.md");
});

test("rejects internal and generated tracked paths", () => {
  const failures = trackedPathFailures([
    "repository-review/findings.md",
    "implementation-evidence/run.json",
    "reports/audit.md",
    "scan.sarif"
  ]);
  assert.equal(failures.length, 4);
});

test("allows Salesforce report metadata", () => {
  assert.deepEqual(
    trackedPathFailures([
      "force-app/main/default/reports/CPQ_Document_Totals/report.report-meta.xml"
    ]),
    []
  );
});

test("detects high-confidence credentials without flagging variable names", () => {
  const credential = ["client_secret", "'abcdefghijk'"].join("=");
  const privateKey = ["-----BEGIN", "PRIVATE KEY-----"].join(" ");
  assert.deepEqual(
    secretContentFailures([["safe.js", "const accessToken = value;"]]),
    []
  );
  assert.equal(secretContentFailures([["bad.env", credential]]).length, 1);
  assert.equal(secretContentFailures([["key.txt", privateKey]]).length, 1);
});
