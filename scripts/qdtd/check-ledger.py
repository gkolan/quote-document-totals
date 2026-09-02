"""Compares the run's ledger against the expectations authored before it.

    python scripts/qdtd/check-ledger.py
    python scripts/qdtd/check-ledger.py --selftest

A mismatch in EITHER direction is a failure: an unexpected error and an
unexpected success are both findings. That is the point of authoring
expectations.csv up front rather than reading the results and calling them the
spec.

WHAT THIS CHECKED BEFORE, AND WHY THAT WAS NOT ENOUGH
-----------------------------------------------------
Two independent reviews corrupted the ledger and watched this file pass.

The first replaced every one of the 166 error reasons with an unrelated
NullPointerException, and every one of the 1085 success totals with
999999999999, and zeroed every depth. It compared outcome CATEGORIES and
nothing else, so a green ledger proved only that each run succeeded-or-failed
as predicted - not that it failed for the predicted reason, nor that the
numbers it produced were right.

The second got past the fix for that one. Deleting every total tag passed with
ZERO totals compared; replacing each with NaN passed with 422 reported as
compared, because every comparison against a NaN is false; and collapsing 143
rows to depth 1 passed while the summary claimed depths had been compared for
equality. Absent evidence reduced coverage silently, and the depth check was a
bound wearing an equality's label.

Five things now close both rounds, each aimed at one of the corruptions:

  1. Every predicted error kind carries a SIGNATURE that must appear in the
     failure text. A NullPointerException does not satisfy ERROR_MAX_GROUPS.
  2. Grand totals are compared against an oracle derived independently - from
     the persisted fixture values - wherever the total is derivable.
  3. A derivable row with no oracle entry, no printed total, or a total that is
     blank, unparseable or nonfinite is a FAILURE. Missing evidence fails; it
     never quietly shrinks the number of rows checked.
  4. Depth is compared against the depth the definition and the fixture between
     them REQUIRE - one level per configured level once the filter leaves any
     line standing - rather than merely bounded above. Only two shapes cannot be
     derived that way and are bounded instead: a BUNDLE level, which indents
     details by CPQ's own option level, and a table with a row customizer, which
     rebuilds the tree from scratch. Those are counted and reported as BOUNDED,
     never as equality.
  5. Duplicate (definition x quote) keys are rejected, and the unnamed-label
     count is read from the payload itself via the harness rather than searched
     for in a text column that never carried labels.

WHAT THE ORACLE IS AND IS NOT
-----------------------------
derived-shape.txt is produced by build-matrix.py THROUGH the production classes
(QuoteDocumentLine.matchesFilter and getGroupingValue). So it is independent of
the aggregation and rendering under test - it catches a wrong sum, a wrong
bucket count, a truncated hierarchy - but it shares the filtering semantics with
them. A filter that is wrong in the same way in both places would agree with
itself. Reading membership straight from the raw fixture inventory would close
that too; it has not been done.

--selftest re-runs the checker against corrupted copies of the current results
and requires each corruption to fail. It is the check on the check: every
corruption above is in it, so the next simplification of this file has to keep
detecting them.
"""

import collections
import csv
import pathlib
import sys
from decimal import Decimal, InvalidOperation

ROOT = pathlib.Path(__file__).resolve().parents[2]
RESULTS = ROOT / "specs/quote-document-test-data/results"

# What the money comparison tolerates. Currency at two decimal places, so one
# cent of slack and no more.
TOTAL_TOLERANCE = Decimal("0.01")

# A BUNDLE level indents each detail row by CPQ's own option level, which this
# checker cannot derive from the fixture inventory. The deepest bundle in the
# roster sits four options down, so that is the allowance - a bound, and
# reported as one.
BUNDLE_INDENT_ALLOWANCE = 4

# The ledger's outcome vocabulary mapped onto what expectations.csv predicts.
EXPECTED_TO_LEDGER = {
    "SUCCESS": {"SUCCESS"},
    "EMPTY": {"EMPTY"},
    "ERROR_MAX_GROUPS": {"ERROR"},
    "ERROR_INDUSTRY_ON_CHANGE": {"ERROR"},
    "ERROR_COUNTED_ROW": {"ERROR"},
    "ERROR_DETAILS_DROPPED": {"ERROR"},
}

