#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const { spawnSalesforce } = require("../ci/sf-command");

const DAY_MS = 24 * 60 * 60 * 1000;
const DEFAULT_RETENTION_DAYS = 90;
const DEFAULT_KB_PER_RECORD = 2;

function positiveNumber(raw, name) {
  const value = Number(raw);
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`${name} must be a positive number.`);
  }
  return value;
}

function parseArguments(argv) {
  const options = {
    retentionDays: DEFAULT_RETENTION_DAYS,
    estimatedKbPerRecord: DEFAULT_KB_PER_RECORD,
    outputDir: "artifacts/retention-inventory"
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const value = argv[++index];
    if (value === undefined) {
      throw new Error(`${argument} requires a value.`);
    }
    if (argument === "--target-org") options.targetOrg = value;
    else if (argument === "--retention-days") {
      options.retentionDays = positiveNumber(value, "--retention-days");
    } else if (argument === "--estimated-kb-per-record") {
      options.estimatedKbPerRecord = positiveNumber(
        value,
        "--estimated-kb-per-record"
      );
    } else if (argument === "--output-dir") options.outputDir = value;
    else throw new Error(`Unknown argument: ${argument}`);
  }
  if (!options.targetOrg) throw new Error("--target-org is required.");
  return options;
}

function salesforceDatetime(value) {
  return value.toISOString().replace(/\.\d{3}Z$/, "Z");
}

function quoteEligibility(cutoff) {
  return `((SBQQ__Status__c IN ('Rejected','Denied') AND Document_Data_Status__c != 'Not Generated') OR (Document_Data_Generated_On__c < ${cutoff} AND SBQQ__Status__c != 'Accepted'))`;
}

function relatedEligibility(prefix, cutoff) {
  return quoteEligibility(cutoff).replaceAll(
    /\b(SBQQ__Status__c|Document_Data_Status__c|Document_Data_Generated_On__c)/g,
    `${prefix}$1`
  );
}

function inconsistentState(prefix) {
  return `(${prefix}Document_Data_Status__c = 'Not Generated' OR ${prefix}Document_Data_Status__c = NULL)`;
}

function buildQueries(cutoff) {
  const quoteEligible = quoteEligibility(cutoff);
  const tableEligible = relatedEligibility("Quote__r.", cutoff);
  const nestedTableEligible = relatedEligibility(
    "Quote_Document_Table__r.Quote__r.",
    cutoff
  );
  const directQuoteEligible = relatedEligibility("Quote__r.", cutoff);
  const quoteInTables = "Id IN (SELECT Quote__c FROM Quote_Document_Table__c)";
  const quoteInBlocks = "Id IN (SELECT Quote__c FROM Quote_Document_Block__c)";

  return {
    eligibleQuotes: `SELECT COUNT() FROM SBQQ__Quote__c WHERE ${quoteEligible}`,
    eligibleTables: `SELECT COUNT() FROM Quote_Document_Table__c WHERE ${tableEligible}`,
    eligibleColumns: `SELECT COUNT() FROM Quote_Document_Column__c WHERE ${nestedTableEligible}`,
    eligibleRows: `SELECT COUNT() FROM Quote_Document_Row__c WHERE ${nestedTableEligible}`,
    eligibleBlocks: `SELECT COUNT() FROM Quote_Document_Block__c WHERE ${directQuoteEligible}`,
    eligibleFacts: `SELECT COUNT() FROM Quote_Document_Fact__c WHERE ${directQuoteEligible}`,
    eligibleBlockOnlyQuotes: `SELECT COUNT() FROM SBQQ__Quote__c WHERE ${quoteEligible} AND ${quoteInBlocks} AND Id NOT IN (SELECT Quote__c FROM Quote_Document_Table__c)`,
    eligibleTableOnlyQuotes: `SELECT COUNT() FROM SBQQ__Quote__c WHERE ${quoteEligible} AND ${quoteInTables} AND Id NOT IN (SELECT Quote__c FROM Quote_Document_Block__c)`,
    eligibleMixedQuotes: `SELECT COUNT() FROM SBQQ__Quote__c WHERE ${quoteEligible} AND ${quoteInTables} AND ${quoteInBlocks}`,
    eligibleFactsOnlyQuotes: `SELECT COUNT_DISTINCT(Quote__c) FROM Quote_Document_Fact__c WHERE ${directQuoteEligible} AND Quote__c NOT IN (SELECT Quote__c FROM Quote_Document_Table__c) AND Quote__c NOT IN (SELECT Quote__c FROM Quote_Document_Block__c)`,
    inconsistentTables: `SELECT COUNT() FROM Quote_Document_Table__c WHERE ${inconsistentState("Quote__r.")}`,
    inconsistentColumns: `SELECT COUNT() FROM Quote_Document_Column__c WHERE ${inconsistentState("Quote_Document_Table__r.Quote__r.")}`,
    inconsistentRows: `SELECT COUNT() FROM Quote_Document_Row__c WHERE ${inconsistentState("Quote_Document_Table__r.Quote__r.")}`,
    inconsistentBlocks: `SELECT COUNT() FROM Quote_Document_Block__c WHERE ${inconsistentState("Quote__r.")}`,
    inconsistentFacts: `SELECT COUNT() FROM Quote_Document_Fact__c WHERE ${inconsistentState("Quote__r.")}`
  };
}

