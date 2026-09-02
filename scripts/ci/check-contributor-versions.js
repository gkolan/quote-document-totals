#!/usr/bin/env node
/**
 * Step 01A section 10 - the contributor version gate.
 *
 * Nothing in the platform can see an Apex body or a Flow definition change.
 * The fingerprint hashes Row_Customizer_Version__c and
 * Row_Customizer_Flow_Version__c instead, so a contributor whose LOGIC
 * changed under an unchanged version token leaves the fingerprint identical,
 * quotes stay Ready, and generation reuses a snapshot the new logic would
 * never have produced. That is a wrong document, not a hygiene problem.
 *
 * Bumping the token is therefore an operational discipline, and this gate is
 * the only thing that enforces it. It compares changed files against the
 * merge base and fails the build when a customizer class or contributor Flow
 * moved without its token moving with it.
 *
 * EVERYTHING HERE FAILS THE BUILD. Nothing warns. A gate that warns is a gate
 * that gets scrolled past, and the failure it is guarding against is silent
 * by construction - there is no second chance to notice it.
 *
 * Exit codes: 0 clean, 1 violations found, 2 the gate itself could not run
 * (which is also a build failure - a gate that cannot run has not passed).
 */

"use strict";

const fs = require("fs");
const path = require("path");
const { execFileSync } = require("child_process");

const REPO_ROOT = path.resolve(__dirname, "..", "..");
const CMDT_DIR = path.join(
  REPO_ROOT,
  "force-app",
  "main",
  "default",
  "customMetadata"
);
const CLASS_DIR = path.join(
  REPO_ROOT,
  "force-app",
  "main",
  "default",
  "classes"
);
const FLOW_DIR = path.join(REPO_ROOT, "force-app", "main", "default", "flows");
const REGISTRY = path.join(CLASS_DIR, "QuoteDocumentRowCustomizerRegistry.cls");

class GateError extends Error {}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/** Reads one Salesforce Custom Metadata field without crossing into the next field. */
function cmdtValue(xml, field) {
  const blockPattern = new RegExp(
    "<values>\\s*<field>" + field + "</field>([\\s\\S]*?)</values>"
  );
  const blockMatch = xml.match(blockPattern);
  if (!blockMatch) {
    return null;
  }

  const valueMatch = blockMatch[1].match(/<value[^>]*>([\s\S]*?)<\/value>/);
  if (valueMatch) {
    return valueMatch[1].trim();
  }

  // Salesforce writes a blank text value as <value ... />. It is blank, not
  // the start of a value that continues through the following metadata fields.
  return /<value\b[^>]*\/>/.test(blockMatch[1]) ? "" : null;
}

/**
 * code -> Apex class name, from the registry's switch.
 *
 * Deliberately strict about the shape it accepts. A `when` branch this regex
 * cannot read is not skipped - skipping is how a gate silently stops covering
 * the one contributor someone reformatted. It is reported, and the build
 * fails. The cases that must not slip through, per section 10: multiline
 * branches, commented-out branches, and a reformatted registry.
 */
function parseRegistry(source) {
  if (!source || !source.includes("switch on")) {
    throw new GateError(
      "QuoteDocumentRowCustomizerRegistry.cls has no switch statement. Either the registry moved or " +
        "this gate is parsing the wrong file - both mean the gate is no longer checking anything."
    );
  }

  const mapping = new Map();
  const unreadable = [];

  // Strip block comments first so a commented-out branch cannot be read as
  // live. Line comments are handled per line below, where the distinction
  // between "commented out" and "unreadable" still matters.
  const withoutBlockComments = source.replace(/\/\*[\s\S]*?\*\//g, "");
  const lines = withoutBlockComments.split(/\r?\n/);

  for (const raw of lines) {
    const line = raw.trim();
    if (line.startsWith("//")) {
      continue;
    }
    if (!/^when\b/.test(line)) {
      continue;
    }
    if (/^when\s+else\b/.test(line)) {
      continue;
    }

    const match = line.match(
      /^when\s+'([^']+)'\s*\{\s*return\s+new\s+([A-Za-z0-9_]+)\s*\(\s*\)\s*;\s*\}/
    );
    if (!match) {
      // A branch that opens here and closes on a later line, or one
      // written in a shape this gate does not know. Never skipped.
      unreadable.push(line);
      continue;
    }
    mapping.set(match[1], match[2]);
  }

  if (unreadable.length > 0) {
    throw new GateError(
      "These registry branches could not be parsed, so the gate cannot tell which class they map to:\n" +
        unreadable.map((l) => "    " + l).join("\n") +
        "\nKeep each branch on one line as `when 'CODE' { return new ClassName(); }`, or update " +
        "this gate to understand the new shape. Skipping them would leave a contributor unguarded."
    );
  }

  if (mapping.size === 0) {
    throw new GateError(
      "Parsed zero customizer codes from the registry. That is almost certainly a parsing failure " +
        "rather than a registry with no entries, and a gate that checks nothing must not report success."
    );
  }

  return mapping;
}

