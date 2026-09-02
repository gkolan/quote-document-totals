/**
 * Allocates a fixed package price down to the components inside it.
 *
 * A customer buys one package at one price. This table answers "what am I
 * actually getting, and what is each part of it worth" - software, training and
 * support each carrying a share of the package price rather than the zeroes
 * they normally show.
 *
 * THE DOUBLE-COUNT TRAP, WHICH IS THE WHOLE PROBLEM
 * -------------------------------------------------
 * Everywhere else in this framework a bundled component contributes NOTHING,
 * because its price is already inside its parent's - QuoteDocumentLine.countsIn
 * returns false for exactly that reason. Here the money moves the other way:
 * the components carry it and the PARENT must not, or the table totals the
 * package twice.
 *
 * So this customizer does two things that must happen together, and neither is
 * safe alone:
 *   - the parent's Detail row stops counting toward any total and keeps its
 *     amount for display, so a reader still sees the package price;
 *   - each component's Detail row starts counting, carrying its share.
 *
 * The table's grand total is then the sum of the components, which equals the
 * package price exactly once. QuoteDocumentVerification checks that
 * independently, so getting half of this right fails generation rather than
 * shipping a document that doubles the deal.
 *
 * HOW THE SHARE IS DECIDED
 * ------------------------
 * By each component's own list amount where the components have one, because
 * that is the closest thing to a defensible relative worth the quote already
 * contains. Otherwise evenly.
 *
 * **In practice that means evenly, and the guide must say so.** CPQ leaves
 * SBQQ__ListTotal__c at zero on a bundled component - its price lives in the
 * parent, which is the whole reason components are excluded from totals
 * everywhere else - so the weighted branch only fires in an org that populates
 * component amounts deliberately. This was measured, not assumed: the first
 * version of the test expected a 6,000/3,000/1,000 split from component list
 * prices and got 3,333.33 three times.
 *
 * "Evenly" is a policy, not a fact, and it is a policy a customer can disagree
 * with. Any guide for a table using this must state it in the words the
 * customer will read.
 *
 * Either way the shares sum back to the parent's amount exactly, with the
 * residual carried into the last component, so no cent is invented or lost.
 *
 * WHAT THIS IS NOT
 * ----------------
 * It is not a claim about cost, margin, or what any component would sell for
 * on its own. It is an allocation of a negotiated package price for display.
 * The guide for any table using it must say that in the words a customer will
 * read, because "Training: $4,000" looks exactly like a price and is not one.
 *
 * See specs/row-generation-extensibility/steps/step-02-allocation-primitive.md
 * section 3.5.
 */
