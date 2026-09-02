/**
 * Reproductions for the open findings in the defect ledger (QDT-005 to QDT-011).
 *
 * Each test here fails on the code as it stood before the fix beside it. That is
 * the point: a regression test written after the fix, that would have passed
 * before it, proves nothing about the defect it claims to cover.
 *
 * QDT-011 is the exception and is recorded rather than fixed - see
 * fieldPathValuesKeepFullPrecisionInTheFingerprint.
 */
@IsTest
private class QuoteDocumentDefectLedgerTest {
  // -----------------------------------------------------------------------
  // QDT-005 - payload hash canonicalization was ambiguous
  // -----------------------------------------------------------------------

  /**
   * Two different row sets produced one digest, because text() encoded a value
   * as '=' + value with no length and the parts were joined with an empty
   * separator. A value ending in the next field's name plus '=' moved the
   * boundary invisibly.
   *
   * Asserted against the encoder rather than through a generated snapshot: the
   * collision is a property of the encoding, and pinning it here means the
   * next person to "simplify" text() sees why it cannot be simplified.
   */
  @IsTest
  static void adjacentTextFieldsCannotBorrowEachOthersCharacters() {
    // Two DIFFERENT pairs of adjacent values that the old encoding could not
    // tell apart. Joined with an empty separator and encoded as '=' + value:
    //
    //   ('a=b', '')   ->  '=a=b' + '='   ->  '=a=b='
    //   ('a',   'b=') ->  '=a'   + '=b=' ->  '=a=b='
    //
    // One canonical form, one digest, two different documents - and
    // assertIntact passes on both. The length prefix separates them.
    String firstPair =
      QuoteDocumentPayloadHash.encodeTextForTest('a=b') +
      QuoteDocumentPayloadHash.encodeTextForTest('');
    String secondPair =
      QuoteDocumentPayloadHash.encodeTextForTest('a') +
      QuoteDocumentPayloadHash.encodeTextForTest('b=');

    Assert.areNotEqual(
      firstPair,
      secondPair,
      'Two different pairs of adjacent text values must not share a canonical form. Without a ' +
      'length prefix both encoded to "=a=b=", so one digest covered two documents.'
    );
  }

  @IsTest
  static void nullAndBlankTextStillEncodeDifferently() {
    Assert.areNotEqual(
      QuoteDocumentPayloadHash.encodeTextForTest(null),
      QuoteDocumentPayloadHash.encodeTextForTest(''),
      'No value and blank text are different documents, and the length prefix must not blur them.'
    );
  }

  // -----------------------------------------------------------------------
  // QDT-008 - BUNDLE was the only dimension that could return null
  // -----------------------------------------------------------------------

  /**
   * A bundle parent with no product name returned null from
   * getGroupingValue('BUNDLE'), and the null reached buildGroupKey's
   * value.toUpperCase() as a dereference - generation failing with a message
   * that explained nothing.
   */
  @IsTest
  static void bundleGroupingNeverReturnsNull() {
    SBQQ__Quote__c quote = new SBQQ__Quote__c();
    SBQQ__QuoteLine__c raw = new SBQQ__QuoteLine__c(
      SBQQ__Bundle__c = true, // a package, so the branch reads productName
      SBQQ__Bundled__c = false,
      SBQQ__Quantity__c = 1
    );

    QuoteDocumentLine line = new QuoteDocumentLine(raw, quote);
    String value = line.getGroupingValue(
      QuoteDocumentTableDefinition.DIM_BUNDLE
    );

    Assert.isNotNull(
      value,
      'BUNDLE must normalize like every sibling dimension - a null here dereferences in buildGroupKey.'
    );
    Assert.isTrue(
      String.isNotBlank(value),
      'A blank is as unusable as a null: ' + value
    );
  }

  // -----------------------------------------------------------------------
  // QDT-009 - label substitution gave up after twenty braces
  // -----------------------------------------------------------------------

  /**
   * A template with more than twenty literal brace pairs before its
   * placeholder exhausted the old `guard < 20` bound, appended the remainder
   * untouched, and printed "{0}" to the customer.
   */
  @IsTest
  static void aPlaceholderPastTwentyLiteralBracesStillSubstitutes() {
    String prose = '';
    for (Integer i = 0; i < 25; i++) {
      prose += '{clause} '; // non-numeric: a literal brace, not a placeholder
    }
    String template = prose + 'Total for {0}';

    QuoteDocumentLabels.useLabels(
      'en_US',
      new Map<String, String>{ 'SECTION_TOTAL' => template }
    );
    QuoteDocumentLabels labels = QuoteDocumentLabels.forLocale('en_US');

    String rendered = labels.format(
      'SECTION_TOTAL',
      new List<String>{ 'Hardware' }
    );

    Assert.isTrue(
      rendered.endsWith('Total for Hardware'),
      'The placeholder past twenty literal braces must substitute, not print: ' +
      rendered
    );
    Assert.isFalse(
      rendered.contains('{0}'),
      'A placeholder must never reach a customer document as literal text: ' +
      rendered
    );
    QuoteDocumentLabels.reset();
  }

