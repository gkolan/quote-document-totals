/**
 * The integrity guards between a stored snapshot and a rendered payload, plus
 * the adapter and customizer edges nothing else reaches.
 *
 * Every check here answers "the snapshot changed after publication" or "the
 * snapshot was never finished". Both produce a document that looks fine and is
 * wrong, which is why they refuse rather than degrade.
 */
@IsTest
private class QuoteDocumentIntegrityGuardTest {
  @TestSetup
  static void setup() {
    QuoteDocumentTestData.setup();
  }

  // -----------------------------------------------------------------------
  // Rows added or removed after publication
  // -----------------------------------------------------------------------

  /**
   * Row_Count__c is stamped at publication. If the rows no longer match it,
   * something edited the snapshot afterwards and the payload must be refused -
   * printing it would present edited numbers as published ones.
   */
  @IsTest
  static void aRowDeletedAfterPublicationIsRefused() {
    Id quoteId = QuoteDocumentTestData.quoteId();

    Test.startTest();
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
    Test.stopTest();

    SBQQ__Quote__c quote = expectations(quoteId);
    Quote_Document_Table__c table = [
      SELECT Id
      FROM Quote_Document_Table__c
      WHERE Quote__c = :quoteId AND Row_Count__c > 1
      LIMIT 1
    ];
    Quote_Document_Row__c victim = [
      SELECT Id
      FROM Quote_Document_Row__c
      WHERE Quote_Document_Table__c = :table.Id
      LIMIT 1
    ];
    Database.delete(victim, true, AccessLevel.SYSTEM_MODE);

    QuoteDocumentPayload.PayloadResult result = QuoteDocumentRenderService.getPayloads(
      new List<QuoteDocumentPayload.PayloadRequest>{
        new QuoteDocumentPayload.PayloadRequest(
          quote.Id,
          quote.Document_Data_Request_Id__c,
          quote.Document_Data_Fingerprint__c
        )
      }
    )[0];

    Assert.isFalse(
      result.success,
      'A snapshot edited after publication must not render.'
    );
    // The CODE matters, not merely that something failed. Asserting only
    // "not success" let this pass on PAYLOAD_INTEGRITY_MISMATCH - the hash
    // catching the edit before the row-count guard ever ran - so the test
    // claimed to cover a guard it never reached. Either code is a correct
    // refusal; naming both is what stops the test drifting into vacuity.
    Assert.isTrue(
      result.errorCode == 'PAYLOAD_INTEGRITY_MISMATCH' ||
        result.errorCode == 'TABLE_ROW_COUNT_MISMATCH',
      'Expected the integrity hash or the row-count guard to refuse, got: ' +
        result.errorCode +
        ' / ' +
        result.errorMessage
    );
  }

  /**
   * A table left mid-generation carries rows belonging to a run that never
   * finished. Rendering it would publish a partial document as a whole one.
   */
  @IsTest
  static void aTableLeftIncompleteIsRefused() {
    Id quoteId = QuoteDocumentTestData.quoteId();

    Test.startTest();
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
    Test.stopTest();

    SBQQ__Quote__c quote = expectations(quoteId);
    Quote_Document_Table__c table = [
      SELECT Id, Status__c
      FROM Quote_Document_Table__c
      WHERE Quote__c = :quoteId
      LIMIT 1
    ];
    table.Status__c = 'Generating';
    Database.update(table, true, AccessLevel.SYSTEM_MODE);

    QuoteDocumentPayload.PayloadResult result = QuoteDocumentRenderService.getPayloads(
      new List<QuoteDocumentPayload.PayloadRequest>{
        new QuoteDocumentPayload.PayloadRequest(
          quote.Id,
          quote.Document_Data_Request_Id__c,
          quote.Document_Data_Fingerprint__c
        )
      }
    )[0];

    Assert.isFalse(
      result.success,
      'A table that is not Complete must not render.'
    );
    Assert.isTrue(
      result.errorCode == 'PAYLOAD_INTEGRITY_MISMATCH' ||
        result.errorCode == 'TABLE_NOT_COMPLETE',
      'Expected the integrity hash or the completeness guard to refuse, got: ' +
        result.errorCode +
        ' / ' +
        result.errorMessage
    );
  }

