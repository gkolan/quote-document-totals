@IsTest
private class QuoteDocumentOperationLedgerTest {
  @TestSetup
  static void setup() {
    QuoteDocumentTestData.setup();
  }

  @IsTest
  static void recordsSanitizedRunOutcome() {
    Test.startTest();
    Id runId = QuoteDocumentOperationLedger.startRun(
      'Invalidation',
      'TEST-RUN-1'
    );
    QuoteDocumentOperationLedger.completeRun(
      runId,
      new QuoteDocumentOperationLedger.Completion(4, 1, 0)
    );
    Test.stopTest();

    Quote_Document_Run__c run = [
      SELECT
        Status__c,
        Processed_Count__c,
        Failed_Count__c,
        Completed_At__c,
        Summary__c
      FROM Quote_Document_Run__c
      WHERE Id = :runId
    ];
    Assert.areEqual('Completed with Errors', run.Status__c);
    Assert.areEqual(4, run.Processed_Count__c);
    Assert.areEqual(1, run.Failed_Count__c);
    Assert.isNotNull(run.Completed_At__c);
    Assert.areEqual(
      'Processed 4; failed 1; platform errors 0.',
      run.Summary__c
    );
  }

  @IsTest
  static void failureBuilderStoresOnlyAllowlistedContent() {
    Id runId = QuoteDocumentOperationLedger.startRun(
      'Invalidation',
      'TEST-RUN-2'
    );
    Quote_Document_Run_Failure__c failure = QuoteDocumentOperationLedger.buildInvalidationFailure(
      runId,
      QuoteDocumentTestData.quoteId(),
      'FIELD_CUSTOM_VALIDATION_EXCEPTION'
    );

    Assert.areEqual('FIELD_CUSTOM_VALIDATION_EXCEPTION', failure.Error_Code__c);
    Assert.areEqual(false, failure.Retryable__c);
    Assert.isTrue(failure.Safe_Message__c.contains('validation rules'));
    Assert.isFalse(
      failure.Safe_Message__c.contains('FIELD_CUSTOM_VALIDATION_EXCEPTION')
    );
  }

  @IsTest
  static void retryRechecksCurrentQuoteState() {
    Id quoteId = QuoteDocumentTestData.quoteId();
    Id runId = QuoteDocumentOperationLedger.startRun(
      'Invalidation',
      'TEST-RUN-3'
    );
    Quote_Document_Run_Failure__c failure = QuoteDocumentOperationLedger.buildInvalidationFailure(
      runId,
      quoteId,
      'UNABLE_TO_LOCK_ROW'
    );
    insert failure;

    Test.startTest();
    QuoteDocumentOperationLedger.RetryResult result = QuoteDocumentOperationLedger.retryInvalidationFailures(
      new List<Id>{ failure.Id }
    );
    Test.stopTest();

    failure = [
      SELECT Resolved__c, Resolved_At__c
      FROM Quote_Document_Run_Failure__c
      WHERE Id = :failure.Id
    ];
    Assert.areEqual(1, result.requested);
    Assert.areEqual(1, result.resolved);
    Assert.areEqual(
      true,
      failure.Resolved__c,
      'A Quote no longer Ready must not be overwritten by an old retry.'
    );
    Assert.isNotNull(failure.Resolved_At__c);
  }
}
