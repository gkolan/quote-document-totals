const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..", "..");
function markdownFiles(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      return markdownFiles(fullPath);
    }
    return entry.name.endsWith(".md") ? [fullPath] : [];
  });
}

// Public checks must work in a clone without local specs or assistant setup.
const markdownRoots = ["docs", "bugs", "enhancements"];
const files = [
  path.join(root, "README.md"),
  path.join(root, "CONTRIBUTING.md"),
  path.join(root, "SECURITY.md"),
  path.join(root, ".github", "PULL_REQUEST_TEMPLATE.md"),
  ...markdownRoots.flatMap((directory) =>
    markdownFiles(path.join(root, directory))
  )
].filter(
  (file, index, allFiles) =>
    fs.existsSync(file) && allFiles.indexOf(file) === index
);

const failures = [];
const audienceLabels =
  /\b(persona|junior|business admin|developer-facing|developer audience|admin audience|developer-only|admin-only|who this is for|audience:)\b/giu;
const computerJargon =
  /\b(framework|renderer|snapshot|idempotent|resumable|registry|pipeline|adapter)\b/giu;
const markdownLink = /!?\[[^\]]*\]\(([^)]+)\)/gu;
const retiredReference =
  /\b(documentation-standards\.md|vendor-neutral-render-contract|row-generation-extensibility|quote-document-row-customizer-guide|quote-document-totals-creation-pipeline|quote-document-totals-row-by-row|quote-line-type-bundle-reporting-guide|product-family-summary-guide|charge-type-summary-guide|discount-summary-guide|bundle-detail-guide|group-family-detail-guide|family-billing-composite-guide|optional-products-guide|best-and-worst-case-showcase|review-artifacts|gkCPQDev|gkCpqDevHub|act\.gkolan|Q-00053)\b/giu;

for (const file of files) {
  const text = fs.readFileSync(file, "utf8");
  const relativeFile = path.relative(root, file).replaceAll("\\", "/");
  const plainText = text
    .replace(/```[\s\S]*?```/gu, "")
    .replace(/`[^`\n]+`/gu, "");

  for (const match of plainText.matchAll(audienceLabels)) {
    const line = plainText.slice(0, match.index).split("\n").length;
    failures.push(
      `${relativeFile}:${line}: remove audience label "${match[0]}"`
    );
  }

  for (const match of text.matchAll(retiredReference)) {
    const line = text.slice(0, match.index).split("\n").length;
    failures.push(
      `${relativeFile}:${line}: remove retired or org-specific reference "${match[0]}"`
    );
  }

  if (
    relativeFile === "README.md" ||
    relativeFile === "docs/README.md" ||
    relativeFile === "docs/how-quote-document-totals-works.md" ||
    relativeFile === "docs/use-cases.md" ||
    relativeFile.startsWith("docs/use-case/")
  ) {
    for (const match of plainText.matchAll(computerJargon)) {
      const line = plainText.slice(0, match.index).split("\n").length;
      failures.push(
        `${relativeFile}:${line}: replace computer jargon "${match[0]}" with plain Salesforce language`
      );
    }
  }

  for (const match of text.matchAll(markdownLink)) {
    let target = match[1].trim().replace(/^<|>$/gu, "");
    target = target.split(/\s+["']/u)[0].split("#")[0];
    if (!target || /^(https?:|mailto:|tel:|data:|app:)/u.test(target)) {
      continue;
    }

    const localPath = path.resolve(
      path.dirname(file),
      decodeURIComponent(target)
    );
    if (!fs.existsSync(localPath)) {
      const line = text.slice(0, match.index).split("\n").length;
      failures.push(`${relativeFile}:${line}: missing link target ${target}`);
    }
  }
}

const retiredPaths = [
  "docs/quote-document-totals-creation-pipeline",
  "docs/quote-document-totals-row-by-row"
];
for (const retiredPath of retiredPaths) {
  if (fs.existsSync(path.join(root, retiredPath))) {
    failures.push(
      `${retiredPath}: retired path must stay outside the repository`
    );
  }
}

function sourceFiles(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    if ([".git", ".agents", "node_modules"].includes(entry.name)) {
      return [];
    }
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      return sourceFiles(fullPath);
    }
    return /\.(apex|cls|js|sh|soql|xml)$/u.test(entry.name) ? [fullPath] : [];
  });
}

const documentationReference = /docs\/[A-Za-z0-9_./-]+\.md/gu;
const sourceOrgReference = /\b(gkCPQDev|gkCpqDevHub|act\.gkolan|Q-00053)\b/gu;
for (const file of [
  ...sourceFiles(path.join(root, "force-app")),
  ...sourceFiles(path.join(root, "scripts"))
]) {
  const text = fs.readFileSync(file, "utf8");
  const relativeFile = path.relative(root, file).replaceAll("\\", "/");
  for (const match of text.matchAll(documentationReference)) {
    if (!fs.existsSync(path.join(root, match[0]))) {
      const line = text.slice(0, match.index).split("\n").length;
      failures.push(
        `${relativeFile}:${line}: missing documentation reference ${match[0]}`
      );
    }
  }
  if (file !== __filename) {
    for (const match of text.matchAll(sourceOrgReference)) {
      const line = text.slice(0, match.index).split("\n").length;
      failures.push(
        `${relativeFile}:${line}: replace org-specific example ${match[0]}`
      );
    }
  }
}

if (failures.length > 0) {
  process.stderr.write(`${failures.join("\n")}\n`);
  process.exit(1);
}

process.stdout.write(
  `Checked ${files.length} current Markdown files, source references, retired paths, links, and plain language.\n`
);
