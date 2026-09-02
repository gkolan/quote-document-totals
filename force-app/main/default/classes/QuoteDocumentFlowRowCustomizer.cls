/**
 * Bridges an autolaunched Flow into the row-contribution seam, so a table's
 * rows can be changed declaratively with no Apex at all.
 *
 * The Flow named in Row_Customizer_Flow__c receives the in-memory rows and
 * returns them. Uninserted Quote_Document_Row__c records survive the round
 * trip intact - order, Decimal scale, null-vs-zero, Booleans, and fields core
 * never populates - which is not an assumption but a proven one: see
 * QuoteDocumentFlowRoundTripProbeTest and step 01A section 4.
 *
 * THE ONE THING FLOW AUTHORS GET WRONG
 * ------------------------------------
 * A Flow loop variable is a COPY. Editing it inside the loop changes nothing.
 * A contributor Flow must collect rows into a second collection and assign
 * that back to `rows` at the end. This fails silently - the Flow runs, reports
 * success, and returns the rows unmodified - so it is called out here, in the
 * field help text, and in the extension recipe.
 *
 * TRUST
 * -----
 * A Flow is a trusted in-transaction extension, not a sandbox. It can perform
 * its own DML, run SOQL, or call an Apex action that does either. Core cannot
 * prevent that and does not claim to - step 01A section 2. What core owns is
 * the row insert, validation of what comes back, and rollback of the whole
 * attempt on failure.
 */
public with sharing class QuoteDocumentFlowRowCustomizer implements QuoteDocumentRowCustomizer {

    /** Matches the variable names the Flow must declare. Changing one is a breaking change to every contributor Flow. */
    @TestVisible
    private static final String VAR_ROWS = 'rows';

    public List<Quote_Document_Row__c> customize(QuoteDocumentRowCustomizerContext context) {
        String flowName = context.definition.rowCustomizerFlow;
        if (String.isBlank(flowName)) {
            return context.rows;
        }

        Map<String, Object> inputs = new Map<String, Object>{
            VAR_ROWS          => context.rows,
            'quoteId'         => String.valueOf(context.quote.Id),
            'tableCode'       => context.definition.tableCode,
            'locale'          => context.locale,
            'currencyIsoCode' => context.currencyIsoCode
        };

        Flow.Interview interview;
        try {
            interview = Flow.Interview.createInterview(flowName, inputs);
        } catch (Exception e) {
            // A missing, inactive, or misnamed Flow surfaces here rather than
            // at start(). Naming the API name matters more than the platform's
            // own message, which does not mention the table that referenced it.
            throw QuoteDocumentContributorError.build(
                QuoteDocumentContributorError.FLOW_UNAVAILABLE,
                'Table ' + context.definition.tableCode + ' names row customizer Flow "' + flowName
                    + '", which could not be started. Check the Flow exists, is an autolaunched Flow, '
                    + 'and has an active version. Underlying error: ' + e.getMessage()
            );
        }

        try {
            interview.start();
        } catch (Exception e) {
            throw QuoteDocumentContributorError.build(
                QuoteDocumentContributorError.FLOW_FAULT,
                'Row customizer Flow "' + flowName + '" for table ' + context.definition.tableCode
                    + ' failed while running. Nothing was saved for this quote. Underlying error: ' + e.getMessage()
            );
        }

        Object returned = interview.getVariableValue(VAR_ROWS);

        // Null is not "unchanged". An Apex customizer may return null to mean
        // that, because returning nothing is a deliberate, visible choice in
        // code. A Flow returning nothing almost always means the author never
        // assigned the output collection - the exact silent-copy mistake above -
        // so reading it as "unchanged" would ship a document missing every
        // change the author believed they had made.
        if (returned == null) {
            throw QuoteDocumentContributorError.build(
                QuoteDocumentContributorError.NO_OUTPUT,
                'Row customizer Flow "' + flowName + '" for table ' + context.definition.tableCode
                    + ' returned no "' + VAR_ROWS + '" collection. The Flow must declare "' + VAR_ROWS
                    + '" as Available for Output and assign to it before finishing. Remember a loop '
                    + 'variable is a copy: collect rows into a second collection and assign that back to "'
                    + VAR_ROWS + '".'
            );
        }

        return (List<Quote_Document_Row__c>) returned;
    }
}