# Text that must appear in the failure for a prediction to count as met. Taken
# from the throw sites, so a different failure with the same outcome category
# cannot satisfy the expectation.
ERROR_SIGNATURES = {
    "ERROR_MAX_GROUPS": ["produced more than", "Max Groups"],
    "ERROR_INDUSTRY_ON_CHANGE": ["IndustryRowCustomizer", "PRICE_WATERFALL"],
    "ERROR_COUNTED_ROW": ["counts toward the grand total"],
    "ERROR_DETAILS_DROPPED": ["grand total vs detail rows"],
}


def load_shape(results):
    """Per (quote, filter): what the production classes derived for it.

    Carries the net total AND the surviving line count. The second is what
    makes an expected depth derivable, since a filter that keeps no line leaves
    a table with nothing but its grand total.
    """
    shape = {}
    for raw in (results / "derived-shape.txt").read_text(encoding="utf-8").splitlines():
        if not raw.strip():
            continue
        parts = raw.split("|")
        shape[(parts[0], parts[1])] = dict(
            chunk.split("=", 1) for chunk in parts[2:] if "=" in chunk
        )
    return shape


def money(text):
    """A finite Decimal, or None if the text is not one.

    Decimal() accepts 'NaN' and 'Infinity' happily, and every comparison
    against a NaN is false - which is how a ledger full of NaN totals passed a
    difference check. is_finite() is the guard for that; float() was not.
    """
    if text is None or not str(text).strip():
        return None
    try:
        value = Decimal(str(text).strip())
    except (InvalidOperation, ValueError):
        return None
    return value if value.is_finite() else None


def tagged(detail, prefix):
    for chunk in (detail or "").split():
        if chunk.startswith(prefix):
            return chunk.split("=", 1)[1]
    return None


