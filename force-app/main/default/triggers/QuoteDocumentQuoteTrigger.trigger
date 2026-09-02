/**
 * A Quote-level change only invalidates the tables when it changes what they
 * would contain - the watched-field list in QuoteDocumentStaleness decides.
 *
 * That check is also what stops this trigger re-entering: writing
 * Document_Data_Status__c fires it again, but the status fields are not
 * watched, so the second pass does nothing.
 */
trigger QuoteDocumentQuoteTrigger on SBQQ__Quote__c (after update) {
    QuoteDocumentStaleness.markStaleFromQuotes(Trigger.new, Trigger.oldMap);
}
