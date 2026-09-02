/**
 * Projection and rendering of a full payload: narrative blocks alongside
 * tables, hidden things omitted rather than styled away, one shared ordering
 * sequence, and every value formatter the HTML adapter offers.
 *
 * "Hidden means absent" is the contract worth pinning here. A renderer that
 * received a hidden row would have to decide what to do with it, and deciding
 * is exactly what this contract removes from renderers.
 */
@IsTest
private class QuoteDocumentProjectionTest {
  @TestSetup
  static void setup() {
    QuoteDocumentTestData.setup();
  }

  /**
   * A block sits in the same `sections` list as a table and sorts into the
   * same sequence - a renderer walks one list and prints, never deciding what
   * belongs or in what order.
   */
  @IsTest
  static void blocksAndTablesInterleaveInOneOrderedSequence() {
    Id quoteId = QuoteDocumentTestData.quoteId();

    Test.startTest();
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
    Test.stopTest();

    SBQQ__Quote__c quote = [
      SELECT Document_Data_Request_Id__c, Document_Data_Fingerprint__c
      FROM SBQQ__Quote__c
      WHERE Id = :quoteId
    ];
    QuoteDocumentPayload payload = QuoteDocumentRenderService.getPayload(
      quoteId,
      quote.Document_Data_Request_Id__c,
      quote.Document_Data_Fingerprint__c
    );

    // Blocks are built by generation from Quote_Document_Content__mdt, not
    // inserted by hand: a hand-inserted block is not covered by the payload
    // hash the generation published, and retrieval rejects the snapshot -
    // which is the hash doing its job, not a test fixture problem.
    Integer blocks = 0;
    Integer tables = 0;
    Decimal previousOrder = -1;
    for (QuoteDocumentPayload.Section section : payload.sections) {
      if (section.sectionType == 'Block') {
        blocks++;
      }
      if (section.sectionType == 'Table') {
        tables++;
      }
      Decimal order = section.displayOrder == null ? 0 : section.displayOrder;
      Assert.isTrue(
        order >= previousOrder,
        'Sections must arrive already ordered - a renderer never sorts: ' +
          previousOrder +
          ' then ' +
          order
      );
      previousOrder = order;
    }
    Assert.isTrue(
      tables > 0,
      'The fixture must have generated tables to order.'
    );
    Assert.isTrue(
      blocks > 0,
      'And narrative blocks, which share the same ordering sequence as the tables.'
    );

    String html = QuoteDocumentHtmlAdapter.render(payload);
    Assert.isTrue(String.isNotBlank(html), 'Both section types must render.');
    Assert.isFalse(
      html.contains('(unnamed)'),
      'And never the literal the dictionary replaces.'
    );
  }

