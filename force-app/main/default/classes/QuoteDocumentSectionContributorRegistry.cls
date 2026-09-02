/** Controlled mapping from administrator-facing composer codes to reviewed Apex. */
public with sharing class QuoteDocumentSectionContributorRegistry {
  /** Resolves one approved Apex document composer. */
  public static QuoteDocumentSectionContributor resolve(String code) {
    switch on code {
      when 'ORDER_FORM_FAMILIES' {
        return new QuoteDocumentOrderFormSectionContributor();
      }
      when else {
        throw QuoteDocumentContributorError.build(
          'DOCUMENT_COMPOSER_UNKNOWN',
          'No approved Apex document composer is registered for code "' +
            code +
            '".'
        );
      }
    }
  }
}
