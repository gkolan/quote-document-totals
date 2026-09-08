const test = require("node:test");
const assert = require("node:assert/strict");

const { extractCliJson, markerPayload } = require("./capacity-common");

test("extracts CLI JSON after a warning", () => {
  assert.equal(extractCliJson('warning\n{"status":0,"result":{}}').status, 0);
});

test("extracts the last benchmark marker without surrounding log data", () => {
  const output = JSON.stringify({
    status: 0,
    result: {
      logs: 'older\nUSER_DEBUG|QDTD_TEST {"tier":10,"quoteId":"001000000000001AAA"}\n'
    }
  });
  assert.equal(markerPayload(output, "QDTD_TEST").tier, 10);
});

test("rejects a successful command with no marker", () => {
  assert.throws(
    () => markerPayload('{"status":0,"result":{"logs":"none"}}', "QDTD_TEST"),
    /no QDTD_TEST marker/
  );
});
