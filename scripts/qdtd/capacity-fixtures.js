#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const { runAnonymous } = require("./capacity-common");

const MARKER = "QDTD_CAPACITY_FIXTURE_V1";
const DEFAULT_TIERS = [10, 100, 500, 1000];

function parseTiers(raw) {
  const tiers = raw.split(",").map((value) => Number(value));
  if (
    tiers.length === 0 ||
    tiers.some(
      (value) => !Number.isInteger(value) || value < 1 || value > 1000
    ) ||
    new Set(tiers).size !== tiers.length
  ) {
    throw new Error("--tiers must be unique integers from 1 through 1000.");
  }
  return tiers;
}

function parseArguments(argv) {
  const options = {
    tiers: DEFAULT_TIERS,
    output: "artifacts/capacity/fixtures.json"
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const value = argv[++index];
    if (value === undefined) throw new Error(`${argument} requires a value.`);
    if (argument === "--target-org") options.targetOrg = value;
    else if (argument === "--tiers") options.tiers = parseTiers(value);
    else if (argument === "--output") options.output = value;
    else throw new Error(`Unknown argument: ${argument}`);
  }
  if (!options.targetOrg) throw new Error("--target-org is required.");
  return options;
}

function fixtureApex(lineCount) {
  const key = `QDTD-CAP-${lineCount}`;
  return `
String fixtureKey = '${key}';
List<SBQQ__Quote__c> prior = [SELECT Id FROM SBQQ__Quote__c WHERE SBQQ__Key__c = :fixtureKey];
if (!prior.isEmpty()) delete prior;

List<Account> accounts = [SELECT Id FROM Account WHERE Name = 'QDTD Capacity Fixture' LIMIT 1];
Account account;
if (accounts.isEmpty()) { account = new Account(Name = 'QDTD Capacity Fixture'); insert account; }
else account = accounts[0];

List<Opportunity> opportunities = [SELECT Id FROM Opportunity WHERE AccountId = :account.Id AND Name = 'QDTD Capacity Fixture' LIMIT 1];
Opportunity opportunity;
if (opportunities.isEmpty()) {
  opportunity = new Opportunity(Name = 'QDTD Capacity Fixture', AccountId = account.Id, StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
  insert opportunity;
} else opportunity = opportunities[0];

List<Product2> products = [SELECT Id FROM Product2 WHERE ProductCode = 'QDTD-CAPACITY-1' LIMIT 1];
Product2 product;
if (products.isEmpty()) {
  product = new Product2(Name = 'QDTD Capacity Product', ProductCode = 'QDTD-CAPACITY-1', Family = 'Software', IsActive = true);
  insert product;
} else product = products[0];

Id pricebookId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
SBQQ__Quote__c quote = new SBQQ__Quote__c(SBQQ__Account__c = account.Id, SBQQ__Opportunity2__c = opportunity.Id, SBQQ__Primary__c = false, SBQQ__Type__c = 'Quote', SBQQ__Status__c = 'Draft', SBQQ__PriceBook__c = pricebookId, SBQQ__Key__c = fixtureKey);
insert quote;

List<SBQQ__QuoteLine__c> lines = new List<SBQQ__QuoteLine__c>();
for (Integer index = 1; index <= ${lineCount}; index++) {
  Decimal price = 100 + Math.mod(index, 37);
  lines.add(new SBQQ__QuoteLine__c(SBQQ__Quote__c = quote.Id, SBQQ__Product__c = product.Id, SBQQ__Number__c = index, SBQQ__Quantity__c = 1 + Math.mod(index, 5), SBQQ__ListPrice__c = price, SBQQ__ProratedListPrice__c = price, SBQQ__RegularPrice__c = price, SBQQ__Discount__c = Math.mod(index, 4) == 0 ? 10 : 0, SBQQ__ChargeType__c = Math.mod(index, 3) == 0 ? 'Recurring' : 'One-Time', SBQQ__BillingFrequency__c = Math.mod(index, 3) == 0 ? 'Monthly' : null, SBQQ__BillingType__c = Math.mod(index, 3) == 0 ? 'Advance' : null, SBQQ__Optional__c = Math.mod(index, 10) == 0));
}
insert lines;
System.debug(LoggingLevel.ERROR, '${MARKER} ' + JSON.serialize(new Map<String,Object>{'tier' => ${lineCount}, 'quoteId' => String.valueOf(quote.Id), 'lineCount' => lines.size()}));
`;
}

function buildFixtureReport(options, fixtures, generatedAt = new Date()) {
  return {
    schemaVersion: "1.0",
    generatedAt: generatedAt.toISOString(),
    targetOrgAlias: options.targetOrg,
    fixtures,
    safety: {
      syntheticDataOnly: true,
      mutatesSalesforceData: true,
      containsOrgRecordIds: true,
      outputMustRemainIgnored: true
    }
  };
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  const fixtures = [];
  for (const tier of options.tiers) {
    try {
      fixtures.push({
        ...runAnonymous(options.targetOrg, fixtureApex(tier), MARKER),
        status: "Completed"
      });
    } catch {
      fixtures.push({
        tier,
        status: "Failed",
        errorCode: "CAPACITY_FIXTURE_FAILED",
        safeMessage:
          "Synthetic fixture creation failed. Review the local Salesforce CLI result without publishing record data."
      });
    }
  }
  const report = buildFixtureReport(options, fixtures);
  fs.mkdirSync(path.dirname(options.output), { recursive: true });
  fs.writeFileSync(options.output, `${JSON.stringify(report, null, 2)}\n`);
  process.stdout.write(
    `Prepared ${fixtures.length} synthetic capacity fixtures. Record IDs were written only to ${options.output}.\n`
  );
  if (fixtures.some((fixture) => fixture.status !== "Completed")) {
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
  DEFAULT_TIERS,
  MARKER,
  buildFixtureReport,
  fixtureApex,
  parseArguments,
  parseTiers
};
