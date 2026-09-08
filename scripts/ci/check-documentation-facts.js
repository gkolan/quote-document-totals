const fs = require("node:fs");
const path = require("node:path");

const root = path.resolve(__dirname, "..", "..");
const failures = [];

function read(relativePath) {
  const fullPath = path.join(root, relativePath);
  if (!fs.existsSync(fullPath)) {
    failures.push(`${relativePath}: required current file is missing`);
    return "";
  }
  return fs.readFileSync(fullPath, "utf8");
}

const tableGuides = [
  [
    "docs/use-case/01-product-family-summary.md",
    "PRODUCT_FAMILY_SUMMARY",
    true
  ],
  ["docs/use-case/02-charge-type-summary.md", "CHARGE_TYPE_SUMMARY", true],
  ["docs/use-case/03-discount-summary.md", "DISCOUNT_SUMMARY", true],
  ["docs/use-case/04-bundle-detail.md", "BUNDLE_DETAIL", true],
  [
    "docs/use-case/05-quote-group-family-detail.md",
    "GROUP_FAMILY_DETAIL",
    true
  ],
  [
    "docs/use-case/06-family-billing-frequency-summary.md",
    "FAMILY_BILLING_COMPOSITE",
    true
  ],
  ["docs/use-case/07-optional-products.md", "OPTIONAL_PRODUCTS", true],
  [
    "docs/use-case/08-monthly-subscription-breakdown.md",
    "MONTHLY_SUBSCRIPTION_SUMMARY",
    false
  ],
  ["docs/use-case/09-multi-year-schedule.md", "ANNUAL_SCHEDULE", false],
  [
    "docs/use-case/20-transaction-change-summary.md",
    "TRANSACTION_SUMMARY",
    false
  ],
  ["docs/use-case/21-product-change-summary.md", "PRODUCT_SUMMARY", false],
  ["docs/use-case/22-bundle-change-summary.md", "BUNDLE_SUMMARY", false],
  [
    "docs/use-case/23-bundle-product-change-detail.md",
    "BUNDLE_PRODUCT_GRID",
    false
  ],
  [
    "docs/use-case/42-flow-row-adjustment.md",
    "FLOW_CONTRIBUTOR_EXAMPLE",
    false
  ],
  [
    "docs/use-case/43-registered-apex-row-adjustment.md",
    "DISCOUNT_EXAMPLE",
    false
  ]
];

for (const [guidePath, code, expectedActive] of tableGuides) {
  const metadataPath = `force-app/main/default/customMetadata/Quote_Document_Table_Def.${code}.md-meta.xml`;
  const metadata = read(metadataPath);
  const activeMatch = metadata.match(
    /<field>Is_Active__c<\/field>\s*<value[^>]*>(true|false)<\/value>/u
  );
  if (!activeMatch) {
    failures.push(`${metadataPath}: Is_Active__c value is missing`);
    continue;
  }
  const actualActive = activeMatch[1] === "true";
  if (actualActive !== expectedActive) {
    failures.push(
      `${metadataPath}: expected Is_Active__c=${expectedActive} for the documented status`
    );
  }

  const guide = read(guidePath);
  const status = expectedActive ? "active" : "inactive";
  const statusBeforeCode = guide.includes(`${status} \`${code}\``);
  const statusAfterCode = new RegExp(
    `\\x60${code}\\x60[^.\\n]{0,80}\\b${status}\\b`,
    "u"
  ).test(guide);
  if (!statusBeforeCode && !statusAfterCode) {
    failures.push(
      `${guidePath}: repository status must identify \`${code}\` as ${status}`
    );
  }
}

const blockGuide = read("docs/use-case/34-document-content-blocks.md");
const blockReadme = read("docs/use-case/README.md");
const blockMetadataFiles = [
  "Quote_Document_Content.Content_en_US_QUOTE_VALIDITY.md-meta.xml",
  "Quote_Document_Content.Content_en_US_SIGNATURE_INSTRUCTIONS.md-meta.xml",
  "Quote_Document_Content.Content_fr_QUOTE_VALIDITY.md-meta.xml",
  "Quote_Document_Content.Content_fr_SIGNATURE_INSTRUCTIONS.md-meta.xml"
];

function decodeXml(value) {
  return value
    .replaceAll("&amp;", "&")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&quot;", '"')
    .replaceAll("&apos;", "'");
}