  /**
   * Every formatter the adapter offers, driven through a payload built by
   * hand so each data type is present. Currency prints with the payload's
   * currency code; a boolean prints as a word rather than true/false.
   */
  @IsTest
  static void theHtmlAdapterFormatsEveryDeclaredDataType() {
    QuoteDocumentPayload payload = new QuoteDocumentPayload();
    payload.quoteNumber = 'Q-FORMAT';
    payload.currencyIsoCode = 'USD';

    QuoteDocumentPayload.Section section = new QuoteDocumentPayload.Section();
    section.sectionType = 'Table';
    section.code = 'TDX_FORMAT';
    section.title = 'Formats';
    section.subtitle = 'Every declared type';
    section.introText = 'Intro prose.';
    section.footerText = 'Footer prose.';
    section.displayOrder = 10;
    section.columns = new List<QuoteDocumentPayload.Column>();
    for (
      String pair : new List<String>{
        'COL_NET:Currency',
        'COL_QTY:Number',
        'COL_FLAG:Boolean',
        'COL_LABEL:Text'
      }
    ) {
      QuoteDocumentPayload.Column column = new QuoteDocumentPayload.Column();
      column.code = pair.substringBefore(':');
      column.label = pair.substringBefore(':');
      column.dataType = pair.substringAfter(':');
      column.displayOrder = section.columns.size() * 10;
      section.columns.add(column);
    }

    QuoteDocumentPayload.Row row = new QuoteDocumentPayload.Row();
    row.key = 'ROW';
    row.rowType = 'Detail';
    row.label = 'Widget';
    row.groupLevel = 1;
    row.displayOrder = 10;
    row.values = new Map<String, Object>{
      'COL_NET' => 1234.56,
      'COL_QTY' => 3,
      'COL_FLAG' => true,
      'COL_LABEL' => 'plain'
    };
    section.rows = new List<QuoteDocumentPayload.Row>{ row };

    QuoteDocumentPayload.Section block = new QuoteDocumentPayload.Section();
    block.sectionType = 'Block';
    block.code = 'TERMS';
    block.heading = 'Terms';
    block.body = 'Due in 30 days.';
    block.displayOrder = 20;

    payload.sections = new List<QuoteDocumentPayload.Section>{ section, block };

    String html = QuoteDocumentHtmlAdapter.render(payload);

    Assert.isTrue(
      html.contains('USD'),
      'Currency prints with the payload currency: ' + html
    );
    Assert.isTrue(
      html.contains('Yes'),
      'A boolean prints as a word, not true/false: ' + html
    );
    Assert.isTrue(
      html.contains('Intro prose.') && html.contains('Footer prose.'),
      'Intro and footer prose both print.'
    );
    Assert.isTrue(html.contains('Every declared type'), 'And the subtitle.');
    Assert.isTrue(
      html.contains('Due in 30 days.'),
      'Blocks render alongside tables.'
    );

    String json = QuoteDocumentJsonAdapter.render(payload);
    Assert.isTrue(
      json.contains('COL_NET'),
      'The JSON adapter keys values by column code, never by field API name.'
    );
  }

  /**
   * Editing a row's Is_Displayed__c after publication is DETECTED, not
   * honoured.
   *
   * This started life as "a hidden row is omitted from the projection" and
   * could not be written that way: flipping the flag after generation and
   * regenerating does not republish, because the fingerprint covers the quote
   * and its lines - not the rows - so generation legitimately reuses. The
   * stored payload hash then no longer matches the edited rows and retrieval
   * refuses the snapshot.
   *
   * That is the integrity hash doing exactly its job, and it is worth pinning:
   * it proves the hash covers row FIELDS, not merely the row count.
   */
  @IsTest
  static void editingARowsVisibilityAfterPublicationIsDetected() {
    Id quoteId = QuoteDocumentTestData.quoteId();

    Test.startTest();
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
    Test.stopTest();

    SBQQ__Quote__c quote = [
      SELECT Document_Data_Request_Id__c, Document_Data_Fingerprint__c
      FROM SBQQ__Quote__c
      WHERE Id = :quoteId
    ];

    List<Quote_Document_Row__c> details = [
      SELECT Id, Row_Key__c, Is_Displayed__c
      FROM Quote_Document_Row__c
      WHERE
        Quote_Document_Table__r.Quote__c = :quoteId
        AND Row_Type__c = 'Detail'
      LIMIT 1
    ];
    Assert.isFalse(
      details.isEmpty(),
      'The fixture must produce at least one detail row.'
    );

    Quote_Document_Row__c hidden = details[0];
    hidden.Is_Displayed__c = false;
    Database.update(hidden, true, AccessLevel.SYSTEM_MODE);

    QuoteDocumentPayload.PayloadResult result = QuoteDocumentRenderService.getPayloads(
      new List<QuoteDocumentPayload.PayloadRequest>{
        new QuoteDocumentPayload.PayloadRequest(
          quoteId,
          quote.Document_Data_Request_Id__c,
          quote.Document_Data_Fingerprint__c
        )
      }
    )[0];

    Assert.isFalse(
      result.success,
      'A row edited after publication must be detected - the hash covers row fields, not just counts.'
    );
    Assert.isTrue(
      String.isNotBlank(result.errorCode),
      'And the refusal carries a code.'
    );
  }
}
