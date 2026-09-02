/**
 * Reference implementation of QuoteDocumentRowCustomizer for the Discount row
 * type. See docs/quote-document-extension-recipes.md before using this class
 * as a template for a real implementation.
 *
 * Applies a flat loyalty discount to whichever Detail row on the table has
 * the highest Amount_Net__c, and emits it as a Discount row tied to that
 * line's Quote_Line__c - the shape Discount is for: a counted row that
 * belongs to one specific line, unlike Rounding, which belongs to the whole
 * table (see QuoteDocumentRoundingRowCustomizer).
 *
 * Row_Type__c = 'Discount' with Include_In_Grand_Total__c = true is a leaf
 * contribution under QuoteDocumentGenerator.verify()'s reconciliation (see
 * AGGREGATE_ROW_TYPES) - so it is not enough to add the row and stop there.
 * Because this row is nested inside a group (Group_Level__c matches the
 * discounted line's own group) rather than sitting at the table level, the
 * discount also has to be folded directly into that group's own Subtotal
 * row, or the "sum of level-1 subtotals" reconciliation path would disagree
 * with the "sum of leaf contributions" path by exactly the discount amount.
 * The Grand Total row is updated the same way. This is the same discipline
 * QuoteDocumentIndustryRowCustomizer follows when it rebuilds subtotals.
 *
 * Deliberately does not attach to a PRICE_WATERFALL + EXCLUDE_OPTIONAL table,
 * for the same reason as the Rounding example: verify() rejects any
 * customizer-added counted row there, because CPQ's own SBQQ__NetAmount__c
 * has no knowledge of it.
 *
 * Scoped to Amount_Net__c only, matching the single-measure scope of
 * QuoteDocumentEstimatedTaxRowCustomizer and QuoteDocumentRoundingRowCustomizer.
 */
public class QuoteDocumentDiscountRowCustomizer implements QuoteDocumentRowCustomizer {

    @TestVisible
    private static final Decimal DISCOUNT_RATE = 0.05;

    public List<Quote_Document_Row__c> customize(QuoteDocumentRowCustomizerContext context) {
        Quote_Document_Row__c target = largestDetailRow(context.rows);
        if (target == null) {
            return context.rows;
        }

        Decimal targetAmount = (Decimal) target.get('Amount_Net__c');
        targetAmount = targetAmount == null ? 0 : targetAmount;
        Decimal discountAmount = -(targetAmount * DISCOUNT_RATE).setScale(2);

        // Nothing to discount - do not clutter the document with a zero-value row.
        if (discountAmount == 0) {
            return context.rows;
        }

        Integer groupLevel = Integer.valueOf(target.Group_Level__c);

        Quote_Document_Row__c discountRow = context.newRow(
            'Discount', groupLevel, 'DISCOUNT:' + target.Quote_Line__c,
            'Loyalty Discount - ' + target.Display_Label__c
        );
        // context.newRow defaults both inclusion flags to false for any type
        // other than Detail. Discount is a leaf, exactly like Detail - override
        // both explicitly rather than rely on the type-based default.
        discountRow.Quote_Line__c = target.Quote_Line__c;
        discountRow.Group_Dimension__c = target.Group_Dimension__c;
        discountRow.Group_Value__c = target.Group_Value__c;
        discountRow.Include_In_Grand_Total__c = true;
        discountRow.Include_In_Subtotal__c = true;
        discountRow.Amount_Net__c = discountAmount;

        applyToSubtotalAndGrandTotal(context.rows, target, discountAmount);

        return context.rows;
    }

    private Quote_Document_Row__c largestDetailRow(List<Quote_Document_Row__c> rows) {
        Quote_Document_Row__c largest;
        for (Quote_Document_Row__c row : rows) {
            if (row.Row_Type__c != 'Detail') {
                continue;
            }
            Decimal amount = (Decimal) row.get('Amount_Net__c');
            if (amount == null) {
                continue;
            }
            if (largest == null || amount > (Decimal) largest.get('Amount_Net__c')) {
                largest = row;
            }
        }
        return largest;
    }

    /**
     * The discount has to reach both of verify()'s independent reconciliation
     * paths: the target line's own group Subtotal (the path a nested leaf
     * relies on, since it has a group of its own) and the Grand Total (every
     * counted leaf's path). Both are updated directly rather than
     * recalculated, the same discipline QuoteDocumentGenerator.stampTable()
     * itself uses for the table's own measures.
     */
    private void applyToSubtotalAndGrandTotal(
        List<Quote_Document_Row__c> rows, Quote_Document_Row__c target, Decimal discountAmount
    ) {
        for (Quote_Document_Row__c row : rows) {
            Boolean isTargetsSubtotal = row.Row_Type__c == 'Subtotal'
                && row.Group_Level__c == target.Group_Level__c
                && row.Group_Value__c == target.Group_Value__c;
            if (isTargetsSubtotal || row.Row_Type__c == 'Grand Total') {
                Decimal current = (Decimal) row.get('Amount_Net__c');
                row.put('Amount_Net__c', (current == null ? 0 : current) + discountAmount);
            }
        }
    }
}
