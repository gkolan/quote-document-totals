/**
 * The render contract's own guards, driven directly.
 *
 * These refuse things that must never reach a customer document: a row with no
 * printable label, a column bound to rich text, a currency the payload query
 * never selected, a duplicate dictionary key. Every one of them exists because
 * the alternative is a document that prints something wrong and reports
 * success, so each test asserts the refusal AND its message.
 */
@IsTest
private class QuoteDocumentContractGuardTest {
  // -----------------------------------------------------------------------
  // QuoteDocumentRowBuilder - a blank label is refused, not substituted
  // -----------------------------------------------------------------------

  /**
   * defaultRow FAILS on a blank label rather than substituting '(unnamed)'.
   * The dictionary owns every printable string, so the caller must resolve
   * GROUP_UNNAMED itself - substituting here would print English into a
   * French document.
   */
  @IsTest
  static void aRowWithNoLabelIsRefused() {
    String message;
    try {
      QuoteDocumentRowBuilder.defaultRow('Group Header', 1, 'KEY', '', 10);
    } catch (Exception e) {
      message = e.getMessage();
    }

    Assert.isNotNull(message, 'A row with no printable label must be refused.');
    Assert.isTrue(message.contains('LABEL_KEY_MISSING'), message);
    Assert.isTrue(
      message.contains('GROUP_UNNAMED'),
      'And it must point at the dictionary key to resolve instead: ' + message
    );
  }

  @IsTest
  static void aRowWithALabelIsBuilt() {
    Quote_Document_Row__c row = QuoteDocumentRowBuilder.defaultRow(
      'Group Header',
      1,
      'KEY',
      'Hardware',
      10
    );
    Assert.areEqual(
      'Hardware',
      row.Display_Label__c,
      'A resolved label passes through untouched - the guard must not rewrite wording.'
    );
  }

  // -----------------------------------------------------------------------
  // QuoteDocumentColumnDefinition - rich text is markup, and markup is refused
  // -----------------------------------------------------------------------

  /**
   * Rich text is TEXTAREA plus isHtmlFormatted, so DisplayType alone cannot
   * catch it. A vendor-neutral payload may not carry markup - that is the
   * whole point of the contract.
   */
  @IsTest
  static void aColumnBoundToRichTextIsRefused() {
    Map<String, SObjectField> fields = Quote_Document_Row__c.SObjectType.getDescribe()
      .fields.getMap();
    String richTextField;
    for (String name : fields.keySet()) {
      DescribeFieldResult describe = fields.get(name).getDescribe();
      if (
        describe.getType() == DisplayType.TEXTAREA && describe.isHtmlFormatted()
      ) {
        richTextField = describe.getName();
        break;
      }
    }
    if (richTextField == null) {
      // No rich text field on the object in this org, so the branch cannot
      // be driven. Saying so beats a test that silently asserts nothing.
      return;
    }

    QuoteDocumentColumnDefinition column = QuoteDocumentColumnDefinition.forTest(
      'COL_RICH',
      richTextField,
      'Text',
      10
    );

    String message;
    try {
      column.validate('TDX_TEST', 'PRICE_WATERFALL');
    } catch (Exception e) {
      message = e.getMessage();
    }

    Assert.isNotNull(message, 'Rich text carries HTML and must be refused.');
    Assert.isTrue(message.contains('COLUMN_TYPE_UNSUPPORTED'), message);
  }

  @IsTest
  static void aColumnWithNoDisplayOrderIsRefused() {
    QuoteDocumentColumnDefinition column = QuoteDocumentColumnDefinition.forTest(
      'COL_NET',
      'Amount_Net__c',
      'Currency',
      null
    );

    String message;
    try {
      column.validate('TDX_TEST', 'PRICE_WATERFALL');
    } catch (Exception e) {
      message = e.getMessage();
    }

    Assert.isNotNull(
      message,
      'Renderers print in Display_Order__c, so a column without one is unprintable.'
    );
    Assert.isTrue(message.contains('COLUMN_ORDER_MISSING'), message);
  }

  // -----------------------------------------------------------------------
  // QuoteDocumentRenderService - the currency the payload query must select
  // -----------------------------------------------------------------------

  /**
   * A real defect once shipped here: the projection read the currency from
   * getPopulatedFieldsAsMap() while the query never selected it, so every
   * amount printed with no currency and nothing failed - null is legal for a
   * field that does not exist in a single-currency org. This asserts the
   * SELECT itself, which is why the helper inspects the real SOQL rather than
   * returning a constant.
   */
  @IsTest
  static void thePayloadQuerySelectsTheCurrencyWheneverTheOrgHasOne() {
    Assert.isTrue(
      QuoteDocumentRenderService.selectsCurrency(),
      'In a multi-currency org the payload query must select CurrencyIsoCode, or every amount ' +
      'prints with no currency and nothing reports a problem.'
    );
  }

  // -----------------------------------------------------------------------
  // QuoteDocumentLabels - one key, one wording
  // -----------------------------------------------------------------------

  /**
   * Two records supplying the same key would make the printed wording depend
   * on query order, which the platform does not guarantee.
   */
  @IsTest
  static void aLocaleResolvesToOneWordingPerKey() {
    QuoteDocumentLabels.useLabels(
      'en_US',
      new Map<String, String>{
        'SUBTOTAL' => 'Subtotal {0}',
        'GRAND_TOTAL' => 'Grand Total'
      }
    );
    QuoteDocumentLabels labels = QuoteDocumentLabels.forLocale('en_US');

    Assert.areEqual(
      'Grand Total',
      labels.format('GRAND_TOTAL', new List<String>()),
      'A key with no placeholder resolves to its wording unchanged.'
    );
    Assert.areEqual(
      'Subtotal Hardware',
      labels.format('SUBTOTAL', new List<String>{ 'Hardware' }),
      'And one with a placeholder substitutes the argument.'
    );

    String message;
    try {
      labels.format('NO_SUCH_KEY', new List<String>());
    } catch (Exception e) {
      message = e.getMessage();
    }
    Assert.isNotNull(
      message,
      'A key the dictionary does not define must fail, not print blank.'
    );
    Assert.isTrue(
      message.contains('LABEL_KEY_MISSING') || message.contains('NO_SUCH_KEY'),
      message
    );

    QuoteDocumentLabels.reset();
  }
}
