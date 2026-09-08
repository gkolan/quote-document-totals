# Salesforce release validation

The protected **Salesforce release validation** workflow compiles the exact checked-out `force-app` source, runs every Apex test class currently present in the repository, rejects component errors, test failures, and coverage warnings, and runs Salesforce Code Analyzer at the moderate-severity threshold. It retains the machine-readable deployment and analyzer results under the candidate commit SHA.

## Repository-owner setup

1. Create a GitHub environment named `salesforce-validation`.
2. Require the reviewers who are allowed to release Salesforce metadata.
3. Add an environment secret named `SFDX_AUTH_URL` for a disposable or resettable CPQ validation org. Generate and rotate this URL under the organization's credential policy.
4. Limit the validation user to the metadata and test operations required by this repository. Do not use a production org or a customer-data org.
5. Keep the environment unavailable to untrusted pull-request code. The workflow is manual and has read-only repository permissions.

The target org must have a compatible Salesforce CPQ installation and support project API version 67.0. The workflow fails before source validation if `SBQQ__Quote__c` cannot be described.

## Run and interpret the gate

Open **Actions**, select **Salesforce release validation**, select the exact candidate ref, and run the workflow. Environment approval is the final authorization step before the secret becomes available.

The gate passes only when:

- the operation is check-only and reaches terminal status `Succeeded`;
- at least one component compiles and at least one Apex test executes;
- component errors, Apex test failures, and coverage warnings are all zero; and
- Code Analyzer finds no recommended critical, high, or moderate violation.

Queued or timed-out validation is pending and cannot pass. The validation script retrieves one final deployment report when the initial 30-minute wait returns a nonterminal job. A job still pending after that report fails the workflow instead of being presented as evidence.

Download the `salesforce-validation-COMMIT_SHA` artifact for `deployment-result.json`, the concise deployment summary, and analyzer JSON/SARIF. Record the job ID and artifact name in the release evidence.

## Local equivalent

After authenticating a suitable CPQ test org, run:

```bash
npm run validate:salesforce -- --target-org qdt-test --output-dir artifacts/salesforce
sf code-analyzer run --workspace force-app/main/default/classes --severity-threshold 3
```

The validation script enumerates `*Test.cls` from the current checkout. This prevents a deleted test class left in a long-lived org from changing the result while still requiring every test shipped by the candidate.

## Controlled failure proof

Before making the workflow a required release check, use a temporary branch to prove each gate independently:

1. Introduce an invalid Apex reference and confirm component validation fails.
2. Change a meaningful assertion to fail and confirm the Apex-test gate fails.
3. Temporarily remove a required execution permission and confirm `npm run test:docs` fails.
4. Introduce a moderate analyzer violation and confirm Code Analyzer fails.

Revert each temporary change after its expected failure. Never deploy those probes, and retain their workflow links with the release-process evidence.