  /**
   * A payload retrieved with the wrong expectations is refused even though the
   * snapshot itself is perfectly good: the launch contract binds a retrieval
   * to the generation that produced it.
   */
  @IsTest
  static void staleExpectationsAreRefusedEvenOnAGoodSnapshot() {
    Id quoteId = QuoteDocumentTestData.quoteId();

    Test.startTest();
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
    Test.stopTest();

    QuoteDocumentPayload.PayloadResult result = QuoteDocumentRenderService.getPayloads(
      new List<QuoteDocumentPayload.PayloadRequest>{
        new QuoteDocumentPayload.PayloadRequest(
          quoteId,
          'not-the-request-id',
          'not-the-fingerprint'
        )
      }
    )[0];

    Assert.isFalse(
      result.success,
      'A retrieval must be bound to the generation that produced the snapshot.'
    );
    Assert.isTrue(
      result.errorCode == 'SNAPSHOT_MOVED' ||
        result.errorCode == 'LAUNCH_CONTRACT_BYPASSED',
      'And it must name WHY - the snapshot moved, or the caller never held real expectations: ' +
        result.errorCode +
        ' / ' +
        result.errorMessage
    );
  }

  // -----------------------------------------------------------------------
  // Adapters - both must render a real payload end to end
  // -----------------------------------------------------------------------

  @IsTest
  static void bothAdaptersRenderARealPayload() {
    Id quoteId = QuoteDocumentTestData.quoteId();

    Test.startTest();
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
    Test.stopTest();

    SBQQ__Quote__c quote = expectations(quoteId);
    QuoteDocumentPayload payload = QuoteDocumentRenderService.getPayload(
      quoteId,
      quote.Document_Data_Request_Id__c,
      quote.Document_Data_Fingerprint__c
    );

    String html = QuoteDocumentHtmlAdapter.render(payload);
    Assert.isTrue(
      String.isNotBlank(html),
      'The HTML adapter must produce something.'
    );
    Assert.isFalse(
      html.contains('(unnamed)'),
      'And it must never print the literal the dictionary exists to replace.'
    );

    String json = QuoteDocumentJsonAdapter.render(payload);
    Assert.isTrue(
      String.isNotBlank(json),
      'The JSON adapter must produce something.'
    );
    Assert.isTrue(
      json.contains('contractVersion'),
      'A consumer keys off the contract version, so it must survive serialization.'
    );
  }

  /**
   * Escaping is the reason the HTML adapter exists rather than string
   * concatenation at the call site: a product name carrying markup must print
   * as text, not as tags.
   */
  @IsTest
  static void theHtmlAdapterEscapesMarkupInContent() {
    QuoteDocumentPayload payload = new QuoteDocumentPayload();
    payload.quoteNumber = 'Q-1';
    QuoteDocumentPayload.Section section = new QuoteDocumentPayload.Section();
    section.sectionType = 'Table';
    section.code = 'TDX_ESCAPE';
    section.title = 'Widgets <script>alert(1)</script> & more';
    section.columns = new List<QuoteDocumentPayload.Column>();
    section.rows = new List<QuoteDocumentPayload.Row>();
    payload.sections = new List<QuoteDocumentPayload.Section>{ section };

    String html = QuoteDocumentHtmlAdapter.render(payload);

    Assert.isFalse(
      html.contains('<script>'),
      'Markup in content must be escaped, not emitted: ' + html
    );
    Assert.isTrue(
      html.contains('&amp;') || html.contains('&lt;'),
      'And the escaped form must actually appear: ' + html
    );
  }

  // -----------------------------------------------------------------------
  // Customizers - the "nothing to add" branches
  // -----------------------------------------------------------------------

  /**
   * Both synthetic-row customizers refuse to clutter a document with a
   * zero-value row. Driven with an empty row set, which is the degenerate
   * form of the same branch.
   */
  @IsTest
  static void customizersAddNothingWhenThereIsNothingToAdd() {
    QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
      'TDX_NOOP',
      new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
      new List<Integer>{ 1 },
      QuoteDocumentTableDefinition.FILTER_ALL
    );
    // Built field-by-field, the way QuoteDocumentGenerator builds it - the
    // context has no constructor taking these, and inventing one purely for
    // a test would widen production surface for the test's convenience.
    QuoteDocumentRowCustomizerContext context = new QuoteDocumentRowCustomizerContext();
    context.definition = definition;
    context.lines = new List<QuoteDocumentLine>();
    context.rows = new List<Quote_Document_Row__c>();
    context.labels = QuoteDocumentLabels.forLocale('en_US');

    Assert.areEqual(
      0,
      new QuoteDocumentDiscountRowCustomizer().customize(context).size(),
      'No rows means nothing to discount - and no zero-value row either.'
    );
    Assert.areEqual(
      0,
      new QuoteDocumentRoundingRowCustomizer().customize(context).size(),
      'No grand total means no rounding adjustment.'
    );
  }

  private static SBQQ__Quote__c expectations(Id quoteId) {
    return [
      SELECT Id, Document_Data_Request_Id__c, Document_Data_Fingerprint__c
      FROM SBQQ__Quote__c
      WHERE Id = :quoteId
    ];
  }
}
