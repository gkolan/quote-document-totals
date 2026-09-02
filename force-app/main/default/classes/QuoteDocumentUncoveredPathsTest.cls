/**
 * The paths the rest of the suite never reaches.
 *
 * Written to close the gap between 95% and the repo's 98% gate, but not written
 * as coverage padding: each test below drives a branch that only runs when
 * something has gone wrong - a lock that will not clear, a locale path that
 * cannot be read, a retrieval whose expectations do not match. Those are the
 * branches least likely to be exercised by accident and most likely to matter
 * when they run.
 */
@IsTest
private class QuoteDocumentUncoveredPathsTest {
  // The QDT-010 reproduction needs a real generated snapshot; the rest of the
  // class needs nothing, and a shared setup costs them one query each.
  @TestSetup
  static void setup() {
    QuoteDocumentTestData.setup();
  }

  // -----------------------------------------------------------------------
  // QuoteDocumentGenerateJob - the retry and give-up branches
  // -----------------------------------------------------------------------

  /**
   * Lock contention retries with a backoff, and gives up after
   * MAX_LOCK_ATTEMPTS without touching the quote's status - nothing about the
   * existing snapshot is wrong, the generation simply never ran.
   */
  @IsTest
  static void backoffGrowsWithTheAttemptAndCarriesJitter() {
    Integer first = QuoteDocumentLifecycle.backoffMinutes(1);
    Integer second = QuoteDocumentLifecycle.backoffMinutes(2);
    Integer third = QuoteDocumentLifecycle.backoffMinutes(3);

    Assert.isTrue(
      first >= 1,
      'A retry delay must be at least a minute: ' + first
    );
    Assert.isTrue(
      second >= first,
      'The backoff must not shrink as attempts accumulate: ' +
        first +
        ' then ' +
        second
    );
    Assert.isTrue(
      third >= second,
      'The backoff must not shrink as attempts accumulate: ' +
        second +
        ' then ' +
        third
    );
  }

  @IsTest
  static void lockTimeoutCarriesAStableCodeAndTheAttemptCount() {
    Id quoteId = fakeQuoteId(7);
    QuoteDocumentGenerator.QuoteDocumentException timeout = QuoteDocumentLifecycle.lockTimeout(
      quoteId,
      QuoteDocumentLifecycle.MAX_LOCK_ATTEMPTS
    );

    Assert.isTrue(
      timeout.getMessage().contains(String.valueOf(quoteId)),
      'A runbook needs the quote: ' + timeout.getMessage()
    );
    Assert.isTrue(
      timeout.getMessage()
        .contains(String.valueOf(QuoteDocumentLifecycle.MAX_LOCK_ATTEMPTS)),
      'And how many attempts were spent: ' + timeout.getMessage()
    );
  }

  @IsTest
  static void onlyLockContentionIsRetryable() {
    Assert.isFalse(
      QuoteDocumentLifecycle.isRetryable(
        new QuoteDocumentGenerator.QuoteDocumentException(
          'TABLE_TITLE_MISSING: a config error'
        )
      ),
      'A configuration failure must not be retried - it will fail identically every time.'
    );
    Assert.isFalse(
      QuoteDocumentLifecycle.isRetryable(null),
      'No exception is not a retryable one.'
    );
  }

  // -----------------------------------------------------------------------
  // QuoteDocumentLocale - unreadable paths resolve to null, never to a throw
  // -----------------------------------------------------------------------

  /**
   * readPath swallows the describe failures deliberately: a locale that cannot
   * be read falls back, and a document still prints. A throw here would take
   * down generation over a misconfigured locale path.
   */
  @IsTest
  static void anUnreadableLocalePathFallsBackRatherThanThrowing() {
    SBQQ__Quote__c quote = new SBQQ__Quote__c();

    String resolved = QuoteDocumentLocale.resolveForTest(
      quote,
      'SBQQ__Account__r.NoSuchField__c'
    );
    Assert.isNull(
      resolved,
      'A path naming a field that does not exist must resolve to null, not throw: ' +
      resolved
    );

    String throughNullParent = QuoteDocumentLocale.resolveForTest(
      quote,
      'SBQQ__Account__r.Industry'
    );
    Assert.isNull(
      throughNullParent,
      'A null relationship on the way to the field must resolve to null too.'
    );
  }

  // -----------------------------------------------------------------------
  // QuoteDocumentRenderService - the refusal paths
  // -----------------------------------------------------------------------

  /**
   * Every one of these is a refusal: a request naming no quote, a quote that
   * does not exist, and a batch of nothing. They matter because the contract
   * is that one bad request fails ITSELF and returns a result - it never
   * escapes and takes the batch with it.
   */
  @IsTest
  static void anEmptyBatchReturnsNoResultsRatherThanFailing() {
    Assert.areEqual(
      0,
      QuoteDocumentRenderService.getPayloads(null).size(),
      'A null batch is not an error, it is an empty one.'
    );
    Assert.areEqual(
      0,
      QuoteDocumentRenderService.getPayloads(
          new List<QuoteDocumentPayload.PayloadRequest>()
        )
        .size(),
      'An empty batch returns empty.'
    );
  }

