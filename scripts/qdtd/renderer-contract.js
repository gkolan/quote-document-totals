"use strict";

const fs = require("node:fs");
const path = require("node:path");

function resolveRef(root, reference) {
  if (!reference.startsWith("#/")) {
    throw new Error(`Only local schema references are supported: ${reference}`);
  }
  return reference
    .slice(2)
    .split("/")
    .reduce(
      (value, token) =>
        value[token.replaceAll("~1", "/").replaceAll("~0", "~")],
      root
    );
}

function typeMatches(value, type) {
  if (type === "null") return value === null;
  if (type === "array") return Array.isArray(value);
  if (type === "object")
    return value !== null && typeof value === "object" && !Array.isArray(value);
  if (type === "integer") return Number.isInteger(value);
  return typeof value === type;
}

function validateSchema(value, schema, root = schema, location = "$") {
  if (schema.$ref)
    return validateSchema(value, resolveRef(root, schema.$ref), root, location);
  const errors = [];
  const allowedTypes = schema.type == null ? [] : [].concat(schema.type);
  if (
    allowedTypes.length &&
    !allowedTypes.some((type) => typeMatches(value, type))
  ) {
    return [`${location}: expected ${allowedTypes.join(" or ")}`];
  }
  if (Object.hasOwn(schema, "const") && value !== schema.const) {
    errors.push(
      `${location}: expected constant ${JSON.stringify(schema.const)}`
    );
  }
  if (schema.enum && !schema.enum.some((candidate) => candidate === value)) {
    errors.push(`${location}: value is not in the allowed set`);
  }
  if (typeof value === "string") {
    if (schema.minLength != null && value.length < schema.minLength)
      errors.push(`${location}: string is too short`);
    if (schema.maxLength != null && value.length > schema.maxLength)
      errors.push(`${location}: string is too long`);
    if (schema.pattern && !new RegExp(schema.pattern).test(value))
      errors.push(`${location}: string does not match ${schema.pattern}`);
    if (schema.format === "date-time" && Number.isNaN(Date.parse(value)))
      errors.push(`${location}: invalid date-time`);
  }
  if (
    typeof value === "number" &&
    schema.minimum != null &&
    value < schema.minimum
  ) {
    errors.push(`${location}: value is below ${schema.minimum}`);
  }
  if (Array.isArray(value)) {
    if (schema.minItems != null && value.length < schema.minItems)
      errors.push(`${location}: array has too few items`);
    if (schema.items)
      value.forEach((item, index) =>
        errors.push(
          ...validateSchema(item, schema.items, root, `${location}[${index}]`)
        )
      );
  }
  if (value !== null && typeof value === "object" && !Array.isArray(value)) {
    for (const name of schema.required || []) {
      if (!Object.hasOwn(value, name))
        errors.push(`${location}.${name}: required property is missing`);
    }
    for (const [name, child] of Object.entries(value)) {
      if (schema.properties && Object.hasOwn(schema.properties, name)) {
        errors.push(
          ...validateSchema(
            child,
            schema.properties[name],
            root,
            `${location}.${name}`
          )
        );
      } else if (schema.additionalProperties === false) {
        errors.push(`${location}.${name}: additional property is not allowed`);
      } else if (
        schema.additionalProperties &&
        typeof schema.additionalProperties === "object"
      ) {
        errors.push(
          ...validateSchema(
            child,
            schema.additionalProperties,
            root,
            `${location}.${name}`
          )
        );
      }
    }
  }
  return errors;
}

function validateTypedValue(value, type, location) {
  if (value === null) return [];
  if (["Number", "Currency"].includes(type) && typeof value !== "number")
    return [`${location}: ${type} requires a JSON number or null`];
  if (type === "Boolean" && typeof value !== "boolean")
    return [`${location}: Boolean requires true, false, or null`];
  if (
    type === "Date" &&
    (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value))
  )
    return [`${location}: Date requires YYYY-MM-DD or null`];
  if (
    type === "DateTime" &&
    (typeof value !== "string" || Number.isNaN(Date.parse(value)))
  )
    return [`${location}: DateTime requires an ISO date-time or null`];
  if (["Text", "Address"].includes(type) && typeof value !== "string")
    return [`${location}: ${type} requires a string or null`];
  return [];
}

