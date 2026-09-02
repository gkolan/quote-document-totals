/** Fails clearly when an output adapter receives a neutral shape it does not support. */
public with sharing class QuoteDocumentContractVersion {
  /** Validates the payload version before any formatting occurs. */
  public static void requireSupported(QuoteDocumentPayload payload) {
    String received = payload == null ? null : payload.contractVersion;
    if (!QuoteDocumentPayload.CONTRACT_VERSION.equals(received)) {
      throw QuoteDocumentContributorError.build(
        'DOCUMENT_CONTRACT_VERSION_UNSUPPORTED',
        'This adapter supports contract ' +
          QuoteDocumentPayload.CONTRACT_VERSION +
          ' but received ' +
          received +
          '.'
      );
    }
  }
}
