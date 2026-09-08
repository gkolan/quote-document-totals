const test = require("node:test");
const assert = require("node:assert/strict");

const {
  summarize,
  validateRoles,
  values
} = require("./check-permission-boundaries");

const role = ({
  className,
  flow = "",
  runFlow = false,
  mutable = false,
  tab = ""
}) => `
<PermissionSet>
  <classAccesses><apexClass>${className}</apexClass></classAccesses>
  ${flow ? `<flowAccesses><flow>${flow}</flow></flowAccesses>` : ""}
  ${runFlow ? "<userPermissions><name>RunFlow</name></userPermissions>" : ""}
  ${mutable ? "<fieldPermissions><editable>true</editable></fieldPermissions>" : ""}
  ${tab ? `<tabSettings><tab>${tab}</tab></tabSettings>` : ""}
</PermissionSet>`;

test("reads values independent of XML whitespace", () => {
  assert.deepEqual(values("<flow>\n  Example_Flow\n</flow>", "flow"), [
    "Example_Flow"
  ]);
});

test("summarizes entry paths and mutation grants", () => {
  const result = summarize(
    role({ className: "Entry", flow: "Flow", runFlow: true, mutable: true })
  );
  assert.deepEqual(result.classes, ["Entry"]);
  assert.deepEqual(result.flows, ["Flow"]);
  assert.equal(result.mutable, true);
});

test("accepts separated read-only roles", () => {
  const failures = validateRoles(
    {
      compatibility: `${role({ className: "QuoteDocumentGenerator", flow: "Generate_Quote_Document_Tables", runFlow: true })}<apexClass>QuoteDocumentJsonAdapter</apexClass><apexClass>QuoteDocumentRestResource</apexClass>`,
      generator: role({
        className: "QuoteDocumentGenerator",
        flow: "Generate_Quote_Document_Tables",
        runFlow: true
      }),
      retrieval: `${role({ className: "QuoteDocumentJsonAdapter" })}<apexClass>QuoteDocumentRestResource</apexClass>`
    },
    {
      tables: "<sharingModel>Private</sharingModel>",
      blocks: "<sharingModel>Private</sharingModel>",
      facts: "<sharingModel>Private</sharingModel>"
    }
  );
  assert.deepEqual(failures, []);
});

test("rejects retrieval generation, mutations, tabs, and public sharing", () => {
  const failures = validateRoles(
    {
      compatibility: `${role({ className: "QuoteDocumentGenerator", flow: "Generate_Quote_Document_Tables", runFlow: true })}<apexClass>QuoteDocumentJsonAdapter</apexClass><apexClass>QuoteDocumentRestResource</apexClass>`,
      generator: role({
        className: "QuoteDocumentGenerator",
        flow: "Generate_Quote_Document_Tables",
        runFlow: true
      }),
      retrieval: `${role({
        className: "QuoteDocumentJsonAdapter",
        flow: "Bad_Flow",
        runFlow: true,
        mutable: true,
        tab: "Quote_Document_Table__c"
      })}<apexClass>QuoteDocumentRestResource</apexClass>`
    },
    {
      tables: "<sharingModel>ReadWrite</sharingModel>",
      blocks: "<sharingModel>Private</sharingModel>",
      facts: "<sharingModel>Private</sharingModel>"
    }
  );
  assert.equal(failures.length, 3);
});
