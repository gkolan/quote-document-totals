#!/usr/bin/env node

"use strict";

const fs = require("node:fs");
const path = require("node:path");

const { spawnSalesforce } = require("../ci/sf-command");
const { extractCliJson } = require("./capacity-common");
const { renderValidated } = require("./render-reference-document");

const MAX_PAYLOAD_BYTES = 20 * 1024 * 1024;

function parseArguments(argv) {
  const options = { outputDir: "artifacts/live-document" };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const value = argv[++index];
    if (value === undefined) throw new Error(`${argument} requires a value.`);
    if (argument === "--target-org") options.targetOrg = value;
    else if (argument === "--quote-id") options.quoteId = value;
    else if (argument === "--request-id") options.requestId = value;
    else if (argument === "--fingerprint") options.fingerprint = value;
    else if (argument === "--output-dir") options.outputDir = value;
    else throw new Error(`Unknown argument: ${argument}`);
  }

  if (!options.targetOrg) throw new Error("--target-org is required.");
  if (!/^[a-zA-Z0-9]{15,18}$/u.test(options.quoteId || "")) {
    throw new Error("--quote-id must be a 15- or 18-character Salesforce Id.");
  }
  for (const name of ["requestId", "fingerprint"]) {
    const value = options[name];
    if (!value || value.length > 255 || /[\r\n]/u.test(value)) {
      throw new Error(
        `--${name === "requestId" ? "request-id" : name} must be a non-empty single-line value of at most 255 characters.`
      );
    }
  }
  assertIgnoredOutput(options.outputDir);
  return options;
}

function assertIgnoredOutput(outputDir, cwd = process.cwd()) {
  const artifactsRoot = path.resolve(cwd, "artifacts");
  const resolved = path.resolve(cwd, outputDir);
  if (
    resolved !== artifactsRoot &&
    !resolved.startsWith(`${artifactsRoot}${path.sep}`)
  ) {
    throw new Error(
      "--output-dir must be inside the ignored artifacts directory because live payloads can contain customer data and record Ids."
    );
  }
  return resolved;
}

function orgCredentials(targetOrg, spawn = spawnSalesforce) {
  const result = spawn(["org", "display", "--target-org", targetOrg, "--json"]);
  if (result.error) throw result.error;
  let payload;
  try {
    const output = String(result.stdout || "").includes("{")
      ? result.stdout
      : `${result.stdout || ""}\n${result.stderr || ""}`;
    payload = extractCliJson(output);
  } catch {
    throw new Error("Salesforce CLI could not describe the target org.");
  }
  const credentials = payload.result || {};
  if (
    payload.status !== 0 ||
    !/^https:\/\//u.test(credentials.instanceUrl || "") ||
    !credentials.accessToken
  ) {
    throw new Error("Salesforce CLI returned no usable target-org session.");
  }
  return {
    instanceUrl: credentials.instanceUrl.replace(/\/$/u, ""),
    accessToken: credentials.accessToken
  };
}

async function retrievePayload(options, dependencies = {}) {
  const credentials = orgCredentials(options.targetOrg, dependencies.spawn);
  const fetchImpl = dependencies.fetch || globalThis.fetch;
  if (typeof fetchImpl !== "function") {
    throw new Error("This command requires Node.js with the Fetch API.");
  }
  const url = `${credentials.instanceUrl}/services/apexrest/quote-document-totals/v2/quotes/${encodeURIComponent(options.quoteId)}`;
  const response = await fetchImpl(url, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${credentials.accessToken}`,
      Accept: "application/json",
      "X-QDTD-Request-Id": options.requestId,
      "X-QDTD-Fingerprint": options.fingerprint
    }
  });
  const body = await response.text();
  if (Buffer.byteLength(body) > MAX_PAYLOAD_BYTES) {
    throw new Error("REST retrieval exceeded the 20 MiB local safety limit.");
  }
  if (!response.ok) {
    let code = "HTTP_ERROR";
    try {
      const parsed = JSON.parse(body);
      const candidate = parsed?.error?.code;
      if (/^[A-Z][A-Z0-9_]{2,63}$/u.test(candidate || "")) code = candidate;
    } catch {
      // Salesforce platform errors do not necessarily use the endpoint envelope.
    }
    throw new Error(`REST retrieval failed (${response.status} ${code}).`);
  }
  try {
    return JSON.parse(body);
  } catch {
    throw new Error("REST retrieval returned invalid JSON.");
  }
}

async function exportLiveDocument(options, dependencies = {}) {
  const payload = await retrievePayload(options, dependencies);
  const schema = JSON.parse(
    fs.readFileSync(
      path.resolve("contracts/v2/quote-document-payload.schema.json"),
      "utf8"
    )
  );
  const rendered = renderValidated(payload, schema, {
    requestId: options.requestId,
    fingerprint: options.fingerprint
  });
  const outputDir = assertIgnoredOutput(options.outputDir);
  fs.mkdirSync(outputDir, { recursive: true });
  fs.writeFileSync(
    path.join(outputDir, "quote-document.payload.json"),
    `${JSON.stringify(payload, null, 2)}\n`
  );
  fs.writeFileSync(path.join(outputDir, "quote-document.html"), rendered.html);
  fs.writeFileSync(
    path.join(outputDir, "quote-document.manifest.json"),
    `${JSON.stringify(rendered.manifest, null, 2)}\n`
  );
  return { outputDir, manifest: rendered.manifest };
}

if (require.main === module) {
  exportLiveDocument(parseArguments(process.argv.slice(2)))
    .then(({ outputDir, manifest }) => {
      process.stdout.write(
        `Exported validated document to ${outputDir} (${manifest.output.sha256})\n`
      );
    })
    .catch((error) => {
      process.stderr.write(`${error.message}\n`);
      process.exitCode = 1;
    });
}

module.exports = {
  MAX_PAYLOAD_BYTES,
  assertIgnoredOutput,
  exportLiveDocument,
  orgCredentials,
  parseArguments,
  retrievePayload
};
