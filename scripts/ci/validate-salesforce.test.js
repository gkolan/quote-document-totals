const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const {
  deploymentSummary,
  extractJson,
  listTestClasses,
  parseArguments,
  validateSummary
} = require("./validate-salesforce");
const { resolveSfInvocation } = require("./sf-command");

test("parses required target org and optional artifact directory", () => {
  assert.deepEqual(
    parseArguments(["--target-org", "qdt-ci", "--output-dir", "results"]),
    { targetOrg: "qdt-ci", outputDir: "results" }
  );
  assert.throws(() => parseArguments([]), /--target-org is required/);
  assert.throws(() => parseArguments(["--unknown"]), /Unknown argument/);
});

test("extracts JSON after a CLI warning", () => {
  assert.deepEqual(extractJson('update available\n{"status":0,"result":{}}'), {
    status: 0,
    result: {}
  });
  assert.throws(() => extractJson("warning only"), /returned no JSON/);
});

test("enumerates only current Apex test classes in stable order", (context) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "qdt-tests-"));
  context.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  fs.writeFileSync(path.join(directory, "ZetaTest.cls"), "");
  fs.writeFileSync(path.join(directory, "AlphaTest.cls"), "");
  fs.writeFileSync(path.join(directory, "Production.cls"), "");
  fs.writeFileSync(path.join(directory, "AlphaTest.cls-meta.xml"), "");
  assert.deepEqual(listTestClasses(directory), ["AlphaTest", "ZetaTest"]);
});

test("a completed clean check-only deployment passes", () => {
  const payload = {
    result: {
      id: "0Af000000000001",
      status: "Succeeded",
      success: true,
      checkOnly: true,
      numberComponentsTotal: 680,
      numberComponentErrors: 0,
      details: {
        runTestResult: {
          numTestsRun: 504,
          numFailures: 0,
          codeCoverageWarnings: []
        }
      }
    }
  };
  const summary = deploymentSummary(payload, 56);
  assert.equal(summary.testClassCount, 56);
  assert.equal(summary.testsRun, 504);
  assert.deepEqual(validateSummary(summary), []);
});

test("pending, skipped, failed, and under-covered validation cannot pass", () => {
  const failures = validateSummary({
    status: "InProgress",
    success: false,
    checkOnly: false,
    componentsTotal: 0,
    componentErrors: 2,
    testsRun: 0,
    testFailures: 1,
    coverageWarnings: 3
  });
  assert.match(failures.join(" | "), /not check-only/);
  assert.match(failures.join(" | "), /InProgress/);
  assert.match(failures.join(" | "), /no components/);
  assert.match(failures.join(" | "), /component error/);
  assert.match(failures.join(" | "), /no Apex tests/);
  assert.match(failures.join(" | "), /test failure/);
  assert.match(failures.join(" | "), /coverage warning/);
});

test("resolves Windows CLI through its JavaScript runner without a shell", () => {
  const existing = new Set([
    "C:\\Program Files\\sf\\bin\\sf.cmd",
    "C:\\Program Files\\sf\\client\\bin\\run.js"
  ]);
  assert.deepEqual(
    resolveSfInvocation({
      platform: "win32",
      environment: { PATH: "C:\\Program Files\\sf\\bin" },
      nodeExecutable: "C:\\Node\\node.exe",
      exists: (candidate) => existing.has(candidate)
    }),
    {
      command: "C:\\Node\\node.exe",
      prefix: ["C:\\Program Files\\sf\\client\\bin\\run.js"]
    }
  );
  assert.deepEqual(
    resolveSfInvocation({ platform: "linux", environment: {} }),
    { command: "sf", prefix: [] }
  );
});
