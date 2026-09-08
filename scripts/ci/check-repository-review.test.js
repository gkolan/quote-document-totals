const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { spawnSync } = require("node:child_process");
const test = require("node:test");

const root = path.resolve(__dirname, "..", "..");
const validator = path.join(__dirname, "check-repository-review.js");
const temporaryRoots = [];

function runValidator(fixtureRoot = root) {
  return spawnSync(process.execPath, [validator], {
    cwd: fixtureRoot,
    encoding: "utf8",
    env: {
      ...process.env,
      REPOSITORY_REVIEW_ROOT: fixtureRoot
    }
  });
}

function copyFixture() {
  const fixtureRoot = fs.mkdtempSync(
    path.join(os.tmpdir(), "quote-document-review-")
  );
  temporaryRoots.push(fixtureRoot);
  fs.cpSync(
    path.join(root, "repository-review"),
    path.join(fixtureRoot, "repository-review"),
    { recursive: true }
  );
  return fixtureRoot;
}

function replaceInFile(file, current, replacement) {
  const original = fs.readFileSync(file, "utf8");
  assert.ok(original.includes(current), `Fixture text not found in ${file}`);
  fs.writeFileSync(file, original.replace(current, replacement));
}

test.after(() => {
  for (const fixtureRoot of temporaryRoots) {
    fs.rmSync(fixtureRoot, { recursive: true, force: true });
  }
});

test("accepts the current traceable scenario catalog", () => {
  const result = runValidator();
  assert.equal(result.status, 0, result.stderr);
  assert.match(
    result.stdout,
    /Validated 15 scenario briefs, 92 traceable work packages/
  );
});

test("rejects a scenario without a Work packages section", () => {
  const fixtureRoot = copyFixture();
  const scenario = path.join(
    fixtureRoot,
    "repository-review",
    "scenarios",
    "01-production-installation-and-standard-user-access.md"
  );
  replaceInFile(scenario, "## Work packages", "## Delivery plan");

  const result = runValidator(fixtureRoot);
  assert.equal(result.status, 1);
  assert.match(
    result.stderr,
    /01-production-installation-and-standard-user-access[.]md: missing required content "## Work packages"/
  );
});

test("rejects a missing document-composition capability matrix", () => {
  const fixtureRoot = copyFixture();
  fs.rmSync(
    path.join(
      fixtureRoot,
      "repository-review",
      "08-document-composition-capability-matrix.md"
    )
  );

  const result = runValidator(fixtureRoot);
  assert.equal(result.status, 1);
  assert.match(
    result.stderr,
    /08-document-composition-capability-matrix[.]md: required file is missing/
  );
});

test("rejects a skipped or duplicate work-package identifier", () => {
  const fixtureRoot = copyFixture();
  const scenario = path.join(
    fixtureRoot,
    "repository-review",
    "scenarios",
    "01-production-installation-and-standard-user-access.md"
  );
  replaceInFile(scenario, "| WP02 |", "| WP03 |");

  const result = runValidator(fixtureRoot);
  assert.equal(result.status, 1);
  assert.match(
    result.stderr,
    /expected contiguous work package "WP02", found "WP03"/
  );
});

test("rejects a brief-to-matrix title mismatch", () => {
  const fixtureRoot = copyFixture();
  const matrix = path.join(
    fixtureRoot,
    "repository-review",
    "07-scenario-verification-matrix.md"
  );
  replaceInFile(
    matrix,
    "**WP01:** Reproduce and fix missing Flow/Apex execution permissions.",
    "**WP01:** Reproduce a different behavior."
  );

  const result = runValidator(fixtureRoot);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /does not match matrix package/);
});

test("accepts a scenario-specific additional contiguous package", () => {
  const fixtureRoot = copyFixture();
  const scenario = path.join(
    fixtureRoot,
    "repository-review",
    "scenarios",
    "14-high-scale-api-batch-and-integration-contracts.md"
  );
  replaceInFile(
    scenario,
    "\n## API resources",
    "\n| WP07 | Validate an additional bounded contract | Revert the bounded contract only | Focused contract evidence passes | 0-6, 9-10 |\n\n## API resources"
  );
  const matrix = path.join(
    fixtureRoot,
    "repository-review",
    "07-scenario-verification-matrix.md"
  );
  replaceInFile(
    matrix,
    "6. **WP06:** Run concurrency, backpressure, and security war tests.",
    "6. **WP06:** Run concurrency, backpressure, and security war tests.\n7. **WP07:** Validate an additional bounded contract."
  );

  const result = runValidator(fixtureRoot);
  assert.equal(result.status, 0, result.stderr);
});

test("rejects a Scenario 15 conditional-composition title mismatch", () => {
  const fixtureRoot = copyFixture();
  const matrix = path.join(
    fixtureRoot,
    "repository-review",
    "07-scenario-verification-matrix.md"
  );
  replaceInFile(
    matrix,
    "**WP06:** Add safe allowlisted resolved text.",
    "**WP06:** Add unrestricted merge expressions."
  );

  const result = runValidator(fixtureRoot);
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Scenario 15: brief package .* does not match/);
});
