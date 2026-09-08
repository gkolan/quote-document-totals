const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const {
  differences,
  inventorySource,
  parseManifest,
  serializeManifest
} = require("./check-release-manifest");

function fixture(files) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "qdtd-manifest-"));
  for (const relative of files) {
    const file = path.join(root, relative);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, "fixture");
  }
  return root;
}

test("inventories deployable source identities and excludes TDX records", () => {
  const root = fixture([
    "main/default/classes/Keep.cls",
    "main/default/classes/Keep.cls-meta.xml",
    "main/default/customMetadata/Thing.KEEP.md-meta.xml",
    "main/default/customMetadata/Thing.TDX_001.md-meta.xml",
    "main/default/objects/Example__c/Example__c.object-meta.xml",
    "main/default/objects/Example__c/fields/Value__c.field-meta.xml",
    "main/default/objects/Example__c/listViews/All.listView-meta.xml",
    "main/default/reports/Folder.reportFolder-meta.xml",
    "main/default/reports/Folder/Current.report-meta.xml"
  ]);
  const inventory = inventorySource(root);
  assert.deepEqual([...inventory.get("ApexClass")], ["Keep"]);
  assert.deepEqual([...inventory.get("CustomMetadata")], ["Thing.KEEP"]);
  assert.deepEqual([...inventory.get("CustomField")], ["Example__c.Value__c"]);
  assert.deepEqual([...inventory.get("Report")].sort(), [
    "Folder/",
    "Folder/Current"
  ]);
});

test("parses exact manifest members and reports drift in both directions", () => {
  const actual = parseManifest(`
    <Package><types><members>Present</members><members
      >
      Extra
    </members><name
      >
      ApexClass
    </name></types></Package>`);
  const expected = new Map([["ApexClass", new Set(["Present", "Missing"])]]);
  assert.deepEqual(differences(expected, actual), {
    missing: ["ApexClass:Missing"],
    unexpected: ["ApexClass:Extra"]
  });
});

test("rejects duplicate type blocks", () => {
  assert.throws(
    () =>
      parseManifest(
        "<types><name>Flow</name></types><types><name>Flow</name></types>"
      ),
    /Duplicate type block/
  );
});

test("serializes a stable exact manifest", () => {
  const source = new Map([
    ["Flow", new Set(["Zulu", "Alpha"])],
    ["ApexClass", new Set(["Example"])]
  ]);
  const xml = serializeManifest(source, "67.0");
  assert.deepEqual(differences(source, parseManifest(xml)), {
    missing: [],
    unexpected: []
  });
  assert.ok(
    xml.indexOf("<name>ApexClass</name>") < xml.indexOf("<name>Flow</name>")
  );
  assert.ok(
    xml.indexOf("<members>Alpha</members>") <
      xml.indexOf("<members>Zulu</members>")
  );
  assert.match(xml, /<version>67\.0<\/version>/u);
});
