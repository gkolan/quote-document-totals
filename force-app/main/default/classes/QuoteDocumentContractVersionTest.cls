@IsTest
private class QuoteDocumentContractVersionTest {
  @IsTest
  static void supportedVersionPasses() {
    QuoteDocumentContractVersion.requireSupported(new QuoteDocumentPayload());
  }

  @IsTest
  static void unsupportedVersionFailsClearly() {
    QuoteDocumentPayload payload = new QuoteDocumentPayload();
    payload.contractVersion = '1.0';
    Exception caught;
    try {
      QuoteDocumentContractVersion.requireSupported(payload);
    } catch (Exception e) {
      caught = e;
    }
    Assert.isNotNull(
      caught,
      'An adapter must not guess how to read an unknown contract.'
    );
    Assert.isTrue(
      caught.getMessage().contains('DOCUMENT_CONTRACT_VERSION_UNSUPPORTED'),
      caught.getMessage()
    );
  }
}
