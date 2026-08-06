/**
 * Reference implementation of QuoteDocumentRowCustomizer for the Rounding row
 * type. Walked through in full in docs/quote-document-totals.md - read that
 * before using this class as a template for a real one.
 *
 * Rounds the table's Amount_Net__c grand total to the nearest ROUND_TO_NEAREST
 * (a clean $100 figure by default - a common ask for a document that should
 * print a round headline number) and adds a Rounding row carrying the
 * difference, so the printed rows foot exactly to the printed grand total
 * even though the grand total no longer matches the unrounded sum of the
 * underlying lines.
 *
 * The row is Row_Type__c = 'Rounding' with Include_In_Grand_Total__c = true,
 * Include_In_Subtotal__c = false, Group_Level__c = 0 - the shape
 * Rounding_Row_Shape enforces declaratively. QuoteDocumentGenerator.verify()
 * folds any such row into both of its independent reconciliation paths
 * automatically (see AGGREGATE_ROW_TYPES), so the grand-total-vs-subtotals
 * check still passes once the grand total itself is updated to the rounded
 * value, which this class does directly on the row already in context.rows.
 *
 * Deliberately does not attach to a PRICE_WATERFALL + EXCLUDE_OPTIONAL table:
 * verify() rejects a Rounding row there, because rounding away from CPQ's own
 * SBQQ__NetAmount__c is exactly the kind of silent discrepancy that check
 * exists to prevent. Use this on a table that does not carry that
 * reconciliation obligation - a subtotal-only summary, or a CHANGE-measures
 * table, for example.
 *
 * Scoped to Amount_Net__c only, matching the single-measure scope of
 * QuoteDocumentEstimatedTaxRowCustomizer. A real implementation that needs
 * every price-waterfall measure rounded consistently should decide its own
 * rounding policy per measure rather than copy this scope assumption.
 */
public class QuoteDocumentRoundingRowCustomizer implements QuoteDocumentRowCustomizer {

    /** Round to the nearest $100 - real seed-data totals are already whole dollars, so rounding to the nearest dollar would never produce a demonstrable adjustment. */
    @TestVisible
    private static final Decimal ROUND_TO_NEAREST = 100;

    public List<Quote_Document_Row__c> customize(QuoteDocumentRowCustomizerContext context) {
        Quote_Document_Row__c grandTotal;
        for (Quote_Document_Row__c row : context.rows) {
            if (row.Row_Type__c == 'Grand Total') {
                grandTotal = row;
                break;
            }
        }
        if (grandTotal == null) {
            return context.rows;
        }

        Decimal actual = (Decimal) grandTotal.get('Amount_Net__c');
        actual = actual == null ? 0 : actual;
        Decimal rounded = (actual / ROUND_TO_NEAREST).setScale(0, System.RoundingMode.HALF_UP) * ROUND_TO_NEAREST;
        Decimal delta = rounded - actual;

        // Nothing to adjust - do not clutter the document with a zero-value row.
        if (delta == 0) {
            return context.rows;
        }

        Quote_Document_Row__c roundingRow = context.newRow(
            'Rounding', 0, 'ROUNDING_ADJUSTMENT', 'Rounding Adjustment'
        );
        // context.newRow defaults both inclusion flags to false for any type
        // other than Detail. Rounding is the one type that must count toward
        // the grand total despite not being Detail - override explicitly.
        roundingRow.Include_In_Grand_Total__c = true;
        roundingRow.Include_In_Subtotal__c = false;
        roundingRow.Amount_Net__c = delta;

        grandTotal.Amount_Net__c = rounded;

        return context.rows;
    }
}
