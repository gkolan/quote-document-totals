const { spawnSync } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

/** Resolve the Salesforce CLI without sending user-controlled arguments through a shell. */
function resolveSfInvocation(options = {}) {
  const platform = options.platform || process.platform;
  const environment = options.environment || process.env;
  const nodeExecutable = options.nodeExecutable || process.execPath;
  const exists = options.exists || fs.existsSync;

  if (environment.SF_BIN) {
    return { command: environment.SF_BIN, prefix: [] };
  }
  if (platform !== "win32") {
    return { command: "sf", prefix: [] };
  }

  const pathApi = path.win32;
  const directories = String(environment.PATH || "")
    .split(";")
    .filter(Boolean);
  for (const directory of directories) {
    if (!exists(pathApi.join(directory, "sf.cmd"))) continue;
    const candidates = [
      pathApi.join(directory, "run.js"),
      pathApi.resolve(directory, "..", "client", "bin", "run.js")
    ];
    const runner = candidates.find((candidate) => exists(candidate));
    if (runner) {
      return { command: nodeExecutable, prefix: [runner] };
    }
  }
  throw new Error(
    "Unable to resolve the Windows Salesforce CLI runner. Set SF_BIN to a directly executable CLI binary."
  );
}

function spawnSalesforce(argumentsList, options = {}) {
  const invocation = resolveSfInvocation(options.resolution);
  return spawnSync(
    invocation.command,
    [...invocation.prefix, ...argumentsList],
    {
      cwd: options.cwd || process.cwd(),
      encoding: "utf8",
      env: { ...process.env, SF_AUTOUPDATE_DISABLE: "true", ...options.env },
      maxBuffer: options.maxBuffer || 100 * 1024 * 1024
    }
  );
}

module.exports = { resolveSfInvocation, spawnSalesforce };
