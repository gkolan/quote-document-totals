#!/usr/bin/env bash
set -euo pipefail

# Bootstraps a fresh scratch org with this entire repo deployed, base CPQ demo
# data seeded and generated for real, and every hand-built worked example from
# every guide under docs/documentation-standards.md built - one command that
# reproduces everything, for every table this framework ships.
#
# Prerequisites (not something this script can do for you):
#   1. Salesforce CLI installed - `sf --version` should work.
#   2. A Dev Hub authenticated and set as default:
#        sf org login web --set-default-dev-hub --alias DevHub
#   3. Salesforce CPQ (the SBQQ__ managed package) available to install into
#      scratch orgs from that Dev Hub. This repo's Apex depends on the SBQQ__
#      namespace and does not install the package itself - if your Dev Hub
#      doesn't already have a CPQ-enabled scratch org feature/license, talk to
#      whoever manages your Salesforce CPQ subscription before running this.
#
# Usage:
#   scripts/scratch-org-bootstrap.sh [org-alias] [duration-days]
#   scripts/scratch-org-bootstrap.sh cpqDemo 7
#
# Safe to re-run with the same alias: every worked-example script in step 5 is
# itself idempotent - each deletes and rebuilds only its own table code(s) for
# its target quote, per docs/documentation-standards.md rule 5. Re-running
# step 1 against an alias that already exists will fail with an sf error
# telling you to delete it first - that's intentional, so you don't silently
# throw away a scratch org you were still using.
#
# One guide, one line here: whenever a new guide is added under
# docs/documentation-standards.md, its worked-example script gets one new
# line in step 5 below - never create a second bootstrap script.

ORG_ALIAS="${1:-cpqDemo}"
DURATION_DAYS="${2:-7}"

echo "=== 1/6  Create scratch org ($ORG_ALIAS, ${DURATION_DAYS}d) ==="
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias "$ORG_ALIAS" \
  --duration-days "$DURATION_DAYS" \
  --set-default

echo "=== 2/6  Deploy all metadata ==="
sf project deploy start --target-org "$ORG_ALIAS" --source-dir force-app

echo "=== 3/6  Assign the CPQ Document Totals permission set ==="
sf org assign permset --target-org "$ORG_ALIAS" --name CPQ_Document_Totals

echo "=== 4/6  Seed base CPQ demo data and generate real totals ==="
echo "         (5 accounts, 18 products, 5 quotes - calls QuoteDocumentGenerator for each)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/quote-document-seed.apex

echo "=== 5/6  Build every guide's hand-written worked example ==="
echo "         (docs/*.md - each script deletes and rebuilds only its own table code(s))"
echo "         5a. Transaction Type / Bundle & Product Grid / Bundle & Product Totals (quote-line-type-bundle-reporting-guide.md)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/quote-line-type-bundle-example.apex
echo "         5b. Product Family Summary (product-family-summary-guide.md)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/product-family-summary-example.apex
echo "         5c. Charge Type Summary (charge-type-summary-guide.md)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/charge-type-summary-example.apex
echo "         5d. Bundle Detail (bundle-detail-guide.md)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/bundle-detail-example.apex
echo "         5e. Quote Group and Family Detail (group-family-detail-guide.md)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/group-family-detail-example.apex
echo "         5f. Optional Products (optional-products-guide.md)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/optional-products-example.apex
echo "         5g. Family and Billing Composite (family-billing-composite-guide.md)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/family-billing-composite-example.apex
echo "         5h. Discount Summary (discount-summary-guide.md)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/discount-summary-example.apex
echo "         5i. Row Customizer Example (quote-document-row-customizer-guide.md)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/row-customizer-example.apex
echo "         5j. Industry Allegiance Example (quote-document-row-customizer-guide.md §12)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/industry-allegiance-example.apex
echo "         5k. Rounding Example (quote-document-row-customizer-guide.md §14)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/rounding-example.apex
echo "         5l. Discount Example (quote-document-row-customizer-guide.md §15)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/discount-example.apex
echo "         5m. Best/Worst Case Showcase (docs/best-and-worst-case-showcase.md)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/best-worst-case-showcase.apex
echo "         5m (settle). CPQ's own async rollup recalculation needs a moment to finish"
echo "              before the showcase quotes' Ready status is stable - see that script's"
echo "              own header comment for why this can't be one script."
sleep 10
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/best-worst-case-showcase-settle.apex

echo "=== 6/6  Run the Apex test suite for this feature ==="
sf apex run test \
  --target-org "$ORG_ALIAS" \
  --class-names QuoteDocumentGeneratorTest \
  --class-names QuoteDocumentLifecycleTest \
  --class-names QuoteDocumentRowCustomizerTest \
  --class-names QuoteDocumentIndustryRowCustomizerTest \
  --class-names QuoteDocumentRoundingRowCustomizerTest \
  --class-names QuoteDocumentDiscountRowCustomizerTest \
  --result-format human \
  --synchronous \
  --code-coverage

echo
echo "Done. Opening the org..."
sf org open --target-org "$ORG_ALIAS"

cat <<'EOF'

Where to look:

  - The "Ridgeline Manufacturing [SEED]" quote (largest of the 5 seeded quotes)
    has real generator output for the six originally-shipped tables
    (PRODUCT_FAMILY_SUMMARY, CHARGE_TYPE_SUMMARY, BUNDLE_DETAIL,
    GROUP_FAMILY_DETAIL, OPTIONAL_PRODUCTS, TRANSACTION_SUMMARY), plus the
    FAMILY_BILLING_COMPOSITE and DISCOUNT_SUMMARY tables' real output too. It
    also carries every
    hand-built illustrative example from step 5, sitting alongside that real
    output on the same quote - compare "what the generator does with real
    demo data today" against "the canonical example numbers used in each
    guide" side by side.
  - Each guide under docs/*.md has its own §"Verify" SOQL query and its own
    §"Review & score" self-assessment - use those to check any one view in
    isolation rather than re-deriving a query from scratch.
  - Ten pre-built reports deploy with the repo in Reports > CPQ Document
    Totals - one per view, already filtered to that view's Table_Code__c.
    Each guide's "Salesforce reports" section names the exact report to
    open; you do not need to build any report yourself. Open one and add a
    filter on Quote.Name to check a specific quote.
  - Query Quote_Document_Table__c / Quote_Document_Row__c directly (Setup >
    Object Manager, or the Developer Console query editor) to see the raw
    rows, if you need something the pre-built reports don't show.
  - Before pointing a DocuSign/CLM template at any of this, re-read the
    relevant guide's "Before trusting it" step: confirm
    Document_Data_Status__c = 'Ready' on the quote you're testing with.

EOF
