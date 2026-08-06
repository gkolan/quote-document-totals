/**
 * Controlled mapping from a Row_Customizer_Code__c value to the customizer
 * that implements it. Replaces the former Type.forName(Row_Customizer_Class__c)
 * dynamic lookup - metadata holds a code, Apex owns the mapping, so a rename
 * shows up as a compile error here instead of a runtime "class not found".
 *
 * See specs/quote-docusign-launch/spec.md Increment 4.
 */
public with sharing class QuoteDocumentRowCustomizerRegistry {
    public static QuoteDocumentRowCustomizer resolve(String customizerCode) {
        switch on customizerCode {
            when 'DISCOUNT_EXAMPLE'      { return new QuoteDocumentDiscountRowCustomizer(); }
            when 'INDUSTRY_ALLEGIANCE'   { return new QuoteDocumentIndustryRowCustomizer(); }
            when 'ROUNDING_EXAMPLE'      { return new QuoteDocumentRoundingRowCustomizer(); }
            when 'ESTIMATED_TAX'         { return new QuoteDocumentEstimatedTaxRowCustomizer(); }
            when else {
                throw new QuoteDocumentGenerator.QuoteDocumentException(
                    'Unknown row customizer code: ' + customizerCode
                );
            }
        }
    }
}
