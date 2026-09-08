#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..", "..");

function values(source, tag) {
  return [...source.matchAll(new RegExp(`<${tag}>([^<]+)</${tag}>`, "gu"))].map(
    (match) => match[1].trim()
  );
}

function summarize(source) {
  return {
    classes: values(source, "apexClass"),
    flows: values(source, "flow"),
    permissions: values(source, "name"),
    tabs: values(source, "tab"),
    mutable:
      source.includes("<editable>true</editable>") ||
      source.includes("<allowCreate>true</allowCreate>") ||
      source.includes("<allowEdit>true</allowEdit>") ||
      source.includes("<allowDelete>true</allowDelete>") ||
      source.includes("<modifyAllRecords>true</modifyAllRecords>")
  };
}

function validateRoles(roleSources, sharingSources) {
  const failures = [];
  const compatibility = summarize(roleSources.compatibility);
  const generator = summarize(roleSources.generator);
  const retrieval = summarize(roleSources.retrieval);

  if (
    !compatibility.classes.includes("QuoteDocumentGenerator") ||
    !compatibility.classes.includes("QuoteDocumentJsonAdapter") ||
    !compatibility.classes.includes("QuoteDocumentRestResource") ||
    !compatibility.flows.includes("Generate_Quote_Document_Tables") ||
    !compatibility.permissions.includes("RunFlow")
  ) {
    failures.push(
      "Compatibility role must retain generation and retrieval access."
    );
  }
  if (
    generator.classes.join(",") !== "QuoteDocumentGenerator" ||
    generator.flows.join(",") !== "Generate_Quote_Document_Tables" ||
    !generator.permissions.includes("RunFlow")
  ) {
    failures.push("Generator role must expose only the generation entry path.");
  }
  if (
    retrieval.classes.join(",") !==
      "QuoteDocumentJsonAdapter,QuoteDocumentRestResource" ||
    retrieval.flows.length !== 0 ||
    retrieval.permissions.includes("RunFlow") ||
    retrieval.tabs.length !== 0
  ) {
    failures.push(
      "Retrieval role must expose only the JSON and REST retrieval paths and no UI generation path."
    );
  }
  for (const [name, role] of Object.entries({
    compatibility,
    generator,
    retrieval
  })) {
    if (role.mutable)
      failures.push(`${name} role grants mutation of generated data.`);
  }
  for (const [name, source] of Object.entries(sharingSources)) {
    if (!source.includes("<sharingModel>Private</sharingModel>")) {
      failures.push(`${name} must use Private sharing.`);
    }
  }
  return failures;
}

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), "utf8");
}

function main() {
  const failures = validateRoles(
    {
      compatibility: read(
        "force-app/main/default/permissionsets/CPQ_Document_Totals.permissionset-meta.xml"
      ),
      generator: read(
        "force-app/main/default/permissionsets/CPQ_Document_Totals_Generator.permissionset-meta.xml"
      ),
      retrieval: read(
        "force-app/main/default/permissionsets/CPQ_Document_Totals_Retrieval.permissionset-meta.xml"
      )
    },
    {
      tables: read(
        "force-app/main/default/objects/Quote_Document_Table__c/Quote_Document_Table__c.object-meta.xml"
      ),
      blocks: read(
        "force-app/main/default/objects/Quote_Document_Block__c/Quote_Document_Block__c.object-meta.xml"
      ),
      facts: read(
        "force-app/main/default/objects/Quote_Document_Fact__c/Quote_Document_Fact__c.object-meta.xml"
      )
    }
  );
  if (failures.length > 0) {
    process.stderr.write(`${failures.join("\n")}\n`);
    process.exit(1);
  }
  process.stdout.write(
    "Verified read-only compatibility, generator, and retrieval roles with private generated-document sharing.\n"
  );
}

if (require.main === module) main();

module.exports = { summarize, validateRoles, values };
