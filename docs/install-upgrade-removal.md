# Install, upgrade, and removal contract

Quote Document Totals currently supports a versioned source distribution. It does not publish an unlocked or managed package, installation URL, or package ID. A Git tag and its commit must identify the source used for an installation; do not install an unrecorded working tree in production.

## Version identities

Keep these values separate in release evidence:

| Identity           | Current source                                                                   | Meaning                                                                |
| ------------------ | -------------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| Repository release | `1.0.0` in `package.json`; no supported release tag is asserted by this document | Version of the source artifact and public instructions                 |
| Salesforce API     | `67.0` in `sfdx-project.json`                                                    | Metadata and Apex compilation API                                      |
| Payload contract   | `2.0` in `QuoteDocumentPayload.CONTRACT_VERSION`                                 | Shape consumed by a document integration                               |
| Output behavior    | Version fields on contributor Custom Metadata                                    | Whether existing generated output may be reused after behavior changes |
| Salesforce CPQ     | Measured per target by the install preflight                                     | External schema and pricing dependency                                 |

A release record must contain the tag, full commit SHA, all five identities, validation job ID, and validation artifact name. Changing one identity does not silently change the others.

After the owner has selected a license, the candidate passes protected validation, and the reviewed tag exists, build the immutable archive and checksum manifest with:

```bash
npm run build:source-release -- --tag v1.0.0 --output-dir artifacts/releases
```

The builder reads files from the tag rather than the working tree, requires the tag to match `package.json`'s version, requires the license and release-governance files, archives that tag with `git archive`, and records its SHA-256 checksum. It excludes inactive `TDX_*` permutation metadata used by the test harness and records the excluded count and path rule. It intentionally fails while the root license or release tag is absent.

The release manifest names every component currently present under `force-app/main/default`, including objects and fields, Custom Metadata, Flows, permission sets, reports, actions, list views, tabs, validation rules, Apex classes, and triggers. It omits the same test-only `TDX_*` records excluded from the tag-built archive. Exact members are intentional: Salesforce CLI source conversion does not expand a wildcard-only manifest into local deployable components.

## Preflight

Authenticate the intended sandbox, check out the exact release tag, and run:

```bash
npm run preflight:install -- --target-org qdt-test --output artifacts/install-preflight.json
```

The command reads the installed-package registry and describes the CPQ objects and fields declared in `install-prerequisites.json`. It uploads no repository source and changes no org data. It exits unsuccessfully when CPQ or a named compile-time dependency is missing. Keep the JSON with the installation evidence.

Preflight success is necessary but does not prove deployment, field-level access, record sharing, page configuration, or runtime behavior. Continue with the check-only deployment, actual deployment, permission assignment, and representative-user checks in the testing guide.

## Source installation

1. Record the selected tag and `git rev-parse HEAD`. Require a clean working tree.
2. Run local checks and the preflight against a CPQ sandbox.
3. Run the repository-exact check-only Salesforce validation and retain its machine-readable result.
4. Deploy the same checkout's `force-app` directory.
5. Assign `CPQ_Document_Totals_Admin` to the release operator and run the read-only configuration diagnostics.
6. Assign `CPQ_Document_Totals_Generator` only to intended pilot generators, assign `CPQ_Document_Totals_Retrieval` only to the document integration principal, add the Quote action and related list, and complete the quick start. Existing installations should follow the [access-role migration](access-model.md#migrate-an-existing-installation).
7. Record the target org, CPQ version, commit, deployment job ID, diagnostic result, permission assignments, active definitions, and document integration version.

The current tagged-archive rule excludes 194 inactive `TDX_*` permutation records from the working-tree inventory. Other Custom Metadata in `force-app` remains part of the source distribution and includes inactive examples as well as active definitions. Review those records before deployment and leave an unwanted definition inactive; classifying the remaining examples into an optional layer remains release work.

## Upgrade

Use a sandbox copied from, or representative of, the subscriber org.

1. Record the installed commit, capture subscriber watched fields with `npm run snapshot:subscriber-config -- --target-org qdt-test --output artifacts/subscriber-upgrade/before.json`, and export other subscriber-owned configuration plus any generated or signed output that must be retained.
2. Check out the target tag and review release notes for payload, metadata schema, permission, and output-version changes.
3. Run preflight and a check-only deployment against the sandbox.
4. Deploy without deleting subscriber records. Capture the watched fields again, compare the before and after snapshots with `npm run compare:subscriber-config`, and retain the passing JSON report. Confirm other subscriber definitions and registered extension classes still resolve.
5. Run all Apex tests and the representative-user access matrix.
6. Regenerate a controlled set of existing Ready Quotes. Verify request binding, fingerprints, payload hashes, totals, and the connected document output before broad rollout.
7. Enable the release for a pilot group, then expand only after operational checks remain clean.

No downgrade contract is established. Preserve exports and use a forward fix or the recovery procedure proven for the specific release.

## Disable and remove

Disabling is the first recovery action:

1. Remove the Quote action from user-facing page configurations and stop calling the generation Flow from automation.
2. Find and abort the scheduled job named `Quote Document Retention` if it was configured. Confirm no retention batch is already executing.
3. Remove permission-set assignments from users who should no longer run or view the feature.
4. Deactivate project Custom Metadata definitions to stop future table generation.
5. Preserve generated records and external customer documents until their owner approves disposition.

Metadata removal is a separate reviewed deployment. Inventory subscriber Apex, Flows, reports, templates, page layouts, and integrations that reference project metadata before preparing a destructive changes manifest. Do not delete generated data as part of metadata removal. Data cleanup needs its own target-org inventory, retention approval, backup decision, and audit evidence.

Removing metadata cannot retract documents already delivered to customers or restore records already deleted by retention. The release owner must record those boundaries in the change record.

## Current compatibility evidence

| Dimension                       | Verified combination                            | Status                                           |
| ------------------------------- | ----------------------------------------------- | ------------------------------------------------ |
| Project API                     | 67.0                                            | Source and focused check-only compilation passed |
| Salesforce CPQ                  | 240.5.0.1                                       | Install preflight passed in `quotedoctotals`     |
| Currency configuration          | No representative target configuration recorded | Untested for release certification               |
| Locale and right-to-left output | No document integration result recorded         | Untested                                         |
| Document tool                   | No reference integration version selected       | Open                                             |
| Upgrade origin                  | No prior supported release tag selected         | Open                                             |

This table records evidence, not a general compatibility promise. Add combinations only after reproducing their installation, generation, and document output.

The owner-controlled license and support choices are prepared in the [governance decision record](governance-decision-record.md).
