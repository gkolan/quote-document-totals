const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const {
  buildReport,
  extractJson,
  inspectCpqPackage,
  inspectDependency,
  parseArguments,
  runPreflight
} = require("./install-preflight");

const manifest = {
  projectApiVersion: "67.0",
  dependencies: [
    {
      capability: "Core",
      object: "SBQQ__Quote__c",
      fields: ["SBQQ__Status__c", "SBQQ__NetAmount__c"]
    }
  ]
};

test("the checked-in prerequisite manifest follows current source identities", () => {
  const root = path.join(__dirname, "..", "..");
  const checkedInManifest = JSON.parse(
    fs.readFileSync(path.join(root, "install-prerequisites.json"), "utf8")
  );
  const project = JSON.parse(
    fs.readFileSync(path.join(root, "sfdx-project.json"), "utf8")
  );
  assert.equal(checkedInManifest.projectApiVersion, project.sourceApiVersion);

  const classDirectory = path.join(
    root,
    "force-app",
    "main",
    "default",
    "classes"
  );
  const productionSource = fs
    .readdirSync(classDirectory)
    .filter((name) => name.endsWith(".cls") && !name.endsWith("Test.cls"))
    .map((name) => fs.readFileSync(path.join(classDirectory, name), "utf8"))
    .join("\n");
  for (const dependency of checkedInManifest.dependencies) {
    assert.match(productionSource, new RegExp(dependency.object));
    for (const field of dependency.fields) {
      assert.match(
        productionSource,
        new RegExp(field),
        `${dependency.object}.${field} is not referenced by production Apex`
      );
    }
  }
});

test("requires an explicit target org and supports an evidence path", () => {
  assert.throws(() => parseArguments([]), /--target-org is required/);
  assert.deepEqual(
    parseArguments(["--target-org", "qdt", "--output", "evidence.json"]),
    { targetOrg: "qdt", output: "evidence.json" }
  );
  assert.throws(
    () => parseArguments(["--target-org", "qdt", "--unknown", "x"]),
    /Unknown argument/
  );
});

test("extracts JSON after a CLI warning", () => {
  assert.deepEqual(extractJson('warning\n{"status":0}'), { status: 0 });
});

test("reports missing objects and fields without hiding the capability", () => {
  assert.deepEqual(
    inspectDependency(manifest.dependencies[0], {
      status: 0,
      result: { fields: [{ name: "SBQQ__Status__c" }] }
    }),
    {
      capability: "Core",
      object: "SBQQ__Quote__c",
      available: false,
      missingFields: ["SBQQ__NetAmount__c"]
    }
  );
  const failed = inspectDependency(manifest.dependencies[0], {
    status: 1,
    message: "not found"
  });
  assert.equal(failed.available, false);
  assert.equal(failed.error, "not found");
});

test("finds the installed CPQ package and records its exact version", () => {
  assert.deepEqual(
    inspectCpqPackage({
      status: 0,
      result: {
        records: [
          {
            SubscriberPackage: {
              Name: "Salesforce CPQ",
              NamespacePrefix: "SBQQ"
            },
            SubscriberPackageVersion: {
              MajorVersion: 240,
              MinorVersion: 5,
              PatchVersion: 0,
              BuildNumber: 1
            }
          }
        ]
      }
    }),
    {
      available: true,
      name: "Salesforce CPQ",
      namespace: "SBQQ",
      version: "240.5.0.1"
    }
  );
  assert.equal(
    inspectCpqPackage({ status: 0, result: { records: [] } }).available,
    false
  );
});

test("runs schema describes without source upload or mutation", () => {
  const calls = [];
  const report = runPreflight(
    { targetOrg: "qdt" },
    manifest,
    (argumentsList) => {
      calls.push(argumentsList);
      if (argumentsList[0] === "data") {
        return {
          stdout: JSON.stringify({
            status: 0,
            result: {
              records: [
                {
                  SubscriberPackage: {
                    Name: "Salesforce CPQ",
                    NamespacePrefix: "SBQQ"
                  },
                  SubscriberPackageVersion: {
                    MajorVersion: 240,
                    MinorVersion: 5,
                    PatchVersion: 0,
                    BuildNumber: 1
                  }
                }
              ]
            }
          })
        };
      }
      return {
        stdout: JSON.stringify({
          status: 0,
          result: {
            fields: [
              { name: "SBQQ__Status__c" },
              { name: "SBQQ__NetAmount__c" }
            ]
          }
        })
      };
    }
  );
  assert.equal(report.ready, true);
  assert.equal(report.safety.schemaDescribeOnly, true);
  assert.equal(report.safety.uploadsRepositorySource, false);
  assert.equal(report.safety.mutatesSalesforceData, false);
  assert.deepEqual(calls[0].slice(0, 2), ["data", "query"]);
  assert.deepEqual(calls[1].slice(0, 2), ["sobject", "describe"]);
});

test("the report fails readiness when any dependency is absent", () => {
  const report = buildReport(
    "qdt",
    manifest,
    { available: true, version: "240.5.0.1" },
    [
      {
        capability: "Core",
        object: "SBQQ__Quote__c",
        available: false,
        missingFields: ["SBQQ__NetAmount__c"]
      }
    ],
    new Date("2026-09-07T00:00:00Z")
  );
  assert.equal(report.ready, false);
  assert.equal(report.generatedAt, "2026-09-07T00:00:00.000Z");
  assert.match(report.limitation, /check-only deployment/);
});
