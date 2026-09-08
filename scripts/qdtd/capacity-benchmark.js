#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const { runAnonymous } = require("./capacity-common");

const MARKER = "QDTD_CAPACITY_BENCHMARK_V1";

function parseArguments(argv) {
  const options = {
    fixtures: "artifacts/capacity/fixtures.json",
    output: "artifacts/capacity/benchmark.json"
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const value = argv[++index];
    if (value === undefined) throw new Error(`${argument} requires a value.`);
    if (argument === "--target-org") options.targetOrg = value;
    else if (argument === "--fixtures") options.fixtures = value;
    else if (argument === "--output") options.output = value;
    else throw new Error(`Unknown argument: ${argument}`);
  }
  if (!options.targetOrg) throw new Error("--target-org is required.");
  return options;
}

function benchmarkApex(fixture) {
  if (
    !Number.isInteger(fixture.tier) ||
    !/^[a-zA-Z0-9]{15,18}$/u.test(fixture.quoteId)
  ) {
    throw new Error(
      "Fixture requires an integer tier and a 15- or 18-character Salesforce Quote Id."
    );
  }
  return `
Id quoteId = (Id)'${fixture.quoteId}';
SBQQ__Quote__c stale = [SELECT Id, Document_Data_Status__c FROM SBQQ__Quote__c WHERE Id = :quoteId];
stale.Document_Data_Status__c = 'Stale';
update stale;
Integer cpuBefore = Limits.getCpuTime(), heapBefore = Limits.getHeapSize(), queriesBefore = Limits.getQueries(), queryRowsBefore = Limits.getQueryRows(), dmlBefore = Limits.getDmlStatements(), dmlRowsBefore = Limits.getDmlRows();
List<QuoteDocumentGenerator.GenerationOutcome> outcomes = QuoteDocumentGenerator.generate(new Set<Id>{quoteId});
Integer generationCpu = Limits.getCpuTime() - cpuBefore, generationHeapEnd = Limits.getHeapSize(), generationQueries = Limits.getQueries() - queriesBefore, generationQueryRows = Limits.getQueryRows() - queryRowsBefore, generationDml = Limits.getDmlStatements() - dmlBefore, generationDmlRows = Limits.getDmlRows() - dmlRowsBefore;
QuoteDocumentGenerator.GenerationOutcome outcome = outcomes[0];
Integer tableCount = [SELECT COUNT() FROM Quote_Document_Table__c WHERE Quote__c = :quoteId];
Integer rowCount = [SELECT COUNT() FROM Quote_Document_Row__c WHERE Quote_Document_Table__r.Quote__c = :quoteId];
Integer columnCount = [SELECT COUNT() FROM Quote_Document_Column__c WHERE Quote_Document_Table__r.Quote__c = :quoteId];
Integer blockCount = [SELECT COUNT() FROM Quote_Document_Block__c WHERE Quote__c = :quoteId];
Integer factCount = [SELECT COUNT() FROM Quote_Document_Fact__c WHERE Quote__c = :quoteId];
Integer renderCpuBefore = Limits.getCpuTime(), renderHeapBefore = Limits.getHeapSize();
String payload = QuoteDocumentJsonAdapter.render(quoteId, outcome.requestId, outcome.fingerprint);
Integer renderCpu = Limits.getCpuTime() - renderCpuBefore, renderHeapEnd = Limits.getHeapSize();
Map<String,Object> result = new Map<String,Object>{
  'tier' => ${fixture.tier},
  'generation' => new Map<String,Object>{'cpuMs' => generationCpu, 'cpuLimitMs' => Limits.getLimitCpuTime(), 'heapStartBytes' => heapBefore, 'heapEndBytes' => generationHeapEnd, 'heapLimitBytes' => Limits.getLimitHeapSize(), 'soqlQueries' => generationQueries, 'soqlLimit' => Limits.getLimitQueries(), 'queriedRows' => generationQueryRows, 'queryRowLimit' => Limits.getLimitQueryRows(), 'dmlStatements' => generationDml, 'dmlStatementLimit' => Limits.getLimitDmlStatements(), 'dmlRows' => generationDmlRows, 'dmlRowLimit' => Limits.getLimitDmlRows()},
  'output' => new Map<String,Object>{'tables' => tableCount, 'columns' => columnCount, 'rows' => rowCount, 'blocks' => blockCount, 'facts' => factCount, 'payloadBytes' => Blob.valueOf(payload).size()},
  'render' => new Map<String,Object>{'cpuMs' => renderCpu, 'heapStartBytes' => renderHeapBefore, 'heapEndBytes' => renderHeapEnd}
};
System.debug(LoggingLevel.ERROR, '${MARKER} ' + JSON.serialize(result));
`;
}