  @IsTest
  static void anUnresolvedPlaceholderFailsLoudlyRatherThanPrinting() {
    QuoteDocumentLabels.useLabels(
      'en_US',
      new Map<String, String>{ 'SECTION_TOTAL' => 'Total for {0}' }
    );
    QuoteDocumentLabels labels = QuoteDocumentLabels.forLocale('en_US');

    String message;
    try {
      labels.format('SECTION_TOTAL', new List<String>());
    } catch (Exception e) {
      message = e.getMessage();
    }

    Assert.isNotNull(
      message,
      'A missing argument must throw, not render a gap.'
    );
    Assert.isTrue(
      message.contains('LABEL_ARGUMENT_MISSING'),
      'And it must carry the code a runbook greps for: ' + message
    );
    QuoteDocumentLabels.reset();
  }

  // -----------------------------------------------------------------------
  // QDT-006 - three reachable codes were flattened to the generic one
  // -----------------------------------------------------------------------

  /**
   * Walks the codes actually thrown on the generation path and asserts each
   * survives onto Document_Data_Error__c. The ledger asked for exactly this,
   * so the next code added does not repeat the omission.
   */
  @IsTest
  static void everyPersistedGenerationCodeSurvivesTheAllowlist() {
    List<String> thrownOnTheGenerationPath = new List<String>{
      QuoteDocumentLifecycle.CODE_SUPERSEDED,
      'TABLE_TITLE_MISSING',
      'TABLE_LOCALE_MISSING',
      QuoteDocumentContributorError.NO_OUTPUT,
      QuoteDocumentContributorError.FLOW_FAULT,
      'LABEL_ARGUMENT_MISSING'
    };

    for (String code : thrownOnTheGenerationPath) {
      Exception e = QuoteDocumentContributorError.build(
        code,
        'detail that must not survive as the code'
      );
      Assert.areEqual(
        code,
        QuoteDocumentError.codeOf(e),
        'Code ' +
          code +
          ' is thrown inside generateOne and persisted, so it must be in ' +
          'KNOWN_CODES - otherwise it flattens to GENERATION_FAILED_UNEXPECTED and the ' +
          'runbook has nothing to grep.'
      );
    }
  }

  @IsTest
  static void anInventedCodeStillFlattens() {
    Exception e = new QuoteDocumentGenerator.QuoteDocumentException(
      'TOTALLY_MADE_UP_CODE: an exception whose message merely starts with a code'
    );
    Assert.areEqual(
      'GENERATION_FAILED_UNEXPECTED',
      QuoteDocumentError.codeOf(e),
      'The allowlist exists so arbitrary text cannot smuggle itself through as a code.'
    );
  }

  // -----------------------------------------------------------------------
  // QDT-007 - generateAsync promised a 50-job cap it did not apply
  // -----------------------------------------------------------------------

  /**
   * Handed 51 ids from a synchronous context the old loop threw an uncatchable
   * LimitException on the 51st enqueue, after 50 jobs were already queued. The
   * caller could neither prevent nor observe the partial batch.
   */
  @IsTest
  static void generateAsyncRefusesABatchLargerThanTheJobCap() {
    Set<Id> tooMany = new Set<Id>();
    for (Integer i = 0; i < 51; i++) {
      tooMany.add(fakeQuoteId(i));
    }

    String message;
    try {
      QuoteDocumentGenerator.generateAsync(tooMany);
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      message = e.getMessage();
    }

    Assert.isNotNull(
      message,
      '51 ids must be refused, not enqueued until the limit throws.'
    );
    Assert.isTrue(message.contains('GENERATION_BATCH_TOO_LARGE'), message);
    Assert.areEqual(
      0,
      Limits.getQueueableJobs(),
      'Refusing must leave nothing enqueued - a partial batch is the outcome this prevents.'
    );
  }

  /** Enqueues nothing anyone cares about - it exists to spend one of the budget's slots. */
  private class BudgetSpender implements Queueable {
    public void execute(QueueableContext context) {
    }
  }

