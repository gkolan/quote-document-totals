/**
 * Regressions for the four findings of the independent review (2026-08-27).
 *
 * Three are behavioural fixes; the fourth was a hole in the permutation
 * checker's oracle and is covered by its own corruption probes rather than by
 * Apex. Each test here fails on the code as it stood before its fix.
 */
@IsTest
private class QuoteDocumentIndependentReviewTest {
  @TestSetup
  static void setup() {
    QuoteDocumentTestData.setup();
  }

  // -----------------------------------------------------------------------
  // P1 - grouping hierarchy was absent from the input fingerprint
  // -----------------------------------------------------------------------

  /**
   * "PRODUCT_FAMILY then CHARGE_TYPE" (two nested levels) and
   * "PRODUCT_FAMILY + CHARGE_TYPE" (one composite level) hashed to the same
   * fragment, because only the parts were encoded - never the level
   * boundaries or the part counts.
   *
   * The row builder treats those as completely different documents: one
   * nests, the other combines into single buckets. Metadata edits fire no
   * staleness trigger, so a Ready quote under STANDARD caching saw an
   * unchanged fingerprint and reused the old hierarchy, with payload
   * integrity passing because the stored output had never been edited.
   */
  @IsTest
  static void nestedAndCompositeGroupingsDoNotShareAFingerprint() {
    Id quoteId = QuoteDocumentTestData.quoteId();
    SBQQ__Quote__c quote = quoteFor(quoteId);
    List<QuoteDocumentLine> lines = linesFor(quote);

    QuoteDocumentTableDefinition nested = QuoteDocumentTableDefinition.build(
      'TDX_SHAPE',
      new List<String>{
        QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY,
        QuoteDocumentTableDefinition.DIM_CHARGE_TYPE
      },
      new List<Integer>{ 1, 2 }, // two levels: nested
      QuoteDocumentTableDefinition.FILTER_ALL
    );
    QuoteDocumentTableDefinition composite = QuoteDocumentTableDefinition.build(
      'TDX_SHAPE', // same code, same everything else
      new List<String>{
        QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY,
        QuoteDocumentTableDefinition.DIM_CHARGE_TYPE
      },
      new List<Integer>{ 1, 1 }, // one level, two parts: composite
      QuoteDocumentTableDefinition.FILTER_ALL
    );

    String nestedPrint = QuoteDocumentFingerprint.compute(
      quote,
      lines,
      new List<QuoteDocumentTableDefinition>{ nested }
    );
    String compositePrint = QuoteDocumentFingerprint.compute(
      quote,
      lines,
      new List<QuoteDocumentTableDefinition>{ composite }
    );

    Assert.areNotEqual(
      nestedPrint,
      compositePrint,
      'Nesting and compositing the same two dimensions produce different documents, so they ' +
        'must produce different fingerprints - otherwise changing one to the other leaves a ' +
        'Ready quote reusing the previous hierarchy.'
    );
  }

  // -----------------------------------------------------------------------
  // P2 - line order was absent from the input fingerprint
  // -----------------------------------------------------------------------

  /**
   * SBQQ__Number__c decides the printed order of detail rows and the order of
   * groups under LINE_SEQUENCE, but was never hashed. The line trigger marks
   * the quote Stale only through a deferred future call, so a
   * generate-or-reuse landing inside that window reused the old order.
   */
  @IsTest
  static void swappingLineOrderChangesTheFingerprint() {
    Id quoteId = QuoteDocumentTestData.quoteId();
    SBQQ__Quote__c quote = quoteFor(quoteId);

    List<QuoteDocumentTableDefinition> definitions = new List<QuoteDocumentTableDefinition>{
      QuoteDocumentTableDefinition.build(
        'TDX_ORDER',
        new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
        new List<Integer>{ 1 },
        QuoteDocumentTableDefinition.FILTER_ALL
      )
    };

    String before = QuoteDocumentFingerprint.compute(
      quote,
      linesFor(quote),
      definitions
    );

    // Swap the sequence of the first two lines and nothing else: same
    // products, same amounts, different printed order.
    List<SBQQ__QuoteLine__c> raw = [
      SELECT Id, SBQQ__Number__c
      FROM SBQQ__QuoteLine__c
      WHERE SBQQ__Quote__c = :quoteId
      ORDER BY SBQQ__Number__c
      LIMIT 2
    ];
    Decimal first = raw[0].SBQQ__Number__c;
    raw[0].SBQQ__Number__c = raw[1].SBQQ__Number__c;
    raw[1].SBQQ__Number__c = first;
    update raw;

    String after = QuoteDocumentFingerprint.compute(
      quoteFor(quoteId),
      linesFor(quoteFor(quoteId)),
      definitions
    );

    Assert.areNotEqual(
      before,
      after,
      'Swapping two line numbers changes what prints and in what order, so it must change the ' +
      'fingerprint - the deferred staleness write cannot be relied on to close that window.'
    );
  }

