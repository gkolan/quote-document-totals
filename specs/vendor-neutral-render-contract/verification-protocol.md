# Vendor-neutral render contract — verification protocol

Every step leaves evidence another person can reproduce. "Tests passed" without the command, the org, and the commit is not evidence.

This file is deliberately short. A protocol nobody completes is worse than none, because it makes an unverified step look verified.

## Gate record — six lines per step close-out

```
commit:      <sha> (clean | dirty)
org:         <alias> / <org id>
command:     <the exact sf command>
result:      <pass/fail, test run id>
fixture:     <quote id> / <request id>
deviations:  <none | what, who owns it, expiry date>
```

Anything beyond these six lines belongs in the step's own close-out section, not here.

## What every step must prove

| | Proof |
|---|---|
| **Positive** | The thing the step adds is present and correct on a regenerated quote — shown by the step's SOQL query, not by inspection. |
| **Negative** | Each failure the step introduces has a test asserting its **stable error code** and the offending key, table, Flow, or locale. A test that asserts only "an exception was thrown" does not close a step. |
| **Non-regression** | Existing test classes pass **unmodified**. Modifying an existing assertion to accommodate a new behaviour is a spec amendment, not a test fix, and needs the owner's sign-off in the close-out. |
| **Rollback** | For any step that changes generation, force a failure and assert the one invariant: **no records created by that attempt survive**. On a first generation that means zero tables; on a regeneration it means the previous snapshot restored unchanged, with its original record Ids. Both cases, one test each. |

## Release gate — version tokens must be enforced, not remembered

Content-identity tokens ([step 01A](steps/step-01a-extension-contracts.md) §6) only work if they are bumped, and the one time they will not be is the urgent Friday Flow edit. Testing that *manually* changing a token changes the fingerprint proves the plumbing, not the discipline. CI must fail the build when:

| Changed | Without a change to |
|---|---|
| An Apex class reachable from `QuoteDocumentRowCustomizerRegistry` | that code's `Row_Customizer_Version__c` |
| A `.flow-meta.xml` named by any `Row_Customizer_Flow__c` | that definition's `Row_Customizer_Flow_Version__c` |
| Any `Quote_Document_Key_Value__mdt` row in a `LABELS_*` or content category, or any clause-content record | `CONTENT/VERSION` |
| The subscriber factory mapping | the affected definition's version token |

For core customizers the mapping is derivable from `QuoteDocumentRowCustomizerRegistry`: code → class file, diffed against the merge base. **Parse it structurally where practical** — a regex over `when` branches breaks on a reformat, a multiline branch, or a commented-out entry, and a silently empty mapping makes the gate pass while checking nothing. At minimum, the parser has its own tests covering multiline branches, comments, and a deliberately malformed registry, and it fails the build when it finds zero mappings. For subscriber-owned Apex and Flows, discovery is not possible from core, so the subscriber pack ships a small `dependency-versions` mapping file and the same check runs against it — a pack without one cannot pass the gate.

**A gate failure blocks the release.** It never degrades to a warning, and the gate's own failure modes are failures too: zero mappings parsed, merge base unavailable, a missing subscriber mapping file, or a rename that breaks the mapping. An emergency deployment that skips CI incurs a recorded manual invalidation run — not an exemption.

This check is worth more than any single test in this spec set, because it is the only thing standing between an edited Flow and a silently reused snapshot.

## Standing rules

- No `SeeAllData=true`.
- No skipped tests in a release gate.
- A test fixture may not call private generator internals to manufacture the state it is verifying.
- Verification SOQL selects `Document_Data_Request_Id__c` and the fingerprint, so records from two attempts cannot be read as one snapshot.
- Limits: **one** test generates the largest supported quote and records queries, DML rows, CPU, and heap against a written budget. One test, at the maximum — not a budget assertion in every suite.

## Deliberately not required

Mutation testing, security personas per step, deployment rehearsal as a gate, and a fixed percentage of limit headroom. They are real practices, but as blanket per-step requirements on a spec with nothing built yet they would be skipped and then cited as done. Where one of them genuinely matters — FLS behaviour under `WITH USER_MODE`, rollback on DML failure — it appears as a named acceptance criterion in the step that needs it.
