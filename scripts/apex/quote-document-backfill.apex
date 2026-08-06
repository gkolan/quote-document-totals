/**
 * Backfills generated document tables for quotes that already exist.
 *
 * Use this after a first deployment, or after adding a table definition, when
 * historical quotes need tables they never had.
 *
 *   sf apex run --target-org gkCPQDev --file scripts/apex/quote-document-backfill.apex
 *
 * WHY generateAsync AND NOT generate
 * ----------------------------------
 * generate() does every quote in one transaction. That is right for a button
 * and wrong here: a hundred quotes at a few hundred rows each blows the 10,000
 * DML row limit. generateAsync queues one Queueable per quote, so row volume
 * scales with the largest single quote rather than with the size of the batch.
 *
 * LIMITS
 * ------
 * A synchronous context can only queue 50 Queueables, so this script caps the
 * batch. Re-run it until the count of quotes still needing tables reaches zero,
 * or convert it to a Batchable if you are backfilling thousands.
 */

Integer batchSize = 50;

// Only quotes with lines - a quote with nothing on it produces six empty
// tables, which is noise rather than data.
List<SBQQ__Quote__c> pending = [
    SELECT Id, Name
    FROM SBQQ__Quote__c
    WHERE SBQQ__LineItemCount__c > 0
      AND Id NOT IN (SELECT Quote__c FROM Quote_Document_Table__c)
    ORDER BY CreatedDate DESC
    LIMIT :batchSize
];

if (pending.isEmpty()) {
    System.debug('Nothing to backfill - every quote with lines already has tables.');
} else {
    Set<Id> quoteIds = new Set<Id>();
    for (SBQQ__Quote__c quote : pending) {
        quoteIds.add(quote.Id);
    }

    QuoteDocumentGenerator.generateAsync(quoteIds);

    Integer remaining = [
        SELECT COUNT()
        FROM SBQQ__Quote__c
        WHERE SBQQ__LineItemCount__c > 0
          AND Id NOT IN (SELECT Quote__c FROM Quote_Document_Table__c)
    ] - pending.size();

    System.debug('Queued ' + pending.size() + ' quotes. Roughly ' + remaining
        + ' still to do - re-run this script until that reaches zero.');
    System.debug('Watch progress in Setup > Apex Jobs, or re-query '
        + 'SBQQ__Quote__c.Document_Data_Status__c.');
}
