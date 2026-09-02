@IsTest
private class QuoteDocumentEnvelopeTest {
  @IsTest
  static void legacyQuoteUsesOrderFormRevisionOne() {
    SBQQ__Quote__c quote = new SBQQ__Quote__c();
    Assert.areEqual('Order Form', QuoteDocumentEnvelope.documentType(quote));
    Assert.areEqual(Decimal.valueOf(1), QuoteDocumentEnvelope.revision(quote));
    QuoteDocumentEnvelope.validate(quote);
  }

  @IsTest
  static void amendmentRequiresPriorDocumentReference() {
    SBQQ__Quote__c quote = new SBQQ__Quote__c(
      Document_Type__c = 'Amendment',
      Document_Revision__c = 2
    );
    Exception caught;
    try {
      QuoteDocumentEnvelope.validate(quote);
    } catch (Exception e) {
      caught = e;
    }
    Assert.isNotNull(
      caught,
      'An Amendment must identify the document it changes.'
    );
    Assert.isTrue(
      caught.getMessage().contains('PRIOR_DOCUMENT_REQUIRED'),
      caught.getMessage()
    );
  }

  @IsTest
  static void validChangeDocumentPasses() {
    SBQQ__Quote__c quote = new SBQQ__Quote__c(
      Document_Type__c = 'Change Order',
      Document_Revision__c = 3,
      Prior_Document_Reference__c = 'OF-000104 / Revision 2'
    );
    QuoteDocumentEnvelope.validate(quote);
  }
}
