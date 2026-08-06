/**
 * Generates one quote's document tables in its own transaction.
 *
 * One quote per job is the whole point. Row volume then scales with the size of
 * a single quote rather than with the size of the batch, so a bulk run cannot
 * blow the DML row limit no matter how many quotes it covers.
 *
 * The staleness re-check makes duplicate requests free. CPQ writes a quote
 * several times during one calculation, so several jobs can be queued for one
 * user action; the first regenerates and clears Stale, the rest exit after a
 * single SOQL. That is cheaper and more robust than trying to debounce.
 */
public with sharing class QuoteDocumentGenerateJob implements Queueable {

    private final Id quoteId;
    private final Boolean onlyIfStale;

    public QuoteDocumentGenerateJob(Id quoteId) {
        this(quoteId, true);
    }

    /** onlyIfStale = false forces a rebuild, which is what a button wants. */
    public QuoteDocumentGenerateJob(Id quoteId, Boolean onlyIfStale) {
        this.quoteId = quoteId;
        this.onlyIfStale = onlyIfStale;
    }

    public void execute(QueueableContext context) {
        if (onlyIfStale && !isStale()) {
            return;
        }

        // Let it throw. A failed Queueable is visible in Apex Jobs, and the
        // generator has already recorded Failed on the Quote, so the readiness
        // gate is closed either way.
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
    }

    private Boolean isStale() {
        List<SBQQ__Quote__c> quotes = [
            SELECT Document_Data_Status__c FROM SBQQ__Quote__c WHERE Id = :quoteId
        ];
        return !quotes.isEmpty() && quotes[0].Document_Data_Status__c == 'Stale';
    }
}
