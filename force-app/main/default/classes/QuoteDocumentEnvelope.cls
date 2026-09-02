/** Applies migration-safe defaults and validates the neutral document identity. */
public with sharing class QuoteDocumentEnvelope {
  private static final Set<String> TYPES = new Set<String>{
    'Quote',
    'Proposal',
    'Order Form',
    'Order Agreement',
    'Purchase Order',
    'Statement of Work',
    'Amendment',
    'Renewal',
    'Change Order',
    'Cancellation'
  };
  private static final Set<String> CHANGE_TYPES = new Set<String>{
    'Amendment',
    'Renewal',
    'Change Order',
    'Cancellation'
  };

  /** Returns Order Form for records created before Document Type existed. */
  public static String documentType(SBQQ__Quote__c quote) {
    String configured = quote == null
      ? null
      : (String) quote.getPopulatedFieldsAsMap().get('Document_Type__c');
    return String.isBlank(configured) ? 'Order Form' : configured;
  }

  /** Returns revision 1 for records created before Document Revision existed. */
  public static Decimal revision(SBQQ__Quote__c quote) {
    Decimal configured = quote == null
      ? null
      : (Decimal) quote.getPopulatedFieldsAsMap().get('Document_Revision__c');
    return configured == null ? 1 : configured;
  }

  /** Returns no prior reference when the migration field was not queried. */
  public static String priorDocumentReference(SBQQ__Quote__c quote) {
    return quote == null
      ? null
      : (String) quote
          .getPopulatedFieldsAsMap()
          .get('Prior_Document_Reference__c');
  }

  /** Stops generation when the document identity is incomplete or contradictory. */
  public static void validate(SBQQ__Quote__c quote) {
    String type = documentType(quote);
    Decimal revisionNumber = revision(quote);
    if (!TYPES.contains(type)) {
      fail(
        'DOCUMENT_TYPE_INVALID',
        'Document Type "' + type + '" is not supported.'
      );
    }
    if (revisionNumber < 1 || revisionNumber.scale() != 0) {
      fail(
        'DOCUMENT_REVISION_INVALID',
        'Document Revision must be a positive whole number.'
      );
    }
    if (
      CHANGE_TYPES.contains(type) &&
      String.isBlank(priorDocumentReference(quote))
    ) {
      fail(
        'PRIOR_DOCUMENT_REQUIRED',
        type + ' requires Prior Document Reference before generation.'
      );
    }
  }

  private static void fail(String code, String detail) {
    throw QuoteDocumentContributorError.build(code, detail);
  }
}