public with sharing class QuoteDocumentCompositionCustomizer implements QuoteDocumentRowCustomizer {

    public static final String CODE = 'PACKAGE_COMPOSITION';

    public static final String ERR_NO_COMPONENTS = 'COMPOSITION_PACKAGE_HAS_NO_COMPONENTS';
    public static final String ERR_NO_PACKAGE = 'COMPOSITION_COMPONENT_HAS_NO_PACKAGE';
    public static final String ERR_FILTER = 'COMPOSITION_FILTER_UNSUPPORTED';

    public List<Quote_Document_Row__c> customize(QuoteDocumentRowCustomizerContext context) {
        // A composition table has to see the components, and every filter except
        // ALL removes them. Pointed at EXCLUDE_OPTIONAL it would silently print
        // packages with nothing inside them.
        if (!QuoteDocumentTableDefinition.FILTER_ALL.equals(context.definition.lineFilter)) {
            QuoteDocumentContributorError.fail(
                ERR_FILTER,
                'Table ' + context.definition.tableCode + ' allocates package prices to components but '
                    + 'uses Line_Filter__c ' + context.definition.lineFilter + ', which removes the '
                    + 'components. Use ALL: this table exists to print what is inside the package.'
            );
        }

        Map<Id, QuoteDocumentLine> packageByLineId = new Map<Id, QuoteDocumentLine>();
        Map<Id, List<QuoteDocumentLine>> componentsByPackageId = new Map<Id, List<QuoteDocumentLine>>();

        for (QuoteDocumentLine line : context.lines) {
            if (line.isPackage) {
                packageByLineId.put(line.quoteLineId, line);
            }
        }
        for (QuoteDocumentLine line : context.lines) {
            if (!line.isBundledComponent) {
                continue;
            }
            Id parentId = line.requiredByLineId;
            if (parentId == null || !packageByLineId.containsKey(parentId)) {
                QuoteDocumentContributorError.fail(
                    ERR_NO_PACKAGE,
                    'Line "' + line.productName + '" is a bundled component whose parent package is not on '
                        + 'this table. Its share would come from nowhere, and leaving it at zero would '
                        + 'print a component the customer is apparently getting for free.'
                );
            }
            if (!componentsByPackageId.containsKey(parentId)) {
                componentsByPackageId.put(parentId, new List<QuoteDocumentLine>());
            }
            componentsByPackageId.get(parentId).add(line);
        }

        if (componentsByPackageId.isEmpty()) {
            QuoteDocumentContributorError.fail(
                ERR_NO_COMPONENTS,
                'Table ' + context.definition.tableCode + ' allocates package prices to components, but no '
                    + 'line on this quote is a bundled component. The table would print packages with '
                    + 'nothing inside them, which reads as a document that failed to load.'
            );
        }

        Map<Id, Decimal> shareByComponentLineId = allocate(
            packageByLineId, componentsByPackageId, context.definition
        );

        for (Quote_Document_Row__c row : context.rows) {
            if (!'Detail'.equals(row.Row_Type__c) || row.Quote_Line__c == null) {
                continue;
            }

            if (packageByLineId.containsKey(row.Quote_Line__c)) {
                // The package keeps its printed amount and stops counting. Both
                // halves matter: dropping the amount hides the price the
                // customer agreed, and leaving it counted doubles the deal.
                row.Include_In_Subtotal__c = false;
                row.Include_In_Grand_Total__c = false;
                continue;
            }

            if (shareByComponentLineId.containsKey(row.Quote_Line__c)) {
                row.Include_In_Subtotal__c = true;
                row.Include_In_Grand_Total__c = true;
                row.Amount_Net__c = shareByComponentLineId.get(row.Quote_Line__c);
                row.Amount_Customer__c = shareByComponentLineId.get(row.Quote_Line__c);
            }
        }

        retotal(context);
        return context.rows;
    }

    /**
     * Each package's amount, split across its own components.
     *
     * Weighted by component list price where any is non-zero, evenly otherwise.
     * The choice is per package rather than per table: one bundle in a quote
     * may carry list prices on its options while another does not.
     */
    private static Map<Id, Decimal> allocate(
        Map<Id, QuoteDocumentLine> packageByLineId,
        Map<Id, List<QuoteDocumentLine>> componentsByPackageId,
        QuoteDocumentTableDefinition definition
    ) {
        Map<Id, Decimal> shareByComponentLineId = new Map<Id, Decimal>();

        for (Id packageId : componentsByPackageId.keySet()) {
            QuoteDocumentLine parent = packageByLineId.get(packageId);
            List<QuoteDocumentLine> components = componentsByPackageId.get(packageId);

            List<Decimal> weights = new List<Decimal>();
            Boolean anyListPrice = false;
            for (QuoteDocumentLine component : components) {
                Decimal listAmount = component.amountList == null ? 0 : component.amountList;
                anyListPrice = anyListPrice || listAmount != 0;
                weights.add(listAmount);
            }
            if (!anyListPrice) {
                weights.clear();
                for (Integer i = 0; i < components.size(); i++) {
                    weights.add(1);
                }
            }

            List<Decimal> shares = QuoteDocumentAllocation.split(parent.amountNet, weights, 2);

            // The check verify() cannot make: it reconciles the TABLE, and one
            // package's money landing in another package's components would
            // reconcile perfectly while every printed row was wrong.
            QuoteDocumentAllocation.reconcile(
                parent.amountNet, shares, 'Package "' + parent.productName + '"'
            );

            for (Integer i = 0; i < components.size(); i++) {
                shareByComponentLineId.put(components[i].quoteLineId, shares[i]);
            }
        }
        return shareByComponentLineId;
    }

    /**
     * Rebuilds every aggregate row from the leaves, because the customizer has
     * just changed which rows are leaves.
     *
     * Recomputed from the rows rather than from the lines: the rows are what a
     * reader adds up, so the totals have to agree with what is printed and not
     * with a second calculation over different inputs.
     */
    private static void retotal(QuoteDocumentRowCustomizerContext context) {
        List<String> measures =
            QuoteDocumentTableDefinition.measureFields(context.definition.measureSet);

        Map<String, Map<String, Decimal>> byGroupKey = new Map<String, Map<String, Decimal>>();
        Map<String, Decimal> grand = new Map<String, Decimal>();
        for (String measure : measures) {
            grand.put(measure, 0);
        }

        for (Quote_Document_Row__c row : context.rows) {
            if ('Group Header'.equals(row.Row_Type__c) || 'Subtotal'.equals(row.Row_Type__c)
                || 'Section Total'.equals(row.Row_Type__c) || 'Grand Total'.equals(row.Row_Type__c)) {
                continue;
            }
            if (row.Include_In_Grand_Total__c != true) {
                continue;
            }
            String key = row.Group_Key__c == null ? '' : row.Group_Key__c;
            if (!byGroupKey.containsKey(key)) {
                Map<String, Decimal> zeroed = new Map<String, Decimal>();
                for (String measure : measures) {
                    zeroed.put(measure, 0);
                }
                byGroupKey.put(key, zeroed);
            }
            for (String measure : measures) {
                Decimal value = (Decimal) row.get(measure);
                Decimal amount = value == null ? 0 : value;
                byGroupKey.get(key).put(measure, byGroupKey.get(key).get(measure) + amount);
                grand.put(measure, grand.get(measure) + amount);
            }
        }

        for (Quote_Document_Row__c row : context.rows) {
            if ('Subtotal'.equals(row.Row_Type__c)) {
                Map<String, Decimal> totals = byGroupKey.get(row.Group_Key__c);
                for (String measure : measures) {
                    row.put(measure, totals == null ? 0 : totals.get(measure));
                }
            } else if ('Grand Total'.equals(row.Row_Type__c)) {
                for (String measure : measures) {
                    row.put(measure, grand.get(measure));
                }
            }
        }
    }
}
