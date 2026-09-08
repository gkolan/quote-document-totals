#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const { spawnSalesforce } = require("./sf-command");

const TERMINAL_STATUSES = new Set([
  "Succeeded",
  "Failed",
  "Canceled",
  "Canceling"
]);

function parseArguments(argv) {
  const options = { outputDir: "artifacts/salesforce" };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--target-org") {
      options.targetOrg = argv[++index];
    } else if (argument === "--output-dir") {
      options.outputDir = argv[++index];
    } else {
      throw new Error(`Unknown argument: ${argument}`);
    }
  }
  if (!options.targetOrg) {
    throw new Error("--target-org is required");
  }
  return options;
}

function extractJson(output) {
  const start = output.indexOf("{");
  if (start < 0) {
    throw new Error(
      `Salesforce CLI returned no JSON:\n${output.slice(0, 2000)}`
    );
  }
  return JSON.parse(output.slice(start));
}

function listTestClasses(classesDirectory) {
  return fs
    .readdirSync(classesDirectory)
    .filter((name) => name.endsWith("Test.cls"))
    .map((name) => name.slice(0, -".cls".length))
    .sort();
}

function runSalesforce(argumentsList) {
  const result = spawnSalesforce(argumentsList, {
    cwd: process.cwd(),
    maxBuffer: 100 * 1024 * 1024
  });
  if (result.error) {
    throw result.error;
  }
  const combined = `${result.stdout || ""}\n${result.stderr || ""}`;
  let payload;
  try {
    payload = extractJson(result.stdout || combined);
  } catch (error) {
    throw new Error(
      `Salesforce CLI exit ${result.status}. ${error.message}\n${combined.slice(0, 4000)}`
    );
  }
  return { exitCode: result.status, payload };
}

function deploymentSummary(payload, testClassCount) {
  const deployment = payload.result || {};
  const tests = deployment.details?.runTestResult || {};
  return {
    jobId: deployment.id,
    status: deployment.status,
    success: deployment.success === true,
    checkOnly: deployment.checkOnly === true,
    testClassCount,
    componentsTotal: Number(deployment.numberComponentsTotal || 0),
    componentErrors: Number(deployment.numberComponentErrors || 0),
    testsRun: Number(tests.numTestsRun || 0),
    testFailures: Number(tests.numFailures || 0),
    coverageWarnings: Array.isArray(tests.codeCoverageWarnings)
      ? tests.codeCoverageWarnings.length
      : tests.codeCoverageWarnings
        ? 1
        : 0
  };
}

function validateSummary(summary) {
  const failures = [];
  if (!summary.checkOnly) failures.push("deployment was not check-only");
  if (summary.status !== "Succeeded" || !summary.success) {
    failures.push(`deployment status is ${summary.status || "unknown"}`);
  }
  if (summary.componentsTotal < 1)
    failures.push("no components were validated");
  if (summary.componentErrors > 0) {
    failures.push(`${summary.componentErrors} component error(s)`);
  }
  if (summary.testsRun < 1) failures.push("no Apex tests ran");
  if (summary.testFailures > 0) {
    failures.push(`${summary.testFailures} Apex test failure(s)`);
  }
  if (summary.coverageWarnings > 0) {
    failures.push(`${summary.coverageWarnings} Apex coverage warning(s)`);
  }
  return failures;
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  const classesDirectory = path.join(
    process.cwd(),
    "force-app",
    "main",
    "default",
    "classes"
  );
  const testClasses = listTestClasses(classesDirectory);
  if (testClasses.length === 0) {
    throw new Error(
      "No current Apex test classes were found; refusing to skip validation."
    );
  }

  const deployArguments = [
    "project",
    "deploy",
    "start",
    "--dry-run",
    "--target-org",
    options.targetOrg,
    "--source-dir",
    "force-app",
    "--test-level",
    "RunSpecifiedTests",
    "--wait",
    "30",
    "--json"
  ];
  for (const testClass of testClasses) {
    deployArguments.push("--tests", testClass);
  }

  let execution = runSalesforce(deployArguments);
  let status = execution.payload.result?.status;
  if (!TERMINAL_STATUSES.has(status)) {
    const jobId = execution.payload.result?.id;
    if (!jobId) {
      throw new Error(
        `Queued validation returned no job ID; status was ${status}.`
      );
    }
    execution = runSalesforce([
      "project",
      "deploy",
      "report",
      "--target-org",
      options.targetOrg,
      "--job-id",
      jobId,
      "--wait",
      "30",
      "--json"
    ]);
    status = execution.payload.result?.status;
  }

  fs.mkdirSync(options.outputDir, { recursive: true });
  fs.writeFileSync(
    path.join(options.outputDir, "deployment-result.json"),
    `${JSON.stringify(execution.payload, null, 2)}\n`
  );
  const summary = deploymentSummary(execution.payload, testClasses.length);
  fs.writeFileSync(
    path.join(options.outputDir, "deployment-summary.json"),
    `${JSON.stringify(summary, null, 2)}\n`
  );
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);

  if (!TERMINAL_STATUSES.has(status)) {
    throw new Error(
      `Validation is still ${status}; queued work is not a passing result.`
    );
  }
  const failures = validateSummary(summary);
  if (failures.length > 0) {
    throw new Error(`Salesforce validation failed: ${failures.join("; ")}`);
  }
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = {
  deploymentSummary,
  extractJson,
  listTestClasses,
  parseArguments,
  validateSummary
};
