/**
 * Deletes generated document data for quotes that will never produce a document.
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

  /**
   * Starts the retention batch from the scheduled entry point.
   * @param context Salesforce scheduling context
   */
  public void execute(SchedulableContext context) {
    Database.executeBatch(this, 200);
  }

  /**
   * Selects Quotes whose generated document data is eligible for retention.
   * @param context Salesforce batch context
   * @return Query locator for eligible Quote lifecycle roots
   */
  public Database.QueryLocator start(Database.BatchableContext context) {
    Datetime cutoff = System.now().addDays(-retentionDays);

    return Database.getQueryLocator(
      [
        SELECT Id
        FROM SBQQ__Quote__c
        WHERE
          (SBQQ__Status__c IN ('Rejected', 'Denied')
          AND Document_Data_Status__c != 'Not Generated')
          OR (Document_Data_Generated_On__c < :cutoff
          AND SBQQ__Status__c != 'Accepted')
      ]
    );
  }

  /**
   * Deleting each table cascades its rows and columns away through the
   * master-detail, so neither has to be handled here.
   *
   * BLOCKS AND FACTS DO NOT CASCADE. Both hang off the Quote by a lookup, not
   * off a Table. They are deleted explicitly in the same transaction, so a
   * quote is never reset to Not Generated while still owning narrative text
   * or header values from the retired snapshot.
   * @param context Salesforce batch context
   * @param scope Quote lifecycle roots selected by start
   */
  public void execute(
    Database.BatchableContext context,
    List<SBQQ__Quote__c> scope
  ) {
    Datetime cutoff = System.now().addDays(-retentionDays);

    // ELIGIBILITY IS RECHECKED HERE, not trusted from start().
    //
    // A batch selects its scope once and executes it later. A quote that
    // became Accepted in between is still in the scope this method was
    // handed, and deleting it anyway would break the one promise retention
    // makes: an accepted quote is never purged. The gap widened when block
    // deletion was added, because blocks carry the contractual text.
    //
    // The quotes are locked FOR UPDATE while eligibility is rechecked, so a
    // status change cannot land between the recheck and deletion. Lock order
    // matches generation's - the Quote first, its children after.
    Set<Id> scopeIds = quoteIdsFrom(scope);
    if (scopeIds.isEmpty()) {
      return;
    }

    // The SAME predicate start() used, re-evaluated against current state.
    // Selecting Quotes instead of one optional child type makes table-only,
    // block-only and mixed snapshots follow the same retention policy.
    List<SBQQ__Quote__c> confirmed = eligibleQuotes(scopeIds, cutoff);
    if (confirmed.isEmpty()) {
      return;
    }

    Set<Id> quoteIds = quoteIdsFrom(confirmed);
    deleteTables(quoteIds);
    deleteBlocks(quoteIds);
    deleteFacts(quoteIds);
    resetQuotes(quoteIds);
  }

  private static Set<Id> quoteIdsFrom(List<SBQQ__Quote__c> quotes) {
    Set<Id> quoteIds = new Set<Id>();
    if (quotes == null) {
      return quoteIds;
    }
    for (SBQQ__Quote__c quote : quotes) {
      if (quote != null && quote.Id != null) {
        quoteIds.add(quote.Id);
      }
    }
    return quoteIds;
  }

  private static List<SBQQ__Quote__c> eligibleQuotes(
    Set<Id> quoteIds,
    Datetime cutoff
  ) {
    return [
      SELECT Id
      FROM SBQQ__Quote__c
      WHERE
        Id IN :quoteIds
        AND ((SBQQ__Status__c IN ('Rejected', 'Denied')
        AND Document_Data_Status__c != 'Not Generated')
        OR (Document_Data_Generated_On__c < :cutoff
        AND SBQQ__Status__c != 'Accepted'))
      FOR UPDATE
    ];
  }

  private static void deleteTables(Set<Id> quoteIds) {
    List<Quote_Document_Table__c> tables = [
      SELECT Id
      FROM Quote_Document_Table__c
      WHERE Quote__c IN :quoteIds
    ];
    if (!tables.isEmpty()) {
      delete tables;
    }
  }

  private static void deleteBlocks(Set<Id> quoteIds) {
    List<Quote_Document_Block__c> blocks = [
      SELECT Id
      FROM Quote_Document_Block__c
      WHERE Quote__c IN :quoteIds
    ];
    if (!blocks.isEmpty()) {
      delete blocks;
    }
  }

  private static void deleteFacts(Set<Id> quoteIds) {
    List<Quote_Document_Fact__c> facts = [
      SELECT Id
      FROM Quote_Document_Fact__c
      WHERE Quote__c IN :quoteIds
    ];
    if (!facts.isEmpty()) {
      delete facts;
    }
  }

  private static void resetQuotes(Set<Id> quoteIds) {
    // A quote whose generated document has gone is Not Generated again, not
    // Ready. Leaving it Ready would let a document action run against nothing.
    List<SBQQ__Quote__c> reset = new List<SBQQ__Quote__c>();
    for (Id quoteId : quoteIds) {
      reset.add(
        new SBQQ__Quote__c(
          Id = quoteId,
          Document_Data_Status__c = 'Not Generated',
          Document_Data_Generated_On__c = null,
          Document_Data_Started_At__c = null,
          Document_Data_Fingerprint__c = null,
          Document_Payload_Hash__c = null
        )
      );
    }
    if (!reset.isEmpty()) {
      update reset;
    }
  }

  /**
   * Completes the batch without starting follow-on work.
   * @param context Salesforce batch context
   */
  public void finish(Database.BatchableContext context) {
    return;
  }
}
