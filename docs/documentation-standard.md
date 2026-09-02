# Documentation standard

Use this standard for every current Markdown guide in the repository.

## Source of truth

Verify every product claim against current metadata, Apex, Flow, reports, scripts, or tests. Do not use a completed specification, old review, prior deployment result, or chat history as evidence of current behavior.

## Status language

Keep these statements separate:

- **Repository status:** what exists in source now.
- **Org verification status:** what has actually been deployed and run in a Salesforce org.
- **Planned:** work that does not ship and belongs only in the roadmap.

Never turn “implemented in source” into “deployed,” or “repository tests pass” into “verified in this org.”

## Operational guide structure

Every numbered use-case guide contains these sections in order:

1. Status and scope
2. Use case scenario
3. What this produces
4. Before you start
5. Terms in plain language
6. Configure in Salesforce
7. Worked example
8. Generate and verify
9. Troubleshooting
10. Deactivate or roll back
11. Production checklist

The prerequisite section contains a clear **Stop here if** condition. Troubleshooting uses **Problem | What it means | What to do**. Production checks are unchecked tasks so the reader can use them during a release.

## Writing rules

- Start with the Salesforce result, not implementation history.
- Use Salesforce labels before API names.
- Explain an API name beside the business term when the reader must enter or troubleshoot it.
- Define necessary technical terms at first use.
- Use short sentences and direct verbs.
- Give exact Setup navigation and exact field values.
- Replace “as needed,” “when appropriate,” and similar assumptions with a decision rule.
- State who supplies legal wording, translations, business policy, Flow review, or Apex review.
- Include an expected result for every worked example.
- Include failure behavior and safe recovery.
- Never instruct a reader to edit generated records.
- Never put calculations, translations, permanent wording, or content-selection rules only in a document template.
- Keep document-tool styling separate from Salesforce business data.

## Current-only rule

The live repository does not retain:

- superseded guides;
- completed build specifications;
- fixed-bug narratives;
- generated test output;
- point-in-time review reports;
- analyzer logs; or
- withdrawn proposals.

Those items belong in the external day-zero archive. Current open defects remain in `bugs/`; current proposed improvements remain in `enhancements/`; current unimplemented product work remains in `docs/roadmap.md`.

## Validation

Run:

```bash
npm run prettier:verify
npm run test:docs
```

Fix every finding. A passing structural check is necessary but not sufficient; review the facts against current source before publishing.