function validateSemantics(payload, expectations = {}) {
  const errors = [];
  if (expectations.requestId && payload.requestId !== expectations.requestId)
    errors.push("$.requestId: does not match the expected generation request");
  if (
    expectations.fingerprint &&
    payload.fingerprint !== expectations.fingerprint
  )
    errors.push(
      "$.fingerprint: does not match the expected snapshot fingerprint"
    );
  const keys = new Set();
  let priorOrder = -Infinity;
  for (const [sectionIndex, section] of (payload.sections || []).entries()) {
    const where = `$.sections[${sectionIndex}]`;
    if (keys.has(section.key))
      errors.push(`${where}.key: duplicate section key`);
    keys.add(section.key);
    if (section.displayOrder < priorOrder)
      errors.push(`${where}.displayOrder: sections are not ordered`);
    priorOrder = section.displayOrder;
    if (section.sectionType === "Block") {
      if (!section.blockType || typeof section.body !== "string")
        errors.push(`${where}: Block requires blockType and body`);
      if (section.columns || section.rows)
        errors.push(`${where}: Block must not contain table rows or columns`);
      continue;
    }
    if (!Array.isArray(section.columns) || !Array.isArray(section.rows)) {
      errors.push(`${where}: Table requires columns and rows`);
      continue;
    }
    const columns = new Map(
      section.columns.map((column) => [column.code, column])
    );
    if (columns.size !== section.columns.length)
      errors.push(`${where}.columns: column codes must be unique`);
    let priorColumnOrder = -Infinity;
    for (const [columnIndex, column] of section.columns.entries()) {
      if (column.displayOrder < priorColumnOrder)
        errors.push(
          `${where}.columns[${columnIndex}].displayOrder: columns are not ordered`
        );
      priorColumnOrder = column.displayOrder;
    }
    let priorRowOrder = -Infinity;
    for (const [rowIndex, row] of section.rows.entries()) {
      const rowWhere = `${where}.rows[${rowIndex}]`;
      if (row.displayOrder < priorRowOrder)
        errors.push(`${rowWhere}.displayOrder: rows are not ordered`);
      priorRowOrder = row.displayOrder;
      for (const [code, value] of Object.entries(row.values || {})) {
        const column = columns.get(code);
        if (!column)
          errors.push(`${rowWhere}.values.${code}: no matching column`);
        else
          errors.push(
            ...validateTypedValue(
              value,
              column.dataType,
              `${rowWhere}.values.${code}`
            )
          );
      }
      for (const code of columns.keys()) {
        if (!Object.hasOwn(row.values || {}, code))
          errors.push(`${rowWhere}.values.${code}: column value is missing`);
      }
    }
  }
  for (const [index, fact] of (payload.facts || []).entries()) {
    errors.push(
      ...validateTypedValue(
        fact.value,
        fact.dataType,
        `$.facts[${index}].value`
      )
    );
    if (
      fact.dataType === "Currency" &&
      !fact.currencyIsoCode &&
      !payload.currencyIsoCode
    )
      errors.push(`$.facts[${index}]: Currency requires a currency code`);
  }
  return errors;
}

function validatePayload(payload, schema, expectations) {
  return [
    ...validateSchema(payload, schema),
    ...validateSemantics(payload, expectations)
  ];
}

function validateExpectedValues(payload, specification) {
  const errors = [];
  for (const check of specification.checks || []) {
    const section = (payload.sections || []).find(
      (item) => item.code === check.sectionCode
    );
    const row = section?.rows?.find((item) => item.key === check.rowKey);
    const actual = row?.values?.[check.columnCode];
    if (!Object.is(actual, check.expectedValue)) {
      errors.push(
        `${check.sectionCode}/${check.rowKey}/${check.columnCode}: expected ${JSON.stringify(check.expectedValue)}, received ${JSON.stringify(actual)}`
      );
    }
  }
  return errors;
}

function loadJson(file) {
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function validateFixtureDirectory(rootDir = path.resolve("contracts/v2")) {
  const schema = loadJson(
    path.join(rootDir, "quote-document-payload.schema.json")
  );
  const validDir = path.join(rootDir, "fixtures", "valid");
  const invalidDir = path.join(rootDir, "fixtures", "invalid");
  const outcomes = [];
  for (const file of fs
    .readdirSync(validDir)
    .filter((name) => name.endsWith(".json"))
    .sort()) {
    const errors = validatePayload(loadJson(path.join(validDir, file)), schema);
    outcomes.push({ file: `valid/${file}`, expected: "valid", errors });
  }
  for (const file of fs
    .readdirSync(invalidDir)
    .filter((name) => name.endsWith(".json"))
    .sort()) {
    const errors = validatePayload(
      loadJson(path.join(invalidDir, file)),
      schema
    );
    outcomes.push({ file: `invalid/${file}`, expected: "invalid", errors });
  }
  const expectationsDir = path.join(rootDir, "fixtures", "expectations");
  for (const file of fs
    .readdirSync(expectationsDir)
    .filter((name) => name.endsWith(".json"))
    .sort()) {
    const specification = loadJson(path.join(expectationsDir, file));
    const payload = loadJson(
      path.resolve(expectationsDir, specification.fixture)
    );
    outcomes.push({
      file: `expectations/${file}`,
      expected: "valid",
      errors: validateExpectedValues(payload, specification)
    });
  }
  return outcomes;
}

if (require.main === module) {
  const outcomes = validateFixtureDirectory(
    process.argv[2] && path.resolve(process.argv[2])
  );
  const failures = outcomes.filter(
    (item) => (item.expected === "valid") !== (item.errors.length === 0)
  );
  for (const item of outcomes)
    process.stdout.write(
      `${item.expected === "valid" ? "VALID" : "INVALID"} ${item.file}: ${item.errors.length} error(s)\n`
    );
  if (failures.length) {
    for (const item of failures)
      process.stderr.write(`${item.file}: ${item.errors.join("; ")}\n`);
    process.exitCode = 1;
  }
}

module.exports = {
  validateSchema,
  validateSemantics,
  validatePayload,
  validateExpectedValues,
  validateFixtureDirectory
};
