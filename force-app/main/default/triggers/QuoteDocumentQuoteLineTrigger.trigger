/**
 * Any change to a Quote Line invalidates every generated table on its Quote.
 *
 * Thin on purpose: it collects Ids and hands off. All the judgement about what
 * counts as a meaningful change lives in QuoteDocumentStaleness, where it can
 * be read and tested without a DML operation.
 */
trigger QuoteDocumentQuoteLineTrigger on SBQQ__QuoteLine__c (
    after insert, after update, after delete, after undelete
) {
    QuoteDocumentStaleness.markStaleFromLines(
        Trigger.isDelete ? Trigger.old : Trigger.new
    );
}
