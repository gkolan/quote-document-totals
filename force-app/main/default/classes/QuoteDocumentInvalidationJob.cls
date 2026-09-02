/**
 * Marks Ready quotes Stale after a change that no trigger can see.
 *
 * WHY THIS EXISTS AT ALL
 * ----------------------
 * Custom Metadata changes do not fire Quote triggers. Bump the content
 * version, edit a clause, deploy a new label - nothing marks a single quote
 * stale, and every existing snapshot keeps reporting Ready while printing the
 * old wording. Deploying the metadata IS NOT invalidation, and no runbook
 * step may claim it is.
 *
 * Blanket invalidation of every Ready quote is the accepted v1 policy.
 * Per-key dependency tracking is deferred until blanket invalidation is
 * measurably too costly, rather than because it is inelegant - a dependency
 * graph that is wrong in one direction reintroduces exactly the silent
 * staleness this job exists to prevent.
 *
 * RESUMABLE BY CONSTRUCTION
 * -------------------------
 * The job selects quotes that are still Ready, and its own work makes them
 * Stale. So re-running it after a failure processes only what is left, and
 * re-running it after success is a no-op. That is idempotence from the query,
 * not from a checkpoint someone has to remember to persist - a checkpoint
 * that can be lost is a checkpoint that will be.
 *
 * One poison quote cannot block the rest: updates are partial-success, and
 * failures are counted and reported rather than thrown.
 */
public with sharing class QuoteDocumentInvalidationJob implements Database.Batchable<SObject>, Database.Stateful {

    /** What the run did, so an operator can report it rather than infer it. */
    public class Outcome {
        public Integer processed = 0;
        public Integer failed = 0;
        public List<String> failures = new List<String>();

        public String describe() {
            return 'Invalidation complete: ' + processed + ' quote(s) marked Stale, ' + failed + ' failed.'
                + (failures.isEmpty() ? '' : ' First failures: ' + String.join(failures, '; '));
        }
    }

    @TestVisible
    private Outcome outcome = new Outcome();

    /** Only the first few are kept - a failure list the length of the batch helps nobody. */
    private static final Integer MAX_REPORTED_FAILURES = 10;

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT Id, Document_Data_Status__c
            FROM SBQQ__Quote__c
            WHERE Document_Data_Status__c = 'Ready'
        ]);
    }

    public void execute(Database.BatchableContext context, List<SBQQ__Quote__c> scope) {
        List<SBQQ__Quote__c> updates = new List<SBQQ__Quote__c>();
        for (SBQQ__Quote__c quote : scope) {
            updates.add(new SBQQ__Quote__c(Id = quote.Id, Document_Data_Status__c = 'Stale'));
        }

        // Suppressed so the staleness trigger does not react to the very write
        // that is setting the status - the same guard generation uses.
        QuoteDocumentStaleness.suppress();
        try {
            // allOrNone = false, deliberately: one quote failing a validation
            // rule must not roll back the other 199 in its batch and leave
            // them silently Ready.
            List<Database.SaveResult> results = Database.update(updates, false);

            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    outcome.processed++;
                    continue;
                }
                outcome.failed++;
                if (outcome.failures.size() < MAX_REPORTED_FAILURES) {
                    outcome.failures.add(
                        updates[i].Id + ': ' + results[i].getErrors()[0].getMessage()
                    );
                }
            }
        } finally {
            QuoteDocumentStaleness.resume();
        }
    }

    public void finish(Database.BatchableContext context) {
        // A partial run must never read as a full invalidation. The counts say
        // what actually happened, and a non-zero failure count means quotes
        // are still Ready on stale content - which is the whole hazard.
        System.debug(LoggingLevel.ERROR, outcome.describe());
    }

    /**
     * Synchronous variant, for a scratch org or a small tenant where a batch
     * is more ceremony than the work deserves. Same idempotence, same
     * partial-success behaviour, bounded by the caller's own limits.
     */
    public static Outcome runNow(Integer maxQuotes) {
        QuoteDocumentInvalidationJob job = new QuoteDocumentInvalidationJob();
        Integer cap = maxQuotes == null ? 200 : maxQuotes;

        List<SBQQ__Quote__c> ready = [
            SELECT Id, Document_Data_Status__c
            FROM SBQQ__Quote__c
            WHERE Document_Data_Status__c = 'Ready'
            LIMIT :cap
        ];
        if (!ready.isEmpty()) {
            job.execute(null, ready);
        }
        return job.outcome;
    }
}