function ratio(value, limit) {
  return Number.isFinite(value) && Number.isFinite(limit) && limit > 0
    ? value / limit
    : null;
}

function assess(measurement) {
  if (measurement.status !== "Completed" || !measurement.generation) {
    return {
      ratios: {},
      observedHeadroomAtLeast25Percent: false,
      supportedEnvelopeEstablished: false,
      reason: "The fixture did not complete, so no capacity claim is available."
    };
  }
  const generation = measurement.generation;
  const ratios = {
    cpu: ratio(generation.cpuMs, generation.cpuLimitMs),
    heapEndpoint: ratio(generation.heapEndBytes, generation.heapLimitBytes),
    soql: ratio(generation.soqlQueries, generation.soqlLimit),
    queriedRows: ratio(generation.queriedRows, generation.queryRowLimit),
    dml: ratio(generation.dmlStatements, generation.dmlStatementLimit),
    dmlRows: ratio(generation.dmlRows, generation.dmlRowLimit)
  };
  return {
    ratios,
    observedHeadroomAtLeast25Percent: Object.values(ratios).every(
      (value) => value !== null && value <= 0.75
    ),
    supportedEnvelopeEstablished: false,
    reason:
      "Apex exposes heap at observation points, not peak heap. Repeat release-candidate measurements and reviewed peak instrumentation are required before publishing a supported envelope."
  };
}

function buildReport(
  options,
  fixtureReport,
  measurements,
  generatedAt = new Date()
) {
  return {
    schemaVersion: "1.0",
    generatedAt: generatedAt.toISOString(),
    fixtureSchemaVersion: fixtureReport.schemaVersion,
    environment: {
      targetOrgAliasIncluded: false
    },
    measurements: measurements.map((measurement) => ({
      ...measurement,
      assessment: assess(measurement)
    })),
    safety: {
      syntheticDataOnly: true,
      mutatesSalesforceData: true,
      containsQuoteOrCustomerFieldValues: false,
      containsOrgRecordIds: false
    }
  };
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  const fixtureReport = JSON.parse(fs.readFileSync(options.fixtures, "utf8"));
  if (
    fixtureReport.schemaVersion !== "1.0" ||
    !fixtureReport.safety?.syntheticDataOnly ||
    !fixtureReport.safety?.containsOrgRecordIds ||
    !Array.isArray(fixtureReport.fixtures) ||
    fixtureReport.fixtures.length === 0
  ) {
    throw new Error(
      "Refusing a fixture manifest that is not marked synthetic and local-ID-bearing."
    );
  }
  const measurements = [];
  for (const fixture of fixtureReport.fixtures) {
    if (fixture.status !== "Completed") {
      measurements.push({
        tier: fixture.tier,
        status: "NotRun",
        errorCode: "CAPACITY_FIXTURE_UNAVAILABLE",
        safeMessage: "The synthetic fixture was not created successfully."
      });
      continue;
    }
    try {
      measurements.push({
        ...runAnonymous(options.targetOrg, benchmarkApex(fixture), MARKER),
        status: "Completed"
      });
    } catch {
      measurements.push({
        tier: fixture.tier,
        status: "Failed",
        errorCode: "CAPACITY_BENCHMARK_FAILED",
        safeMessage:
          "Generation or retrieval failed. Review the local Salesforce CLI result without publishing record data."
      });
    }
  }
  const report = buildReport(options, fixtureReport, measurements);
  fs.mkdirSync(path.dirname(options.output), { recursive: true });
  fs.writeFileSync(options.output, `${JSON.stringify(report, null, 2)}\n`);
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (measurements.some((measurement) => measurement.status !== "Completed")) {
    process.exitCode = 1;
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
  MARKER,
  assess,
  benchmarkApex,
  buildReport,
  parseArguments,
  ratio
};
