#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const { spawnSalesforce } = require("../ci/sf-command");

function parseArguments(argv) {
  const options = { output: "artifacts/install-preflight.json" };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const value = argv[++index];
    if (value === undefined) throw new Error(`${argument} requires a value.`);
    if (argument === "--target-org") options.targetOrg = value;
    else if (argument === "--output") options.output = value;
    else throw new Error(`Unknown argument: ${argument}`);
  }
  if (!options.targetOrg) throw new Error("--target-org is required.");
  return options;
}

function extractJson(output) {
  const start = output.indexOf("{");
  if (start < 0) throw new Error(`Salesforce CLI returned no JSON:\n${output}`);
  return JSON.parse(output.slice(start));
}

function inspectDependency(specification, payload) {
  if (payload.status !== 0) {
    return {
      capability: specification.capability,
      object: specification.object,
      available: false,
      missingFields: [...specification.fields],
      error: payload.message || payload.name || "Describe failed"
    };
  }
  const availableFields = new Set(
    (payload.result?.fields || []).map((field) => field.name.toLowerCase())
  );
  const missingFields = specification.fields.filter(
    (field) => !availableFields.has(field.toLowerCase())
  );
  return {
    capability: specification.capability,
    object: specification.object,
    available: missingFields.length === 0,
    missingFields
  };
}

function inspectCpqPackage(payload) {
  if (payload.status !== 0) {
    return {
      available: false,
      error: payload.message || payload.name || "Installed package query failed"
    };
  }
  const record = (payload.result?.records || []).find(
    (candidate) => candidate.SubscriberPackage?.NamespacePrefix === "SBQQ"
  );
  if (!record) return { available: false, error: "SBQQ package not installed" };
  const version = record.SubscriberPackageVersion || {};
  return {
    available: true,
    name: record.SubscriberPackage.Name,
    namespace: record.SubscriberPackage.NamespacePrefix,
    version: [
      version.MajorVersion,
      version.MinorVersion,
      version.PatchVersion,
      version.BuildNumber
    ].join(".")
  };
}

function buildReport(
  targetOrg,
  manifest,
  cpqPackage,
  inspections,
  generatedAt = new Date()
) {
  return {
    schemaVersion: "1.0",
    generatedAt: generatedAt.toISOString(),
    targetOrgAlias: targetOrg,
    projectApiVersion: manifest.projectApiVersion,
    ready:
      cpqPackage.available &&
      inspections.every((inspection) => inspection.available),
    cpqPackage,
    dependencies: inspections,
    safety: {
      schemaDescribeOnly: true,
      uploadsRepositorySource: false,
      mutatesSalesforceData: false
    },
    limitation:
      "This preflight verifies named compile-time CPQ schema dependencies. The check-only deployment and representative-user test remain authoritative for installation and runtime access."
  };
}

function queryCpqPackage(targetOrg, spawn = spawnSalesforce) {
  const query =
    "SELECT SubscriberPackage.Name, SubscriberPackage.NamespacePrefix, " +
    "SubscriberPackageVersion.MajorVersion, SubscriberPackageVersion.MinorVersion, " +
    "SubscriberPackageVersion.PatchVersion, SubscriberPackageVersion.BuildNumber " +
    "FROM InstalledSubscriberPackage";
  const result = spawn(
    [
      "data",
      "query",
      "--target-org",
      targetOrg,
      "--use-tooling-api",
      "--query",
      query,
      "--json"
    ],
    { cwd: process.cwd() }
  );
  if (result.error) throw result.error;
  const payload = extractJson(
    result.stdout || `${result.stdout || ""}\n${result.stderr || ""}`
  );
  return inspectCpqPackage(payload);
}

function describe(targetOrg, specification, spawn = spawnSalesforce) {
  const result = spawn(
    [
      "sobject",
      "describe",
      "--target-org",
      targetOrg,
      "--sobject",
      specification.object,
      "--json"
    ],
    { cwd: process.cwd() }
  );
  if (result.error) throw result.error;
  const payload = extractJson(
    result.stdout || `${result.stdout || ""}\n${result.stderr || ""}`
  );
  return inspectDependency(specification, payload);
}

function runPreflight(options, manifest, spawn = spawnSalesforce) {
  const cpqPackage = queryCpqPackage(options.targetOrg, spawn);
  const inspections = manifest.dependencies.map((specification) =>
    describe(options.targetOrg, specification, spawn)
  );
  return buildReport(options.targetOrg, manifest, cpqPackage, inspections);
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  const manifest = JSON.parse(
    fs.readFileSync(
      path.join(__dirname, "..", "..", "install-prerequisites.json"),
      "utf8"
    )
  );
  const report = runPreflight(options, manifest);
  fs.mkdirSync(path.dirname(options.output), { recursive: true });
  fs.writeFileSync(options.output, `${JSON.stringify(report, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (!report.ready) process.exitCode = 1;
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
  buildReport,
  extractJson,
  inspectCpqPackage,
  inspectDependency,
  parseArguments,
  queryCpqPackage,
  runPreflight
};
