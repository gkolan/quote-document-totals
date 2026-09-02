# ENH-002: Separate generation, rendering, and support access

**Priority:** P2

**Status:** Proposed

## Current behavior

`CPQ_Document_Totals` is one broad permission set for generation, generated-record access, reports, Flow, and Apex. The render service applies sharing and field-access checks, but the package does not ship smaller permission sets for distinct operating responsibilities.

## Target result

Provide least-privilege access packages for:

- running generation from a Quote;
- retrieving a bound document payload; and
- inspecting technical status, errors, request identity, and generated records.

## Required safeguards

- document retrieval still requires a Ready Quote, request Id, and fingerprint;
- a rendering integration cannot edit generated records;
- a generation user does not automatically receive technical support access;
- support access does not grant Custom Metadata or Apex deployment rights;
- existing customers have a documented migration path; and
- access-denied tests cover each public entry point.

## Completion evidence

- deployable permission metadata;
- Apex access-control tests;
- administrator assignment and removal instructions;
- upgrade behavior for the existing permission set; and
- target-org verification with representative users.
