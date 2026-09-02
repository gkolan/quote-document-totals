/** Marks published document facts stale when the customer name or billing address changes. */
trigger QuoteDocumentAccountStaleness on Account (after update) {
  QuoteDocumentStaleness.markStaleFromAccounts(Trigger.new, Trigger.oldMap);
}
