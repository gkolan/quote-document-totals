@IsTest
private class QuoteDocumentEnvelopeStalenessTest {
  @TestSetup
  static void setupData() {
    QuoteDocumentTestData.setup();
  }

  @IsTest
  static void changingDocumentTypeMarksReadySnapshotStale() {
    Id quoteId = readyQuote();

    Test.startTest();
    update new SBQQ__Quote__c(Id = quoteId, Document_Type__c = 'Amendment');
    Test.stopTest();

    Assert.areEqual(
      'Stale',
      statusOf(quoteId),
      'Changing the document envelope must invalidate the old snapshot.'
    );
  }

  @IsTest
  static void changingBillingAddressMarksReadySnapshotStale() {
    Id quoteId = readyQuote();
    Id accountId = [
      SELECT SBQQ__Account__c
      FROM SBQQ__Quote__c
      WHERE Id = :quoteId
    ]
    .SBQQ__Account__c;

    Test.startTest();
    update new Account(Id = accountId, BillingCity = 'Madison');
    Test.stopTest();

    Assert.areEqual(
      'Stale',
      statusOf(quoteId),
      'A changed billing-address Fact must invalidate the old snapshot.'
    );
  }

  private static Id readyQuote() {
    Id quoteId = QuoteDocumentTestData.quoteId();
    QuoteDocumentStaleness.suppress();
    update new SBQQ__Quote__c(Id = quoteId, Document_Data_Status__c = 'Ready');
    QuoteDocumentStaleness.resume();
    return quoteId;
  }

  private static String statusOf(Id quoteId) {
    return [
      SELECT Document_Data_Status__c
      FROM SBQQ__Quote__c
      WHERE Id = :quoteId
    ]
    .Document_Data_Status__c;
  }
}
