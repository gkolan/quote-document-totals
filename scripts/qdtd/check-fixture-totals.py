"""Fails if the org did not persist the writable inputs the fixtures wrote.

    python scripts/qdtd/check-fixture-totals.py

Compares specs/quote-document-test-data/results/fixture-intended.csv (what
build-quote-fixtures.py told the org to store) against fixture-totals.csv (what
the org actually returned). A CPQ trigger, validation rule or field-level
security problem that rewrites an input shows up here and nowhere else - and if
it goes unnoticed, every expectation derived from these fixtures is wrong in a
way no downstream assertion would catch.

Exit code 1 on any mismatch, so this can gate the permutation run.
"""

import csv
import pathlib
import sys
from decimal import Decimal, InvalidOperation

RESULTS = pathlib.Path(__file__).resolve().parents[2] / "specs/quote-document-test-data/results"

# Only writable inputs are compared. Everything else on the line - NetPrice,
# CustomerPrice and every formula total - is CPQ's to compute from these, and is
# recorded for the ledger to derive expectations from rather than asserted here.
#
# net_price is deliberately NOT compared: writing it directly does not survive
# CPQ's asynchronous recalculation, so the fixtures state a Discount percent and
# let the org derive the money. Comparing a derived value against an intent we
# never wrote would fail permanently and for the wrong reason.
COMPARED = ["quantity", "list_price", "discount", "charge_type", "billing_frequency", "optional"]


def numeric(value):
    try:
        return Decimal(value)
    except (InvalidOperation, ValueError):
        return None


def same(intended, persisted):
    a, b = numeric(intended), numeric(persisted)
    if a is not None and b is not None:
        return a == b
    return (intended or "").strip().lower() == (persisted or "").strip().lower()


def main():
    intended = {}
    with (RESULTS / "fixture-intended.csv").open(encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            intended[(row["quote_key"], row["line_number"])] = row

    persisted = {}
    with (RESULTS / "fixture-totals.csv").open(encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            persisted[(row["quote_key"], row["line_number"])] = row

    mismatches = []
    missing = []
    for key, want in intended.items():
        got = persisted.get(key)
        if got is None:
            missing.append(key)
            continue
        for field in COMPARED:
            if not same(want[field], got[field]):
                mismatches.append((key, field, want[field], got[field]))

    print("compared {} explicitly specified lines against {} persisted lines".format(
        len(intended), len(persisted)))

    if missing:
        print("\nMISSING - intended but not found in the org:")
        for key in missing:
            print("  {} line {}".format(*key))

    if mismatches:
        print("\nMISMATCHED writable inputs - the org did not store what was written:")
        for (quote, line), field, want, got in mismatches:
            print("  {} line {:>3}  {:<18} wrote {:<12} persisted {}".format(quote, line, field, want, got))

    if missing or mismatches:
        print("\nFAIL: {} missing, {} mismatched.".format(len(missing), len(mismatches)))
        return 1

    print("\nOK: every writable input persisted exactly as written.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
