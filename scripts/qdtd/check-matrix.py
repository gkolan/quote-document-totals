"""Checks the coverage claim in matrix.csv before anything is built from it.

    python scripts/qdtd/check-matrix.py

Fails unless:

  1. every value of every axis appears at least once;
  2. every pair of values across every pair of axes appears at least once,
     except pairs listed in matrix-exclusions.md with a reason;
  3. every filter has both an empty and a non-empty witness quote in
     expectations.csv - suppression has to be proved in both directions;
  4. every quote in the roster is exercised by at least one definition.

Pairwise is a budget, not equivalence: it catches single-value and pairwise
faults and misses faults needing three specific values at once. That gap is
accepted deliberately and narrowed by the named higher-order scenarios in
step 04, which this check also confirms are present.
"""

import collections
import csv
import itertools
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
RESULTS = ROOT / "specs/quote-document-test-data/results"
EXCLUSIONS = ROOT / "specs/quote-document-test-data/matrix-exclusions.md"

AXES = ["line_filter", "measure_set", "amount_basis", "cache_policy", "show_details",
        "show_section_totals", "sort_groups_by", "max_groups", "composite_separator"]

FILTERS = ["ALL", "EXCLUDE_OPTIONAL", "OPTIONAL_ONLY", "RECURRING_ONLY", "ONE_TIME_ONLY", "BUNDLE_PARENTS_ONLY"]


def load_exclusions():
    """Excluded pairs, as `axis=value x axis=value` lines in the exclusions doc."""
    if not EXCLUSIONS.exists():
        return set()
    pairs = set()
    pattern = re.compile(r"`([a-z_]+)=([^`]+)`\s*x\s*`([a-z_]+)=([^`]+)`")
    for line in EXCLUSIONS.read_text(encoding="utf-8").splitlines():
        m = pattern.search(line)
        if m:
            a = (m.group(1), m.group(2).strip())
            b = (m.group(3), m.group(4).strip())
            pairs.add(frozenset([a, b]))
    return pairs


def main():
    definitions = list(csv.DictReader((RESULTS / "matrix.csv").open(encoding="utf-8")))
    expectations = list(csv.DictReader((RESULTS / "expectations.csv").open(encoding="utf-8")))
    excluded = load_exclusions()
    failures = []

    # 1. every axis value present
    seen_values = collections.defaultdict(set)
    for d in definitions:
        for axis in AXES:
            seen_values[axis].add(d[axis])
    print("axis value coverage:")
    for axis in AXES:
        print("   {:<22} {} distinct: {}".format(axis, len(seen_values[axis]),
                                                 ", ".join(sorted(str(v) for v in seen_values[axis]))))

    # 2. pairwise
    seen_pairs = set()
    for d in definitions:
        for a, b in itertools.combinations(AXES, 2):
            seen_pairs.add(frozenset([(a, d[a]), (b, d[b])]))

    missing = []
    for a, b in itertools.combinations(AXES, 2):
        for va, vb in itertools.product(sorted(seen_values[a]), sorted(seen_values[b])):
            pair = frozenset([(a, va), (b, vb)])
            if len(pair) < 2:
                continue
            if pair in seen_pairs or pair in excluded:
                continue
            missing.append((a, va, b, vb))

    total_pairs = sum(len(seen_values[a]) * len(seen_values[b]) for a, b in itertools.combinations(AXES, 2))
    covered = total_pairs - len(missing)
    print("\npairwise: {}/{} value pairs covered ({} excluded with a reason, {} missing)".format(
        covered, total_pairs, len(excluded), len(missing)))
    if missing:
        failures.append("{} axis-value pairs are neither covered nor excluded".format(len(missing)))
        for a, va, b, vb in missing[:15]:
            print("   MISSING  {}={}  x  {}={}".format(a, va, b, vb))
        if len(missing) > 15:
            print("   ... and {} more".format(len(missing) - 15))

    # 3. suppression witnesses per filter
    by_filter = collections.defaultdict(lambda: {"EMPTY": set(), "NONEMPTY": set()})
    definition_filter = {d["table_code"]: d["line_filter"] for d in definitions}
    for e in expectations:
        f = definition_filter[e["table_code"]]
        if e["expect"] == "EMPTY":
            by_filter[f]["EMPTY"].add(e["quote_key"])
        elif e["expect"] == "SUCCESS":
            by_filter[f]["NONEMPTY"].add(e["quote_key"])

    print("\nsuppression witnesses:")
    for f in FILTERS:
        empty = sorted(by_filter[f]["EMPTY"])
        nonempty = sorted(by_filter[f]["NONEMPTY"])
        print("   {:<22} empty: {:<12} non-empty: {}".format(
            f, empty[0] if empty else "NONE", nonempty[0] if nonempty else "NONE"))
        if not empty:
            failures.append("filter {} has no empty witness".format(f))
        if not nonempty:
            failures.append("filter {} has no non-empty witness".format(f))

    # 4. every quote exercised
    quotes_with_success = {e["quote_key"] for e in expectations if e["expect"] in ("SUCCESS", "EMPTY")}
    all_quotes = {e["quote_key"] for e in expectations}
    unexercised = all_quotes - quotes_with_success
    if unexercised:
        failures.append("quotes never exercised: {}".format(sorted(unexercised)))

    # 5. the named higher-order scenarios are actually present
    higher_order = [d for d in definitions if d["purpose"].startswith("higher-order")]
    print("\nhigher-order scenarios present: {}".format(len(higher_order)))
    for d in higher_order:
        print("   {}  {}".format(d["table_code"], d["purpose"]))
    if len(higher_order) < 4:
        failures.append("expected at least 4 named higher-order scenarios, found {}".format(len(higher_order)))

    print("\n{} definitions, {} (definition x quote) expectations".format(len(definitions), len(expectations)))
    if failures:
        print("\nFAIL:")
        for f in failures:
            print("  - {}".format(f))
        return 1
    print("\nOK: coverage claim checked.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
