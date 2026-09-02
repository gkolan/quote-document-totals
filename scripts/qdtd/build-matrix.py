"""Builds the step-04 permutation matrix and its per-quote expectations.

    python scripts/qdtd/build-matrix.py

Writes:

    specs/quote-document-test-data/results/matrix.csv        one row per TDX definition
    specs/quote-document-test-data/results/expectations.csv  one row per (definition x quote)

Nothing is generated as metadata until check-matrix.py passes on these two
files, which is the order step 04 insists on: the coverage claim is checked
before anything is built from it.

Expectations are per (definition x quote) because Max_Groups__c THROWS rather
than truncating (QuoteDocumentRowBuilder.cls:165), so one definition is a
success on a small quote and a failure on a large one.
"""

import csv
import itertools
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
RESULTS = ROOT / "specs/quote-document-test-data/results"

FILTERS = ["ALL", "EXCLUDE_OPTIONAL", "OPTIONAL_ONLY", "RECURRING_ONLY", "ONE_TIME_ONLY", "BUNDLE_PARENTS_ONLY"]
MEASURES = ["PRICE_WATERFALL", "CHANGE"]
# Amount_Basis__c is a RESTRICTED picklist on Quote_Document_Table__c. Its real
# values are Net Change / Final Value / TCV / ACV / First-Year Value /
# Remaining-Term Value / Recurring Value / One-Time Value - "List Value" and
# "Customer Value" were invented and every table insert using them was rejected
# at run time. Three real values, one of them the CHANGE-shaped Net Change.
BASES = ["Final Value", "Net Change", "TCV"]
DIMENSIONS = ["PRODUCT_FAMILY", "CHARGE_TYPE", "QUOTE_LINE_GROUP", "BUNDLE", "TRANSACTION_TYPE", "INDUSTRY"]

QUOTES = ["QDTD-Q{}".format(i) for i in range(1, 20)]

# Lines surviving each filter, and the distinct values each dimension yields
# AFTER that filter, read from results/derived-shape.txt.
#
# That file is produced by running the production classes against the fixtures -
# QuoteDocumentQuery builds the lines, QuoteDocumentLine.matchesFilter decides
# survival, getGroupingValue decides the buckets. The first version of this file
# used hand-estimated counts and was wrong twice over: BUNDLE_PARENTS_ONLY is
# `isPackage || !isBundledComponent`, so it keeps every standalone line rather
# than only bundle parents; and grouping happens AFTER filtering, so the distinct
# values have to be counted on the surviving lines, not on the whole quote.
#
# Derived from the code's own semantics, never from the ledger: reading outcomes
# back into expectations would make the comparison meaningless.
def load_derived():
    lines_after = {}
    groups_after = {}
    totals = {}
    counted = {}
    path = RESULTS / "derived-shape.txt"
    for raw in path.read_text(encoding="utf-8").splitlines():
        if not raw.strip():
            continue
        parts = raw.split("|")
        quote, line_filter = parts[0], parts[1]
        lines_after.setdefault(quote, {})[line_filter] = int(parts[2].split("=")[1])
        totals.setdefault(quote, {})[line_filter] = float(parts[3].split("=")[1])
        counted.setdefault(quote, {})[line_filter] = int(parts[4].split("=")[1])
        for chunk in parts[5:]:
            dimension, count = chunk.split("=")
            groups_after.setdefault((quote, line_filter), {})[dimension] = int(count)
    return lines_after, groups_after, totals, counted


LINES_AFTER_FILTER, GROUPS_AFTER_FILTER, NET_TOTAL_AFTER_FILTER, COUNTED_AFTER_FILTER = load_derived()

ERR_MAX_GROUPS = "ERROR_MAX_GROUPS"
ERR_MEASURE_SET = "ERROR_INDUSTRY_ON_CHANGE"
ERR_COUNTED_ROW = "ERROR_COUNTED_ROW"
ERR_DETAILS_DROPPED = "ERROR_DETAILS_DROPPED"

