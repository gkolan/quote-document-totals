"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { validatePayload } = require("./renderer-contract");

const RENDERER_NAME = "quote-document-totals-reference-html";
const RENDERER_VERSION = "1.0.0";

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function formatValue(value, dataType, locale, currency) {
  if (value == null) return "";
  if (dataType === "Currency") {
    return escapeHtml(
      new Intl.NumberFormat(locale, {
        style: "currency",
        currency,
        currencyDisplay: "code"
      }).format(value)
    );
  }
  if (dataType === "Number")
    return escapeHtml(new Intl.NumberFormat(locale).format(value));
  if (dataType === "Boolean") return value ? "Yes" : "No";
  return escapeHtml(value);
}

function renderBlock(block) {
  const heading = block.heading ? `<h2>${escapeHtml(block.heading)}</h2>` : "";
  return `<section class="document-block" data-code="${escapeHtml(block.code)}" data-type="${escapeHtml(block.blockType)}">${heading}<p>${escapeHtml(block.body)}</p></section>`;
}

function renderRowBlock(block, columnCount) {
  const heading = block.heading
    ? `<strong>${escapeHtml(block.heading)}</strong> `
    : "";
  return `<tr class="row-block" data-placement="${escapeHtml(block.placement)}"><td colspan="${columnCount}">${heading}${escapeHtml(block.body)}</td></tr>`;
}

function renderTable(section, payload) {
  const columns = section.columns;
  const head = columns
    .map(
      (column) =>
        `<th data-code="${escapeHtml(column.code)}">${escapeHtml(column.label)}</th>`
    )
    .join("");
  const rows = [];
  for (const row of section.rows) {
    for (const block of row.blocks.filter(
      (item) => item.placement === "Before Row"
    ))
      rows.push(renderRowBlock(block, columns.length));
    const cells = columns
      .map(
        (column) =>
          `<td data-code="${escapeHtml(column.code)}">${formatValue(row.values[column.code], column.dataType, section.locale || payload.locale, section.currencyIsoCode || payload.currencyIsoCode)}</td>`
      )
      .join("");
    rows.push(
      `<tr data-key="${escapeHtml(row.key)}" data-row-type="${escapeHtml(row.rowType)}">${cells}</tr>`
    );
    for (const block of row.blocks.filter(
      (item) => item.placement !== "Before Row"
    ))
      rows.push(renderRowBlock(block, columns.length));
  }
  const title = section.title ? `<h2>${escapeHtml(section.title)}</h2>` : "";
  return `<section class="document-table" data-code="${escapeHtml(section.code)}">${title}<table><thead><tr>${head}</tr></thead><tbody>${rows.join("")}</tbody></table></section>`;
}

function render(payload) {
  const facts = payload.facts.length
    ? `<dl>${payload.facts.map((fact) => `<dt>${escapeHtml(fact.label)}</dt><dd>${formatValue(fact.value, fact.dataType, payload.locale, fact.currencyIsoCode || payload.currencyIsoCode)}</dd>`).join("")}</dl>`
    : "";
  const sections = payload.sections
    .map((section) =>
      section.sectionType === "Block"
        ? renderBlock(section)
        : renderTable(section, payload)
    )
    .join("");
  return `<!doctype html><html lang="${escapeHtml(payload.locale)}"><head><meta charset="utf-8"><title>${escapeHtml(payload.quoteNumber)}</title></head><body><main data-contract-version="${escapeHtml(payload.contractVersion)}" data-request-id="${escapeHtml(payload.requestId)}" data-fingerprint="${escapeHtml(payload.fingerprint)}"><h1>Quote ${escapeHtml(payload.quoteNumber)}</h1>${facts}${sections}</main></body></html>`;
}

function sha256(content) {
  return crypto.createHash("sha256").update(content).digest("hex");
}

function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value !== null && typeof value === "object") {
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(",")}}`;
  }
  return JSON.stringify(value);
}

function createManifest(payload, html) {
  return {
    manifestVersion: "1.0",
    contractVersion: payload.contractVersion,
    quoteId: payload.quoteId,
    requestId: payload.requestId,
    fingerprint: payload.fingerprint,
    sourcePayloadSha256: sha256(canonicalJson(payload)),
    renderer: { name: RENDERER_NAME, version: RENDERER_VERSION },
    output: {
      mediaType: "text/html; charset=utf-8",
      bytes: Buffer.byteLength(html),
      sha256: sha256(html)
    }
  };
}

function renderValidated(payload, schema, expectations) {
  const errors = validatePayload(payload, schema, expectations);
  if (errors.length) throw new Error(`Payload rejected:\n${errors.join("\n")}`);
  const html = render(payload);
  return { html, manifest: createManifest(payload, html) };
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 2)
    args[argv[index]] = argv[index + 1];
  if (
    !args["--input"] ||
    !args["--output-dir"] ||
    !args["--expected-request-id"] ||
    !args["--expected-fingerprint"]
  ) {
    throw new Error(
      "Usage: node scripts/qdtd/render-reference-document.js --input payload.json --output-dir directory --expected-request-id id --expected-fingerprint fingerprint"
    );
  }
  return args;
}

if (require.main === module) {
  try {
    const args = parseArgs(process.argv.slice(2));
    const payload = JSON.parse(
      fs.readFileSync(path.resolve(args["--input"]), "utf8")
    );
    const schema = JSON.parse(
      fs.readFileSync(
        path.resolve("contracts/v2/quote-document-payload.schema.json"),
        "utf8"
      )
    );
    const result = renderValidated(payload, schema, {
      requestId: args["--expected-request-id"],
      fingerprint: args["--expected-fingerprint"]
    });
    const outputDir = path.resolve(args["--output-dir"]);
    fs.mkdirSync(outputDir, { recursive: true });
    fs.writeFileSync(path.join(outputDir, "quote-document.html"), result.html);
    fs.writeFileSync(
      path.join(outputDir, "quote-document.manifest.json"),
      `${JSON.stringify(result.manifest, null, 2)}\n`
    );
    process.stdout.write(
      `Rendered ${path.join(outputDir, "quote-document.html")} (${result.manifest.output.sha256})\n`
    );
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  }
}

module.exports = {
  canonicalJson,
  escapeHtml,
  formatValue,
  render,
  createManifest,
  renderValidated,
  parseArgs
};
