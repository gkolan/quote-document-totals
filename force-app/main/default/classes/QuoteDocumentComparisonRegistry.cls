/**
 * Controlled mapping from a Comparison_Source_Code__c value to the source that
 * implements it. Same closed-registry shape as the customizer and expander
 * registries: a rename is a compile error here, not a runtime failure on
 * somebody's quote.
 */
public with sharing class QuoteDocumentComparisonRegistry {

    public static QuoteDocumentComparisonSource resolve(String sourceCode) {
        switch on sourceCode {
            when 'SOURCE_QUOTE' { return new QuoteDocumentSourceQuoteComparison(); }
            when else {
                throw new QuoteDocumentGenerator.QuoteDocumentException(
                    'Unknown comparison source code: ' + sourceCode + '. Register the class in '
                    + 'QuoteDocumentComparisonRegistry before naming it on a table definition.'
                );
            }
        }
    }
}
