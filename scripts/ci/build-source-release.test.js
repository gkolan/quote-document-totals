const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const {
  REQUIRED_RELEASE_PATHS,
  TEST_METADATA_EXCLUDE,
  buildRelease,
  createManifest,
  parseArguments,
  payloadContract,
  rendererContract,
  releaseVersion,
  verifyReleasePaths
} = require("./build-source-release");

test("requires an explicit immutable tag", () => {
  assert.throws(() => parseArguments([]), /--tag is required/);
  assert.deepEqual(
    parseArguments(["--tag", "v1.2.3", "--output-dir", "release"]),
    { tag: "v1.2.3", outputDir: "release" }
  );
});

test("requires the tag to match the repository release version", () => {
  assert.equal(releaseVersion("v1.2.3", "1.2.3"), "1.2.3");
  assert.equal(releaseVersion("1.2.3", "1.2.3"), "1.2.3");
  assert.throws(() => releaseVersion("v2.0.0", "1.2.3"), /does not match/);
});

test("requires governance and installation files in the tagged tree", () => {
  assert.doesNotThrow(() => verifyReleasePaths(REQUIRED_RELEASE_PATHS));
  assert.throws(
    () =>
      verifyReleasePaths(
        REQUIRED_RELEASE_PATHS.filter((name) => name !== "LICENSE")
      ),
    /LICENSE/
  );
});

test("extracts the payload contract from tagged Apex", () => {
  assert.equal(
    payloadContract("public static final String CONTRACT_VERSION = '2.0';"),
    "2.0"
  );
  assert.throws(() => payloadContract("public class Payload {}"), /not found/);
});

test("requires Apex, schema, and renderer contract versions to agree", () => {
  assert.deepEqual(
    rendererContract(
      "2.0",
      { properties: { contractVersion: { const: "2.0" } } },
      { renderer: { version: "1.0.0" }, contractVersions: ["2.0"] }
    ),
    { contractVersion: "2.0", referenceRendererVersion: "1.0.0" }
  );
  assert.throws(
    () =>
      rendererContract(
        "2.0",
        { properties: { contractVersion: { const: "3.0" } } },
        { renderer: { version: "1.0.0" }, contractVersions: ["2.0"] }
      ),
    /does not match renderer schema/
  );
  assert.throws(
    () =>
      rendererContract(
        "2.0",
        { properties: { contractVersion: { const: "2.0" } } },
        { renderer: { version: "1.0.0" }, contractVersions: ["1.0"] }
      ),
    /does not declare payload contract/
  );
});

test("creates a machine-readable checksum and validation contract", () => {
  const manifest = createManifest({
    tag: "v1.2.3",
    commit: "abc123",
    releaseVersion: "1.2.3",
    salesforceApiVersion: "67.0",
    payloadContractVersion: "2.0",
    rendererContractVersion: "2.0",
    referenceRendererVersion: "1.0.0",
    archiveFile: "quote-document-totals-1.2.3.zip",
    archiveSha256: "deadbeef",
    excludedTestMetadataRecords: 194
  });
  assert.equal(manifest.commit, "abc123");
  assert.equal(manifest.archive.sha256, "deadbeef");
  assert.equal(manifest.validation.required, true);
  assert.equal(manifest.validation.evidenceBundled, false);
  assert.equal(manifest.rendererContract.contractVersion, "2.0");
  assert.equal(manifest.rendererContract.referenceRendererVersion, "1.0.0");
  assert.equal(manifest.layers.excludedTestMetadataRecords, 194);
  assert.deepEqual(manifest.layers.excludedPathspecs, [TEST_METADATA_EXCLUDE]);
});

test("builds the archive from tagged content and writes its checksum manifest", () => {
  const outputDir = fs.mkdtempSync(path.join(os.tmpdir(), "qdt-release-"));
  const calls = [];
  const git = (argumentsList) => {
    calls.push(argumentsList);
    if (argumentsList[0] === "rev-parse") return "abc123\n";
    if (argumentsList[0] === "ls-tree") {
      return `${REQUIRED_RELEASE_PATHS.join("\n")}\nforce-app/main/default/customMetadata/Quote_Document_Table_Def.TDX_001.md-meta.xml\n`;
    }
    if (
      argumentsList[0] === "show" &&
      argumentsList[1].endsWith("package.json")
    ) {
      return JSON.stringify({ version: "1.2.3" });
    }
    if (
      argumentsList[0] === "show" &&
      argumentsList[1].endsWith("sfdx-project.json")
    ) {
      return JSON.stringify({ sourceApiVersion: "67.0" });
    }
    if (
      argumentsList[0] === "show" &&
      argumentsList[1].endsWith("quote-document-payload.schema.json")
    ) {
      return JSON.stringify({
        properties: { contractVersion: { const: "2.0" } }
      });
    }
    if (
      argumentsList[0] === "show" &&
      argumentsList[1].endsWith("reference-html-capabilities.json")
    ) {
      return JSON.stringify({
        renderer: { version: "1.0.0" },
        contractVersions: ["2.0"]
      });
    }
    if (argumentsList[0] === "show") {
      return "public static final String CONTRACT_VERSION = '2.0';";
    }
    if (argumentsList[0] === "archive") {
      const output = argumentsList.find((value) =>
        value.startsWith("--output=")
      );
      fs.writeFileSync(output.slice("--output=".length), "tagged archive");
      return "";
    }
    throw new Error(`Unexpected git call: ${argumentsList.join(" ")}`);
  };

  try {
    const manifest = buildRelease({ tag: "v1.2.3", outputDir }, git);
    assert.equal(manifest.commit, "abc123");
    assert.match(manifest.archive.sha256, /^[a-f0-9]{64}$/);
    assert.equal(
      fs.existsSync(path.join(outputDir, "quote-document-totals-1.2.3.zip")),
      true
    );
    assert.equal(
      fs.existsSync(path.join(outputDir, "source-release-manifest.json")),
      true
    );
    assert.equal(calls.at(-1)[0], "archive");
    assert.equal(calls.at(-1).includes(TEST_METADATA_EXCLUDE), true);
    assert.equal(manifest.layers.excludedTestMetadataRecords, 1);
    assert.equal(manifest.rendererContract.contractVersion, "2.0");
  } finally {
    fs.rmSync(outputDir, { recursive: true, force: true });
  }
});