def main(results=None):
    results = results or RESULTS
    ledger_path = results / "ledger.csv"
    if not ledger_path.exists():
        print("no ledger.csv - run scripts/qdtd/run-matrix.ps1 first")
        return 1

    matrix = {
        r["table_code"]: r
        for r in csv.DictReader((results / "matrix.csv").open(encoding="utf-8"))
    }
    expectations = {
        (r["table_code"], r["quote_key"]): r
        for r in csv.DictReader((results / "expectations.csv").open(encoding="utf-8"))
    }
    shape = load_shape(results)
    ledger = list(csv.DictReader(ledger_path.open(encoding="utf-8")))
    print("ledger rows: {}".format(len(ledger)))

    failures = collections.defaultdict(list)
    seen = set()
    totals_compared = 0
    depths_compared = 0
    depths_bounded = 0

    for row in ledger:
        key = (row["table_code"], row["quote_key"])
        if key in seen:
            failures["duplicate ledger keys"].append("{} {}".format(*key))
            continue
        seen.add(key)

        want = expectations.get(key)
        if want is None:
            failures["ledger rows with no expectation"].append("{} {}".format(*key))
            continue

        expect, got = want["expect"], row["outcome"]
        if got not in EXPECTED_TO_LEDGER.get(expect, set()):
            bucket = ("unexpected successes" if got == "SUCCESS"
                      else "unexpected errors" if got.startswith("ERROR") or got == "PAYLOAD_ERROR"
                      else "other mismatches")
            failures[bucket].append("{} {}  expected {}  got {}  :: {}".format(
                key[0], key[1], expect, got, (row["detail"] or "")[:100]))
            continue

        definition = matrix[row["table_code"]]

        # 1. The failure must be the PREDICTED failure, not merely a failure.
        if expect in ERROR_SIGNATURES:
            detail = row["detail"] or ""
            if not any(marker in detail for marker in ERROR_SIGNATURES[expect]):
                failures["errors with the wrong reason"].append(
                    "{} {}  expected {} whose text contains one of {}  :: {}".format(
                        key[0], key[1], expect, ERROR_SIGNATURES[expect], detail[:110]))

        if got != "SUCCESS":
            continue

        if int(row["row_count"] or 0) <= 0:
            failures["successes with no rows"].append("{} {}".format(*key))

        derived = shape.get((row["quote_key"], definition["line_filter"]))
        if derived is None:
            # Nothing below can be judged without it, and silently skipping the
            # row is how this checker used to lose coverage without saying so.
            failures["successes with no derived-shape entry"].append(
                "{} {}  filter {}".format(key[0], key[1], definition["line_filter"]))
            continue

        customized = bool(definition["row_customizer_code"] or definition["row_customizer_flow"])

        # 2. The grand total against an independently derived oracle.
        #
        # Derivable only where the printed net total is the sum of the surviving
        # lines: Final Value on a PRICE_WATERFALL table with no contributor
        # adding or re-bucketing rows. Everything else is skipped deliberately
        # rather than compared against a number this checker cannot derive - but
        # a row that IS derivable must produce both numbers, or it fails.
        derivable = (
            definition["amount_basis"] == "Final Value"
            and definition["measure_set"] == "PRICE_WATERFALL"
            and not customized
        )
        if derivable:
            expected_total = money(derived.get("netTotal"))
            raw_total = tagged(row["detail"], "total=")
            actual_total = money(raw_total)
            if expected_total is None:
                failures["derivable rows whose oracle total is missing or nonfinite"].append(
                    "{} {}  netTotal={}".format(key[0], key[1], derived.get("netTotal")))
            elif raw_total is None:
                failures["derivable rows with no printed total"].append(
                    "{} {}  detail :: {}".format(key[0], key[1], (row["detail"] or "")[:80]))
            elif actual_total is None:
                failures["derivable rows with a blank, unparseable or nonfinite total"].append(
                    "{} {}  total={!r}".format(key[0], key[1], raw_total))
            else:
                totals_compared += 1
                if abs(expected_total - actual_total) > TOTAL_TOLERANCE:
                    failures["wrong grand totals"].append(
                        "{} {}  expected {}  printed {}".format(
                            key[0], key[1], expected_total, actual_total))

        # 3. Depth, against the depth this shape REQUIRES.
        #
        # Every configured level emits a group row whenever the filter leaves
        # any line standing - one bucket is still a bucket, so a level is never
        # skipped for having a single value - which makes the emitted depth the
        # level count exactly, and zero when no line survives.
        configured = len(definition["levels"].split(">"))
        reported = int(row["depth"] or 0)
        surviving = int(derived.get("lines") or 0)
        bundle = "BUNDLE" in definition["levels"]

        if not bundle and not customized:
            depths_compared += 1
            expected_depth = configured if surviving else 0
            if reported != expected_depth:
                failures["wrong depth"].append(
                    "{} {}  configured {}  lines {}  expected {}  reported {}".format(
                        key[0], key[1], configured, surviving, expected_depth, reported))
        else:
            # Bounded, and counted as bounded. A BUNDLE level indents its
            # details by an option level this checker cannot see, so it keeps a
            # floor but not a ceiling; a customizer regroups the rows entirely
            # and may legitimately flatten them, so it gets no floor at all.
            depths_bounded += 1
            ceiling = configured + (BUNDLE_INDENT_ALLOWANCE if bundle else 0)
            floor = configured if (bundle and surviving) else 0
            if reported > ceiling or reported < floor:
                failures["depth outside the bounds this shape allows"].append(
                    "{} {}  configured {}  lines {}  allowed {}..{}  reported {}".format(
                        key[0], key[1], configured, surviving, floor, ceiling, reported))

        # 4. The render contract's own invariant, counted in the payload by the
        #    harness. Searching the ledger's detail column for '(unnamed)' never
        #    worked: that column carries the total and the reuse flag, not labels.
        unnamed = tagged(row["detail"], "unnamed=")
        if unnamed is None:
            failures["ledger rows missing the unnamed-label count"].append("{} {}".format(*key))
        elif unnamed != "0":
            failures["literal '(unnamed)' in a payload"].append(
                "{} {}  {} rows".format(key[0], key[1], unnamed))

    not_run = set(expectations) - seen
    if not_run:
        failures["expectations with no ledger row"].extend("{} {}".format(*k) for k in sorted(not_run))

    print("\noutcome distribution:")
    for outcome, count in sorted(collections.Counter(r["outcome"] for r in ledger).items()):
        print("   {:<16} {}".format(outcome, count))
    print("\ngrand totals compared against the derived oracle: {}".format(totals_compared))
    print("depths compared for equality: {}".format(depths_compared))
    print("depths bounds-checked (bundle indent or row customizer): {}".format(depths_bounded))

    if failures:
        print("")
        for bucket in sorted(failures):
            rows = failures[bucket]
            print("{} ({}):".format(bucket.upper(), len(rows)))
            for line in rows[:12]:
                print("   {}".format(line))
            if len(rows) > 12:
                print("   ... and {} more".format(len(rows) - 12))
        print("\nFAIL")
        return 1

    print("\nOK: every outcome matched the expectation authored before the run, every predicted")
    print("failure failed for the predicted reason, every derivable grand total matched an oracle")
    print("computed from the persisted fixture values, and every derivable depth equalled the one")
    print("its definition and fixture require.")
    return 0