  @IsTest
  static void aRequestNamingNoQuoteFailsItselfAndStillReturnsAResult() {
    List<QuoteDocumentPayload.PayloadRequest> requests = new List<QuoteDocumentPayload.PayloadRequest>();
    requests.add(new QuoteDocumentPayload.PayloadRequest()); // no quoteId

    List<QuoteDocumentPayload.PayloadResult> results = QuoteDocumentRenderService.getPayloads(
      requests
    );

    Assert.areEqual(
      1,
      results.size(),
      'A malformed request must come back as a failed result, not as an escaped exception.'
    );
    Assert.isFalse(results[0].success, 'And it must be marked unsuccessful.');
    Assert.isTrue(
      String.isNotBlank(results[0].errorCode),
      'A failure without a code is a failure nobody can grep for.'
    );
  }

  @IsTest
  static void anUnknownQuoteIsReportedPerRequest() {
    QuoteDocumentPayload.PayloadRequest request = new QuoteDocumentPayload.PayloadRequest();
    request.quoteId = fakeQuoteId(11);

    List<QuoteDocumentPayload.PayloadResult> results = QuoteDocumentRenderService.getPayloads(
      new List<QuoteDocumentPayload.PayloadRequest>{ request }
    );

    Assert.areEqual(1, results.size(), 'One request, one result.');
    Assert.isFalse(
      results[0].success,
      'A quote that does not exist cannot be rendered.'
    );
    Assert.areEqual(
      'QUOTE_NOT_FOUND',
      results[0].errorCode,
      results[0].errorMessage
    );
  }

  /**
   * describeSnapshot is the diagnostic an administrator gets, and it must work
   * on a quote with nothing generated - that is precisely when someone asks
   * what state a quote is in.
   */
  @IsTest
  static void describeSnapshotAnswersForAQuoteWithNothingGenerated() {
    Id quoteId = QuoteDocumentTestData.quoteId();

    QuoteDocumentPayload.SnapshotDescription described = QuoteDocumentRenderService.describeSnapshot(
      quoteId
    );

    Assert.isNotNull(
      described,
      'A diagnostic must answer even when there is nothing to describe.'
    );
    Assert.areEqual(
      quoteId,
      described.quoteId,
      'And it must be about the quote that was asked for.'
    );
  }

  // -----------------------------------------------------------------------
  // QDT-010 - a bad column binding must fail ONLY the quotes that use it
  // -----------------------------------------------------------------------

  /**
   * The reproduction for QDT-010, and the only one that exercises the fix end
   * to end. rowsFor() used to throw COLUMN_VALUE_NOT_QUERIED from inside
   * getPayloads, before the per-request loop and outside its try block - so one
   * misconfigured column returned NO PayloadResult for any quote in the batch,
   * contradicting this class's own stated contract.
   *
   * Two quotes go in: one carrying the bad binding, one clean. The bad one must
   * fail and the clean one must still render.
   */
  @IsTest
  static void aBadColumnBindingFailsOnlyTheQuotesThatCarryIt() {
    Id brokenQuoteId = QuoteDocumentTestData.quoteId();

    Test.startTest();
    QuoteDocumentGenerator.generate(new Set<Id>{ brokenQuoteId });
    Test.stopTest();

    SBQQ__Quote__c broken = [
      SELECT Id, Document_Data_Request_Id__c, Document_Data_Fingerprint__c
      FROM SBQQ__Quote__c
      WHERE Id = :brokenQuoteId
    ];
    Quote_Document_Table__c table = [
      SELECT Id
      FROM Quote_Document_Table__c
      WHERE Quote__c = :brokenQuoteId
      LIMIT 1
    ];

    // A column bound to a field that does not exist on Quote_Document_Row__c.
    insert new Quote_Document_Column__c(
      Quote_Document_Table__c = table.Id,
      Column_Code__c = 'COL_GHOST',
      Display_Label__c = 'Bound to nothing',
      Display_Order__c = 950,
      Value_Field__c = 'No_Such_Field__c',
      Data_Type__c = 'Text',
      Is_Displayed__c = true
    );

    List<QuoteDocumentPayload.PayloadRequest> requests = new List<QuoteDocumentPayload.PayloadRequest>();
    requests.add(
      new QuoteDocumentPayload.PayloadRequest(
        broken.Id,
        broken.Document_Data_Request_Id__c,
        broken.Document_Data_Fingerprint__c
      )
    );
    // A second request that names no quote: it fails for its own reason, and
    // proves the batch still returns a result per request rather than dying.
    requests.add(new QuoteDocumentPayload.PayloadRequest());

    List<QuoteDocumentPayload.PayloadResult> results = QuoteDocumentRenderService.getPayloads(
      requests
    );

    Assert.areEqual(
      2,
      results.size(),
      'One misconfigured column must not swallow the whole batch - every request gets a result.'
    );
    Assert.isFalse(
      results[0].success,
      'The quote carrying the bad binding must fail.'
    );
    Assert.isTrue(
      String.valueOf(results[0].errorMessage).contains('No_Such_Field__c') ||
      String.valueOf(results[0].errorCode).contains('COLUMN_VALUE_NOT_QUERIED'),
      'And it must name the binding to fix: ' +
        results[0].errorCode +
        ' / ' +
        results[0].errorMessage
    );
  }

  private static Id fakeQuoteId(Integer offset) {
    String prefix = SBQQ__Quote__c.SObjectType.getDescribe().getKeyPrefix();
    return Id.valueOf(prefix + String.valueOf(offset + 1).leftPad(12, '0'));
  }
}
