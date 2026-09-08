# Install and generate your first table

Deploy the project to a Salesforce CPQ test org, then generate a **Product Family Summary** from a calculated Quote. You finish with saved Salesforce records and a report you can check.

**Repository status:** The Quote action, Flow, Apex, permission set, table settings, and report ship in source.

**Org verification status:** These instructions must be verified in your own CPQ test org. Local project checks do not prove that deployment or pricing behavior works in that org.

## 1. Prepare a test org

You need:

- A sandbox or disposable test org with Salesforce CPQ installed and configured, supporting Salesforce API version 67.0.
- Salesforce CLI (`sf`) and Git available in your terminal.
- Permission to deploy metadata, edit page layouts, assign permission sets, and access CPQ Quotes.
- A calculated test Quote with non-optional Quote Lines and a Product Family on each included Product. If you do not have one, you do not need to build it by hand: `scripts/apex/quote-document-seed.apex` ships in this repository and creates accounts, products and quotes shaped to exercise every table. Step 2 runs it.

**Stop here if** CPQ is not installed. This project depends on CPQ's `SBQQ__` objects and does not include CPQ installation or licenses. A standard Trailhead Playground cannot run it without that dependency.

Node.js 20 is needed for the repository checks, not for the Salesforce CLI deployment commands below. A separate document tool is needed only when you want to create a final document.

## 2. Download and deploy

Run these commands in a terminal. Each command works in PowerShell or Bash.

```bash
git clone https://github.com/gkolan/quote-document-totals.git
cd quote-document-totals
sf org login web --instance-url https://test.salesforce.com --alias qdt-test
```

The login command opens your browser. Sign in to the intended CPQ sandbox. For a CPQ test org that uses a different login host, replace `https://test.salesforce.com` with that org's login URL. `qdt-test` is a local alias used by the remaining commands.

Run the read-only prerequisite check, then deploy only when it reports `"ready": true`:

```bash
npm run preflight:install -- --target-org qdt-test --output artifacts/install-preflight.json
sf project deploy start --target-org qdt-test --source-dir force-app --wait 30
```

The preflight records the installed CPQ version and required object and field availability. It uploads no source and changes no org data. See the [install, upgrade, and removal contract](install-upgrade-removal.md) before a production rollout.

Continue only when the deployment reports **Succeeded**. If it is still running, use the job ID printed by the command:

```bash
sf project deploy report --target-org qdt-test --job-id YOUR_DEPLOYMENT_ID --wait 30
```

Assign project access to the user you authenticated and open the org:

```bash
sf org assign permset --target-org qdt-test --name CPQ_Document_Totals_Generator
sf org open --target-org qdt-test
```

This permission set includes Run Flows, access to the `QuoteDocumentGenerator` invocable entry class, and read-only review of generated output. It does not grant the JSON retrieval adapter, diagnostics, recovery tools, a Salesforce CPQ license, CPQ permissions, or access to the target Quote. Assign it separately to any other user who will generate tables. Existing installations can migrate from `CPQ_Document_Totals`; see [Access roles](access-model.md).

If you do not already have a calculated Quote to work from, create one now:

```bash
sf apex run --target-org qdt-test --file scripts/apex/quote-document-seed.apex
```

Run this only in a disposable test org. It builds accounts, products and quotes shaped to exercise every table this project generates, including bundles, optional products and recurring charges. On every run it deletes accounts tagged `[SEED]`, their CPQ Quotes, and products whose Product Code starts with `SEED-`, then recreates the sample. Do not run it in an org where those identifiers may belong to other data. Use any of the quotes it reports for the rest of this guide.

To reproduce every worked example in the documentation rather than only the seed data, run `scripts/scratch-org-bootstrap.sh`, which chains deploy, permission set assignment, the seed, and each example script in order.

## 3. Add the action and review fields

1. Open **Setup -> Object Manager** and select the CPQ **Quote** object, API name `SBQQ__Quote__c`.
2. Open **Page Layouts** and edit the layout assigned to your test user.
3. In **Mobile & Lightning Actions**, add **Generate Document Tables** to **Salesforce Mobile and Lightning Experience Actions**. Override the predefined actions if the layout asks you to do so.
4. Add **Document Data Status**, **Document Data Generated On**, and **Document Data Error** from **Fields**.
5. Add **Document Tables** from **Related Lists**, then save the layout.
6. If the Lightning record page manages actions through Dynamic Actions, add **Generate Document Tables** to that page's action configuration too.

