#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const root = path.resolve(__dirname, "..", "..");

const FORBIDDEN_TRACKED_PREFIXES = [
  ".agents/",
  ".codex/",
  ".sf/",
  ".sfdx/",
  "artifacts/",
  "bugs/",
  "development/",
  "enhancements/",
  "implementation-evidence/",
  "internal/",
  "reports/",
  "repository-review/",
  "research/",
  "results/",
  "review-artifacts/",
  "scripts/ci/check-repository-review.js",
  "scripts/ci/check-repository-review.test.js",
  "specs/",
  "test-results/",
  "tmp/"
];

const FORBIDDEN_TRACKED_FILES = [
  /(^|\/)\.env(\.|$)/u,
  /\.(key|pem|sarif)$/iu,
  /(^|\/)junit[^/]*\.xml$/iu,
  /(^|\/)lcov\.info$/iu,
  /(^|\/)code-analyzer-results-[^/]+\.(json|log)$/iu
];

const REQUIRED_IGNORED_EXAMPLES = [
  "artifacts/example.json",
  "bugs/BUG-001.md",
  "development/notes.md",
  "enhancements/plan.md",
  "implementation-evidence/run.json",
  "internal/decision.md",
  "reports/audit.md",
  "repository-review/findings.md",
  "research/notes.md",
  "results/output.xml",
  "review-artifacts/review.json",
  "scripts/ci/check-repository-review.js",
  "scripts/ci/check-repository-review.test.js",
  "specs/draft.md",
  "test-results/junit.xml",
  "tmp/scratch.txt",
  ".env.local",
  "private-key.pem",
  "scan.sarif"
];

function normalize(value) {
  return value.replaceAll("\\", "/").replace(/^\.\//u, "");
}

function trackedPathFailures(paths) {
  const failures = [];
  for (const rawPath of paths) {
    const file = normalize(rawPath);
    const prefix = FORBIDDEN_TRACKED_PREFIXES.find((entry) =>
      file.startsWith(entry)
    );
    if (prefix) {
      failures.push(`${file}: internal or generated path is tracked`);
      continue;
    }
    if (FORBIDDEN_TRACKED_FILES.some((pattern) => pattern.test(file))) {
      failures.push(
        `${file}: secret-bearing or generated file type is tracked`
      );
    }
  }
  return failures;
}

function secretContentFailures(entries) {
  const failures = [];
  const patterns = [
    [/-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/u, "private key"],
    [/\bforce:\/\/[^\s'"]+@/u, "Salesforce authentication URL"],
    [
      /\b(?:access_token|refresh_token|client_secret)\s*[:=]\s*["'][^"']{8,}["']/iu,
      "credential value"
    ]
  ];
  for (const [file, content] of entries) {
    for (const [pattern, label] of patterns) {
      if (pattern.test(content)) failures.push(`${file}: possible ${label}`);
    }
  }
  return failures;
}

function runGit(args, options = {}) {
  const result = spawnSync("git", args, {
    cwd: root,
    encoding: "utf8",
    input: options.input,
    maxBuffer: 100 * 1024 * 1024
  });
  if (result.error) throw result.error;
  return result;
}

function publicationCandidateFiles() {
  const result = runGit([
    "ls-files",
    "-z",
    "--cached",
    "--others",
    "--exclude-standard"
  ]);
  if (result.status !== 0) throw new Error(result.stderr.trim());
  return result.stdout.split("\0").filter(Boolean).map(normalize);
}

function ignoredExampleFailures() {
  const result = runGit(["check-ignore", "--no-index", "--stdin"], {
    input: `${REQUIRED_IGNORED_EXAMPLES.join("\n")}\n`
  });
  if (![0, 1].includes(result.status)) throw new Error(result.stderr.trim());
  const ignored = new Set(
    result.stdout.split(/\r?\n/u).filter(Boolean).map(normalize)
  );
  return REQUIRED_IGNORED_EXAMPLES.filter((file) => !ignored.has(file)).map(
    (file) => `${file}: representative path is not ignored`
  );
}

function trackedTextEntries(files) {
  return files.flatMap((file) => {
    const fullPath = path.join(root, file);
    if (!fs.existsSync(fullPath) || fs.statSync(fullPath).size > 2_000_000)
      return [];
    const content = fs.readFileSync(fullPath);
    if (content.includes(0)) return [];
    return [[file, content.toString("utf8")]];
  });
}

function main() {
  const files = publicationCandidateFiles();
  const failures = [
    ...trackedPathFailures(files),
    ...ignoredExampleFailures(),
    ...secretContentFailures(trackedTextEntries(files))
  ];
  const salesforceReports = files.filter((file) =>
    file.startsWith("force-app/main/default/reports/")
  );
  if (salesforceReports.length === 0) {
    failures.push(
      "force-app/main/default/reports/: product report metadata is missing"
    );
  }
  if (failures.length > 0) {
    process.stderr.write(`${failures.join("\n")}\n`);
    process.exitCode = 1;
    return;
  }
  process.stdout.write(
    `Checked ${files.length} publication-candidate paths, ${REQUIRED_IGNORED_EXAMPLES.length} ignore examples, high-confidence credential patterns, and ${salesforceReports.length} Salesforce report metadata files.\n`
  );
}

if (require.main === module) main();

module.exports = {
  FORBIDDEN_TRACKED_FILES,
  FORBIDDEN_TRACKED_PREFIXES,
  REQUIRED_IGNORED_EXAMPLES,
  normalize,
  secretContentFailures,
  trackedPathFailures
};
