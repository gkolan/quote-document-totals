#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const { spawnSalesforce } = require("../ci/sf-command");

const QUERY =
  "SELECT DeveloperName, MasterLabel, Field_API_Name__c, Is_Active__c, Version__c " +
  "FROM Quote_Document_Watched_Field__mdt " +
  "WHERE DeveloperName LIKE 'SUB_%' ORDER BY DeveloperName";

function parseArguments(argv) {
  const [command, ...argumentsList] = argv;
  if (command === "capture") {
    const options = { command };
    for (let index = 0; index < argumentsList.length; index += 1) {
      const argument = argumentsList[index];
      const value = argumentsList[++index];
      if (value === undefined) throw new Error(`${argument} requires a value.`);
      if (argument === "--target-org") options.targetOrg = value;
      else if (argument === "--output") options.output = value;
      else throw new Error(`Unknown argument: ${argument}`);
    }
    if (!options.targetOrg) throw new Error("--target-org is required.");
    if (!options.output) throw new Error("--output is required.");
    return options;
  }
  if (command === "compare") {
    const options = { command };
    for (let index = 0; index < argumentsList.length; index += 1) {
      const argument = argumentsList[index];
      const value = argumentsList[++index];
      if (value === undefined) throw new Error(`${argument} requires a value.`);
      if (argument === "--before") options.before = value;
      else if (argument === "--after") options.after = value;
      else if (argument === "--output") options.output = value;
      else throw new Error(`Unknown argument: ${argument}`);
    }
    if (!options.before) throw new Error("--before is required.");
    if (!options.after) throw new Error("--after is required.");
    if (!options.output) throw new Error("--output is required.");
    return options;
  }
  throw new Error('Expected command "capture" or "compare".');
}

function extractJson(output) {
  const start = output.indexOf("{");
  if (start < 0) throw new Error(`Salesforce CLI returned no JSON:\n${output}`);
  return JSON.parse(output.slice(start));
}

function normalizeRecords(records) {
  const names = new Set();
  return records
    .map((record) => {
      const normalized = {
        developerName: record.DeveloperName,
        masterLabel: record.MasterLabel,
        fieldApiName: record.Field_API_Name__c,
        active: record.Is_Active__c === true,
        version: record.Version__c
      };
      if (!normalized.developerName?.startsWith("SUB_")) {
        throw new Error(
          `Unexpected non-subscriber record: ${normalized.developerName || "(unnamed)"}`
        );
      }
      if (names.has(normalized.developerName)) {
        throw new Error(
          `Duplicate Developer Name: ${normalized.developerName}`
        );
      }
      names.add(normalized.developerName);
      return normalized;
    })
    .sort((left, right) =>
      left.developerName.localeCompare(right.developerName)
    );
}

function buildSnapshot(targetOrg, payload, generatedAt = new Date()) {
  if (payload.status !== 0) {
    throw new Error(
      payload.message || payload.name || "Subscriber metadata query failed."
    );
  }
  return {
    schemaVersion: "1.0",
    generatedAt: generatedAt.toISOString(),
    targetOrgAlias: targetOrg,
    records: normalizeRecords(payload.result?.records || []),
    safety: {
      readOnlyMetadataQuery: true,
      uploadsRepositorySource: false,
      mutatesSalesforceData: false,
      containsQuoteOrCustomerFieldValues: false
    }
  };
}

function capture(targetOrg, spawn = spawnSalesforce, generatedAt = new Date()) {
  const result = spawn(
    ["data", "query", "--target-org", targetOrg, "--query", QUERY, "--json"],
    { cwd: process.cwd(), maxBuffer: 10 * 1024 * 1024 }
  );
  if (result.error) throw result.error;
  const payload = extractJson(
    result.stdout || `${result.stdout || ""}\n${result.stderr || ""}`
  );
  return buildSnapshot(targetOrg, payload, generatedAt);
}

function validateSnapshot(snapshot, label) {
  if (snapshot.schemaVersion !== "1.0" || !Array.isArray(snapshot.records)) {
    throw new Error(`${label} is not a supported subscriber snapshot.`);
  }
  return normalizeRecords(
    snapshot.records.map((record) => ({
      DeveloperName: record.developerName,
      MasterLabel: record.masterLabel,
      Field_API_Name__c: record.fieldApiName,
      Is_Active__c: record.active,
      Version__c: record.version
    }))
  );
}

function compareSnapshots(before, after, comparedAt = new Date()) {
  const beforeRecords = validateSnapshot(before, "Before snapshot");
  const afterRecords = validateSnapshot(after, "After snapshot");
  const beforeByName = new Map(
    beforeRecords.map((record) => [record.developerName, record])
  );
  const afterByName = new Map(
    afterRecords.map((record) => [record.developerName, record])
  );
  const removed = beforeRecords.filter(
    (record) => !afterByName.has(record.developerName)
  );
  const added = afterRecords.filter(
    (record) => !beforeByName.has(record.developerName)
  );
  const changed = [];
  for (const previous of beforeRecords) {
    const current = afterByName.get(previous.developerName);
    if (!current) continue;
    const fields = ["masterLabel", "fieldApiName", "active", "version"].filter(
      (field) => previous[field] !== current[field]
    );
    if (fields.length > 0) {
      changed.push({
        developerName: previous.developerName,
        fields,
        before: previous,
        after: current
      });
    }
  }
  return {
    schemaVersion: "1.0",
    comparedAt: comparedAt.toISOString(),
    preserved: removed.length === 0 && changed.length === 0,
    counts: {
      before: beforeRecords.length,
      after: afterRecords.length,
      removed: removed.length,
      changed: changed.length,
      added: added.length
    },
    removed,
    changed,
    added,
    policy: {
      additionsAllowed: true,
      removalsAllowed: false,
      changesAllowed: false
    }
  };
}

function writeJson(output, value) {
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, `${JSON.stringify(value, null, 2)}\n`);
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  if (options.command === "capture") {
    const snapshot = capture(options.targetOrg);
    writeJson(options.output, snapshot);
    process.stdout.write(`${JSON.stringify(snapshot, null, 2)}\n`);
    return;
  }
  const before = JSON.parse(fs.readFileSync(options.before, "utf8"));
  const after = JSON.parse(fs.readFileSync(options.after, "utf8"));
  const report = compareSnapshots(before, after);
  writeJson(options.output, report);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (!report.preserved) process.exitCode = 1;
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
  QUERY,
  buildSnapshot,
  capture,
  compareSnapshots,
  extractJson,
  normalizeRecords,
  parseArguments,
  validateSnapshot,
  writeJson
};
