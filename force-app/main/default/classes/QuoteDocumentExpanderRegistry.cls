/**
 * Controlled mapping from an Expander_Code__c value to the expander that
 * implements it. Same shape and same reasoning as
 * QuoteDocumentRowCustomizerRegistry: metadata holds a code, Apex owns the
 * mapping, so renaming a class is a compile error here rather than a runtime
 * "class not found" on the first quote somebody generates.
 */
public with sharing class QuoteDocumentExpanderRegistry {

    public static QuoteDocumentLineExpander resolve(String expanderCode) {
        switch on expanderCode {
            when 'PERIOD'   { return new QuoteDocumentPeriodExpander(); }
            when 'SCHEDULE' { return new QuoteDocumentScheduleExpander(); }
            when else {
                throw new QuoteDocumentGenerator.QuoteDocumentException(
                    'Unknown expander code: ' + expanderCode + '. Register the class in '
                    + 'QuoteDocumentExpanderRegistry before naming it on a table definition.'
                );
            }
        }
    }
}
