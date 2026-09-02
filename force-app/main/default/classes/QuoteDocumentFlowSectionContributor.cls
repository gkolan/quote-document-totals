/** Runs an autolaunched Flow that contributes complete document sections. */
public with sharing class QuoteDocumentFlowSectionContributor {
  /**
   * The Flow accepts quoteId, locale, currencyIsoCode, documentType, revision,
   * and quoteLineIds. It returns any of tables, columns, rows, blocks, facts.
   */
  public static QuoteDocumentSectionContributorOutput compose(
    String flowApiName,
    QuoteDocumentSectionContributorContext context
  ) {
    List<String> quoteLineIds = new List<String>();
    for (QuoteDocumentLine line : context.lines) {
      quoteLineIds.add(String.valueOf(line.quoteLineId));
    }
    Map<String, Object> inputs = new Map<String, Object>{
      'quoteId' => String.valueOf(context.quote.Id),
      'locale' => context.locale,
      'currencyIsoCode' => context.currencyIsoCode,
      'documentType' => QuoteDocumentEnvelope.documentType(context.quote),
      'revision' => QuoteDocumentEnvelope.revision(context.quote),
      'quoteLineIds' => quoteLineIds,
      'sourceLines' => context.quote.SBQQ__LineItems__r,
      'documentFacts' => context.documentFacts
    };

    Flow.Interview interview;
    try {
      interview = Flow.Interview.createInterview(flowApiName, inputs);
      interview.start();
    } catch (Exception e) {
      throw QuoteDocumentContributorError.build(
        QuoteDocumentContributorError.FLOW_FAULT,
        'Document composer Flow "' +
          flowApiName +
          '" could not complete. ' +
          e.getMessage()
      );
    }

    QuoteDocumentSectionContributorOutput output = new QuoteDocumentSectionContributorOutput();
    output.tables = tables(interview.getVariableValue('tables'));
    output.columns = columns(interview.getVariableValue('columns'));
    output.rows = rows(interview.getVariableValue('rows'));
    output.blocks = blocks(interview.getVariableValue('blocks'));
    output.facts = facts(interview.getVariableValue('facts'));
    return output;
  }

  private static List<Quote_Document_Table__c> tables(Object value) {
    return value == null
      ? new List<Quote_Document_Table__c>()
      : (List<Quote_Document_Table__c>) value;
  }
  private static List<Quote_Document_Column__c> columns(Object value) {
    return value == null
      ? new List<Quote_Document_Column__c>()
      : (List<Quote_Document_Column__c>) value;
  }
  private static List<Quote_Document_Row__c> rows(Object value) {
    return value == null
      ? new List<Quote_Document_Row__c>()
      : (List<Quote_Document_Row__c>) value;
  }
  private static List<Quote_Document_Block__c> blocks(Object value) {
    return value == null
      ? new List<Quote_Document_Block__c>()
      : (List<Quote_Document_Block__c>) value;
  }
  private static List<Quote_Document_Fact__c> facts(Object value) {
    return value == null
      ? new List<Quote_Document_Fact__c>()
      : (List<Quote_Document_Fact__c>) value;
  }
}
