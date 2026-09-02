# Test and verification guide

**Repository status:** The repository includes JavaScript checks, Apex tests, Salesforce metadata, repeatable test-data scripts, and a generated permutation harness. Generated run output is not committed as current documentation.

**Org verification status:** Local checks run without a Salesforce org. Apex deployment and CPQ behavior require a Salesforce CPQ test org.

## Local checks

Install Node.js 20 dependencies once:

```bash
npm ci
```

Run:

```bash
npm test
npm run lint
npm run prettier:verify
npm run test:docs
npm run test:ci-gate
```

| Check                     | What it proves                                                                             |
| ------------------------- | ------------------------------------------------------------------------------------------ |
| `npm test`                | Runs Lightning Web Component tests when present; currently reports an explicit skip        |
| `npm run lint`            | JavaScript follows the project lint rules                                                  |
| `npm run prettier:verify` | Current documentation and project configuration files are formatted                        |
| `npm run test:docs`       | Links, plain language, retired references, runbook structure, and source facts are checked |
| `npm run test:ci-gate`    | Unit tests for the contributor version check pass                                          |

Run `npm run ci:contributor-versions` to check actual contributor changes. GitHub Actions supplies the pull-request base or exact pre-push commit. A manual run without a base compares with the repository's root commit. After a history rewrite, CI fetches the exact pre-push commit and fails if it remains unavailable; it never substitutes an unverified comparison.

## Salesforce test org prerequisites

You need:

- Salesforce CPQ installed;
- permission to deploy metadata and run Apex tests;
- a non-production org;
- the project metadata deployed; and
- the `CPQ_Document_Totals` permission set assigned to the test operator.

Use the shared bootstrap script when its prerequisites match the org:

```bash
scripts/scratch-org-bootstrap.sh
```

Read the script before running it. It creates or changes test data and is not a production command.

## Apex tests

Validate the entire source and run all local Apex tests together. Use your authenticated CPQ test-org alias in place of `qdt-test`:

```bash
sf project deploy start --dry-run --target-org qdt-test --source-dir force-app --test-level RunLocalTests --wait 30
```

This compiles the source being reviewed and runs its tests without saving metadata changes. It can detect missing objects or dependencies that the JavaScript checks cannot detect. If Salesforce returns a job Id before completion, retrieve the final result:

```bash
sf project deploy report --target-org qdt-test --job-id YOUR_DEPLOYMENT_ID --wait 30
```

Require **Succeeded**, zero component errors, and zero test failures. Review coverage and warnings in the result. A queued or in-progress result is not a pass.

After installation, rerun the already deployed code's tests when needed:

```bash
sf apex run test --target-org qdt-test --test-level RunLocalTests --code-coverage --result-format human --wait 30
```

An existing org can supply dependencies absent from a clone. Before distribution, also verify installation in a clean CPQ test org and follow the [quick start](quick-start.md) as a user with the documented permissions. Repeat generation after a Product description, unit price, or fractional quantity change and confirm the saved result is refreshed. Do not claim org verification from local source inspection alone.

Record:

- target org alias;
- deployment or test command;
- test run Id;
- pass, fail, and skipped counts;
- failing class and method names;
- coverage required by the deployment policy; and
- the source revision tested.

Generated JSON, JUnit, debug logs, and coverage files belong in a temporary or ignored results directory, not in the documentation tree.

## Realistic Quote data

The current test-data utilities are under `scripts/qdtd/`, `scripts/apex/`, and `datasets/qdtd/`.

They separate foundation data from CPQ Quote creation:

1. foundation Accounts, Contacts, Opportunities, Products, and Pricebook Entries are loaded from repeatable data recipes;
2. Apex creates Quotes and Quote Lines because CPQ bundle and pricing relationships require Salesforce behavior;
3. generated `TDX_*` definitions exercise configuration combinations; and
4. the runner records results in `specs/quote-document-test-data/results/` for that run.

The entire `specs/` directory is local and excluded from Git. Test-data scripts create their output directories when run; a fresh clone does not need local planning notes. The results directory is generated evidence. Recreate it for the current source; do not treat an old copy as proof.

## Permutation run

Before running, confirm all `TDX_*` Table Definitions are inactive. The harness activates only the definitions needed for its current slice and must return them to inactive.

Use the maintained scripts in this order:

1. build or load foundation data;
2. build Quote fixtures;
3. generate the matrix definitions and expected cases;
4. deploy the generated metadata;
5. run the matrix harness;
6. export current fixture totals;
7. run ledger, matrix, and fixture-total checks; and
8. query the org to confirm no `TDX_*` definition remains active.

Use each script's `--help` or header for its exact parameters. Never copy an org alias or user name from an old result file.

## Required behavior tests

At minimum, current verification covers:

- each line filter and measure set;
- nested and composite grouping;
- detail, subtotal, section-total, and grand-total rows;
- expansion and allocation;
- non-additive measures;
- comparison and ambiguous-match rejection;
- partitioning and cross-partition total policy;
- Apex and Flow contributors;
- localization and content blocks;
- input fingerprint reuse and rebuild;
- output payload integrity;
- concurrent and abandoned-request behavior;
- failure rollback and persisted Quote error;
- access control and sharing; and
- renderer request binding.

## Documentation verification

Every numbered guide must contain:

- repository and org verification status;
- scenario and expected result;
- prerequisites with a stop condition;
- plain-language definitions;
- exact Salesforce configuration;
- a worked example;
- generation and verification steps;
- problem, meaning, and action troubleshooting;
- rollback; and
- a production checklist.

Documentation claims must be traced to current metadata, Apex, Flow, reports, scripts, or tests. Planned items belong only in [Current roadmap](roadmap.md).

## Release evidence

A release is ready only when:

- [ ] local checks pass;
- [ ] the target-org deployment check passes;
- [ ] required Apex tests pass;
- [ ] changed definitions generate expected saved records;
- [ ] changed contributors prove version-token behavior;
- [ ] language and content changes are reviewed;
- [ ] invalidation is run when output identity changed;
- [ ] named reports match generated records;
- [ ] the final document adapter matches the saved payload; and
- [ ] generated test output is stored outside current documentation.
