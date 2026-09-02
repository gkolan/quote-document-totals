# BUG-018: The fingerprint rounds every decimal to two places before hashing

**Priority:** P4
**Status:** Open
**Evidence:** Read of the encoding against what it is applied to.

## Location

[`QuoteDocumentFingerprint.cls`](../force-app/main/default/classes/QuoteDocumentFingerprint.cls),
`encodeDecimal()`.

## Problem and impact

`value.setScale(2)` normalizes 10.5 and 10.50 to one token, which is the stated
and correct intent for money. It also makes any change beyond the second
decimal invisible to the reuse decision.

That is harmless for the declared currency measures, which are Currency(16,2).
It is not harmless for a resolved `Field_Path__c` value, which is hashed
through the same encoding - and a Product2 numeric field used as a grouping
path is exactly the case the fingerprint exists to catch, because no trigger
watches it. A change in the third decimal there leaves the quote `Ready` and
the snapshot reused, which is the silent staleness the whole mechanism is
built to prevent.

Narrow in practice: it needs a grouping path pointing at a field with more than
two decimal places. Worth closing because the one case it breaks is the one
case the fingerprint is the only defence for.

## Suggested fix

Keep `setScale(2)` for the declared measures. Encode resolved field-path values
with `stripTrailingZeros().toPlainString()` instead - the same 10.5 / 10.50
equivalence, without discarding real precision. Note that `setScale` also
rounds half-even, so the current behaviour is a rounding decision as well as a
truncation.