# QuoteDocumentIndustryRowCustomizer.emitBucket writes only a Group Header and a
# Subtotal per bucket, after context.rows.clear() has discarded everything - so
# the detail rows are gone. On a Show_Details__c = true table, verification then
# reconciles the grand total against detail rows that no longer exist and throws.
# The shipped INDUSTRY_ALLEGIANCE definition sets Show_Details__c = false, which
# is why this never showed up before; the class header's claim that the
# reconciliation "still has to pass, and does" holds only for details-off tables.
# One definition keeps details on deliberately, as a predicted failure that
# documents the gap.

# Quotes whose net total is not a whole number, so the rounding customizer
# actually has a remainder to add a row for. Computed from the persisted
# fixture-totals.csv, not assumed.
# Contributors that REPLACE the row set rather than appending to it. The
# industry customizer clears context.rows and re-emits headers and subtotals
# only, so the detail rows are gone and verification's grand-total-vs-details
# check cannot pass. The sample Flow contributor does NOT do this - it appends,
# and its details-on tables reconcile fine, which the run confirmed.
ROW_REPLACING_CUSTOMIZERS = {"INDUSTRY_ALLEGIANCE"}

# Customizers that add a COUNTED row. On a PRICE_WATERFALL + EXCLUDE_OPTIONAL
# table, QuoteDocumentVerification rejects those, because CPQ's own
# SBQQ__NetAmount__c knows nothing about the added row - see
# QuoteDocumentVerification.cls:109-110 and each customizer's class header.
COUNTED_ROW_CUSTOMIZERS = {"DISCOUNT_EXAMPLE", "ROUNDING_EXAMPLE", "ESTIMATED_TAX"}


class Definition(dict):
    pass


def define(code, purpose, **kw):
    d = Definition({
        "table_code": code,
        "purpose": purpose,
        "line_filter": "ALL",
        "measure_set": "PRICE_WATERFALL",
        "amount_basis": "Final Value",
        "cache_policy": "STANDARD",
        "show_details": "true",
        "show_section_totals": "false",
        "sort_groups_by": "ALPHABETICAL",
        "max_groups": 50,
        "composite_separator": " / ",
        "levels": "PRODUCT_FAMILY",          # '>' nests, '+' composites within a level
        "row_customizer_code": "",
        "row_customizer_flow": "",
        "row_customizer_version": "",
        "row_customizer_flow_version": "",
        "contributor_dependency_set": "",
    })
    d.update(kw)

    # The loader refuses a contributor without a version token, and refuses
    # DECLARED_DEPENDENCIES without dependency paths (and paths without that
    # policy). Fill those in here so every generated definition is valid by
    # construction - the negatives are Apex tests, not deployed metadata.
    if d["row_customizer_code"] and not d["row_customizer_version"]:
        d["row_customizer_version"] = "1"
    if d["row_customizer_flow"] and not d["row_customizer_flow_version"]:
        d["row_customizer_flow_version"] = "1"
    if d["cache_policy"] == "DECLARED_DEPENDENCIES" and not d["contributor_dependency_set"]:
        d["contributor_dependency_set"] = "SBQQ__Account__r.Industry"
    if d["cache_policy"] != "DECLARED_DEPENDENCIES":
        d["contributor_dependency_set"] = ""
    return d