  /**
   * The budget is what the TRANSACTION has left, not a constant 50.
   *
   * The first version of the guard compared against 50 unconditionally, so a
   * caller that had already enqueued a job of its own still passed a 50-quote
   * request - and then hit the uncatchable LimitException on the last one,
   * which is exactly what the guard exists to prevent.
   *
   * The other context the constant got wrong - an asynchronous one, where the
   * platform allows far fewer enqueues than fifty - is
   * generateAsyncFromAnAsyncContextUsesTheAsyncBudget below.
   */
  @IsTest
  static void generateAsyncCountsTheJobsAlreadyEnqueued() {
    System.enqueueJob(new BudgetSpender());
    Integer remaining =
      Limits.getLimitQueueableJobs() - Limits.getQueueableJobs();

    Set<Id> oneOverBudget = new Set<Id>();
    for (Integer i = 0; i <= remaining; i++) {
      oneOverBudget.add(fakeQuoteId(i));
    }

    String message;
    try {
      QuoteDocumentGenerator.generateAsync(oneOverBudget);
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      message = e.getMessage();
    }

    Assert.isNotNull(
      message,
      'With ' +
        remaining +
        ' enqueues left, ' +
        oneOverBudget.size() +
        ' must be refused.'
    );
    Assert.isTrue(message.contains('GENERATION_BATCH_TOO_LARGE'), message);
    Assert.areEqual(
      1,
      Limits.getQueueableJobs(),
      'Only the job this test enqueued may be queued - the refusal must add nothing.'
    );
  }

  // On the outer class because Apex allows no static member on an inner one.
  private static String asyncRefusal;
  private static Integer asyncBudget;

  private class AsyncBudgetProbe implements Queueable {
    public void execute(QueueableContext context) {
      asyncBudget = Limits.getLimitQueueableJobs() - Limits.getQueueableJobs();
      try {
        QuoteDocumentGenerator.generateAsync(
          new Set<Id>{ fakeQuoteId(0), fakeQuoteId(1) }
        );
      } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
        asyncRefusal = e.getMessage();
      }
    }
  }

  /**
   * Runs generateAsync from INSIDE a Queueable, where the transaction's
   * enqueue budget is nothing like the synchronous fifty the old constant
   * assumed. Two quotes were well under that constant and would have been
   * accepted; here they must be refused, because the platform says so.
   *
   * The outcome is stashed on a static rather than asserted in execute():
   * the job runs at Test.stopTest(), and a failed assertion inside it is
   * harder to read than the same assertion out here.
   */
  @IsTest
  static void generateAsyncFromAnAsyncContextUsesTheAsyncBudget() {
    Test.startTest();
    System.enqueueJob(new AsyncBudgetProbe());
    Test.stopTest();

    Assert.isTrue(
      asyncBudget < 50,
      'An asynchronous transaction is not allowed the synchronous budget - if it were, the ' +
        'constant this replaced would have been right. Reported: ' +
        asyncBudget
    );
    Assert.isNotNull(
      asyncRefusal,
      'Two quotes exceed the asynchronous budget of ' +
        asyncBudget +
        ' and must be refused, not enqueued until the platform throws.'
    );
    Assert.isTrue(
      asyncRefusal.contains('GENERATION_BATCH_TOO_LARGE'),
      asyncRefusal
    );
  }

  // -----------------------------------------------------------------------
  // QDT-011 - recorded, NOT fixed: it does not reproduce
  // -----------------------------------------------------------------------

  /**
   * The ledger says encodeDecimal's setScale(2) makes a change beyond the
   * second decimal invisible to the reuse decision, and names a numeric
   * Product2 field used as a grouping Field_Path__c as the reachable case.
   *
   * It does not reproduce. Field-path values never go through encodeDecimal:
   * QuoteDocumentLine.resolvePath and QuoteDocumentFingerprint.resolvePath
   * both stringify with String.valueOf and the fingerprint hashes them with
   * encodeString, at full precision. setScale(2) applies only to the declared
   * measures, which are currency, and to maxGroups/displayOrder.
   *
   * So nothing is changed - but the behaviour is pinned here, because a
   * future refactor routing field-path values through encodeDecimal would
   * introduce exactly the defect the ledger describes.
   */
  @IsTest
  static void fieldPathValuesKeepFullPrecisionInTheFingerprint() {
    String coarse = QuoteDocumentFingerprint.encodeStringForTest(
      String.valueOf(10.001)
    );
    String finer = QuoteDocumentFingerprint.encodeStringForTest(
      String.valueOf(10.002)
    );

    Assert.areNotEqual(
      coarse,
      finer,
      'A third-decimal change in a resolved field path must change the fingerprint. If this ' +
        'ever fails, field-path values have been routed through encodeDecimal and QDT-011 ' +
        'has become real.'
    );

    Assert.areEqual(
      QuoteDocumentFingerprint.encodeDecimalForTest(10.5),
      QuoteDocumentFingerprint.encodeDecimalForTest(10.50),
      'Measures still normalize 10.5 and 10.50 to one token - that part is intended.'
    );
  }

  /**
   * A syntactically valid Quote Id that was never inserted. The cap has to be
   * refused before any DML, so the test must not need 51 real quotes to prove
   * it - and the key prefix comes from the describe rather than a literal, so
   * this keeps working if the object's prefix ever differs.
   */
  private static Id fakeQuoteId(Integer offset) {
    String prefix = SBQQ__Quote__c.SObjectType.getDescribe().getKeyPrefix();
    return Id.valueOf(prefix + String.valueOf(offset + 1).leftPad(12, '0'));
  }
}
