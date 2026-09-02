# Contributing

Thank you for improving Quote Document Totals.

## Before making a change

1. Use a Salesforce CPQ test org or sandbox. Do not test a new change in production first.
2. Read [docs/README.md](docs/README.md) and the guide for the area being changed.
3. Keep Salesforce labels, object names, field names, and menu paths exact.
4. Use plain language. Explain an unfamiliar term the first time it appears.
5. Do not describe people by experience level or job title. Write the instruction for anyone completing the task.
6. State clearly whether a change was only written, deployed to an org, or tested in an org.

## Make and check the change

```bash
npm ci
npm test
npm run lint
npm run prettier:verify
npm run test:docs
npm run test:ci-gate
```

For Salesforce changes:

1. Deploy to a Salesforce CPQ test org.
2. Run the affected Apex tests.
3. Run the full Quote Document Totals Apex test set when shared generation or total rules change.
4. Generate tables from a real test Quote.
5. Confirm the Quote reaches **Document Data Status = Ready**.
6. Review the saved rows and the affected report.

## Open a pull request

Use the pull request template. Include:

- What changed and why.
- The Salesforce items changed.
- The checks that passed.
- The Salesforce org type used for testing, without including an org URL or customer information.
- Any check that was not run and the reason.
- Screenshots only when they contain no customer, credential, or private org information.

Keep generated test output, local review files, credentials, and org-specific data out of the pull request.

## What belongs in Git

Commit source, automated tests, shared scripts, CI configuration, test-org definitions, and public documentation. Keep known defects and proposed improvements available so others can understand the current limitations and contribute.

The `specs/` directory contains local planning material and is ignored. Personal editor settings, AI-assistant instructions and installed skills, authentication state, dependencies, and generated results are also ignored. None of these local files should be required to install the project or run its public checks.
