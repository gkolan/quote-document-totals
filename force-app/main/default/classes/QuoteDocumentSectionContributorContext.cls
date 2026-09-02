/** Read-only business context supplied to an Apex or Flow document composer. */
public with sharing class QuoteDocumentSectionContributorContext {
  public SBQQ__Quote__c quote { get; private set; }
  public List<QuoteDocumentLine> lines { get; private set; }
  public List<Quote_Document_Fact__c> documentFacts { get; private set; }
  public String locale { get; private set; }
  public String currencyIsoCode { get; private set; }
  public String contributorCode { get; private set; }
  public String contributorVersion { get; private set; }

  public QuoteDocumentSectionContributorContext(
    SBQQ__Quote__c quote,
    List<QuoteDocumentLine> lines,
    List<Quote_Document_Fact__c> documentFacts,
    String locale,
    String currencyIsoCode,
    String contributorCode,
    String contributorVersion
  ) {
    this.quote = quote;
    this.lines = lines == null
      ? new List<QuoteDocumentLine>()
      : new List<QuoteDocumentLine>(lines);
    this.documentFacts = documentFacts == null
      ? new List<Quote_Document_Fact__c>()
      : new List<Quote_Document_Fact__c>(documentFacts);
    this.locale = locale;
    this.currencyIsoCode = currencyIsoCode;
    this.contributorCode = contributorCode;
    this.contributorVersion = contributorVersion;
  }
}
