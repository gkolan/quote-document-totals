const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const {
  buildQueries,
  buildReport,
  csvRows,
  parseArguments,
  parseCount,
  quoteEligibility,
  salesforceDatetime
} = require("./retention-inventory");

test("requires an explicit org and validates planning assumptions", () => {
  assert.throws(() => parseArguments([]), /--target-org is required/);
  assert.throws(
    () => parseArguments(["--target-org", "qdt", "--retention-days", "0"]),
    /positive number/
  );
  assert.deepEqual(
    parseArguments([
      "--target-org",
      "qdt",
      "--retention-days",
      "45",
      "--estimated-kb-per-record",
      "2.5",
      "--output-dir",
      "evidence"
    ]),
    {
      targetOrg: "qdt",
      retentionDays: 45,
      estimatedKbPerRecord: 2.5,
      outputDir: "evidence"
    }
  );
});

test("uses the same lifecycle fields and protections as Apex retention", () => {
  const cutoff = "2026-06-09T12:00:00Z";
  const predicate = quoteEligibility(cutoff);
  assert.match(predicate, /SBQQ__Status__c IN \('Rejected','Denied'\)/);
  assert.match(predicate, /Document_Data_Status__c != 'Not Generated'/);
  assert.match(predicate, /Document_Data_Generated_On__c < 2026-06-09/);
  assert.match(predicate, /SBQQ__Status__c != 'Accepted'/);

  const queries = buildQueries(cutoff);
  assert.equal(Object.keys(queries).length, 15);
  for (const query of Object.values(queries)) {
    assert.match(
      query,
      /^SELECT (COUNT\(\)|COUNT_DISTINCT\([A-Za-z0-9_]+\)) FROM /
    );
  }
  assert.match(queries.eligibleBlockOnlyQuotes, /Id NOT IN.*Table/);
  assert.match(
    queries.eligibleFactsOnlyQuotes,
    /^SELECT COUNT_DISTINCT\(Quote__c\).*Quote__c NOT IN.*Table/
  );
  assert.match(queries.inconsistentRows, /Document_Data_Status__c = NULL/);

  const retentionSource = fs.readFileSync(
    path.join(
      __dirname,
      "..",
      "..",
      "force-app",
      "main",
      "default",
      "classes",
      "QuoteDocumentRetention.cls"
    ),
    "utf8"
  );
  for (const token of [
    "SBQQ__Status__c IN ('Rejected', 'Denied')",
    "Document_Data_Status__c != 'Not Generated'",
    "Document_Data_Generated_On__c < :cutoff",
    "SBQQ__Status__c != 'Accepted'"
  ]) {
    assert.match(
      retentionSource,
      new RegExp(token.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
    );
  }
});

test("formats a Salesforce UTC cutoff without milliseconds", () => {
  assert.equal(
    salesforceDatetime(new Date("2026-09-07T12:34:56.789Z")),
    "2026-09-07T12:34:56Z"
  );
});

test("reads named or implicit aggregate counts and rejects bad responses", () => {
  assert.equal(
    parseCount({ status: 0, result: { records: [], totalSize: 5 } }, "count"),
    5
  );
  assert.equal(
    parseCount(
      { status: 0, result: { records: [{ recordCount: 7 }] } },
      "named"
    ),
    7
  );
  assert.equal(
    parseCount(
      { status: 0, result: { records: [{ attributes: {}, expr0: 9 }] } },
      "implicit"
    ),
    9
  );
  assert.throws(
    () => parseCount({ status: 1, message: "denied" }, "failed"),
    /failed/
  );
  assert.throws(
    () => parseCount({ status: 0, result: { records: [] } }, "empty"),
    /returned no count/
  );
});

test("reports total eligible records and labels storage as an estimate", () => {
  const counts = {
    eligibleQuotes: 2,
    eligibleTables: 3,
    eligibleColumns: 4,
    eligibleRows: 5,
    eligibleBlocks: 6,
    eligibleFacts: 7
  };
  const report = buildReport(
    {
      targetOrg: "qdt",
      retentionDays: 90,
      estimatedKbPerRecord: 2
    },
    counts,
    "2026-06-09T00:00:00Z",
    new Date("2026-09-07T00:00:00Z")
  );
  assert.equal(report.estimate.eligibleRecords, 25);
  assert.equal(report.estimate.estimatedStorageKb, 50);
  assert.equal(report.safety.aggregateOnly, true);
  assert.equal(report.safety.mutatesSalesforceData, false);
  assert.match(report.estimate.caveat, /planning estimate/);
  assert.match(csvRows(report), /eligibleRecords,25/);
});