  // -----------------------------------------------------------------------
  // P2 - retention deleted snapshots for quotes accepted after selection
  // -----------------------------------------------------------------------

  /**
   * A batch selects its scope once and executes it later. execute() trusted
   * that scope, so a quote that became Accepted in between had its tables -
   * and, once block deletion was added, its contractual text - deleted anyway.
   */
  @IsTest
  static void retentionSkipsAQuoteAcceptedAfterTheScopeWasSelected() {
    Id quoteId = QuoteDocumentTestData.quoteId();

    Test.startTest();
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
    Test.stopTest();

    List<Quote_Document_Table__c> scope = [
      SELECT Id
      FROM Quote_Document_Table__c
      WHERE Quote__c = :quoteId
    ];
    Assert.isFalse(
      scope.isEmpty(),
      'The fixture must have generated something to retain.'
    );

    // The status changes AFTER the scope was captured - the race the fix is about.
    update new SBQQ__Quote__c(Id = quoteId, SBQQ__Status__c = 'Accepted');

    new QuoteDocumentRetention().execute(null, scope);

    Assert.areEqual(
      scope.size(),
      [SELECT COUNT() FROM Quote_Document_Table__c WHERE Quote__c = :quoteId],
      'An accepted quote must never be purged, even when it was eligible at selection time.'
    );
    Assert.areNotEqual(
      'Not Generated',
      [SELECT Document_Data_Status__c FROM SBQQ__Quote__c WHERE Id = :quoteId]
      .Document_Data_Status__c,
      'And its status must not be reset behind a surviving snapshot.'
    );
  }

  /**
   * The complement: a quote that is still eligible IS purged. A guard that
   * refuses everything looks identical to a correct one.
   */
  @IsTest
  static void retentionStillPurgesAQuoteThatRemainsEligible() {
    Id quoteId = QuoteDocumentTestData.quoteId();

    Test.startTest();
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
    Test.stopTest();

    update new SBQQ__Quote__c(Id = quoteId, SBQQ__Status__c = 'Rejected');

    List<Quote_Document_Table__c> scope = [
      SELECT Id
      FROM Quote_Document_Table__c
      WHERE Quote__c = :quoteId
    ];
    new QuoteDocumentRetention().execute(null, scope);

    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Quote_Document_Table__c WHERE Quote__c = :quoteId],
      'A rejected quote is exactly what retention exists to clear.'
    );
    Assert.areEqual(
      0,
      [SELECT COUNT() FROM Quote_Document_Block__c WHERE Quote__c = :quoteId],
      'And its narrative blocks go with it - they must not outlive the snapshot.'
    );
  }

  private static SBQQ__Quote__c quoteFor(Id quoteId) {
    return QuoteDocumentQuery.quotesWithLines(new Set<Id>{ quoteId })[0];
  }

  private static List<QuoteDocumentLine> linesFor(SBQQ__Quote__c quote) {
    List<QuoteDocumentLine> lines = new List<QuoteDocumentLine>();
    for (SBQQ__QuoteLine__c raw : quote.SBQQ__LineItems__r) {
      lines.add(new QuoteDocumentLine(raw, quote));
    }
    return lines;
  }
}