function customMetadataValue(metadata, field) {
  const match = metadata.match(
    new RegExp(
      `<values>\\s*<field>${field}</field>\\s*<value[^>]*>([\\s\\S]*?)</value>\\s*</values>`,
      "u"
    )
  );
  return match ? decodeXml(match[1].trim()) : null;
}

for (const file of blockMetadataFiles) {
  const relativePath = `force-app/main/default/customMetadata/${file}`;
  const metadata = read(relativePath);
  for (const field of [
    "Block_Code__c",
    "Locale__c",
    "Block_Type__c",
    "Display_Order__c",
    "Heading__c",
    "Body__c",
    "Version__c"
  ]) {
    const value = customMetadataValue(metadata, field);
    if (value === null) {
      failures.push(`${relativePath}: ${field} value is missing`);
    } else if (!blockGuide.includes(value)) {
      failures.push(
        `docs/use-case/34-document-content-blocks.md: supplied Block value is missing: ${value}`
      );
    }
  }
}

for (const code of ["QUOTE_VALIDITY", "SIGNATURE_INSTRUCTIONS"]) {
  if (!blockReadme.includes(code)) {
    failures.push(
      `docs/use-case/README.md: supplied Block example is missing: ${code}`
    );
  }
}

const reportGuides = [
  [
    "docs/use-case/01-product-family-summary.md",
    "Quote Document - Product Family Summary"
  ],
  [
    "docs/use-case/02-charge-type-summary.md",
    "Quote Document - Charge Type Summary"
  ],
  ["docs/use-case/03-discount-summary.md", "Quote Document - Discount Summary"],
  ["docs/use-case/04-bundle-detail.md", "Quote Document - Bundle Detail"],
  [
    "docs/use-case/05-quote-group-family-detail.md",
    "Quote Document - Group and Family Detail"
  ],
  [
    "docs/use-case/06-family-billing-frequency-summary.md",
    "Quote Doc - Family & Billing Composite"
  ],
  [
    "docs/use-case/07-optional-products.md",
    "Quote Document - Optional Products"
  ],
  [
    "docs/use-case/20-transaction-change-summary.md",
    "Quote Document - Transaction Type Totals"
  ],
  [
    "docs/use-case/21-product-change-summary.md",
    "Quote Document - Product Totals"
  ],
  [
    "docs/use-case/22-bundle-change-summary.md",
    "Quote Document - Bundle Totals"
  ],
  [
    "docs/use-case/23-bundle-product-change-detail.md",
    "Quote Document - Bundle and Product Grid"
  ]
];

const reportDirectory = path.join(
  root,
  "force-app",
  "main",
  "default",
  "reports",
  "CPQ_Document_Totals"
);
const reportText = fs
  .readdirSync(reportDirectory)
  .filter((name) => name.endsWith(".report-meta.xml"))
  .map((name) => fs.readFileSync(path.join(reportDirectory, name), "utf8"))
  .join("\n")
  .replaceAll("&amp;", "&");

for (const [guidePath, reportName] of reportGuides) {
  if (!reportText.includes(`<name>${reportName}</name>`)) {
    failures.push(`reports: current report name is missing: ${reportName}`);
  }
  if (!read(guidePath).includes(`**${reportName}**`)) {
    failures.push(
      `${guidePath}: current report name is missing: ${reportName}`
    );
  }
}

const metadataTypes = fs
  .readdirSync(path.join(root, "force-app", "main", "default", "objects"), {
    withFileTypes: true
  })
  .filter((entry) => entry.isDirectory() && entry.name.endsWith("__mdt"));
if (metadataTypes.length !== 10) {
  failures.push(
    `force-app/main/default/objects: expected 10 Custom Metadata Types, found ${metadataTypes.length}`
  );
}
if (
  !read("docs/quote-document-totals-architecture-guide.md").includes(
    "ten Custom Metadata Types"
  )
) {
  failures.push(
    "docs/quote-document-totals-architecture-guide.md: update the Custom Metadata Type count"
  );
}

const registry = read(
  "force-app/main/default/classes/QuoteDocumentRowCustomizerRegistry.cls"
);
const registeredCodes = [...registry.matchAll(/when\s+'[A-Z_]+'/gu)];
if (registeredCodes.length !== 6) {
  failures.push(
    `QuoteDocumentRowCustomizerRegistry.cls: expected 6 registered codes, found ${registeredCodes.length}`
  );
}
if (
  !read("docs/use-case/43-registered-apex-row-adjustment.md").includes(
    "six registered"
  )
) {
  failures.push(
    "docs/use-case/43-registered-apex-row-adjustment.md: update the registered-code count"
  );
}

