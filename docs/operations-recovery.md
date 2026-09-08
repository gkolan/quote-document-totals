# Operations and recovery

Quote document invalidation creates a private `Quote_Document_Run__c` record for every batch or synchronous run. A run records its correlation ID, source version, start and completion times, processed and failed counts, platform batch errors, and a sanitized summary. Failed Quote updates create child `Quote_Document_Run_Failure__c` records. These records contain a stable status code and fixed remediation text; they never copy exception messages or customer content.

Assign `CPQ_Document_Totals_Operations` only to staff responsible for recovery. It grants read and edit access across the two private operations objects and access to the invalidation and retry classes. Generation users do not need this permission set. Failures inherit sharing from their parent run. Retry selection runs in user mode and therefore also requires access to the referenced Quote and its status field.

## Review an invalidation

1. Open **Quote Document Runs** and select **Recent Runs**. Match `Correlation Id` to the Async Apex job ID when the run was asynchronous.
2. Treat `Running` as incomplete. `Succeeded` means the recorded execution had no item or platform errors. `Completed with Errors` needs investigation.
3. Open the run's failures or use **Unresolved Failures**. Review `Error Code`, `Safe Message`, attempt count, and the referenced Quote. Check record access, validation rules, and subscriber automation without editing generated document children.
4. Correct the cause. Confirm the Quote is still `Ready`. If it is already `Stale`, `Failed`, or has moved to another lifecycle state, the retry service resolves the old failure without overwriting the newer state.

Retry selected records from Execute Anonymous after collecting their IDs:

```apex
QuoteDocumentOperationLedger.RetryResult result =
    QuoteDocumentOperationLedger.retryInvalidationFailures(
        new List<Id>{ 'a failure record Id' }
    );
System.debug(result);
```

The retry action rechecks current Quote state, increments the attempt count, and retains an unresolved record when the update still fails. `UNABLE_TO_LOCK_ROW` is classified as transient; validation and permission failures require correction before retry. Automated invalidation retries are disabled for the initial rollout so an error cannot create an uncontrolled retry loop.

## Other operation families

The run schema reserves Generation, Retention, and Document Delivery operation types, but this release writes durable records only for invalidation. Generation continues to write its safe status and error to the Quote, retention uses its inventory and batch results, and document delivery remains the responsibility of the selected document tool. Do not infer coverage for these operations from the reserved picklist values.

## Retention and alerts

Create an organization policy for operations evidence before scheduling deletion. A starting review point is 90 days for successful runs and one year for unresolved failures, adjusted for the organization's audit obligations. Never delete an unresolved failure merely because its parent run is old. Alert from a Flow or monitoring product when a run completes with errors or an unresolved failure exceeds the team's response target; keep notification destinations in subscriber configuration.

Disabling or unassigning the operations permission set prevents operator access and manual retry. It does not stop invalidation jobs already scheduled and does not remove the durable evidence.
