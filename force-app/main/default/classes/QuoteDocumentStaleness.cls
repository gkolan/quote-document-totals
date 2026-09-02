/**
 * Marks quotes whose generated document data no longer reflects the quote.
 *
 * This is the only thing the triggers do. If a regeneration is never run the
 * quote simply stays Stale and the document action stays closed - the failure
 * mode is a blocked document rather than a silently wrong one, which is the
 * right way round.
 *
 * Deliberately does NOT generate. CPQ writes a quote several times during one
 * calculation, so generating here would rebuild three to five times for one
 * user action and throw most of it away.
 *
 * WHY THE WRITE IS ASYNCHRONOUS
 * -----------------------------
 * A synchronous update to SBQQ__Quote__c from inside the Quote Line trigger
 * does not survive. CPQ's own QuoteLineAfter handler reads the quote, does its
 * calculation, and writes the quote back later in the same cascade - using the
 * copy it read before we wrote. Our Stale value is silently overwritten and the
 * quote reads Ready with out-of-date tables behind it.
 *
 * That was observed, not assumed: the trigger ran, the update executed, and the
 * committed value was still Ready. Deferring the write to a future method puts
 * it after the cascade has committed, where nothing can clobber it.
 */
// Trigger-driven invalidation must reliably close the document gate after a
// source edit. It reads only the publication identity/status and writes only
// Document_Data_Status__c; applying user-mode field checks here could leave a
// stale snapshot marked Ready when the editor cannot see the internal field.
@SuppressWarnings('PMD.ApexCRUDViolation')
public with sharing class QuoteDocumentStaleness {
  /**
   * Quote fields that change what a generated table would contain. Anything
   * outside this set - including the document status fields this class
   * writes - is ignored, which is what keeps the trigger from re-entering.
   */
  private static final Set<String> WATCHED_QUOTE_FIELDS = new Set<String>{
    'SBQQ__NetAmount__c',
    'SBQQ__ListAmount__c',
    'SBQQ__CustomerAmount__c',
    'AccountIndustry__c',
    'SBQQ__LineItemsGrouped__c',
    'SBQQ__ExpirationDate__c',
    'Document_Type__c',
    'Document_Revision__c',
    'Prior_Document_Reference__c'
  };

  /**
   * Statuses this must leave alone, for two different reasons.
   *
   * Not Generated and Stale have nothing generated behind them, so there is
   * nothing to invalidate.
   *
   * Generating is different: something IS behind it, and it is still being
   * written. This write lands from a future call, in its own transaction,
   * so it can overwrite an in-flight claim - and the only thing refusing a
   * second concurrent attempt is that same Generating marker. Clearing it
   * would let a second worker start, which is a race the FOR UPDATE lock on
   * the Quote otherwise prevents outright. A generation in flight resolves
   * to Ready or Failed on its own, and the edit that triggered this is then
   * caught by the fingerprint on the next generate-or-reuse.
   */
  private static final Set<String> NOT_WORTH_MARKING = new Set<String>{
    'Not Generated',
    'Stale',
    'Generating'
  };

  /**
   * Set while the generator writes its own status to the Quote. Without it
   * the generator's write would fire this class and mark the quote stale
   * from inside the generator's own DML.
   */
  private static Boolean suppressed = false;

  /** Quotes already handled in this transaction - one future call is enough. */
  private static Set<Id> handledThisTransaction = new Set<Id>();

  public static void suppress() {
    suppressed = true;
  }

  public static void resume() {
    suppressed = false;
  }

  // -----------------------------------------------------------------------
  // Trigger entry points
  // -----------------------------------------------------------------------

  /** Quote Lines: any change to any line invalidates every table. */
  public static void markStaleFromLines(List<SBQQ__QuoteLine__c> lines) {
    Set<Id> quoteIds = new Set<Id>();
    for (SBQQ__QuoteLine__c line : lines) {
      quoteIds.add(line.SBQQ__Quote__c);
    }
    markStale(quoteIds);
  }

  /** Quotes: only a change to a watched field matters. */
  public static void markStaleFromQuotes(
    List<SBQQ__Quote__c> updated,
    Map<Id, SBQQ__Quote__c> priorById
  ) {
    Set<Id> quoteIds = new Set<Id>();

    for (SBQQ__Quote__c quote : updated) {
      SBQQ__Quote__c prior = priorById.get(quote.Id);
      if (prior == null) {
        continue;
      }
      for (String field : WATCHED_QUOTE_FIELDS) {
        if (quote.get(field) != prior.get(field)) {
          quoteIds.add(quote.Id);
          break;
        }
      }
    }

    markStale(quoteIds);
  }

  /** Accounts: customer name and billing address are published header facts. */
  public static void markStaleFromAccounts(
    List<Account> updated,
    Map<Id, Account> priorById
  ) {
    Set<Id> changedAccountIds = new Set<Id>();
    for (Account account : updated) {
      Account prior = priorById.get(account.Id);
      if (
        prior != null &&
        (account.Name != prior.Name ||
        account.BillingStreet != prior.BillingStreet ||
        account.BillingCity != prior.BillingCity ||
        account.BillingState != prior.BillingState ||
        account.BillingPostalCode != prior.BillingPostalCode ||
        account.BillingCountry != prior.BillingCountry)
      ) {
        changedAccountIds.add(account.Id);
      }
    }
    if (changedAccountIds.isEmpty()) {
      return;
    }
    Set<Id> quoteIds = new Set<Id>();
    for (SBQQ__Quote__c quote : [
      SELECT Id
      FROM SBQQ__Quote__c
      WHERE SBQQ__Account__c IN :changedAccountIds
    ]) {
      quoteIds.add(quote.Id);
    }
    markStale(quoteIds);
  }

  // -----------------------------------------------------------------------

  public static void markStale(Set<Id> quoteIds) {
    if (suppressed) {
      return;
    }

    Set<Id> toMark = new Set<Id>(quoteIds);
    toMark.remove(null);
    toMark.removeAll(handledThisTransaction);

    if (toMark.isEmpty()) {
      return;
    }
    List<Id> ids = new List<Id>();
    List<String> requestIds = new List<String>();
    for (SBQQ__Quote__c quote : [
      SELECT Id, Document_Data_Status__c, Document_Data_Request_Id__c
      FROM SBQQ__Quote__c
      WHERE Id IN :toMark
    ]) {
      if (
        quote.Document_Data_Status__c == null ||
        NOT_WORTH_MARKING.contains(quote.Document_Data_Status__c)
      ) {
        continue;
      }
      ids.add(quote.Id);
      // Future parameters are serialized. Keep nulls out of the primitive
      // collection so an edit made before the first request Id exists can
      // still be deferred safely.
      requestIds.add(requestToken(quote.Document_Data_Request_Id__c));
    }
    if (ids.isEmpty()) {
      return;
    }
    handledThisTransaction.addAll(ids);

    // A future call is only possible from a synchronous context. Anywhere
    // else - a Queueable, a batch, another future - there is no CPQ cascade
    // to lose the write to, so doing it inline is both safe and correct.
    if (canDefer()) {
      applyStaleAsync(ids, requestIds);
    } else {
      applyStale(ids, requestIds);
    }
  }

  private static Boolean canDefer() {
    return !System.isFuture() &&
      !System.isBatch() &&
      !System.isQueueable() &&
      Limits.getFutureCalls() < Limits.getLimitFutureCalls();
  }

  @future
  private static void applyStaleAsync(
    List<Id> quoteIds,
    List<String> requestIds
  ) {
    applyStale(quoteIds, requestIds);
  }

  /**
   * Re-reads the status and compares the publication request that existed
   * when the edit occurred. A later generation changes the request Id; that
   * proves the new snapshot already includes the edit, so an older deferred
   * invalidation must not close the gate on the current document.
   */
  private static void applyStale(List<Id> quoteIds, List<String> requestIds) {
    List<SBQQ__Quote__c> updates = new List<SBQQ__Quote__c>();
    Map<Id, String> expectedRequestIdByQuote = new Map<Id, String>();
    for (Integer index = 0; index < quoteIds.size(); index++) {
      expectedRequestIdByQuote.put(quoteIds[index], requestIds[index]);
    }

    for (SBQQ__Quote__c quote : [
      SELECT Id, Document_Data_Status__c, Document_Data_Request_Id__c
      FROM SBQQ__Quote__c
      WHERE Id IN :quoteIds
    ]) {
      if (
        quote.Document_Data_Status__c == null ||
        NOT_WORTH_MARKING.contains(quote.Document_Data_Status__c) ||
        requestToken(quote.Document_Data_Request_Id__c) !=
        expectedRequestIdByQuote.get(quote.Id)
      ) {
        continue;
      }
      updates.add(
        new SBQQ__Quote__c(Id = quote.Id, Document_Data_Status__c = 'Stale')
      );
    }

    if (!updates.isEmpty()) {
      update updates;
    }
  }

  private static String requestToken(String requestId) {
    return requestId == null ? '(none)' : requestId;
  }
}
