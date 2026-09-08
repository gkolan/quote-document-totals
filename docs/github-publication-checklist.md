# Publish the repository on GitHub

Use this checklist after the local project checks pass. It separates publishing the source repository from declaring a supported Salesforce release.

## 1. Make the repository safe to publish

Run the complete local gate from a clean checkout:

```bash
npm ci
npm run audit:dependencies
npm test
npm run lint
npm run prettier:verify
npm run test:docs
npm run test:ci-gate
git status --short
```

`test:ci-gate` fails when internal research, implementation evidence, development plans, defect notes, root-level reports, generated output, authentication material, or common secret files are tracked. It also confirms that Salesforce report metadata remains publishable under `force-app/main/default/reports/`.

Review the pending diff. Confirm that it contains no customer names, org URLs, screenshots from private orgs, access tokens, private keys, exported records, or test output. The ignore rules reduce accidental additions; they do not replace reviewing the diff.

## 2. Make the owner decisions

Choose a license before describing the project as open source or publishing a release archive. Follow the [license and support decision record](governance-decision-record.md); do not copy a license from another repository without confirming ownership and obligations.

Confirm that GitHub Issues is the public support route and enable private vulnerability reporting so the link in [SECURITY.md](../SECURITY.md) works. Update `SECURITY.md` and `SUPPORT.md` if the owner selects different routes.

## 3. Configure GitHub

1. Create or open `github.com/gkolan/quote-document-totals`.
2. Set the description to the sentence under the README title and add Salesforce and Salesforce CPQ topics.
3. Enable Issues and preserve the structured issue forms in `.github/ISSUE_TEMPLATE`.
4. Enable private vulnerability reporting under **Settings -> Security -> Code security and analysis**.
5. Add a `salesforce-validation` environment under **Settings -> Environments**. Restrict it to trusted reviewers and store the authentication secret named by `.github/workflows/salesforce-validation.yml`.
6. Protect `main`. Require a pull request and the **Documentation and project checks** status. Require the Salesforce validation status for a release candidate after the environment is configured.
7. Disable force pushes and branch deletion for `main`.

Repository visibility and branch rules are owner-controlled GitHub changes. Verify them in the GitHub settings page after saving.

## 4. Test the reader path

In a new directory, clone the GitHub URL and follow [Install and generate your first table](quick-start.md) exactly. Before using Salesforce, run the local reference example from the README. Confirm that:

- `npm ci` and every documented local check pass;
- the reference HTML and manifest are created under the ignored `artifacts/` directory;
- the install preflight reports `ready: true` for the intended CPQ test org;
- the source deployment succeeds;
- a representative non-administrator can run **Generate Document Tables**;
- the Quote reaches **Ready**, its Table reaches **Complete**, and the saved rows match the Salesforce report; and
- removal and recovery steps in the [install contract](install-upgrade-removal.md) work in the test org.

Record remote validation evidence in the protected workflow artifact or the release record. Do not commit org-specific results.

## 5. Publish a release

A public repository can exist before the first supported release. Publish a release only after a license exists and the protected Salesforce validation succeeds for the exact commit.

1. Update `package.json` and `CHANGELOG.md` with the release version.
2. Create an annotated tag with the same version, such as `v1.0.0`.
3. Run `npm run build:source-release -- --tag v1.0.0`.
4. Attach the generated ZIP, source release manifest, and protected Salesforce validation artifact to the GitHub release.
5. Follow [Install, upgrade, and removal](install-upgrade-removal.md) once more using the published tag or archive.

The release builder deliberately requires `LICENSE`, so it will stop until the owner completes the license decision.

## Expected result

The GitHub repository contains installable source, public guides, a runnable local document example, issue and security routes, and automated publication checks. Internal working material and generated evidence remain local. A release is described as supported only when the owner decisions and org-backed validation are complete.
