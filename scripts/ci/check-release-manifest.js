#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");

function files(directory) {
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = path.join(directory, entry.name);
    return entry.isDirectory() ? files(fullPath) : [fullPath];
  });
}

function withoutSuffix(name, suffix) {
  return name.endsWith(suffix) ? name.slice(0, -suffix.length) : null;
}

function add(inventory, type, member) {
  if (!member || member.includes("TDX_")) return;
  if (!inventory.has(type)) inventory.set(type, new Set());
  inventory.get(type).add(member.replaceAll(path.sep, "/"));
}

function inventorySource(sourceRoot) {
  const inventory = new Map();
  const defaultRoot = path.join(sourceRoot, "main", "default");
  const simpleDirectories = [
    ["classes", ".cls", "ApexClass"],
    ["triggers", ".trigger", "ApexTrigger"],
    ["flows", ".flow-meta.xml", "Flow"],
    ["permissionsets", ".permissionset-meta.xml", "PermissionSet"],
    ["quickActions", ".quickAction-meta.xml", "QuickAction"],
    ["reportTypes", ".reportType-meta.xml", "ReportType"],
    ["tabs", ".tab-meta.xml", "CustomTab"]
  ];
  for (const [directory, suffix, type] of simpleDirectories) {
    for (const file of files(path.join(defaultRoot, directory))) {
      add(inventory, type, withoutSuffix(path.basename(file), suffix));
    }
  }
  for (const file of files(path.join(defaultRoot, "customMetadata"))) {
    add(
      inventory,
      "CustomMetadata",
      withoutSuffix(path.basename(file), ".md-meta.xml")
    );
  }
  const objectsRoot = path.join(defaultRoot, "objects");
  for (const file of files(objectsRoot)) {
    const relative = path.relative(objectsRoot, file).split(path.sep);
    const objectName = relative[0];
    const fileName = path.basename(file);
    if (fileName === `${objectName}.object-meta.xml`) {
      add(inventory, "CustomObject", objectName);
    } else if (relative[1] === "fields") {
      add(
        inventory,
        "CustomField",
        `${objectName}.${withoutSuffix(fileName, ".field-meta.xml")}`
      );
    } else if (relative[1] === "listViews") {
      add(
        inventory,
        "ListView",
        `${objectName}.${withoutSuffix(fileName, ".listView-meta.xml")}`
      );
    } else if (relative[1] === "validationRules") {
      add(
        inventory,
        "ValidationRule",
        `${objectName}.${withoutSuffix(fileName, ".validationRule-meta.xml")}`
      );
    }
  }
  const reportsRoot = path.join(defaultRoot, "reports");
  for (const file of files(reportsRoot)) {
    const relative = path.relative(reportsRoot, file);
    const folder = withoutSuffix(path.basename(file), ".reportFolder-meta.xml");
    if (folder) add(inventory, "Report", `${folder}/`);
    const report = withoutSuffix(path.basename(file), ".report-meta.xml");
    if (report) {
      add(inventory, "Report", `${path.dirname(relative)}/${report}`);
    }
  }
  return inventory;
}

function parseManifest(xml) {
  const inventory = new Map();
  for (const block of xml.matchAll(/<types\s*>([\s\S]*?)<\/types>/gu)) {
    const type = block[1].match(/<name\s*>([^<]+)<\/name>/u)?.[1].trim();
    if (!type)
      throw new Error("Manifest contains a type block without a name.");
    const members = new Set(
      [...block[1].matchAll(/<members\s*>([^<]+)<\/members>/gu)].map((match) =>
        match[1].trim()
      )
    );
    if (inventory.has(type)) throw new Error(`Duplicate type block: ${type}`);
    inventory.set(type, members);
  }
  return inventory;
}

function differences(expected, actual) {
  const missing = [];
  const unexpected = [];
  const types = new Set([...expected.keys(), ...actual.keys()]);
  for (const type of [...types].sort()) {
    const expectedMembers = expected.get(type) || new Set();
    const actualMembers = actual.get(type) || new Set();
    for (const member of expectedMembers) {
      if (!actualMembers.has(member)) missing.push(`${type}:${member}`);
    }
    for (const member of actualMembers) {
      if (!expectedMembers.has(member)) unexpected.push(`${type}:${member}`);
    }
  }
  return { missing: missing.sort(), unexpected: unexpected.sort() };
}

function serializeManifest(inventory, apiVersion = "67.0") {
  const lines = [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<Package xmlns="http://soap.sforce.com/2006/04/metadata">'
  ];
  for (const type of [...inventory.keys()].sort()) {
    lines.push("    <types>");
    for (const member of [...inventory.get(type)].sort()) {
      lines.push(`        <members>${member}</members>`);
    }
    lines.push(`        <name>${type}</name>`, "    </types>");
  }
  lines.push(`    <version>${apiVersion}</version>`, "</Package>", "");
  return lines.join("\n");
}

function validate(root) {
  const expected = inventorySource(path.join(root, "force-app"));
  const manifest = fs.readFileSync(
    path.join(root, "manifest", "package.xml"),
    "utf8"
  );
  const actual = parseManifest(manifest);
  const result = differences(expected, actual);
  if (result.missing.length || result.unexpected.length) {
    throw new Error(
      `Release manifest is out of sync. Missing: ${result.missing.join(", ") || "none"}. Unexpected: ${result.unexpected.join(", ") || "none"}.`
    );
  }
  return [...expected.values()].reduce((sum, members) => sum + members.size, 0);
}

function main() {
  const root = path.resolve(__dirname, "..", "..");
  const count = validate(root);
  process.stdout.write(
    `Release manifest exactly covers ${count} non-TDX source components.\n`
  );
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
  differences,
  inventorySource,
  parseManifest,
  serializeManifest,
  validate
};