/** Every table definition that names a contributor, with its declared version tokens. */
function parseDefinitions(dir, readFile, listFiles) {
  const files = listFiles(dir).filter(
    (f) =>
      f.startsWith("Quote_Document_Table_Def.") && f.endsWith(".md-meta.xml")
  );

  if (files.length === 0) {
    throw new GateError(
      "Found no Quote_Document_Table_Def__mdt records under " +
        dir +
        ". The gate cannot map a " +
        "changed contributor back to the token that must be bumped."
    );
  }

  const definitions = [];
  for (const file of files) {
    const xml = readFile(path.join(dir, file));
    const code = cmdtValue(xml, "Row_Customizer_Code__c");
    const flow = cmdtValue(xml, "Row_Customizer_Flow__c");
    if (!code && !flow) {
      continue;
    }
    definitions.push({
      file,
      tableCode: cmdtValue(xml, "Table_Code__c"),
      customizerCode: code,
      customizerVersion: cmdtValue(xml, "Row_Customizer_Version__c"),
      flowName: flow,
      flowVersion: cmdtValue(xml, "Row_Customizer_Flow_Version__c")
    });
  }
  return definitions;
}

// ---------------------------------------------------------------------------
// The rule
// ---------------------------------------------------------------------------

/**
 * Pure, so the suite can drive it without a git repository.
 *
 * changedFiles: repo-relative paths changed since the merge base.
 */
