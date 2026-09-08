const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const { spawnSalesforce } = require("../ci/sf-command");

function extractCliJson(output) {
  const start = output.indexOf("{");
  if (start < 0) throw new Error(`Salesforce CLI returned no JSON:\n${output}`);
  return JSON.parse(output.slice(start));
}

function markerPayload(output, marker) {
  const payload = extractCliJson(output);
  if (payload.status !== 0) {
    throw new Error(
      payload.message || payload.name || "Anonymous Apex failed."
    );
  }
  const logs = String(payload.result?.logs || payload.result?.output || "");
  const markerAt = logs.lastIndexOf(marker);
  if (markerAt < 0)
    throw new Error(`Anonymous Apex returned no ${marker} marker.`);
  const jsonAt = logs.indexOf("{", markerAt + marker.length);
  const lineEnd = logs.indexOf("\n", jsonAt);
  if (jsonAt < 0) throw new Error(`${marker} marker contains no JSON.`);
  return JSON.parse(
    logs.slice(jsonAt, lineEnd < 0 ? undefined : lineEnd).trim()
  );
}

function runAnonymous(targetOrg, source, marker, spawn = spawnSalesforce) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "qdtd-capacity-"));
  const sourcePath = path.join(directory, "run.apex");
  try {
    fs.writeFileSync(sourcePath, source);
    const result = spawn(
      [
        "apex",
        "run",
        "--target-org",
        targetOrg,
        "--file",
        sourcePath,
        "--json"
      ],
      { cwd: process.cwd(), maxBuffer: 20 * 1024 * 1024 }
    );
    if (result.error) throw result.error;
    const output = String(result.stdout || "").includes("{")
      ? result.stdout
      : `${result.stdout || ""}\n${result.stderr || ""}`;
    return markerPayload(output, marker);
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

module.exports = { extractCliJson, markerPayload, runAnonymous };
