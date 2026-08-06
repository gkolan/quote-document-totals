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
        'SBQQ__LineItemsGrouped__c'
    };

    /** Statuses with nothing generated behind them, so nothing to invalidate. */
    private static final Set<String> NOT_WORTH_MARKING = new Set<String>{
        'Not Generated', 'Stale'
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
        handledThisTransaction.addAll(toMark);

        List<Id> ids = new List<Id>(toMark);

        // A future call is only possible from a synchronous context. Anywhere
        // else - a Queueable, a batch, another future - there is no CPQ cascade
        // to lose the write to, so doing it inline is both safe and correct.
        if (canDefer()) {
            applyStaleAsync(ids);
        } else {
            applyStale(ids);
        }
    }

    private static Boolean canDefer() {
        return !System.isFuture()
            && !System.isBatch()
            && !System.isQueueable()
            && Limits.getFutureCalls() < Limits.getLimitFutureCalls();
    }

    @future
    private static void applyStaleAsync(List<Id> quoteIds) {
        applyStale(quoteIds);
    }

    /**
     * Re-reads the status rather than trusting the caller. By the time this
     * runs the quote may already have been regenerated, in which case marking
     * it stale would close the gate on data that is perfectly current.
     */
    private static void applyStale(List<Id> quoteIds) {
        List<SBQQ__Quote__c> updates = new List<SBQQ__Quote__c>();

        for (SBQQ__Quote__c quote : [
            SELECT Id, Document_Data_Status__c
            FROM SBQQ__Quote__c
            WHERE Id IN :quoteIds
        ]) {
            if (quote.Document_Data_Status__c == null
                || NOT_WORTH_MARKING.contains(quote.Document_Data_Status__c)) {
                continue;
            }
            updates.add(new SBQQ__Quote__c(Id = quote.Id, Document_Data_Status__c = 'Stale'));
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }
}