const generateFlow = read(
  "force-app/main/default/flows/Generate_Quote_Document_Tables.flow-meta.xml"
);
const generateAction = read(
  "force-app/main/default/quickActions/SBQQ__Quote__c.Generate_Document_Tables.quickAction-meta.xml"
);
const generationGuide = read(
  "docs/use-case/37-generate-or-refresh-from-quote.md"
);
const generationPermissionSet = read(
  "force-app/main/default/permissionsets/CPQ_Document_Totals_Generator.permissionset-meta.xml"
);
const diagnosticsClass = read(
  "force-app/main/default/classes/QuoteDocumentConfigurationDiagnostics.cls"
);
const diagnosticsPermissionSet = read(
  "force-app/main/default/permissionsets/CPQ_Document_Totals_Admin.permissionset-meta.xml"
);
const diagnosticsGuide = read("docs/configuration-diagnostics.md");
const operationsLedger = read(
  "force-app/main/default/classes/QuoteDocumentOperationLedger.cls"
);
const invalidationJob = read(
  "force-app/main/default/classes/QuoteDocumentInvalidationJob.cls"
);
const operationsPermissionSet = read(
  "force-app/main/default/permissionsets/CPQ_Document_Totals_Operations.permissionset-meta.xml"
);
const operationsGuide = read("docs/operations-recovery.md");
const rendererSchema = read("contracts/v2/quote-document-payload.schema.json");
const rendererCapabilities = read(
  "contracts/v2/reference-html-capabilities.json"
);
const rendererGuide = read("docs/document-integration-contract.md");
const restResource = read(
  "force-app/main/default/classes/QuoteDocumentRestResource.cls"
);
const liveExporter = read("scripts/qdtd/export-live-document.js");
const subscriberFields = read(
  "force-app/main/default/classes/QuoteDocumentSubscriberFields.cls"
);
const subscriberMetadata = read(
  "force-app/main/default/objects/Quote_Document_Watched_Field__mdt/Quote_Document_Watched_Field__mdt.object-meta.xml"
);
const queryService = read(
  "force-app/main/default/classes/QuoteDocumentQuery.cls"
);
const fingerprintService = read(
  "force-app/main/default/classes/QuoteDocumentFingerprint.cls"
);
const stalenessService = read(
  "force-app/main/default/classes/QuoteDocumentStaleness.cls"
);
const subscriberGuide = read("docs/subscriber-configuration.md");
const subscriberSnapshot = read("scripts/qdtd/subscriber-config-snapshot.js");
const packageManifest = read("manifest/package.xml");
const capacityFixtures = read("scripts/qdtd/capacity-fixtures.js");
const capacityBenchmark = read("scripts/qdtd/capacity-benchmark.js");
const capacityGuide = read("docs/capacity-benchmark.md");
if (!generateFlow.includes("<status>Active</status>")) {
  failures.push(
    "Generate_Quote_Document_Tables.flow-meta.xml: expected Active status"
  );
}
if (
  !capacityFixtures.includes("[10, 100, 500, 1000]") ||
  !capacityFixtures.includes("outputMustRemainIgnored: true") ||
  !capacityBenchmark.includes("supportedEnvelopeEstablished: false") ||
  !capacityGuide.includes("10, 100, 500, and 1,000") ||
  !capacityGuide.includes("observedHeadroomAtLeast25Percent")
) {
  failures.push(
    "capacity benchmark: expected versioned tiers, ignored ID-bearing fixtures, sanitized measurements, and no unsupported envelope claim"
  );
}
if (!generateAction.includes("<label>Generate Document Tables</label>")) {
  failures.push(
    "SBQQ__Quote__c.Generate_Document_Tables.quickAction-meta.xml: current action label is missing"
  );
}
if (!generationGuide.includes("**Generate Document Tables**")) {
  failures.push(
    "docs/use-case/37-generate-or-refresh-from-quote.md: current action label is missing"
  );
}
if (
  !generationPermissionSet.includes(
    "<flow>Generate_Quote_Document_Tables</flow>"
  ) ||
  !generationPermissionSet.includes(
    "<apexClass>QuoteDocumentGenerator</apexClass>"
  ) ||
  !generationPermissionSet.includes("<name>RunFlow</name>")
) {
  failures.push(
    "CPQ_Document_Totals_Generator.permissionset-meta.xml: expected the exact Generate_Quote_Document_Tables Flow access plus QuoteDocumentGenerator class access and RunFlow"
  );
}
if (
  !subscriberFields.includes("SUBSCRIBER_PREFIX = 'SUB_'") ||
  !subscriberMetadata.includes("Quote Document Watched Field") ||
  !queryService.includes("QuoteDocumentSubscriberFields.quoteFieldPaths()") ||
  !fingerprintService.includes(
    "QuoteDocumentSubscriberFields.fingerprintParts"
  ) ||
  !stalenessService.includes(
    "watchedFields.addAll(QuoteDocumentSubscriberFields.quoteFieldPaths())"
  ) ||
  !subscriberGuide.includes("append-only") ||
  !subscriberGuide.includes("snapshot:subscriber-config") ||
  !subscriberGuide.includes("compare:subscriber-config") ||
  !subscriberSnapshot.includes("containsQuoteOrCustomerFieldValues: false") ||
  !subscriberSnapshot.includes("removalsAllowed: false")
) {
  failures.push(
    "subscriber configuration: expected validated SUB_ ownership, shared query/fingerprint/staleness, and a read-only upgrade comparison"
  );
}
if (
  !rendererSchema.includes('"contractVersion": { "const": "2.0" }') ||
  !rendererCapabilities.includes(
    '"name": "quote-document-totals-reference-html"'
  ) ||
  !rendererGuide.includes("--expected-request-id") ||
  !rendererGuide.includes("--expected-fingerprint") ||
  !restResource.includes(
    "@RestResource(urlMapping='/quote-document-totals/v2/quotes/*')"
  ) ||
  !restResource.includes("Cache-Control") ||
  !liveExporter.includes("assertIgnoredOutput") ||
  !rendererGuide.includes("npm run export:live-document")
) {
  failures.push(
    "renderer contract: expected strict v2 schema, identity-bound REST retrieval, ignored live export, and documented identity binding"
  );
}
if (
  !operationsLedger.includes("retryInvalidationFailures") ||
  !operationsLedger.includes("Safe_Message__c = INVALIDATION_REMEDIATION") ||
  !invalidationJob.includes("recordInvalidationFailures") ||
  !operationsPermissionSet.includes(
    "<object>Quote_Document_Run_Failure__c</object>"
  ) ||
  !operationsGuide.includes("Unresolved Failures")
) {
  failures.push(
    "operations recovery: expected durable sanitized invalidation failures, guarded retry, operator access, and recovery instructions"
  );
}
if (
  !diagnosticsClass.includes("@AuraEnabled(cacheable=true)") ||
  !diagnosticsClass.includes("public static Report inspect()") ||
  !diagnosticsPermissionSet.includes(
    "<apexClass>QuoteDocumentConfigurationDiagnostics</apexClass>"
  ) ||
  !diagnosticsGuide.includes("QDTD_CONFIGURATION_DIAGNOSTICS")
) {
  failures.push(
    "configuration diagnostics: expected the cacheable entry point, separate admin class access, and documented CLI marker"
  );
}

for (const metadataType of [
  "ApexClass",
  "ApexTrigger",
  "CustomField",
  "CustomMetadata",
  "CustomObject",
  "CustomTab",
  "Flow",
  "ListView",
  "PermissionSet",
  "QuickAction",
  "Report",
  "ReportType",
  "ValidationRule"
]) {
  if (!packageManifest.includes(`<name>${metadataType}</name>`)) {
    failures.push(`manifest/package.xml: missing ${metadataType}`);
  }
}
if (!packageManifest.includes("<version>67.0</version>")) {
  failures.push("manifest/package.xml: expected Salesforce API 67.0");
}

if (failures.length > 0) {
  process.stderr.write(`${failures.join("\n")}\n`);
  process.exit(1);
}

process.stdout.write(
  `Checked ${tableGuides.length} table statuses, ${reportGuides.length} report names, ${blockMetadataFiles.length} supplied Block examples, metadata types, registered adjustments, the Quote action, its execution permissions, configuration diagnostics, operations recovery, the renderer contract, and subscriber fields.\n`
);
