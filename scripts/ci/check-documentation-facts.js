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
if (metadataTypes.length !== 9) {
  failures.push(
    `force-app/main/default/objects: expected 9 Custom Metadata Types, found ${metadataTypes.length}`
  );
}
if (
  !read("docs/quote-document-totals-architecture-guide.md").includes(
    "nine Custom Metadata Types"
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
if (registeredCodes.length !== 7) {
  failures.push(
    `QuoteDocumentRowCustomizerRegistry.cls: expected 7 registered codes, found ${registeredCodes.length}`
  );
}
if (
  !read("docs/use-case/43-registered-apex-row-adjustment.md").includes(
    "seven registered"
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
if (!generateFlow.includes("<status>Active</status>")) {
  failures.push(
    "Generate_Quote_Document_Tables.flow-meta.xml: expected Active status"
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

if (failures.length > 0) {
  process.stderr.write(`${failures.join("\n")}\n`);
  process.exit(1);
}

process.stdout.write(
  `Checked ${tableGuides.length} table statuses, ${reportGuides.length} report names, ${blockMetadataFiles.length} supplied Block examples, metadata types, registered adjustments, and the Quote action.\n`
);
