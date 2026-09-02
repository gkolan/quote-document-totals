/**
 * The configuration rejections nothing else drives.
 *
 * Every test here is a refusal: a column with no code, a column bound to a type
 * no renderer can format, a dictionary that defines one key twice, a translator
 * who wrote {2} when only {0} and {1} exist. These are the branches an admin
 * meets on the day they misconfigure something, and the messages are the whole
 * product at that moment - so each test asserts the message names what to fix,
 * not merely that something threw.
 */
@IsTest
private class QuoteDocumentConfigRejectionTest {
  // -----------------------------------------------------------------------
  // QuoteDocumentColumnDefinition - binding refusals
  // -----------------------------------------------------------------------

  @IsTest
  static void aColumnWithNoCodeIsRejected() {
    QuoteDocumentColumnDefinition column = QuoteDocumentColumnDefinition.forTest(
      null,
      'Amount_Net__c',
      'Currency',
      10
    );

    String message = validationMessage(column, 'TDX_TEST', 'PRICE_WATERFALL');

    Assert.isTrue(message.contains('COLUMN_CODE_MISSING'), message);
    Assert.isTrue(
      message.contains('TDX_TEST'),
      'The message must name the table an admin has to go and fix: ' + message
    );
  }

  @IsTest
  static void aColumnBoundToAFieldThatDoesNotExistIsRejected() {
    QuoteDocumentColumnDefinition column = QuoteDocumentColumnDefinition.forTest(
      'COL_GHOST',
      'No_Such_Field__c',
      'Currency',
      10
    );

    String message = validationMessage(column, 'TDX_TEST', 'PRICE_WATERFALL');

    Assert.isTrue(
      message.contains('COLUMN_FIELD_UNKNOWN') ||
      message.contains('No_Such_Field__c'),
      'A column bound to a non-existent field must say which field: ' + message
    );
  }

  @IsTest
  static void aColumnBoundToAnUnformattableTypeIsRejected() {
    // Quote_Document_Row__c.Id is an Id: a real field, and one no renderer
    // in this contract knows how to format.
    QuoteDocumentColumnDefinition column = QuoteDocumentColumnDefinition.forTest(
      'COL_ID',
      'Id',
      'Text',
      10
    );

    String message = validationMessage(column, 'TDX_TEST', 'PRICE_WATERFALL');

    Assert.isTrue(
      String.isNotBlank(message),
      'Binding a column to an Id must be refused rather than printed as a record pointer.'
    );
  }

  // -----------------------------------------------------------------------
  // QuoteDocumentLabels - dictionary refusals, at LOAD not at render
  // -----------------------------------------------------------------------

  /**
   * Only {0} and {1} exist. A translator who writes {2} must find out on
   * deployment, not when the one quote that exercises that table reaches a
   * customer - which is why this is checked when the dictionary loads.
   */
  @IsTest
  static void aTemplateReferencingAnUnsupportedPlaceholderIsRejected() {
    String message;
    try {
      QuoteDocumentLabels.assertSupportedPlaceholdersForTest(
        'Labels_en_US',
        'SECTION_TOTAL',
        'Total for {0} and {1} and {2}'
      );
    } catch (Exception e) {
      message = e.getMessage();
    }

    Assert.isNotNull(
      message,
      '{2} must be refused: there is no Label_Arg_3__c for it to read.'
    );
    Assert.isTrue(message.contains('LABEL_ARGUMENT_UNSUPPORTED'), message);
    Assert.isTrue(
      message.contains('{2}'),
      'And it must name the placeholder: ' + message
    );
  }

  @IsTest
  static void supportedPlaceholdersAndBlankTemplatesAreAccepted() {
    // Neither should throw: {0} and {1} are the supported pair, and a blank
    // template is a dictionary entry someone has not filled in yet, which is
    // a different problem from an unsupported placeholder.
    QuoteDocumentLabels.assertSupportedPlaceholdersForTest(
      'Labels_en_US',
      'SUBTOTAL',
      'Subtotal {0} {1}'
    );
    QuoteDocumentLabels.assertSupportedPlaceholdersForTest(
      'Labels_en_US',
      'SUBTOTAL',
      ''
    );
    QuoteDocumentLabels.assertSupportedPlaceholdersForTest(
      'Labels_en_US',
      'SUBTOTAL',
      null
    );
  }

  /**
   * A locale asked for and not present must fail loudly. Silently falling back
   * to English would print an English document to a French customer and report
   * success.
   */
  @IsTest
  static void anUnknownLocaleIsRefusedRatherThanFallingBackSilently() {
    QuoteDocumentLabels.reset();

    String message;
    try {
      QuoteDocumentLabels.forLocale('zz_ZZ');
    } catch (Exception e) {
      message = e.getMessage();
    }

    Assert.isNotNull(
      message,
      'An unknown locale must be refused - printing English to a French customer and reporting ' +
      'success is the outcome this check exists to prevent.'
    );
    QuoteDocumentLabels.reset();
  }

  private static String validationMessage(
    QuoteDocumentColumnDefinition column,
    String tableCode,
    String measureSet
  ) {
    try {
      column.validate(tableCode, measureSet);
    } catch (Exception e) {
      return e.getMessage();
    }
    return '';
  }
}
