"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const fixture = require("../../contracts/v2/fixtures/valid/mixed.json");
const {
  assertIgnoredOutput,
  orgCredentials,
  parseArguments,
  retrievePayload
} = require("./export-live-document");

test("requires identity-bound inputs and an ignored output directory", () => {
  assert.throws(() => parseArguments([]), /target-org/);
  assert.throws(
    () =>
      parseArguments([
        "--target-org",
        "org",
        "--quote-id",
        "bad",
        "--request-id",
        "request",
        "--fingerprint",
        "fingerprint"
      ]),
    /quote-id/
  );
  assert.throws(() => assertIgnoredOutput("docs/live"), /ignored artifacts/);
  assert.match(assertIgnoredOutput("artifacts/live"), /artifacts[\\/]live$/u);
});

test("reads an authenticated org session without returning CLI noise", () => {
  const credentials = orgCredentials("example", () => ({
    stdout: JSON.stringify({
      status: 0,
      result: {
        instanceUrl: "https://example.my.salesforce.com/",
        accessToken: "secret-token"
      }
    }),
    stderr: "warning"
  }));
  assert.deepEqual(credentials, {
    instanceUrl: "https://example.my.salesforce.com",
    accessToken: "secret-token"
  });
});

test("retrieves the exact endpoint with bearer and identity headers", async () => {
  let call;
  const payload = await retrievePayload(
    {
      targetOrg: "example",
      quoteId: "a0Q000000000001AAA",
      requestId: fixture.requestId,
      fingerprint: fixture.fingerprint
    },
    {
      spawn: () => ({
        stdout: JSON.stringify({
          status: 0,
          result: {
            instanceUrl: "https://example.my.salesforce.com",
            accessToken: "secret-token"
          }
        })
      }),
      fetch: async (url, options) => {
        call = { url, options };
        return {
          ok: true,
          status: 200,
          text: async () => JSON.stringify(fixture)
        };
      }
    }
  );
  assert.equal(payload.contractVersion, "2.0");
  assert.match(
    call.url,
    /\/services\/apexrest\/quote-document-totals\/v2\/quotes\//u
  );
  assert.equal(call.options.headers.Authorization, "Bearer secret-token");
  assert.equal(call.options.headers["X-QDTD-Request-Id"], fixture.requestId);
  assert.equal(call.options.headers["X-QDTD-Fingerprint"], fixture.fingerprint);
});

test("reports only a safe status and stable endpoint code on rejection", async () => {
  await assert.rejects(
    retrievePayload(
      {
        targetOrg: "example",
        quoteId: "a0Q000000000001AAA",
        requestId: "private-request",
        fingerprint: "private-fingerprint"
      },
      {
        spawn: () => ({
          stdout: JSON.stringify({
            status: 0,
            result: {
              instanceUrl: "https://example.my.salesforce.com",
              accessToken: "secret-token"
            }
          })
        }),
        fetch: async () => ({
          ok: false,
          status: 409,
          text: async () =>
            JSON.stringify({
              error: { code: "SNAPSHOT_MOVED", message: "safe" }
            })
        })
      }
    ),
    (error) => {
      assert.equal(
        error.message,
        "REST retrieval failed (409 SNAPSHOT_MOVED)."
      );
      assert.doesNotMatch(error.message, /private|secret/u);
      return true;
    }
  );
});

test("the default path resolves beneath artifacts", () => {
  const options = parseArguments([
    "--target-org",
    "example",
    "--quote-id",
    "a0Q000000000001AAA",
    "--request-id",
    fixture.requestId,
    "--fingerprint",
    fixture.fingerprint
  ]);
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "qdtd-live-"));
  try {
    assert.match(
      assertIgnoredOutput(options.outputDir, temporary),
      /artifacts[\\/]live-document$/u
    );
  } finally {
    fs.rmSync(temporary, { recursive: true, force: true });
  }
});
