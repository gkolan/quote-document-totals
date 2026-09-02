# Current known defect

This folder contains only defects that remain present in the current source.

| ID                                                   | Priority | Current behavior                                             | Impact                                                              |
| ---------------------------------------------------- | -------- | ------------------------------------------------------------ | ------------------------------------------------------------------- |
| [BUG-018](018-fingerprint-rounds-to-two-decimals.md) | P4       | The input fingerprint normalizes every Decimal to two places | A third-decimal-only input change can reuse an earlier Ready result |

## Operating guidance

Until BUG-018 is fixed:

- do not use third-decimal-only values as document-significant inputs without forcing a rebuild;
- use `ALWAYS_REBUILD` for a contributor whose result depends on Decimal precision beyond two places;
- include a third-decimal test when adding a Decimal field path; and
- do not treat an unchanged fingerprint as proof that third-decimal inputs are unchanged.

## Close-out rule

When the implementation and regression test fix this defect, move the defect document to the external day-zero archive and remove the row from this index. Do not keep fixed-defect history in the live repository.