function findViolations({
  changedFiles,
  registry,
  definitions,
  previousTokens
}) {
  const violations = [];
  const changed = new Set(changedFiles);
  const previous = previousTokens || {};

  const classChanged = (className) =>
    changed.has("force-app/main/default/classes/" + className + ".cls");
  const flowChanged = (flowName) =>
    changed.has("force-app/main/default/flows/" + flowName + ".flow-meta.xml");

  /**
   * Whether the TOKEN VALUE moved - not whether the file did.
   *
   * This is the whole gate. The first version compared file paths: "the
   * customizer changed, did its metadata file also change?" That is
   * satisfied by editing anything at all in the record - a help text, an
   * unrelated field, a whitespace change - while the version token stays
   * exactly as it was. A reviewer reproduced it: changed customizer, changed
   * metadata file, unchanged token, gate green.
   *
   * A missing previous value means the record is new in this change, which
   * cannot be a stale-token problem.
   */
  const tokenMoved = (file, field, current) => {
    const before = previous[file] && previous[file][field];
    if (before === undefined || before === null) {
      return true;
    }
    return (
      String(before) !==
      String(current === undefined || current === null ? "" : current)
    );
  };

  for (const definition of definitions) {
    if (definition.customizerCode) {
      const className = registry.get(definition.customizerCode);
      if (!className) {
        violations.push(
          definition.tableCode +
            ' names Row_Customizer_Code__c "' +
            definition.customizerCode +
            '", which the registry does not resolve. Either the code was renamed and the ' +
            "metadata was not updated, or the registry branch was removed. Generation would " +
            "fail at runtime, and until then this contributor is outside the version gate."
        );
      } else if (
        classChanged(className) &&
        !tokenMoved(
          definition.file,
          "customizerVersion",
          definition.customizerVersion
        )
      ) {
        violations.push(
          className +
            ".cls changed but Row_Customizer_Version__c on " +
            definition.file +
            ' is still "' +
            definition.customizerVersion +
            '". Editing the metadata record is ' +
            "not enough - the TOKEN has to move, because the token is what the fingerprint " +
            "hashes. Quotes using table " +
            definition.tableCode +
            " would stay Ready and " +
            "reuse a snapshot the new logic would not have produced. Bump it and run the " +
            "step 05 invalidation job."
        );
      }
    }

    if (definition.flowName) {
      if (
        flowChanged(definition.flowName) &&
        !tokenMoved(definition.file, "flowVersion", definition.flowVersion)
      ) {
        violations.push(
          definition.flowName +
            ".flow-meta.xml changed but Row_Customizer_Flow_Version__c on " +
            definition.file +
            ' is still "' +
            definition.flowVersion +
            '". Editing a Flow does ' +
            "not change its API name, so the fingerprint cannot see the change unless the " +
            "token moves. Bump it and run the step 05 invalidation job."
        );
      }
    }
  }

  return violations;
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function commitExists(ref) {
  try {
    // stderr ignored: a missing commit is an ANSWER here, not a fault,
    // and git's fatal: line reads like the gate itself broke.
    execFileSync("git", ["cat-file", "-e", ref + "^{commit}"], {
      cwd: REPO_ROOT,
      stdio: ["ignore", "ignore", "ignore"]
    });
    return true;
  } catch (e) {
    return false;
  }
}

function rootCommit() {
  const output = execFileSync("git", ["rev-list", "--max-parents=0", "HEAD"], {
    cwd: REPO_ROOT,
    encoding: "utf8"
  })
    .trim()
    .split(/\r?\n/);
  return output[output.length - 1];
}

/**
 * The commit this run is compared against.
 *
 * A PR compares with the merge base: its branch is behind the target and the
 * commits it does not contain are not its changes. A PUSH compares with the
 * pre-push tip EXACTLY - the merge base of that tip and HEAD is their common
 * ancestor, and a force-push replacing the tip with different work leaves an
 * ancestor old enough to make an unbumped token look bumped. The push is
 * being judged against what was actually deployed, not against where the two
 * histories last agreed.
 */
function comparisonCommit(base, exact) {
  if (exact) {
    if (!commitExists(base)) {
      throw new GateError(
        'The pre-push commit "' +
          base +
          '" is not in this clone, so the gate cannot see what the ' +
          "push actually changed. Failing closed: an unverifiable push is not a passing one. " +
          "Check that actions/checkout used fetch-depth: 0."
      );
    }
    return base;
  }
  try {
    return execFileSync("git", ["merge-base", base, "HEAD"], {
      cwd: REPO_ROOT,
      encoding: "utf8"
    }).trim();
  } catch (e) {
    throw new GateError(
      'Could not resolve a merge base against "' +
        base +
        '". Without it the gate has no idea what ' +
        "changed, and a gate that cannot run has not passed. In CI, fetch the base branch first " +
        "(actions/checkout defaults to a shallow clone). Underlying error: " +
        e.message
    );
  }
}

function changedFilesSince(commit, cwd) {
  const output = execFileSync("git", ["diff", "--name-only", commit, "HEAD"], {
    cwd: cwd || REPO_ROOT,
    encoding: "utf8"
  });
  return output.split(/\r?\n/).filter(Boolean);
}

/**
 * The version tokens as they were at the comparison commit.
 *
 * Read with `git show <commit>:<path>` rather than from the diff, so the gate
 * compares VALUES. A file-level comparison is satisfied by editing anything in
 * the record while the token stands still, which is exactly the case that
 * ships a stale snapshot.
 *
 * A file that did not exist there yields no entry, and a definition with
 * no previous value is treated as new rather than stale - a record being added
 * cannot be a stale-token problem.
 */
function tokensAt(commit, definitions) {
  const previous = {};
  for (const definition of definitions) {
    const path = "force-app/main/default/customMetadata/" + definition.file;
    let xml;
    try {
      xml = execFileSync("git", ["show", commit + ":" + path], {
        cwd: REPO_ROOT,
        encoding: "utf8",
        // A file absent at the base is the NEW-record case, which is
        // expected and handled below. Letting git print its "exists on
        // disk, but not in <sha>" fatal to stderr would make every
        // clean run of a branch that adds a contributor look broken.
        stdio: ["ignore", "pipe", "ignore"]
      });
    } catch (e) {
      // Not present at the base: a new record, not a stale one.
      continue;
    }
    previous[definition.file] = {
      customizerVersion: cmdtValue(xml, "Row_Customizer_Version__c"),
      flowVersion: cmdtValue(xml, "Row_Customizer_Flow_Version__c")
    };
  }
  return previous;
}

/**
 * Which commit this run compares against.
 *
 * A pull request compares with the target branch. A PUSH must compare with
 * the commit that was there BEFORE the push: `origin/main` has already been
 * advanced to the pushed commit by then, so its merge base with HEAD is HEAD
 * and the gate would inspect an empty diff - a direct push could change a
 * customizer without touching its version and sail through.
 *
 * `before` is all-zeros for the first push of a branch, and can name a commit
 * a force-push has since orphaned. The workflow fetches that exact commit;
 * if it is still unavailable, the gate fails instead of guessing a base.
 */
function resolveBase({ baseRef, before, rootCommit, exists }) {
  if (baseRef) {
    return { base: "origin/" + baseRef, exact: false };
  }
  if (!before || /^0+$/.test(before)) {
    // All-zeros: the first push of a branch, with nothing before it.
    // Every file reads as newly added, which is what it is.
    return { base: rootCommit(), exact: false };
  }
  if (!exists(before)) {
    throw new GateError(
      'The push names "' +
        before +
        '" as its previous commit, but that commit is not in this ' +
        "clone. The gate cannot tell what the push changed, so it fails closed rather than " +
        "comparing against a guess. Check that actions/checkout used fetch-depth: 0."
    );
  }
  return { base: before, exact: true };
}

function main(argv) {
  const baseArg = argv.indexOf("--base");
  const selected =
    baseArg !== -1
      ? { base: argv[baseArg + 1], exact: false }
      : resolveBase({
          baseRef: process.env.GITHUB_BASE_REF,
          before: process.env.GITHUB_EVENT_BEFORE,
          exists: commitExists,
          rootCommit: rootCommit
        });
  const base = selected.base;
  const against = comparisonCommit(base, selected.exact);

  if (!fs.existsSync(REGISTRY)) {
    throw new GateError(
      "QuoteDocumentRowCustomizerRegistry.cls not found at " +
        REGISTRY +
        ". The gate cannot map " +
        "customizer codes to classes."
    );
  }

  const registry = parseRegistry(fs.readFileSync(REGISTRY, "utf8"));
  const definitions = parseDefinitions(
    CMDT_DIR,
    (p) => fs.readFileSync(p, "utf8"),
    (d) => fs.readdirSync(d)
  );
  const changedFiles = changedFilesSince(against);
  const previousTokens = tokensAt(against, definitions);
  const violations = findViolations({
    changedFiles,
    registry,
    definitions,
    previousTokens
  });

  if (violations.length > 0) {
    console.error("Contributor version gate FAILED:\n");
    violations.forEach((v, i) =>
      console.error("  " + (i + 1) + ". " + v + "\n")
    );
    console.error(
      "If this is an emergency deployment, the only supported way past this gate is to record a " +
        "manual invalidation run - not to skip the gate and fix it later. The document is already " +
        "wrong by the time anyone notices."
    );
    return 1;
  }

  console.log(
    "Contributor version gate passed: " +
      registry.size +
      " registry codes, " +
      definitions.length +
      " contributor table definitions, " +
      changedFiles.length +
      " changed files since " +
      base +
      "."
  );
  return 0;
}

if (require.main === module) {
  try {
    process.exit(main(process.argv.slice(2)));
  } catch (e) {
    if (e instanceof GateError) {
      console.error(
        "Contributor version gate COULD NOT RUN:\n\n  " + e.message
      );
      process.exit(2);
    }
    throw e;
  }
}

module.exports = {
  parseRegistry,
  resolveBase,
  parseDefinitions,
  findViolations,
  tokensAt,
  changedFilesSince,
  comparisonCommit,
  cmdtValue,
  GateError,
  FLOW_DIR
};