# ---------------------------------------------------------------------------
# The check on the check
# ---------------------------------------------------------------------------

CORRUPTIONS = (
    "baseline",
    "unrelated_errors",
    "wrong_totals",
    "missing_totals",
    "blank_totals",
    "nan_totals",
    "shallow_depth",
    "missing_oracle",
)


def _corrupt(case, original, shape_text):
    """One corrupted copy of the results: the rows, the oracle, and what changed."""
    import re

    rows = [dict(row) for row in original]
    changed = 0
    for row in rows:
        before = dict(row)
        if case == "unrelated_errors" and row["outcome"] == "ERROR":
            row["detail"] = "System.NullPointerException: unrelated failure"
        elif row["outcome"] == "SUCCESS":
            if case == "wrong_totals":
                row["detail"] = re.sub(r"total=\S*", "total=999999999999", row["detail"])
            elif case == "missing_totals":
                row["detail"] = re.sub(r"total=\S*\s*", "", row["detail"])
            elif case == "blank_totals":
                row["detail"] = re.sub(r"total=\S*", "total=", row["detail"])
            elif case == "nan_totals":
                row["detail"] = re.sub(r"total=\S*", "total=NaN", row["detail"])
            elif case == "shallow_depth" and int(row["depth"] or 0) > 1:
                row["depth"] = "1"
        changed += row != before

    text = shape_text
    if case == "missing_oracle":
        kept = [line for line in text.splitlines() if not line.startswith("QDTD-Q1|")]
        changed = len(text.splitlines()) - len(kept)
        text = "\n".join(kept) + "\n"
    return rows, text, changed


def selftest():
    import contextlib
    import io
    import tempfile

    with (RESULTS / "ledger.csv").open(encoding="utf-8") as stream:
        reader = csv.DictReader(stream)
        fields, original = reader.fieldnames, list(reader)
    shape_text = (RESULTS / "derived-shape.txt").read_text(encoding="utf-8")

    undetected = []
    for case in CORRUPTIONS:
        rows, text, changed = _corrupt(case, original, shape_text)
        with tempfile.TemporaryDirectory(prefix="qdt-selftest-") as folder:
            target = pathlib.Path(folder)
            for name in ("matrix.csv", "expectations.csv"):
                (target / name).write_bytes((RESULTS / name).read_bytes())
            (target / "derived-shape.txt").write_text(text, encoding="utf-8")
            with (target / "ledger.csv").open("w", newline="", encoding="utf-8") as stream:
                writer = csv.DictWriter(stream, fieldnames=fields)
                writer.writeheader()
                writer.writerows(rows)
            captured = io.StringIO()
            with contextlib.redirect_stdout(captured):
                code = main(target)
        wanted = 0 if case == "baseline" else 1
        ok = code == wanted
        if not ok:
            undetected.append(case)
        print("{:<18} corrupted {:>5}  exit {}  {}".format(
            case, changed, code,
            "ok" if ok else ("BROKE THE BASELINE" if case == "baseline" else "UNDETECTED")))
        for line in captured.getvalue().splitlines():
            if "compared" in line:
                print("      " + line.strip())

    if undetected:
        print("\nFAIL: the checker did not reject {}".format(", ".join(undetected)))
        return 1
    print("\nOK: every corruption was rejected and the real results still pass.")
    return 0


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv[1:] else main())
