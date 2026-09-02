#!/usr/bin/env bash
set -euo pipefail

# Optional demo setup for a disposable Salesforce CPQ test org. Deploys this
# repo, seeds demo data, runs the examples listed below, and runs selected Apex
# tests. For the shortest first installation, use docs/quick-start.md instead.
#
# Prerequisites (not something this script can do for you):
#   1. Salesforce CLI installed - `sf --version` should work.
#   2. Bash (for example Git Bash on Windows).
#   3. For creation mode only, a Dev Hub authenticated and set as default:
#        sf org login web --set-default-dev-hub --alias DevHub
#   4. Salesforce CPQ installed, configured, and accessible in the target org.
#      This script does not install CPQ. A newly created scratch org normally
#      needs that separate setup; the CPQ check stops before project deployment.
#      Install/configure CPQ through your organization's supported process,
#      then resume with --existing-org and the same alias.
#
# Usage:
#   bash scripts/scratch-org-bootstrap.sh [org-alias] [duration-days]
#   bash scripts/scratch-org-bootstrap.sh cpqDemo 7
#   bash scripts/scratch-org-bootstrap.sh --existing-org cpqDemo
#
# Existing-org mode reruns deployment and demo setup. The seed script deletes
# Accounts whose names end in [SEED], their Quotes, and SEED-* Products before
# rebuilding them. Worked examples also replace their own output. Use only a
# disposable test org, never production or an org containing valuable data.

if [[ "${1:-}" == "--existing-org" ]]; then
  if [[ $# -ne 2 || -z "$2" ]]; then
    echo "Usage: bash scripts/scratch-org-bootstrap.sh --existing-org <test-org-alias>" >&2
    exit 1
  fi
  ORG_ALIAS="$2"
  echo "=== 1/6  Use existing disposable test org ($ORG_ALIAS) ==="
else
  ORG_ALIAS="${1:-cpqDemo}"
  DURATION_DAYS="${2:-7}"
  echo "=== 1/6  Create scratch org ($ORG_ALIAS, ${DURATION_DAYS}d) ==="
  sf org create scratch \
    --definition-file config/project-scratch-def.json \
    --alias "$ORG_ALIAS" \
    --duration-days "$DURATION_DAYS" \
    --set-default
fi

if ! sf sobject describe --sobject SBQQ__Quote__c --target-org "$ORG_ALIAS" >/dev/null; then
  echo "CPQ Quote is not accessible. Install/configure CPQ and verify access before continuing." >&2
  echo "Then run: bash scripts/scratch-org-bootstrap.sh --existing-org $ORG_ALIAS" >&2
  exit 1
fi

echo "=== 2/6  Deploy all metadata ==="
sf project deploy start --target-org "$ORG_ALIAS" --source-dir force-app --wait 30

echo "=== 3/6  Assign the CPQ Document Totals permission set ==="
sf org assign permset --target-org "$ORG_ALIAS" --name CPQ_Document_Totals

echo "=== 4/6  Seed base CPQ demo data and generate real totals ==="
echo "         (5 accounts, 18 products, 5 quotes - calls QuoteDocumentGenerator for each)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/quote-document-seed.apex

echo "=== 5/6  Build the selected hand-written worked examples ==="
echo "         (docs/*.md - each script deletes and rebuilds only its own table code(s))"
echo "         5a. Transaction, bundle, and product change examples (use cases 20-23)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/quote-line-type-bundle-example.apex
echo "         5b. Product Family Summary (use case 01)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/product-family-summary-example.apex
echo "         5c. Charge Type Summary (use case 02)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/charge-type-summary-example.apex
echo "         5d. Bundle Detail (use case 04)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/bundle-detail-example.apex
echo "         5e. Quote Group and Family Detail (use case 05)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/group-family-detail-example.apex
echo "         5f. Optional Products (use case 07)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/optional-products-example.apex
echo "         5g. Family and Billing Composite (use case 06)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/family-billing-composite-example.apex
echo "         5h. Discount Summary (use case 03)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/discount-summary-example.apex
echo "         5i. Row Customizer Example (use case 43)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/row-customizer-example.apex
echo "         5j. Industry Allegiance Example (extension recipes)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/industry-allegiance-example.apex
echo "         5k. Rounding Example (extension recipes)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/rounding-example.apex
echo "         5l. Discount Example (extension recipes)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/discount-example.apex
echo "         5m. Best/Worst Case Showcase (docs/testing-guide.md)"
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/best-worst-case-showcase.apex
echo "         5m (settle). CPQ's own async rollup recalculation needs a moment to finish"
echo "              before the showcase quotes' Ready status is stable - see that script's"
echo "              own header comment for why this can't be one script."
sleep 10
sf apex run --target-org "$ORG_ALIAS" --file scripts/apex/best-worst-case-showcase-settle.apex

echo "=== 6/6  Run selected Apex tests ==="
sf apex run test \
  --target-org "$ORG_ALIAS" \
  --class-names QuoteDocumentGeneratorTest \
  --class-names QuoteDocumentLifecycleTest \
  --class-names QuoteDocumentRowCustomizerTest \
  --class-names QuoteDocumentIndustryRowCustomizerTest \
  --class-names QuoteDocumentRoundingRowCustomizerTest \
  --class-names QuoteDocumentDiscountRowCustomizerTest \
  --result-format human \
  --wait 30 \
  --code-coverage

echo
echo "Demo commands completed. If a test run Id was returned without results, retrieve and review it before claiming success."
echo "Opening the org..."
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
  - Use the numbered guides linked from docs/use-case/README.md for exact
    configuration, expected results, and generation checks.
  - Pre-built reports deploy in Reports > CPQ Document Totals. Each use-case
    guide names its report. Add a Quote filter to check a specific Quote.
  - Query Quote_Document_Table__c / Quote_Document_Row__c directly (Setup >
    Object Manager, or the Developer Console query editor) to see the raw
    rows, if you need something the pre-built reports don't show.
  - Before pointing a DocuSign/CLM template at any of this, follow the
    relevant guide's "Generate and verify" steps: confirm
    Document_Data_Status__c = 'Ready' on the quote you're testing with.

EOF
