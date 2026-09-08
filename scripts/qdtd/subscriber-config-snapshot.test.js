const assert = require("node:assert/strict");
const test = require("node:test");

const {
  QUERY,
  buildSnapshot,
  capture,
  compareSnapshots,
  parseArguments
} = require("./subscriber-config-snapshot");

const records = [
  {
    DeveloperName: "SUB_REGION",
    MasterLabel: "Region",
    Field_API_Name__c: "Region__c",
    Is_Active__c: true,
    Version__c: "1"
  },
  {
    DeveloperName: "SUB_CLASS",
    MasterLabel: "Class",
    Field_API_Name__c: "Class__c",
    Is_Active__c: false,
    Version__c: "2"
  }
];

test("parses explicit capture and compare commands", () => {
  assert.deepEqual(
    parseArguments([
      "capture",
      "--target-org",
      "qdt",
      "--output",
      "before.json"
    ]),
    {
      command: "capture",
      targetOrg: "qdt",
      output: "before.json"
    }
  );
  assert.deepEqual(
    parseArguments([
      "compare",
      "--before",
      "before.json",
      "--after",
      "after.json",
      "--output",
      "report.json"
    ]),
    {
      command: "compare",
      before: "before.json",
      after: "after.json",
      output: "report.json"
    }
  );
  assert.throws(() => parseArguments([]), /capture.*compare/);
  assert.throws(
    () => parseArguments(["capture", "--target-org", "qdt"]),
    /--output is required/
  );
});

test("captures only the declared subscriber metadata fields with a read-only query", () => {
  const calls = [];
  const snapshot = capture(
    "qdt",
    (argumentsList) => {
      calls.push(argumentsList);
      return {
        stdout: `warning\n${JSON.stringify({
          status: 0,
          result: { records }
        })}`
      };
    },
    new Date("2026-09-07T01:00:00Z")
  );
  assert.deepEqual(calls[0], [
    "data",
    "query",
    "--target-org",
    "qdt",
    "--query",
    QUERY,
    "--json"
  ]);
  assert.equal(snapshot.records[0].developerName, "SUB_CLASS");
  assert.equal(snapshot.generatedAt, "2026-09-07T01:00:00.000Z");
  assert.equal(snapshot.safety.readOnlyMetadataQuery, true);
  assert.equal(snapshot.safety.uploadsRepositorySource, false);
  assert.equal(snapshot.safety.containsQuoteOrCustomerFieldValues, false);
});

test("accepts additions while proving previous records are unchanged", () => {
  const before = buildSnapshot(
    "qdt",
    { status: 0, result: { records: [records[0]] } },
    new Date("2026-09-07T01:00:00Z")
  );
  const after = buildSnapshot(
    "qdt",
    { status: 0, result: { records } },
    new Date("2026-09-07T02:00:00Z")
  );
  const report = compareSnapshots(
    before,
    after,
    new Date("2026-09-07T03:00:00Z")
  );
  assert.equal(report.preserved, true);
  assert.deepEqual(report.counts, {
    before: 1,
    after: 2,
    removed: 0,
    changed: 0,
    added: 1
  });
});

test("fails preservation when an upgrade removes or changes prior records", () => {
  const before = buildSnapshot("qdt", {
    status: 0,
    result: { records }
  });
  const after = buildSnapshot("qdt", {
    status: 0,
    result: {
      records: [
        {
          ...records[0],
          Field_API_Name__c: "Replacement__c",
          Version__c: "3"
        }
      ]
    }
  });
  const report = compareSnapshots(before, after);
  assert.equal(report.preserved, false);
  assert.deepEqual(
    report.removed.map((record) => record.developerName),
    ["SUB_CLASS"]
  );
  assert.deepEqual(report.changed[0].fields, ["fieldApiName", "version"]);
});

test("rejects malformed, duplicate, and non-subscriber records", () => {
  assert.throws(
    () =>
      buildSnapshot("qdt", {
        status: 0,
        result: { records: [{ ...records[0], DeveloperName: "QDTD_REGION" }] }
      }),
    /non-subscriber/
  );
  assert.throws(
    () =>
      buildSnapshot("qdt", {
        status: 0,
        result: { records: [records[0], records[0]] }
      }),
    /Duplicate Developer Name/
  );
  assert.throws(
    () => compareSnapshots({ schemaVersion: "2.0", records: [] }, {}),
    /not a supported subscriber snapshot/
  );
});