def build_definitions():
    defs = []
    n = 0

    def nxt():
        nonlocal n
        n += 1
        return "TDX_{:03d}".format(n)

    # 1. Exhaustive on the three axes that genuinely interact: 6 x 2 x 3 = 36.
    for f, m, b in itertools.product(FILTERS, MEASURES, BASES):
        defs.append(define(nxt(), "filter x measure x basis", line_filter=f, measure_set=m, amount_basis=b))

    # 2. Exhaustive on nesting depth 1..5, plus a 3-part composite at level 3.
    depth_dims = ["PRODUCT_FAMILY", "CHARGE_TYPE", "BUNDLE", "TRANSACTION_TYPE", "INDUSTRY"]
    for depth in range(1, 6):
        defs.append(define(nxt(), "nesting depth {}".format(depth),
                           levels=">".join(depth_dims[:depth]), max_groups=500))
    defs.append(define(nxt(), "5 levels with a 3-part composite at level 3",
                       levels="PRODUCT_FAMILY>CHARGE_TYPE>BUNDLE+TRANSACTION_TYPE+INDUSTRY>PRODUCT_FAMILY>CHARGE_TYPE",
                       max_groups=500))

    # 3. Display axes, pairwise.
    display = [
        ("details off, section totals on", {"show_details": "false", "show_section_totals": "true"}),
        ("details on, section totals on", {"show_details": "true", "show_section_totals": "true"}),
        ("details off, section totals off", {"show_details": "false", "show_section_totals": "false"}),
        ("line-sequence sort", {"sort_groups_by": "LINE_SEQUENCE"}),
        ("line-sequence sort with details off", {"sort_groups_by": "LINE_SEQUENCE", "show_details": "false"}),
        ("custom composite separator", {"composite_separator": " - ", "levels": "PRODUCT_FAMILY+CHARGE_TYPE"}),
        ("tight group ceiling", {"max_groups": 3}),
        ("ceiling of one", {"max_groups": 1}),
    ]
    for purpose, kw in display:
        defs.append(define(nxt(), purpose, **kw))

    # 4. One per contributor entry point.
    for purpose, kw in [
        # PRICE_WATERFALL + EXCLUDE_OPTIONAL is the one place verify() rejects a
        # customizer-added counted row, and both these classes say in their own
        # header not to attach there. ALL keeps them off that combination.
        ("apex customizer - discount", {"row_customizer_code": "DISCOUNT_EXAMPLE", "line_filter": "ALL"}),
        ("apex customizer - estimated tax", {"row_customizer_code": "ESTIMATED_TAX"}),
        ("apex customizer - rounding", {"row_customizer_code": "ROUNDING_EXAMPLE", "line_filter": "ALL"}),
        ("apex customizer - industry key-value map", {"row_customizer_code": "INDUSTRY_ALLEGIANCE",
                                                      "show_details": "false"}),
        ("industry customizer on a details-on table - expected detail-row rejection",
         {"row_customizer_code": "INDUSTRY_ALLEGIANCE", "show_details": "true"}),
        ("flow customizer - interface pattern", {"row_customizer_flow": "QuoteDocumentSampleFlowContributor",
                                                 "cache_policy": "ALWAYS_REBUILD"}),
        ("industry customizer on a CHANGE table - expected failure",
         {"row_customizer_code": "INDUSTRY_ALLEGIANCE", "measure_set": "CHANGE"}),
    ]:
        defs.append(define(nxt(), purpose, **kw))

    # 5. Cache policies, including the sequences that only mean anything across runs.
    for purpose, kw in [
        ("cache STANDARD, reuse then invalidate", {"cache_policy": "STANDARD"}),
        ("cache ALWAYS_REBUILD", {"cache_policy": "ALWAYS_REBUILD"}),
        ("cache DECLARED_DEPENDENCIES", {"cache_policy": "DECLARED_DEPENDENCIES",
                                         "row_customizer_code": "INDUSTRY_ALLEGIANCE",
                                         "show_details": "false"}),
    ]:
        defs.append(define(nxt(), purpose, **kw))

    # 6. Named higher-order scenarios from step 04, beyond what pairwise reaches.
    for purpose, kw in [
        ("higher-order 1: CHANGE x EXCLUDE_OPTIONAL x 3 levels",
         {"measure_set": "CHANGE", "line_filter": "EXCLUDE_OPTIONAL",
          "levels": "TRANSACTION_TYPE>PRODUCT_FAMILY>CHARGE_TYPE", "max_groups": 500}),
        ("higher-order 2: waterfall x exclude-optional x rounding - expected counted-row rejection",
         {"measure_set": "PRICE_WATERFALL", "line_filter": "EXCLUDE_OPTIONAL",
          "show_section_totals": "true", "row_customizer_code": "ROUNDING_EXAMPLE"}),
        ("higher-order 4: line-sequence x bundle x depth 5",
         {"sort_groups_by": "LINE_SEQUENCE", "levels": "BUNDLE>PRODUCT_FAMILY>CHARGE_TYPE>INDUSTRY>TRANSACTION_TYPE",
          "max_groups": 500}),
        ("higher-order 5: locale x narrative x section totals",
         {"show_section_totals": "true", "levels": "PRODUCT_FAMILY>CHARGE_TYPE", "max_groups": 500}),
    ]:
        defs.append(define(nxt(), purpose, **kw))

    # 7. Pairwise fill. The five hand-designed groups above cover what matters
    # semantically, but leave axis-value pairs untouched (a filter that never
    # meets ALWAYS_REBUILD, say). Rather than hand-write those, fill them
    # greedily: take an uncovered pair, then pack as many other uncovered pairs
    # into the same definition as its already-assigned axes allow.
    defs.extend(pairwise_fill(defs, nxt))

    return defs


