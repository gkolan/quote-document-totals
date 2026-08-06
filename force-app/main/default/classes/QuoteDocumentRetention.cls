/**
 * Deletes generated tables for quotes that will never produce a document.
 *
 * Without this, rows accumulate forever: six tables across fifty thousand
 * quotes is millions of records that no one will ever read. Generated data is
 * disposable by design - the Quote Lines remain the source of truth and any
 * table can be rebuilt on demand - so deleting it costs nothing but storage
 * recovered.
 *
 * Two rules, both conservative:
 *   - the quote was rejected or denied, so no document is coming;
 *   - the data was generated longer ago than the retention window and the quote
 *     has not been accepted, so it is almost certainly abandoned.
 *
 * An accepted quote is never purged here. Its numbers may sit behind a signed
 * document, and that is not a judgement a scheduled job should make.
 *
 * Schedule it:
 *   System.schedule('Quote Document Retention', '0 0 2 * * ?', new QuoteDocumentRetention());
 */
public with sharing class QuoteDocumentRetention implements Database.Batchable<SObject>, Schedulable {

    /** Days of inactivity before generated data is considered abandoned. */
    @TestVisible
    private static Integer retentionDays = 90;

    public void execute(SchedulableContext context) {
        Database.executeBatch(this, 200);
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Datetime cutoff = System.now().addDays(-retentionDays);

        return Database.getQueryLocator([
            SELECT Id
            FROM Quote_Document_Table__c
            WHERE Quote__r.SBQQ__Status__c IN ('Rejected', 'Denied')
               OR (Generated_On__c < :cutoff AND Quote__r.SBQQ__Status__c != 'Accepted')
        ]);
    }

    /**
     * Deleting the table cascades its rows away through the master-detail, so
     * the row count never has to be handled here.
     */
    public void execute(Database.BatchableContext context, List<Quote_Document_Table__c> scope) {
        Set<Id> quoteIds = new Set<Id>();
        for (Quote_Document_Table__c table : [
            SELECT Quote__c FROM Quote_Document_Table__c WHERE Id IN :scope
        ]) {
            quoteIds.add(table.Quote__c);
        }

        delete scope;

        // A quote whose tables have gone is Not Generated again, not Ready.
        // Leaving it Ready would let a document action run against nothing.
        List<SBQQ__Quote__c> reset = new List<SBQQ__Quote__c>();
        for (Id quoteId : quoteIds) {
            reset.add(new SBQQ__Quote__c(
                Id = quoteId,
                Document_Data_Status__c = 'Not Generated',
                Document_Data_Generated_On__c = null
            ));
        }
        if (!reset.isEmpty()) {
            update reset;
        }
    }

    public void finish(Database.BatchableContext context) {
        // Nothing to do. The job record in Apex Jobs is the audit trail.
    }
}
