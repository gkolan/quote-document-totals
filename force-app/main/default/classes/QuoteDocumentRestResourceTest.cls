@IsTest
private class QuoteDocumentRestResourceTest {
  @TestSetup
  static void setup() {
    QuoteDocumentTestData.setup();
  }

  @IsTest
  static void returnsIdentityBoundPayloadWithoutCaching() {
    QuoteDocumentGenerator.GenerationOutcome outcome = launch();
    prepare(outcome.quoteId, outcome.requestId, outcome.fingerprint);

    Test.startTest();
    QuoteDocumentRestResource.retrieve();
    Test.stopTest();

    Assert.areEqual(200, RestContext.response.statusCode);
    Assert.areEqual(
      'no-store',
      RestContext.response.headers.get('Cache-Control')
    );
    Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(
      RestContext.response.responseBody.toString()
    );
    Assert.areEqual(outcome.requestId, payload.get('requestId'));
    Assert.areEqual(outcome.fingerprint, payload.get('fingerprint'));
    Assert.areEqual('2.0', payload.get('contractVersion'));
  }

  @IsTest
  static void rejectsMissingIdentityBeforeReadingSnapshot() {
    Id quoteId = QuoteDocumentTestData.quoteId();
    prepare(quoteId, null, null);

    QuoteDocumentRestResource.retrieve();

    Assert.areEqual(400, RestContext.response.statusCode);
    assertError(400, 'INVALID_REQUEST');
  }

  @IsTest
  static void rejectsMalformedAndNonQuoteRoutes() {
    prepareUri(
      '/services/apexrest/quote-document-totals/v2/quotes/not-a-record-id'
    );
    QuoteDocumentRestResource.retrieve();
    Assert.areEqual(400, RestContext.response.statusCode);
    assertError(400, 'INVALID_REQUEST');

    Account account = [SELECT Id FROM Account LIMIT 1];
    prepare(account.Id, 'request', 'fingerprint');
    QuoteDocumentRestResource.retrieve();
    assertError(400, 'INVALID_REQUEST');
  }

  @IsTest
  static void rejectsMovedSnapshotWithoutReflectingIdentity() {
    QuoteDocumentGenerator.GenerationOutcome outcome = launch();
    String oldRequest = 'REQ-SECRET-OLD';
    String oldFingerprint = 'FINGERPRINT-SECRET-OLD';
    prepare(outcome.quoteId, oldRequest, oldFingerprint);

    QuoteDocumentRestResource.retrieve();

    assertError(409, 'SNAPSHOT_MOVED');
    String body = RestContext.response.responseBody.toString();
    Assert.isFalse(body.contains(oldRequest));
    Assert.isFalse(body.contains(oldFingerprint));
    Assert.isFalse(body.contains(String.valueOf(outcome.quoteId)));
  }

  private static QuoteDocumentGenerator.GenerationOutcome launch() {
    return QuoteDocumentGenerator.generate(
      new Set<Id>{ QuoteDocumentTestData.quoteId() }
    )[0];
  }

  private static void prepare(
    Id quoteId,
    String requestId,
    String fingerprint
  ) {
    prepareUri('/services/apexrest/quote-document-totals/v2/quotes/' + quoteId);
    if (requestId != null) {
      RestContext.request.addHeader('X-QDTD-Request-Id', requestId);
    }
    if (fingerprint != null) {
      RestContext.request.addHeader('X-QDTD-Fingerprint', fingerprint);
    }
  }

  private static void prepareUri(String uri) {
    RestRequest request = new RestRequest();
    request.requestURI = uri;
    request.httpMethod = 'GET';
    RestContext.request = request;
    RestContext.response = new RestResponse();
  }

  private static void assertError(Integer statusCode, String errorCode) {
    Assert.areEqual(statusCode, RestContext.response.statusCode);
    Map<String, Object> envelope = (Map<String, Object>) JSON.deserializeUntyped(
      RestContext.response.responseBody.toString()
    );
    Map<String, Object> error = (Map<String, Object>) envelope.get('error');
    Assert.areEqual(errorCode, error.get('code'));
    Assert.isNotNull(error.get('message'));
  }
}
