# Current roadmap

This page lists work that is not implemented in the current repository. It is intentionally short so planned behavior cannot be mistaken for shipped behavior.

## One-click Quote-scoped report links

**Current state:** Salesforce reports ship, but users must open a report and filter it to the Quote. No report-link Custom Metadata Type, Quote preview component, or report-navigation Flow ships.

**Target result:** From a Ready Quote, a user opens the rendered-view or table-specific report already filtered to that Quote. Report identity must be deployment-safe and must not hardcode an org-specific Report Id.

**Required proof:**

- Quote Id is the stable first runtime filter;
- every active shipped table with a report has a current link configuration;
- Rendered View remains non-summing across mixed row types;
- users without report access receive a clear error; and
- documentation and permission metadata ship with the feature.

## Upgrade-safe subscriber configuration

**Current state:** The core package ships closed registries and examples. Organizations that need additional Quote Line fields, eligibility rules, interpretation policy, or retention policy must currently extend source or configuration directly.

**Target result:** A documented subscriber layer can add approved fields and policies without weakening core validation or requiring edits to stock classes for routine changes.

**Required proof:**

- extra field paths are schema-validated and included in freshness checks;
- table eligibility is declarative, bulk-safe, deterministic, and fingerprinted;
- subscriber staleness fields append to core watched fields;
- retention never leaves generated records behind or clears a Quote incorrectly;
- stock behavior is unchanged when no subscriber configuration exists; and
- install and removal are documented and tested.

## Dynamic table eligibility

**Current state:** An active definition applies whenever its line filter and configured features produce a valid table. There is no separate declarative rule that limits a definition by Quote-level conditions.

**Target result:** Administrators can state when a table applies using a restricted, validated rule model without arbitrary formula evaluation or dynamic SOQL.

**Required proof:**

- supported operators and field types are explicit;
- every referenced value is included in the input fingerprint;
- bulk generation does not query once per rule or Quote;
- invalid rules fail before output is published; and
- each use-case guide states the table's eligibility in plain language.

## Quote-change classification validation

**Current state:** CHANGE-measure tables and classification logic exist, but customer-facing enablement remains conditional on validation against representative amendment and renewal data from the target CPQ org.

**Target result:** Transaction labels and signs match the organization's actual amendment, cancellation, renewal, and replacement behavior.

**Required proof:**

- real amendment and renewal Quotes exercise every enabled classification;
- expected labels and signed amounts are approved by the commercial owner;
- unreachable or organization-specific branches are documented honestly; and
- CHANGE table definitions remain inactive until the validation passes.

## Roadmap rule

Do not describe any item on this page as available until its source, tests, permissions, operational instructions, and applicable use-case guide are present and validated. When an item ships, remove it from this page instead of adding a historical completion narrative.