AXIS_VALUES = {
    "line_filter": FILTERS,
    "measure_set": MEASURES,
    "amount_basis": BASES,
    "cache_policy": ["STANDARD", "ALWAYS_REBUILD", "DECLARED_DEPENDENCIES"],
    "show_details": ["true", "false"],
    "show_section_totals": ["true", "false"],
    "sort_groups_by": ["ALPHABETICAL", "LINE_SEQUENCE"],
    "max_groups": [1, 3, 50, 500],
    "composite_separator": [" / ", " - "],
}


def covered_pairs(defs):
    seen = set()
    for d in defs:
        for a, b in itertools.combinations(AXIS_VALUES, 2):
            seen.add(frozenset([(a, str(d[a])), (b, str(d[b]))]))
    return seen


def all_pairs():
    pairs = []
    for a, b in itertools.combinations(AXIS_VALUES, 2):
        for va, vb in itertools.product(AXIS_VALUES[a], AXIS_VALUES[b]):
            pairs.append(frozenset([(a, str(va)), (b, str(vb))]))
    return pairs


UNSATISFIABLE = []


def pairwise_fill(defs, nxt):
    """Greedy set cover over the uncovered axis-value pairs.

    Some pairs cannot be built at all - DECLARED_DEPENDENCIES needs a
    contributor, and the industry customizer refuses a CHANGE measure set, so a
    definition asking for both is rejected by the loader rather than generated.
    Those are dropped and recorded in matrix-exclusions.md with the reason, which
    is what check-matrix.py reads; they are never silently ignored.
    """
    added = []
    seen = covered_pairs(defs)
    remaining = [p for p in all_pairs() if p not in seen]

    while remaining:
        target = remaining[0]
        assigned = {axis: value for axis, value in target}

        for pair in remaining[1:]:
            (a1, v1), (a2, v2) = tuple(pair)
            if assigned.get(a1, v1) == v1 and assigned.get(a2, v2) == v2:
                assigned[a1] = v1
                assigned[a2] = v2

        kw = dict(assigned)
        if "max_groups" in kw:
            kw["max_groups"] = int(kw["max_groups"])
        # DECLARED_DEPENDENCIES is invalid without a contributor and a dependency
        # set - the loader rejects it, so give it the industry customizer.
        if kw.get("cache_policy") == "DECLARED_DEPENDENCIES":
            kw.setdefault("row_customizer_code", "INDUSTRY_ALLEGIANCE")
            kw["show_details"] = "false"
            if kw.get("measure_set") == "CHANGE":
                kw["row_customizer_code"] = ""
                kw["cache_policy"] = "STANDARD"
        definition = define(nxt(), "pairwise fill", **kw)
        added.append(definition)

        # Incremental: only this definition's own pairs can have become covered.
        for a, b in itertools.combinations(AXIS_VALUES, 2):
            seen.add(frozenset([(a, str(definition[a])), (b, str(definition[b]))]))

        if target not in seen:
            # The adjustments above (a contributor added, a policy downgraded)
            # moved the definition off the pair that asked for it. It cannot be
            # built; record why and stop trying, or this loops forever.
            UNSATISFIABLE.append(target)
            seen.add(target)

        remaining = [pair for pair in remaining if pair not in seen]

    return added


def predicted_groups(levels, quote, line_filter):
    """Upper bound on groups the builder counts, mirroring how it accumulates.

    QuoteDocumentRowBuilder counts groups as the tree is built, adding each
    level's distinct values, and a composite multiplies its parts - which is
    exactly what its own error message warns about.
    """
    per_dimension = GROUPS_AFTER_FILTER.get((quote, line_filter), {})
    total = 0
    running = 1
    for level in levels.split(">"):
        size = 1
        for part in level.split("+"):
            size *= max(per_dimension.get(part, 1), 1)
        running *= size
        total += running
    return total


