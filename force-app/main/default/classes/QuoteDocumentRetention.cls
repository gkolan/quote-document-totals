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

    return Database.getQueryLocator(
      [
        SELECT Id
        FROM Quote_Document_Table__c
        WHERE
          Quote__r.SBQQ__Status__c IN ('Rejected', 'Denied')
          OR (Generated_On__c < :cutoff
          AND Quote__r.SBQQ__Status__c != 'Accepted')
      ]
    );
  }

  /**
   * Deleting the table cascades its rows and columns away through the
   * master-detail, so neither has to be handled here.
   *
   * BLOCKS AND FACTS DO NOT CASCADE. Both hang off the Quote by a lookup, not
   * off a Table. They are deleted explicitly in the same transaction, so a
   * quote is never reset to Not Generated while still owning narrative text
   * or header values from the retired snapshot.
   */
  public void execute(
    Database.BatchableContext context,
    List<Quote_Document_Table__c> scope
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
    // The parent quotes are locked FOR UPDATE before anything is deleted, so
    // a status change cannot land between the recheck and the delete. Lock
    // order matches generation's - the Quote first, its children after.
    Set<Id> scopeIds = new Set<Id>();
    Set<Id> parentQuoteIds = new Set<Id>();
    for (Quote_Document_Table__c table : [
      SELECT Id, Quote__c
      FROM Quote_Document_Table__c
      WHERE Id IN :scope
    ]) {
      scopeIds.add(table.Id);
      parentQuoteIds.add(table.Quote__c);
    }
    if (scopeIds.isEmpty()) {
      return;
    }

    for (SBQQ__Quote__c locked : [
      SELECT Id
      FROM SBQQ__Quote__c
      WHERE Id IN :parentQuoteIds
      FOR UPDATE
    ]) {
      parentQuoteIds.add(locked.Id);
    }

    // The SAME predicate start() used, re-evaluated against current state.
    // Written once here rather than duplicated in prose, so the two cannot
    // drift apart: a table is purged only if it still qualifies now.
    List<Quote_Document_Table__c> confirmed = [
      SELECT Id, Quote__c
      FROM Quote_Document_Table__c
      WHERE
        Id IN :scopeIds
        AND (Quote__r.SBQQ__Status__c IN ('Rejected', 'Denied')
        OR (Generated_On__c < :cutoff
        AND Quote__r.SBQQ__Status__c != 'Accepted'))
    ];
    if (confirmed.isEmpty()) {
      return;
    }

    // Blocks are deleted only for quotes whose tables are actually going.
    // Deriving this from the SCOPE rather than from `confirmed` would strip
    // the narrative text off a quote whose snapshot just survived the
    // recheck - the precise failure this whole method now guards against.
    Set<Id> quoteIds = new Set<Id>();
    for (Quote_Document_Table__c table : confirmed) {
      quoteIds.add(table.Quote__c);
    }

    delete confirmed;

    // A quote is only finished with once its LAST table has gone. A batch
    // chunk can hold some of a quote's tables and not the others, and the
    // recheck above can spare one table of a set - either way, deleting the
    // narrative and resetting the quote to Not Generated here would leave
    // surviving tables with no terms beside them, on a quote that claims
    // nothing was ever generated.
    for (Quote_Document_Table__c surviving : [
      SELECT Quote__c
      FROM Quote_Document_Table__c
      WHERE Quote__c IN :quoteIds
    ]) {
      quoteIds.remove(surviving.Quote__c);
    }
    if (quoteIds.isEmpty()) {
      return;
    }

    delete [SELECT Id FROM Quote_Document_Block__c WHERE Quote__c IN :quoteIds];
    delete [SELECT Id FROM Quote_Document_Fact__c WHERE Quote__c IN :quoteIds];

    // A quote whose tables have gone is Not Generated again, not Ready.
    // Leaving it Ready would let a document action run against nothing.
    List<SBQQ__Quote__c> reset = new List<SBQQ__Quote__c>();
    for (Id quoteId : quoteIds) {
      reset.add(
        new SBQQ__Quote__c(
          Id = quoteId,
          Document_Data_Status__c = 'Not Generated',
          Document_Data_Generated_On__c = null
        )
      );
    }
    if (!reset.isEmpty()) {
      update reset;
    }
  }

  public void finish(Database.BatchableContext context) {
    // Nothing to do. The job record in Apex Jobs is the audit trail.
  }
}
