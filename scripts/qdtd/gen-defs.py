"""Generates the TDX_* custom metadata from the checked matrix.

    python scripts/qdtd/gen-defs.py

Reads specs/quote-document-test-data/results/matrix.csv and writes, into
force-app/main/default/customMetadata/:

    Quote_Document_Table_Def.TDX_###.md-meta.xml
    Quote_Document_Grouping.TDX_###_L#_P#.md-meta.xml

Every definition is written with Is_Active__c = false. Activation is the
harness's job, one slice at a time, because the loader validates every ACTIVE
definition in a single pass - so an active-but-broken record breaks generation
for every quote in the org, not just its own table (step 05).

Step 05 originally said Node, on the grounds that scripts/ci/*.js establishes
that toolchain. The rest of the qdtd tooling ended up in Python, and a lone Node
script here would mean two languages for one pipeline, so this is Python. The
reasoning in step 05 stands; only the language changed.

Run scripts/qdtd/check-matrix.py first: nothing should be generated from an
unchecked coverage claim.
"""

import csv
import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[2]
MATRIX = ROOT / "specs/quote-document-test-data/results/matrix.csv"
OUT = ROOT / "force-app/main/default/customMetadata"

HEADER = ('<?xml version="1.0" encoding="UTF-8"?>\n'
          '<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" '
          'xmlns:xsd="http://www.w3.org/2001/XMLSchema" '
          'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\n')


def field(name, value, xsd_type):
    return ("    <values>\n"
            "        <field>{}</field>\n"
            "        <value xsi:type=\"xsd:{}\">{}</value>\n"
            "    </values>\n").format(name, xsd_type, value)


def escape(text):
    return (str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def table_def_xml(row, order):
    code = row["table_code"]
    xml = HEADER
    xml += "    <label>{}</label>\n".format(escape("QDTD " + code))
    xml += "    <protected>false</protected>\n"
    xml += field("Table_Code__c", code, "string")
    xml += field("Table_Name__c", escape("QDTD permutation " + code), "string")
    # The printed heading. Kept literal here, matching every shipped definition -
    # the render contract's dictionary covers column headings and row labels, and
    # no shipped Table_Def resolves its title through it either.
    xml += field("Display_Title__c", escape("QDTD {} - {}".format(code, row["purpose"])), "string")
    xml += field("Amount_Basis__c", escape(row["amount_basis"]), "string")
    xml += field("Line_Filter__c", row["line_filter"], "string")
    xml += field("Measure_Set__c", row["measure_set"], "string")
    xml += field("Show_Details__c", row["show_details"], "boolean")
    xml += field("Show_Section_Totals__c", row["show_section_totals"], "boolean")
    xml += field("Sort_Groups_By__c", row["sort_groups_by"], "string")
    xml += field("Max_Groups__c", row["max_groups"], "double")
    xml += field("Composite_Separator__c", escape(row["composite_separator"]), "string")
    xml += field("Cache_Policy__c", row["cache_policy"], "string")
    # Emitted unconditionally, even when empty. A custom metadata deploy only
    # SETS the fields the file contains - it does not clear the ones it omits -
    # so dropping a field here leaves the previous deployment's value in the org.
    # That is exactly how one definition ended up carrying dependency paths from
    # an earlier generation while its policy had been changed to STANDARD, a
    # combination validateContributorConfig rejects outright.
    xml += field("Row_Customizer_Code__c", row["row_customizer_code"], "string")
    xml += field("Row_Customizer_Version__c", row["row_customizer_version"], "string")
    xml += field("Row_Customizer_Flow__c", row["row_customizer_flow"], "string")
    xml += field("Row_Customizer_Flow_Version__c", row["row_customizer_flow_version"], "string")
    xml += field("Contributor_Dependency_Set__c", escape(row["contributor_dependency_set"]), "string")
    # Inactive on deploy. The harness activates a slice at a time.
    xml += field("Is_Active__c", "false", "boolean")
    # Display_Order__c is a 3-digit field, so the TDX block starts at 100 -
    # comfortably after the shipped definitions (10-40) and still in range.
    xml += field("Display_Order__c", 100 + order, "double")
    xml += "</CustomMetadata>\n"
    return xml


def grouping_xml(code, level_index, part_index, dimension, sequence):
    xml = HEADER
    xml += "    <label>{}</label>\n".format(escape("{} L{} P{}".format(code, level_index, part_index)))
    xml += "    <protected>false</protected>\n"
    xml += field("Table_Definition__c", code, "string")
    xml += field("Dimension__c", dimension, "string")
    xml += field("Level__c", level_index, "double")
    xml += field("Sequence__c", sequence, "double")
    xml += "</CustomMetadata>\n"
    return xml


def main():
    rows = list(csv.DictReader(MATRIX.open(encoding="utf-8")))

    # Clear previously generated TDX files, so a removed matrix row does not
    # leave an orphan definition behind in source.
    removed = 0
    for existing in OUT.glob("Quote_Document_*.TDX_*.md-meta.xml"):
        existing.unlink()
        removed += 1

    definitions = 0
    groupings = 0
    for order, row in enumerate(rows, start=1):
        code = row["table_code"]
        (OUT / "Quote_Document_Table_Def.{}.md-meta.xml".format(code)).write_text(
            table_def_xml(row, order), encoding="utf-8")
        definitions += 1

        # levels: '>' nests, '+' makes a composite bucket within one level.
        for level_index, level in enumerate(row["levels"].split(">"), start=1):
            for part_index, dimension in enumerate(level.split("+"), start=1):
                name = "Quote_Document_Grouping.{}_L{}_P{}.md-meta.xml".format(code, level_index, part_index)
                (OUT / name).write_text(
                    grouping_xml(code, level_index, part_index, dimension, part_index * 10),
                    encoding="utf-8")
                groupings += 1

    print("removed {} previously generated TDX files".format(removed))
    print("wrote {} table definitions and {} groupings (all Is_Active__c = false)".format(
        definitions, groupings))


if __name__ == "__main__":
    main()
