const test = require("node:test");
const assert = require("node:assert/strict");

const {
  DEFAULT_TIERS,
  buildFixtureReport,
  fixtureApex,
  parseArguments,
  parseTiers
} = require("./capacity-fixtures");

test("defaults to the versioned 10, 100, 500, and 1000 line tiers", () => {
  assert.deepEqual(
    parseArguments(["--target-org", "qdt"]).tiers,
    DEFAULT_TIERS
  );
});

test("rejects duplicate, zero, and oversized fixture tiers", () => {
  assert.throws(() => parseTiers("10,10"), /unique integers/);
  assert.throws(() => parseTiers("0"), /unique integers/);
  assert.throws(() => parseTiers("1001"), /unique integers/);
});

test("fixture Apex owns records by an exact key and creates the requested lines", () => {
  const source = fixtureApex(500);
  assert.match(source, /QDTD-CAP-500/);
  assert.match(source, /index <= 500/);
  assert.match(source, /WHERE SBQQ__Key__c = :fixtureKey/);
  assert.doesNotMatch(source, /LIKE/);
});

test("fixture manifest warns that local record IDs must stay ignored", () => {
  const report = buildFixtureReport(
    { targetOrg: "qdt" },
    [
      {
        tier: 10,
        quoteId: "a0q000000000001AAA",
        lineCount: 10,
        status: "Completed"
      }
    ],
    new Date("2026-09-08T00:00:00Z")
  );
  assert.equal(report.safety.containsOrgRecordIds, true);
  assert.equal(report.safety.outputMustRemainIgnored, true);
});
