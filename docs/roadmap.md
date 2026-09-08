# Current roadmap

This page lists work that is not implemented in the current repository. It is intentionally short so planned behavior cannot be mistaken for shipped behavior.

## Installation and adoption readiness

**Current state:** The project is in active development and installs from source. The repository has no selected license or declared installable package. A manual protected Salesforce workflow, exact-test enumerator, analyzer policy, install preflight, tag-bound archive builder, read-only configuration diagnostic, and private invalidation operations ledger now ship in source. Separate read-only Generator and Retrieval roles, a read-only compatibility role, private top-level generated objects, and separate diagnostics and operations roles define the intended access boundaries. A [capacity harness](capacity-benchmark.md) prepares versioned synthetic 10/100/500/1,000-line fixtures and records governor, output, payload-size, and retrieval observations without declaring a supported envelope. The GitHub environment is not configured here, no successful full candidate run has established the gate, and the new source has not compiled or run in an org. Representative generator, retrieval, denial, sharing, and field-access checks remain required. Retention discovers candidates from the Quote lifecycle and has a focused block-only regression. An aggregate-only [retention inventory](retention-inventory.md) reports eligible shapes, inconsistent historical children, and an assumption-based storage estimate. Its scratch-org rehearsal completed with zero records in every category; a representative established-org inventory and rollout approval remain open. The source includes an identity-bound REST endpoint, strict live exporter, v2 contract, and deterministic HTML renderer. Release-candidate validation, a representative live export, an independently approved commercial comparison, any required PDF/signature product qualification, and a measured operating envelope remain open.

**Target result:** An organization can evaluate a real document, install a known version, operate with appropriate access, and follow tested upgrade and recovery instructions.

**Required proof:**

- owner-approved reuse terms and a working support route;
- clean CPQ-org installation and real non-administrator execution;
- complete retention coverage and org-backed release validation;
- a reproducible document integration that preserves request binding;
- measured capacity and commercial-scenario coverage; and
- subscriber-safe upgrades, durable failure recovery, and removal instructions.

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

**Current state:** The core package ships closed registries and examples. A first subscriber layer now accepts active direct Quote fields through `Quote_Document_Watched_Field__mdt`: records are schema-validated, append to trigger staleness, are selected in user mode, and contribute their name, version, path, and value to the fingerprint. Prefix and duplicate-path rules provide deterministic ownership. Read-only before/after snapshot commands detect removed or changed subscriber records without reading Quote values. Org compilation and a real package-upgrade rehearsal remain open. Additional Quote Line policies, eligibility rules, interpretation policy, and retention policy still require the existing contributor/composer mechanisms or source changes.

**Target result:** A documented subscriber layer can add approved fields and policies without weakening core validation or requiring edits to stock classes for routine changes.

**Required proof:**

- extra field paths are schema-validated and included in freshness checks;
- table eligibility is declarative, bulk-safe, deterministic, and fingerprinted;
- subscriber staleness fields append to core watched fields (implemented in source; org and upgrade proof open);
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