In **Setup -> Custom Metadata Types -> Quote Document Table Definition -> Manage Records**, confirm **Product Family Summary** is active. It ships active; do not create a duplicate. Other active definitions may create additional tables.

## 4. Generate and check the result

1. Open your CPQ test Quote. Calculate and save its Quote Lines, then wait for CPQ processing to finish.
2. Select **Generate Document Tables**. Read the result and finish the Flow.
3. Refresh the Quote and confirm **Document Data Status = Ready**. If it is **Failed**, read **Document Data Error** and use the troubleshooting table below.
4. Open the Quote's **Related** tab, then **Document Tables**. Open the record with Table Code `PRODUCT_FAMILY_SUMMARY` and confirm its status is **Complete**.
5. Open the table's **Rows** related list. If it is absent, add **Rows** to the assigned **Quote Document Table** page layout in Object Manager.
6. Open **Reports -> All Folders -> CPQ Document Totals -> Quote Document - Product Family Summary**. Filter the report to your test Quote and run it.
7. Compare the saved family amounts and grand total with the calculated, non-optional Quote Lines. The report and saved records must agree.

For example, a Quote with these final calculated line amounts should produce these family totals:

| Product Family | List amount | Discount amount | Net amount |
| -------------- | ----------: | --------------: | ---------: |
| Software       |     $12,000 |          $1,200 |    $10,800 |
| Services       |      $5,000 |              $0 |     $5,000 |
| Grand Total    |     $17,000 |          $1,200 |    $15,800 |

These are illustrative amounts, not values the installation creates. An optional Services line worth $2,000 must stay out of this summary. Your totals depend on your Quote. See the [full worked example](use-case/01-product-family-summary.md) for exact configuration and line values.

You have completed the first-use check when the Quote is **Ready**, the table is **Complete**, and its saved rows and report match the expected totals. This creates document data; it does not create or send a PDF. Connecting a document tool is a separate step.

## Daily use

Save and calculate the Quote, select **Generate Document Tables**, and review the result only when the status is **Ready**. Generate again after relevant Quote changes. Correct source Quote data or table settings instead of editing generated tables or rows.

## Troubleshooting

| Problem                                  | What it means                                                           | What to do                                                                                                                       |
| ---------------------------------------- | ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `SBQQ__` objects or fields are missing   | The target org lacks CPQ, access, or a required CPQ field               | Confirm the login target, CPQ installation, and permissions. Review the exact missing field before retrying deployment.          |
| API version is unsupported               | The org does not support the project's API version                      | Use an org supporting 67.0. Do not lower the version without validating compatibility.                                           |
| Deployment is still running or failed    | Installation is not complete                                            | Run the deployment report command and resolve its listed errors before continuing.                                               |
| The Quote action is missing              | The assigned layout or Dynamic Actions configuration does not expose it | Check step 3 and confirm you opened `SBQQ__Quote__c`.                                                                            |
| Access is denied                         | The user lacks required project or CPQ access                           | Confirm the `CPQ_Document_Totals_Generator` permission set, CPQ access, and access to this Quote.                                |
| Status is Failed                         | Generation could not complete its checks                                | Read **Document Data Error**, correct the named data or configuration problem, and generate again.                               |
| Status is not Ready yet                  | Generation or subsequent CPQ changes may still be processing            | Refresh and inspect the status. Use the [status guide](use-case/38-quote-generation-status-and-errors.md) if it does not settle. |
| The summary is missing or amounts differ | Definition settings, optional lines, or calculated values may differ    | Confirm the definition is active and compare against the [Product Family Summary guide](use-case/01-product-family-summary.md).  |
| The report contains other Quotes         | The report is not filtered to your test Quote                           | Add a Quote filter before comparing totals.                                                                                      |

## Next steps

- [Available table examples](use-case/README.md): choose a second table to configure.
- [How the tables are built](how-quote-document-totals-works.md): understand the design.
- [Testing guide](testing-guide.md): validate deployment, Apex tests, permissions, and output before production use.
- [Configuration and maintenance](quote-document-totals-architecture-guide.md): configure document-tool access and maintain the feature.

To stop exposing the feature during evaluation, remove the Quote action from the page configuration. Deactivate a table definition to stop generating that table on future runs; this does not uninstall metadata or erase prior output. Use a disposable org when you need a clean removal after evaluation.
