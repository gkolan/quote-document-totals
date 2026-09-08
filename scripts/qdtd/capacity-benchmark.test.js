const test = require("node:test");
const assert = require("node:assert/strict");

const {
  assess,
  benchmarkApex,
  buildReport,
  parseArguments,
  ratio
} = require("./capacity-benchmark");

function measurement(cpuMs = 5000) {
  return {
    tier: 100,
    status: "Completed",
    generation: {
      cpuMs,
      cpuLimitMs: 10000,
      heapEndBytes: 1000,
      heapLimitBytes: 10000,
      soqlQueries: 5,
      soqlLimit: 100,
      queriedRows: 100,
      queryRowLimit: 50000,
      dmlStatements: 10,
      dmlStatementLimit: 150,
      dmlRows: 500,
      dmlRowLimit: 10000
    },
    output: { payloadBytes: 1000 },
    render: { cpuMs: 10 }
  };
}

test("requires a target org and uses ignored artifact defaults", () => {
  assert.throws(() => parseArguments([]), /--target-org/);
  const options = parseArguments(["--target-org", "qdt"]);
  assert.match(options.fixtures, /^artifacts\//u);
  assert.match(options.output, /^artifacts\//u);
});

test("benchmark source forces rebuild and binds renderer identity", () => {
  const source = benchmarkApex({ tier: 100, quoteId: "a0q000000000001AAA" });
  assert.match(source, /Document_Data_Status__c = 'Stale'/);
  assert.match(source, /outcome\.requestId, outcome\.fingerprint/);
  assert.match(source, /Blob\.valueOf\(payload\)\.size\(\)/);
});

test("rejects an injectable or malformed fixture ID", () => {
  assert.throws(
    () => benchmarkApex({ tier: 10, quoteId: "x'; delete Account;" }),
    /Salesforce Quote Id/
  );
});

test("reports observed headroom without claiming a supported envelope", () => {
  assert.equal(ratio(75, 100), 0.75);
  const result = assess(measurement());
  assert.equal(result.observedHeadroomAtLeast25Percent, true);
  assert.equal(result.supportedEnvelopeEstablished, false);
  assert.match(result.reason, /peak heap/);
});

test("fails observed headroom when a measured ratio exceeds 75 percent", () => {
  assert.equal(
    assess(measurement(7501)).observedHeadroomAtLeast25Percent,
    false
  );
});

test("published report removes fixture record IDs", () => {
  const report = buildReport(
    { targetOrg: "qdt" },
    { schemaVersion: "1.0", fixtures: [{ quoteId: "a0q000000000001AAA" }] },
    [measurement()],
    new Date("2026-09-08T00:00:00Z")
  );
  assert.equal(report.safety.containsOrgRecordIds, false);
  assert.doesNotMatch(JSON.stringify(report), /a0q000000000001AAA/);
  assert.doesNotMatch(JSON.stringify(report), /qdt/);
});
