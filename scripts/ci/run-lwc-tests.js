const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.resolve(__dirname, "..", "..");
const sourceDir = path.join(root, "force-app");

function findTests(directory) {
  if (!fs.existsSync(directory)) {
    return [];
  }

  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      return findTests(fullPath);
    }
    return entry.name.endsWith(".test.js") ? [fullPath] : [];
  });
}

const tests = findTests(sourceDir);

if (tests.length === 0) {
  process.stdout.write("No LWC test files are present; skipping LWC Jest.\n");
  process.exit(0);
}

const runner = require.resolve("@salesforce/sfdx-lwc-jest/bin/sfdx-lwc-jest");
const result = spawnSync(process.execPath, [runner, ...process.argv.slice(2)], {
  cwd: root,
  stdio: "inherit"
});

if (result.error) {
  throw result.error;
}

process.exit(result.status ?? 1);