function extractJson(output) {
  const start = output.indexOf("{");
  if (start < 0) throw new Error(`Salesforce CLI returned no JSON:\n${output}`);
  return JSON.parse(output.slice(start));
}

function parseCount(payload, queryName) {
  if (payload.status !== 0) {
    throw new Error(`${queryName} failed: ${JSON.stringify(payload)}`);
  }
  const record = payload.result?.records?.[0];
  if (!record && Number.isFinite(payload.result?.totalSize)) {
    return payload.result.totalSize;
  }
  if (!record) throw new Error(`${queryName} returned no count.`);
  const key = Object.keys(record).find(
    (candidate) => candidate !== "attributes" && candidate !== "totalSize"
  );
  const count = Number(record[key]);
  if (!Number.isFinite(count) || count < 0) {
    throw new Error(`${queryName} returned an invalid count.`);
  }
  return count;
}

function queryCount(targetOrg, queryName, query) {
  if (
    !/^SELECT (COUNT\(\)|COUNT_DISTINCT\([A-Za-z0-9_]+\)) FROM /i.test(query)
  ) {
    throw new Error(`${queryName} is not aggregate-only; refusing to run it.`);
  }
  const result = spawnSalesforce(
    ["data", "query", "--target-org", targetOrg, "--query", query, "--json"],
    { cwd: process.cwd(), maxBuffer: 10 * 1024 * 1024 }
  );
  if (result.error) throw result.error;
  const payload = extractJson(
    result.stdout || `${result.stdout || ""}\n${result.stderr || ""}`
  );
  return parseCount(payload, queryName);
}

function buildReport(options, counts, cutoff, generatedAt) {
  const eligibleRecordKeys = [
    "eligibleTables",
    "eligibleColumns",
    "eligibleRows",
    "eligibleBlocks",
    "eligibleFacts"
  ];
  const eligibleRecords = eligibleRecordKeys.reduce(
    (sum, key) => sum + counts[key],
    0
  );
  return {
    schemaVersion: "1.0",
    generatedAt: generatedAt.toISOString(),
    targetOrgAlias: options.targetOrg,
    policy: {
      retentionDays: options.retentionDays,
      cutoff,
      acceptedQuotesProtected: true,
      rejectedAndDeniedRequireGeneratedState: true
    },
    counts,
    estimate: {
      eligibleRecords,
      assumedKbPerRecord: options.estimatedKbPerRecord,
      estimatedStorageKb: eligibleRecords * options.estimatedKbPerRecord,
      caveat:
        "This planning estimate multiplies record count by the supplied assumption. Actual Salesforce storage depends on platform and field storage behavior."
    },
    safety: {
      aggregateOnly: true,
      mutatesSalesforceData: false,
      containsQuoteOrCustomerFieldValues: false
    }
  };
}

function csvRows(report) {
  const rows = [["metric", "value"]];
  for (const [name, value] of Object.entries(report.counts)) {
    rows.push([name, String(value)]);
  }
  rows.push(["eligibleRecords", String(report.estimate.eligibleRecords)]);
  rows.push(["estimatedStorageKb", String(report.estimate.estimatedStorageKb)]);
  return `${rows.map((row) => row.join(",")).join("\n")}\n`;
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  const generatedAt = new Date();
  const cutoff = salesforceDatetime(
    new Date(generatedAt.getTime() - options.retentionDays * DAY_MS)
  );
  const queries = buildQueries(cutoff);
  const counts = {};
  for (const [name, query] of Object.entries(queries)) {
    counts[name] = queryCount(options.targetOrg, name, query);
  }
  const report = buildReport(options, counts, cutoff, generatedAt);
  fs.mkdirSync(options.outputDir, { recursive: true });
  fs.writeFileSync(
    path.join(options.outputDir, "retention-inventory.json"),
    `${JSON.stringify({ ...report, queries }, null, 2)}\n`
  );
  fs.writeFileSync(
    path.join(options.outputDir, "retention-inventory.csv"),
    csvRows(report)
  );
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
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
  buildQueries,
  buildReport,
  csvRows,
  parseArguments,
  parseCount,
  quoteEligibility,
  salesforceDatetime
};