def expectation(definition, quote):
    """What this definition should do on this quote, and why."""
    lines = LINES_AFTER_FILTER[quote][definition["line_filter"]]

    if definition["row_customizer_code"] == "INDUSTRY_ALLEGIANCE" and definition["measure_set"] == "CHANGE":
        return ERR_MEASURE_SET, "industry customizer refuses a CHANGE table by design"

    if (definition["row_customizer_code"] in COUNTED_ROW_CUSTOMIZERS
            and definition["measure_set"] == "PRICE_WATERFALL"
            and definition["line_filter"] == "EXCLUDE_OPTIONAL"):
        # Only rejected when the customizer actually adds a row. The rounding
        # customizer adds one only where there is a remainder to absorb, so on a
        # quote whose total is already whole it contributes nothing and the table
        # builds cleanly.
        total = NET_TOTAL_AFTER_FILTER.get(quote, {}).get(definition["line_filter"], 0.0)
        # QuoteDocumentRoundingRowCustomizer.ROUND_TO_NEAREST is 100, and it
        # returns the rows untouched when the delta is zero - so a row is only
        # added when the grand total is not already a multiple of 100.
        needs_rounding = abs(total - round(total / 100.0) * 100.0) > 1e-9
        if definition["row_customizer_code"] != "ROUNDING_EXAMPLE" or needs_rounding:
            return ERR_COUNTED_ROW, "verify() rejects a customizer-added counted row on this combination"

    if definition["row_customizer_code"] in ROW_REPLACING_CUSTOMIZERS and definition["show_details"] == "true":
        # With no counted lines there are no buckets to emit, so the customizer
        # leaves nothing behind to contradict the grand total.
        if COUNTED_AFTER_FILTER.get(quote, {}).get(definition["line_filter"], 0) > 0:
            return ERR_DETAILS_DROPPED, "industry customizer replaces the row set, so a details-on table cannot reconcile"

    if lines == 0:
        return "EMPTY", "no lines survive {}".format(definition["line_filter"])

    groups = predicted_groups(definition["levels"], quote, definition["line_filter"])
    if groups > int(definition["max_groups"]):
        return ERR_MAX_GROUPS, "predicted {} groups over ceiling {}".format(groups, definition["max_groups"])

    return "SUCCESS", ""


def main():
    RESULTS.mkdir(parents=True, exist_ok=True)
    definitions = build_definitions()

    with (RESULTS / "matrix.csv").open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(definitions[0].keys()))
        writer.writeheader()
        writer.writerows(definitions)

    rows = []
    for d in definitions:
        for quote in QUOTES:
            outcome, why = expectation(d, quote)
            rows.append({"table_code": d["table_code"], "quote_key": quote, "expect": outcome, "reason": why})

    with (RESULTS / "expectations.csv").open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=["table_code", "quote_key", "expect", "reason"])
        writer.writeheader()
        writer.writerows(rows)

    if UNSATISFIABLE:
        lines = ["# Matrix exclusions",
                 "",
                 "Axis-value pairs that cannot be built as a valid table definition, and so",
                 "are excluded from the pairwise claim. `check-matrix.py` reads this file;",
                 "a pair missing from the matrix and absent here is a failure.",
                 "",
                 "GENERATED by scripts/qdtd/build-matrix.py.",
                 ""]
        for pair in UNSATISFIABLE:
            (a1, v1), (a2, v2) = tuple(pair)
            lines.append("- `{}={}` x `{}={}` - rejected at config load: DECLARED_DEPENDENCIES".format(a1, v1, a2, v2))
            lines.append("  requires a contributor, and the industry customizer refuses a CHANGE")
            lines.append("  measure set, so no definition can hold both values at once.")
        (ROOT / "specs/quote-document-test-data/matrix-exclusions.md").write_text(
            chr(10).join(lines) + chr(10), encoding="utf-8")
        print("wrote matrix-exclusions.md  {} unbuildable pairs".format(len(UNSATISFIABLE)))

    counts = {}
    for r in rows:
        counts[r["expect"]] = counts.get(r["expect"], 0) + 1

    print("wrote matrix.csv       {} definitions".format(len(definitions)))
    print("wrote expectations.csv {} (definition x quote) rows".format(len(rows)))
    for k in sorted(counts):
        print("   {:<22} {}".format(k, counts[k]))


if __name__ == "__main__":
    main()
