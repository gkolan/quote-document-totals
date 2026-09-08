#!/usr/bin/env node

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const REQUIRED_RELEASE_PATHS = [
  "LICENSE",
  "CHANGELOG.md",
  "contracts/v2/quote-document-payload.schema.json",
  "contracts/v2/reference-html-capabilities.json",
  "docs/access-model.md",
  "docs/document-integration-contract.md",
  "README.md",
  "SECURITY.md",
  "SUPPORT.md",
  "docs/install-upgrade-removal.md",
  "docs/subscriber-configuration.md",
  "force-app/main/default/classes/QuoteDocumentPayload.cls",
  "force-app/main/default/classes/QuoteDocumentSubscriberFields.cls",
  "force-app/main/default/objects/Quote_Document_Watched_Field__mdt/Quote_Document_Watched_Field__mdt.object-meta.xml",
  "install-prerequisites.json",
  "manifest/package.xml",
  "package.json",
  "scripts/qdtd/subscriber-config-snapshot.js",
  "sfdx-project.json"
];
const TEST_METADATA_MARKER = "TDX_";
const TEST_METADATA_EXCLUDE =
  ":(exclude)force-app/main/default/customMetadata/*TDX_*";

function parseArguments(argv) {
  const options = { outputDir: "artifacts/releases" };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const value = argv[++index];
    if (value === undefined) throw new Error(`${argument} requires a value.`);
    if (argument === "--tag") options.tag = value;
    else if (argument === "--output-dir") options.outputDir = value;
    else throw new Error(`Unknown argument: ${argument}`);
  }
  if (!options.tag) throw new Error("--tag is required.");
  return options;
}

function runGit(argumentsList, options = {}) {
  const result = spawnSync("git", argumentsList, {
    cwd: options.cwd || process.cwd(),
    encoding: "utf8",
    maxBuffer: 100 * 1024 * 1024
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(
      `git ${argumentsList[0]} failed: ${(result.stderr || result.stdout).trim()}`
    );
  }
  return result.stdout;
}

function releaseVersion(tag, packageVersion) {
  const tagVersion = tag.startsWith("v") ? tag.slice(1) : tag;
  if (tagVersion !== packageVersion) {
    throw new Error(
      `Tag ${tag} does not match package.json version ${packageVersion}.`
    );
  }
  return packageVersion;
}

function verifyReleasePaths(paths) {
  const available = new Set(paths);
  const missing = REQUIRED_RELEASE_PATHS.filter((name) => !available.has(name));
  if (missing.length > 0) {
    throw new Error(
      `Release tag is missing required files: ${missing.join(", ")}`
    );
  }
}

function payloadContract(source) {
  const match = source.match(/CONTRACT_VERSION\s*=\s*'([^']+)'/);
  if (!match) throw new Error("Payload contract version was not found.");
  return match[1];
}

function rendererContract(payloadVersion, rendererSchema, capabilities) {
  const schemaVersion = rendererSchema.properties?.contractVersion?.const;
  if (schemaVersion !== payloadVersion) {
    throw new Error(
      `Apex payload contract ${payloadVersion} does not match renderer schema ${schemaVersion || "(missing)"}.`
    );
  }
  if (!capabilities.contractVersions?.includes(payloadVersion)) {
    throw new Error(
      `Reference renderer does not declare payload contract ${payloadVersion}.`
    );
  }
  if (!capabilities.renderer?.version) {
    throw new Error("Reference renderer version is missing.");
  }
  return {
    contractVersion: schemaVersion,
    referenceRendererVersion: capabilities.renderer.version
  };
}

function sha256(filePath) {
  return crypto
    .createHash("sha256")
    .update(fs.readFileSync(filePath))
    .digest("hex");
}

function createManifest(input) {
  return {
    schemaVersion: "1.0",
    distribution: "versioned-source-archive",
    tag: input.tag,
    commit: input.commit,
    releaseVersion: input.releaseVersion,
    salesforceApiVersion: input.salesforceApiVersion,
    payloadContractVersion: input.payloadContractVersion,
    rendererContract: {
      schema: "contracts/v2/quote-document-payload.schema.json",
      contractVersion: input.rendererContractVersion,
      referenceRendererVersion: input.referenceRendererVersion
    },
    archive: {
      file: input.archiveFile,
      sha256: input.archiveSha256
    },
    layers: {
      productionSource: "force-app",
      excludedTestMetadataRecords: input.excludedTestMetadataRecords,
      excludedPathspecs: [TEST_METADATA_EXCLUDE]
    },
    validation: {
      required: true,
      evidenceBundled: false,
      note: "Attach the protected Salesforce validation artifact and job ID to the hosted release."
    }
  };
}

function buildRelease(options, git = runGit) {
  const tag = options.tag;
  const commit = git(["rev-parse", `${tag}^{commit}`]).trim();
  const paths = git(["ls-tree", "-r", "--name-only", tag])
    .split(/\r?\n/)
    .filter(Boolean);
  verifyReleasePaths(paths);
  const excludedTestMetadataRecords = paths.filter(
    (name) =>
      name.startsWith("force-app/main/default/customMetadata/") &&
      name.includes(TEST_METADATA_MARKER)
  ).length;

  const packageMetadata = JSON.parse(git(["show", `${tag}:package.json`]));
  const project = JSON.parse(git(["show", `${tag}:sfdx-project.json`]));
  const contract = payloadContract(
    git([
      "show",
      `${tag}:force-app/main/default/classes/QuoteDocumentPayload.cls`
    ])
  );
  const rendererSchema = JSON.parse(
    git(["show", `${tag}:contracts/v2/quote-document-payload.schema.json`])
  );
  const rendererCapabilities = JSON.parse(
    git(["show", `${tag}:contracts/v2/reference-html-capabilities.json`])
  );
  const renderer = rendererContract(
    contract,
    rendererSchema,
    rendererCapabilities
  );
  const version = releaseVersion(tag, packageMetadata.version);
  fs.mkdirSync(options.outputDir, { recursive: true });
  const archiveFile = `quote-document-totals-${version}.zip`;
  const archivePath = path.join(options.outputDir, archiveFile);
  git([
    "archive",
    "--format=zip",
    `--prefix=quote-document-totals-${version}/`,
    `--output=${path.resolve(archivePath)}`,
    tag,
    "--",
    ".",
    TEST_METADATA_EXCLUDE
  ]);
  const manifest = createManifest({
    tag,
    commit,
    releaseVersion: version,
    salesforceApiVersion: project.sourceApiVersion,
    payloadContractVersion: contract,
    rendererContractVersion: renderer.contractVersion,
    referenceRendererVersion: renderer.referenceRendererVersion,
    archiveFile,
    archiveSha256: sha256(archivePath),
    excludedTestMetadataRecords
  });
  const manifestPath = path.join(
    options.outputDir,
    "source-release-manifest.json"
  );
  fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  return manifest;
}

function main() {
  const report = buildRelease(parseArguments(process.argv.slice(2)));
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
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
  REQUIRED_RELEASE_PATHS,
  TEST_METADATA_EXCLUDE,
  buildRelease,
  createManifest,
  parseArguments,
  payloadContract,
  rendererContract,
  releaseVersion,
  verifyReleasePaths
};
