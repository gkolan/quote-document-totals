/**
 * Durable, sanitized operational evidence for Quote Document Totals jobs.
 *
 * This service deliberately uses system-mode DML. Jobs must be able to record
 * their own outcome even when the initiating user has no access to the private
 * operations objects. Human access remains controlled by object sharing and
 * the CPQ_Document_Totals_Operations permission set.
 */
public with sharing class QuoteDocumentOperationLedger {
  private static final String SOURCE_VERSION = '1.0.0';
  private static final String INVALIDATION_STAGE = 'Mark Quote Stale';
  private static final String INVALIDATION_REMEDIATION = 'Quote could not be marked Stale. Review access, validation rules, and subscriber automation, then retry.';

  public static Id startRun(String operationType, String correlationId) {
    Quote_Document_Run__c run = new Quote_Document_Run__c(
      Operation_Type__c = operationType,
      Status__c = 'Running',
      Correlation_Id__c = correlationId,
      Started_At__c = System.now(),
      Source_Version__c = SOURCE_VERSION
    );
    Database.insert(run, AccessLevel.SYSTEM_MODE);
    return run.Id;
  }

  public static void recordInvalidationFailures(
    Id runId,
    List<SBQQ__Quote__c> updates,
    List<Database.SaveResult> results
  ) {
    List<Quote_Document_Run_Failure__c> failures = new List<Quote_Document_Run_Failure__c>();
    for (Integer index = 0; index < results.size(); index++) {
      if (results[index].isSuccess()) {
        continue;
      }
      Database.Error error = results[index].getErrors()[0];
      failures.add(
        buildInvalidationFailure(
          runId,
          updates[index].Id,
          String.valueOf(error.getStatusCode())
        )
      );
    }
    if (!failures.isEmpty()) {
      Database.insert(failures, AccessLevel.SYSTEM_MODE);
    }
  }

  @TestVisible
  private static Quote_Document_Run_Failure__c buildInvalidationFailure(
    Id runId,
    Id quoteId,
    String errorCode
  ) {
    return new Quote_Document_Run_Failure__c(
      Run__c = runId,
      Quote__c = quoteId,
      Stage__c = INVALIDATION_STAGE,
      Error_Code__c = errorCode,
      Safe_Message__c = INVALIDATION_REMEDIATION,
      Attempt__c = 1,
      Retryable__c = errorCode == 'UNABLE_TO_LOCK_ROW',
      Resolved__c = false
    );
  }

  public class Completion {
    public Integer processed;
    public Integer failed;
    public Integer platformErrors;

    public Completion(
      Integer processed,
      Integer failed,
      Integer platformErrors
    ) {
      this.processed = processed;
      this.failed = failed;
      this.platformErrors = platformErrors;
    }
  }

  public static void completeRun(Id runId, Completion completion) {
    Integer safeProcessed = completion.processed == null
      ? 0
      : completion.processed;
    Integer safeFailed = completion.failed == null ? 0 : completion.failed;
    Integer safePlatformErrors = completion.platformErrors == null
      ? 0
      : completion.platformErrors;
    String status = safeFailed > 0 ||
      safePlatformErrors > 0
      ? 'Completed with Errors'
      : 'Succeeded';
    Quote_Document_Run__c run = new Quote_Document_Run__c(
      Id = runId,
      Status__c = status,
      Completed_At__c = System.now(),
      Processed_Count__c = safeProcessed,
      Failed_Count__c = safeFailed,
      Platform_Error_Count__c = safePlatformErrors,
      Summary__c = 'Processed ' +
        safeProcessed +
        '; failed ' +
        safeFailed +
        '; platform errors ' +
        safePlatformErrors +
        '.'
    );
    Database.update(run, AccessLevel.SYSTEM_MODE);
  }

  public class RetryResult {
    @AuraEnabled
    public Integer requested = 0;
    @AuraEnabled
    public Integer resolved = 0;
    @AuraEnabled
    public Integer failed = 0;
  }

  /** Retry selected unresolved invalidation failures after their cause is corrected. */
  @AuraEnabled
  public static RetryResult retryInvalidationFailures(List<Id> failureIds) {
    RetryResult result = new RetryResult();
    if (failureIds == null || failureIds.isEmpty()) {
      return result;
    }
    List<Quote_Document_Run_Failure__c> failures = [
      SELECT
        Id,
        Quote__c,
        Attempt__c,
        Resolved__c,
        Quote__r.Document_Data_Status__c
      FROM Quote_Document_Run_Failure__c
      WHERE
        Id IN :failureIds
        AND Resolved__c = FALSE
        AND Stage__c = :INVALIDATION_STAGE
      WITH USER_MODE
    ];
    result.requested = failures.size();
    List<SBQQ__Quote__c> quoteUpdates = new List<SBQQ__Quote__c>();
    List<Quote_Document_Run_Failure__c> attempted = new List<Quote_Document_Run_Failure__c>();
    for (Quote_Document_Run_Failure__c failure : failures) {
      if (failure.Quote__r.Document_Data_Status__c != 'Ready') {
        failure.Resolved__c = true;
        failure.Resolved_At__c = System.now();
        result.resolved++;
        continue;
      }
      quoteUpdates.add(
        new SBQQ__Quote__c(
          Id = failure.Quote__c,
          Document_Data_Status__c = 'Stale'
        )
      );
      attempted.add(failure);
    }

    QuoteDocumentStaleness.suppress();
    try {
      List<Database.SaveResult> updates = Database.update(
        quoteUpdates,
        false,
        AccessLevel.SYSTEM_MODE
      );
      for (Integer index = 0; index < updates.size(); index++) {
        Quote_Document_Run_Failure__c failure = attempted[index];
        failure.Attempt__c = failure.Attempt__c == null
          ? 2
          : failure.Attempt__c + 1;
        if (updates[index].isSuccess()) {
          failure.Resolved__c = true;
          failure.Resolved_At__c = System.now();
          result.resolved++;
        } else {
          String code = String.valueOf(
            updates[index].getErrors()[0].getStatusCode()
          );
          failure.Error_Code__c = code;
          failure.Retryable__c = code == 'UNABLE_TO_LOCK_ROW';
          failure.Safe_Message__c = INVALIDATION_REMEDIATION;
          result.failed++;
        }
      }
    } finally {
      QuoteDocumentStaleness.resume();
    }
    if (!failures.isEmpty()) {
      Database.update(failures, AccessLevel.SYSTEM_MODE);
    }
    return result;
  }
}
