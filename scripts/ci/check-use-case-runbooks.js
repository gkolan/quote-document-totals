const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..", "..");
const guideDir = path.join(root, "docs", "use-case");
const guidePattern = /^\d{2}-.*\.md$/;

const requiredHeadings = [
  "## Status and scope",
  "## Use case scenario",
  "## What this produces",
  "## Before you start",
  "## Terms in plain language",
  "## Configure in Salesforce",
  "## Worked example",
  "## Generate and verify",
  "## Troubleshooting",
  "## Deactivate or roll back",
  "## Production checklist"
];

const unresolvedInstructions = [
  /use the approved/iu,
  /enter the approved/iu,
  /choose the required/iu,
  /value required in the agreement/iu,
  /complete any additional/iu,
  /when a report exists/iu,
  /use the existing (?:record|grouping)/iu,
  /as appropriate/iu,
  /where applicable/iu
];

const files = fs
  .readdirSync(guideDir)
  .filter((name) => guidePattern.test(name))
  .sort();
const failures = [];

for (const file of files) {
  const text = fs.readFileSync(path.join(guideDir, file), "utf8");

  for (const heading of requiredHeadings) {
    if (!text.includes(heading)) {
      failures.push(`${file}: missing heading "${heading}"`);
    }
  }

  let previousHeadingPosition = -1;
  for (const heading of requiredHeadings) {
    const position = text.indexOf(heading);
    if (position >= 0 && position < previousHeadingPosition) {
      failures.push(`${file}: heading "${heading}" is out of runbook order`);
    }
    if (position >= 0) {
      previousHeadingPosition = position;
    }
  }

  for (const pattern of unresolvedInstructions) {
    if (pattern.test(text)) {
      failures.push(`${file}: unresolved instruction matches ${pattern}`);
    }
  }

  if (!/^\*\*Repository status:\*\*/mu.test(text)) {
    failures.push(`${file}: missing explicit repository status`);
  }
  if (!/^\*\*Org verification status:\*\*/mu.test(text)) {
    failures.push(`${file}: missing explicit org verification status`);
  }
  if (!text.includes("**Stop here if")) {
    failures.push(`${file}: missing a clear prerequisite stop condition`);
  }
  if (
    !/^\|\s*Problem\s*\|\s*What it means\s*\|\s*What to do\s*\|/mu.test(text)
  ) {
    failures.push(
      `${file}: troubleshooting must use Problem | What it means | What to do`
    );
  }
  if (!/^- \[ \]/mu.test(text)) {
    failures.push(`${file}: production checklist has no unchecked items`);
  }

  if (/^\*\*Availability:\*\*/mu.test(text)) {
    failures.push(
      `${file}: use Status and scope instead of a second Availability statement`
    );
  }

  // Only require table fields when the guide is creating a Table Definition.
  // Other Custom Metadata types, such as Document Content, also use New.
  if (
    /Quote Document Table Definition[\s\S]{0,800}(?:Create a new record|select \*\*New\*\*)/iu.test(
      text
    )
  ) {
    for (const field of [
      "Table Code",
      "Table Name",
      "Amount Basis",
      "Line Filter",
      "Measure Set",
      "Display Order"
    ]) {
      const fieldRow = new RegExp(`^\\s*\\|\\s*${field}\\s*\\|`, "mu");
      if (!fieldRow.test(text)) {
        failures.push(
          `${file}: new table instructions omit required field "${field}"`
        );
      }
    }
  }

  if (/^\s*\|\s*Expander Code\s*\|/mu.test(text)) {
    if (!/^\s*\|\s*Expander Version\s*\|/mu.test(text)) {
      failures.push(`${file}: expanded table omits Expander Version`);
    }
    if (!/^\s*\|\s*(?:Allocation Basis|Suppress Amounts)\s*\|/mu.test(text)) {
      failures.push(
        `${file}: expanded table must declare Allocation Basis or Suppress Amounts`
      );
    }
    if (!/^\s*\|\s*Show Section Totals\s*\|/mu.test(text)) {
      failures.push(`${file}: expanded table must clear Show Section Totals`);
    }
  }
}

const readme = fs.readFileSync(path.join(guideDir, "README.md"), "utf8");
const linkedGuideNumbers = [
  ...readme.matchAll(/\|\s*(\d+)\s*\|\s*\[[^\]]+\]\((\d{2}-[^)]+\.md)\)/gu)
];
const linkedFiles = new Set(linkedGuideNumbers.map((match) => match[2]));

for (const file of files) {
  if (!linkedFiles.has(file)) {
    failures.push(`README.md: missing guide link for ${file}`);
  }
}

if (
  !readme.includes(
    `This catalog contains ${files.length} self-contained Salesforce CPQ runbooks`
  )
) {
  failures.push(
    `README.md: opening count must say ${files.length} self-contained Salesforce CPQ runbooks`
  );
}

const catalogNumbers = [...readme.matchAll(/^\|\s*(\d{1,3})\s*\|/gmu)].map(
  (match) => Number(match[1])
);
const uniqueCatalogNumbers = new Set(catalogNumbers);

if (
  catalogNumbers.length !== uniqueCatalogNumbers.size ||
  catalogNumbers.some((value, index) => value !== index + 1)
) {
  failures.push(
    "README.md: catalog numbers must be unique and continuous from 1"
  );
}

const additionalPatternCount = catalogNumbers.length - files.length;
if (
  !readme.includes(`and ${additionalPatternCount} additional design patterns`)
) {
  failures.push(
    `README.md: opening count must say ${additionalPatternCount} additional design patterns`
  );
}

if (failures.length > 0) {
  process.stderr.write(`${failures.join("\n")}\n`);
  process.exitCode = 1;
} else {
  process.stdout.write(
    `Validated ${files.length} self-contained use-case runbooks.\n`
  );
}
