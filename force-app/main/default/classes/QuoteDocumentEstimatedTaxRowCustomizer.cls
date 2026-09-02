/**
 * Reference implementation of QuoteDocumentRowCustomizer, attached to the
 * ROW_CUSTOMIZER_EXAMPLE table definition. Walked through in full in
 * docs/quote-document-extension-recipes.md - read that guide before using
 * this class as a template for a real implementation.
 *
 * Adds a flat-rate estimated tax row that has no corresponding
 * SBQQ__QuoteLine__c and so cannot be produced by any Line_Filter__c /
 * grouping / measure combination alone - exactly the situation this
 * extension point exists for. The row is Row_Type__c = 'Informational' with
 * both inclusion flags false (set by QuoteDocumentRowCustomizerContext.newRow
 * because 'Informational' is not 'Detail'), so it prints on the document
 * without being part of the grand-total reconciliation every table is still
 * held to after a customizer runs.
 */
public class QuoteDocumentEstimatedTaxRowCustomizer implements QuoteDocumentRowCustomizer {

    @TestVisible
    private static final Decimal TAX_RATE = 0.08;

    public List<Quote_Document_Row__c> customize(QuoteDocumentRowCustomizerContext context) {
        Decimal netAmount = 0;
        for (Quote_Document_Row__c row : context.rows) {
            if (row.Row_Type__c == 'Grand Total') {
                Decimal value = (Decimal) row.get('Amount_Net__c');
                netAmount = value == null ? 0 : value;
                break;
            }
        }

        Quote_Document_Row__c taxRow = context.newRow(
            'Informational', 0, 'ESTIMATED_TAX',
            'Estimated Tax (' + (TAX_RATE * 100) + '%, informational only)'
        );
        taxRow.Amount_Net__c = (netAmount * TAX_RATE).setScale(2);

        return context.rows;
    }
}
