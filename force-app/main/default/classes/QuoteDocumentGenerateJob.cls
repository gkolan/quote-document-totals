/**
 * Generates one quote's document tables in its own transaction.
 *
 * One quote per job is the whole point. Row volume then scales with the size of
 * a single quote rather than with the size of the batch, so a bulk run cannot
 * blow the DML row limit no matter how many quotes it covers.
 *
 * FAILURE IS REPORTED ON THE QUOTE, NOT THROUGH APEX JOBS. An unhandled
 * exception here would roll back the generator's own failure bookkeeping,
 * because that write happens after the savepoint rollback but inside the same
 * transaction. See execute().
 *
 * The staleness re-check makes duplicate requests free. CPQ writes a quote
 * several times during one calculation, so several jobs can be queued for one
 * user action; the first regenerates and clears Stale, the rest exit after a
 * single SOQL. That is cheaper and more robust than trying to debounce.
 */
public with sharing class QuoteDocumentGenerateJob implements Queueable {

    private final Id quoteId;
    private final Boolean onlyIfStale;

    /** Which lock attempt this is. Bounded, so contention cannot become an infinite queue. */
    private final Integer attempt;

    public QuoteDocumentGenerateJob(Id quoteId) {
        this(quoteId, true);
    }

    /** onlyIfStale = false forces a rebuild, which is what a button wants. */
    public QuoteDocumentGenerateJob(Id quoteId, Boolean onlyIfStale) {
        this(quoteId, onlyIfStale, 1);
    }

    public QuoteDocumentGenerateJob(Id quoteId, Boolean onlyIfStale, Integer attempt) {
        this.quoteId = quoteId;
        this.onlyIfStale = onlyIfStale;
        this.attempt = attempt == null ? 1 : attempt;
    }

    public void execute(QueueableContext context) {
        if (onlyIfStale && !isStale()) {
            return;
        }

        // DO NOT let this throw.
        //
        // The comment that used to sit here said the generator had already
        // recorded Failed on the Quote, so letting the exception escape was
        // harmless. It was not. The generator rolls back to its savepoint and
        // then writes Failed in its own DML - but that write is still part of
        // THIS transaction, so an unhandled exception escaping execute() rolls
        // it back too. The async path lost the status, the request Id and the
        // error code: exactly the evidence the runbook promises is queryable
        // without trawling debug logs.
        //
        // Catching here is step 05's option A. The trade is explicit: a failed
        // generation no longer appears as a failed row in Apex Jobs, and is
        // visible instead on the Quote - Document_Data_Status__c = 'Failed',
        // with the request Id and the stable error code. That is the record
        // support actually queries, and unlike the job row it survives.
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        } catch (Exception e) {
            // Apex has no guarded catch, so the retry decision is made here.
            // Lock contention only, and only on the async path: a synchronous
            // caller fails immediately and lets the user click again, because
            // a UI thread must not sit in a retry loop.
            Boolean retryable = QuoteDocumentLifecycle.isRetryable(e)
                && attempt < QuoteDocumentLifecycle.MAX_LOCK_ATTEMPTS;

            if (retryable) {
                // Re-queued rather than looped: Apex has no sleep, and a busy
                // wait would burn the CPU limit the backoff exists to protect.
                // The jitter matters more than the exponent - two jobs
                // retrying on the same fixed schedule collide again every
                // time.
                System.debug(
                    LoggingLevel.WARN,
                    'QuoteDocumentGenerateJob lock contention on ' + quoteId + ', attempt ' + attempt
                        + ' of ' + QuoteDocumentLifecycle.MAX_LOCK_ATTEMPTS + '; backoff '
                        + QuoteDocumentLifecycle.backoffSeconds(attempt) + 's; re-queueing.'
                );
                // Enqueueing from a test context would exceed the chained-job
                // limit and prove nothing about the retry decision, which is
                // what the tests assert directly.
                if (!Test.isRunningTest()) {
                    System.enqueueJob(new QuoteDocumentGenerateJob(quoteId, onlyIfStale, attempt + 1));
                }
                return;
            }

            // The generator has already persisted the failure. Re-throwing
            // would undo it - see the class comment. The detail still reaches
            // the debug log, which is access-controlled; the Quote carries the
            // stable code.
            System.debug(
                LoggingLevel.ERROR,
                'QuoteDocumentGenerateJob failed for ' + quoteId + ': ' + e.getMessage()
                    + ' | ' + e.getStackTraceString()
            );
        }
    }

    private Boolean isStale() {
        List<SBQQ__Quote__c> quotes = [
            SELECT Document_Data_Status__c FROM SBQQ__Quote__c WHERE Id = :quoteId
        ];
        return !quotes.isEmpty() && quotes[0].Document_Data_Status__c == 'Stale';
    }
}
