/**
 * Controlled mapping from a Row_Customizer_Code__c value to the customizer
 * that implements it. Replaces the former Type.forName(Row_Customizer_Class__c)
 * dynamic lookup - metadata holds a code, Apex owns the mapping, so a rename
 * shows up as a compile error here instead of a runtime "class not found".
 *
 * See docs/use-case/43-registered-apex-row-adjustment.md.
 */
public with sharing class QuoteDocumentRowCustomizerRegistry {
    public static QuoteDocumentRowCustomizer resolve(String customizerCode) {
        switch on customizerCode {
            when 'DISCOUNT_EXAMPLE'      { return new QuoteDocumentDiscountRowCustomizer(); }
            when 'INDUSTRY_ALLEGIANCE'   { return new QuoteDocumentIndustryRowCustomizer(); }
            when 'ROUNDING_EXAMPLE'      { return new QuoteDocumentRoundingRowCustomizer(); }
            when 'ESTIMATED_TAX'         { return new QuoteDocumentEstimatedTaxRowCustomizer(); }
            when 'MONTHLY_SUBSCRIPTION'  { return new QuoteDocumentMonthlyRowCustomizer(); }
            when 'PACKAGE_COMPOSITION'   { return new QuoteDocumentCompositionCustomizer(); }
            // The Flow bridge. Reachable this way for a table whose only
            // contributor is a Flow referenced through Row_Customizer_Code__c,
            // though the ordinary path is Row_Customizer_Flow__c, which the
            // generator runs after any Apex customizer - see step 01A section 7.
            when 'FLOW'                  { return new QuoteDocumentFlowRowCustomizer(); }
            when else {
                throw new QuoteDocumentGenerator.QuoteDocumentException(
                    'Unknown row customizer code: ' + customizerCode
                );
            }
        }
    }
}
