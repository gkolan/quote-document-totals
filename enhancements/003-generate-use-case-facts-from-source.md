# ENH-003: Validate repeated documentation facts from source

**Priority:** P3

**Status:** Proposed

## Current behavior

Documentation checks validate links, wording rules, required runbook sections, and contributor versions. They do not yet derive every repeated table fact from Custom Metadata and compare it with the use-case catalog.

## Target result

Generate or validate these facts directly from source:

- Table Code and active state;
- display order and title;
- grouping count and levels;
- displayed columns;
- configured report name;
- contributor, expander, comparison, and partition settings; and
- whether the guide describes the feature as shipped, inactive, provisional, or unsupported.

## Completion evidence

- one source-fact extractor;
- a checked machine-readable inventory;
- CI failures for mismatched guide facts; and
- no duplicate hand-maintained status table that can drift independently.
