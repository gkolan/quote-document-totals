@IsTest
private class QuoteDocumentRowBlockAdapterTest {
  @IsTest
  static void rowBlocksRenderBeforeAndAfterTheirCommercialRow() {
    QuoteDocumentPayload payload = new QuoteDocumentPayload();
    payload.quoteNumber = 'Q-ROW-BLOCK';
    payload.locale = 'en_US';
    payload.currencyIsoCode = 'USD';

    QuoteDocumentPayload.Column product = new QuoteDocumentPayload.Column();
    product.code = 'PRODUCT';
    product.label = 'Product';
    product.dataType = 'Text';

    QuoteDocumentPayload.Column amount = new QuoteDocumentPayload.Column();
    amount.code = 'CUSTOMER_PRICE';
    amount.label = 'Customer Price';
    amount.dataType = 'Currency';

    QuoteDocumentPayload.Row row = new QuoteDocumentPayload.Row();
    row.key = 'ROW-1';
    row.rowType = 'Detail';
    row.totalRole = 'Line Extension';
    row.values.put('PRODUCT', 'Implementation');
    row.values.put('CUSTOMER_PRICE', Decimal.valueOf(12000));
    row.blocks.add(
      block('BEFORE', 'Before Row', 'Read before the service Row.')
    );

    QuoteDocumentPayload.Row payable = new QuoteDocumentPayload.Row();
    payable.key = 'SERVICES:PAYABLE';
    payable.rowType = 'Grand Total';
    payable.totalRole = 'Payable';
    payable.values.put('PRODUCT', 'Services Total');
    payable.values.put('CUSTOMER_PRICE', Decimal.valueOf(12000));
    payable.blocks.add(
      block(
        'PAYABLE_NOTE',
        'Full Width After Row',
        'Taxes, if applicable, are shown separately.'
      )
    );
    row.blocks.add(
      block('AFTER', 'Full Width After Row', 'Scope follows the service Row.')
    );

    QuoteDocumentPayload.Section section = new QuoteDocumentPayload.Section();
    section.sectionType = 'Table';
    section.code = 'SERVICES';
    section.columns = new List<QuoteDocumentPayload.Column>{ product, amount };
    section.rows = new List<QuoteDocumentPayload.Row>{ row, payable };
    payload.sections.add(section);

    String html = QuoteDocumentHtmlAdapter.render(payload);
    Integer beforePosition = html.indexOf('Read before the service Row.');
    Integer rowPosition = html.indexOf('Implementation');
    Integer afterPosition = html.indexOf('Scope follows the service Row.');

    Assert.isTrue(
      beforePosition < rowPosition,
      'Before Row wording must render before the commercial Row.'
    );
    Assert.isTrue(
      afterPosition > rowPosition,
      'Full Width After Row wording must render after the commercial Row.'
    );
    Assert.isTrue(
      html.contains('data-placement="Full Width After Row"'),
      'Placement must remain explicit in output.'
    );
    Assert.isTrue(
      html.indexOf('Taxes, if applicable, are shown separately.') >
      html.indexOf('Services Total'),
      'A Payable total Row may carry its own governed Block in the same Table.'
    );
  }

  private static QuoteDocumentPayload.Block block(
    String code,
    String placement,
    String body
  ) {
    QuoteDocumentPayload.Block block = new QuoteDocumentPayload.Block();
    block.code = code;
    block.blockType = 'Notice';
    block.placement = placement;
    block.body = body;
    return block;
  }
}
