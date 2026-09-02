# ENH-001: Extend cross-feature test coverage

**Priority:** P2

**Status:** Proposed

## Current behavior

The repository tests expansion, allocation, non-additive measures, comparison, partitioning, localization, contributors, integrity, and lifecycle behavior. Configuration validation also rejects several unsafe combinations.

The generated permutation harness does not yet derive and test every meaningful pair across the newer row-production features.

## Target result

Generate the supported and rejected feature-pair matrix from current registry values and Table Definition fields.

Required outcomes:

- every supported pair has a positive test;
- every rejected pair has a negative test with the expected error code;
- a new feature expands the matrix automatically;
- expected results are authored independently of generator output; and
- run output remains generated evidence rather than permanent documentation.

## Completion evidence

- matrix-generation source and tests;
- current allowed and rejected pair inventory;
- CI failure when a pair has no declared expectation; and
- a clean full Salesforce test run against the current revision.
