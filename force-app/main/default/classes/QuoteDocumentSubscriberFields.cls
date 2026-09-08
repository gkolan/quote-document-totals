/**
 * Validated, append-only subscriber Quote dependencies.
 *
 * Core watched fields remain authoritative. Active subscriber records add to
 * that set; they cannot remove a core dependency. The same ordered records
 * feed query selection, trigger staleness, and fingerprinting so those three
 * contracts cannot drift independently.
 */
public with sharing class QuoteDocumentSubscriberFields {
  private static final String SUBSCRIBER_PREFIX = 'SUB_';
  private static final Set<String> PROTECTED_FIELDS = new Set<String>{
    'document_data_status__c',
    'document_data_error__c',
    'document_data_fingerprint__c',
    'document_data_generated_on__c',
    'document_data_request_id__c',
    'document_data_started_at__c',
    'document_payload_hash__c'
  };

  @TestVisible
  private static List<Quote_Document_Watched_Field__mdt> testRecords;

  public static List<String> quoteFieldPaths() {
    List<String> paths = new List<String>(definitionsByPath().keySet());
    paths.sort();
    return paths;
  }

  /** Stable configuration and value fragments added to the input fingerprint. */
  public static List<String> fingerprintParts(SBQQ__Quote__c quote) {
    Map<String, Quote_Document_Watched_Field__mdt> byPath = definitionsByPath();
    List<String> paths = new List<String>(byPath.keySet());
    paths.sort();
    List<String> parts = new List<String>();
    for (String fieldPath : paths) {
      Quote_Document_Watched_Field__mdt record = byPath.get(fieldPath);
      Object value = quote.get(fieldPath);
      parts.add(
        record.DeveloperName +
          '|' +
          record.Version__c.trim() +
          '|' +
          fieldPath +
          '|' +
          (value == null ? '(null)' : String.valueOf(value))
      );
    }
    return parts;
  }

  private static Map<String, Quote_Document_Watched_Field__mdt> definitionsByPath() {
    Map<String, Quote_Document_Watched_Field__mdt> byPath = new Map<String, Quote_Document_Watched_Field__mdt>();
    Set<String> normalizedPaths = new Set<String>();
    for (Quote_Document_Watched_Field__mdt record : activeRecords()) {
      validateIdentity(record);
      String fieldPath = validatedFieldName(record);
      if (!normalizedPaths.add(fieldPath.toLowerCase())) {
        throw invalid(
          record,
          'duplicates another active subscriber watched field.'
        );
      }
      byPath.put(fieldPath, record);
    }
    return byPath;
  }

  private static List<Quote_Document_Watched_Field__mdt> activeRecords() {
    if (Test.isRunningTest() && testRecords != null) {
      List<Quote_Document_Watched_Field__mdt> active = new List<Quote_Document_Watched_Field__mdt>();
      for (Quote_Document_Watched_Field__mdt record : testRecords) {
        if (record.Is_Active__c) {
          active.add(record);
        }
      }
      return active;
    }
    return [
      SELECT DeveloperName, Field_API_Name__c, Is_Active__c, Version__c
      FROM Quote_Document_Watched_Field__mdt
      WHERE Is_Active__c = TRUE
      WITH USER_MODE
      ORDER BY DeveloperName
    ];
  }

  private static void validateIdentity(
    Quote_Document_Watched_Field__mdt record
  ) {
    if (
      String.isBlank(record.DeveloperName) ||
      !record.DeveloperName.toUpperCase().startsWith(SUBSCRIBER_PREFIX)
    ) {
      throw invalid(
        record,
        'Developer Name must start with SUB_ so upgrades cannot collide with stock records.'
      );
    }
    if (String.isBlank(record.Version__c)) {
      throw invalid(record, 'Version is required.');
    }
  }

  private static String validatedFieldName(
    Quote_Document_Watched_Field__mdt record
  ) {
    String fieldName = String.isBlank(record.Field_API_Name__c)
      ? ''
      : record.Field_API_Name__c.trim();
    if (fieldName.contains('.')) {
      throw invalid(
        record,
        'relationship paths are not supported; configure a direct Quote field.'
      );
    }
    Map<String, Schema.SObjectField> fields = SBQQ__Quote__c.SObjectType.getDescribe(
        SObjectDescribeOptions.DEFERRED
      )
      .fields.getMap();
    Schema.SObjectField field = fields.get(fieldName.toLowerCase());
    if (field == null) {
      throw invalid(
        record,
        'field "' + fieldName + '" does not exist on Quote.'
      );
    }
    String canonicalName = field.getDescribe().getName();
    if (PROTECTED_FIELDS.contains(canonicalName.toLowerCase())) {
      throw invalid(
        record,
        'generation lifecycle fields cannot be subscriber dependencies.'
      );
    }
    return canonicalName;
  }

  private static QuoteDocumentGenerator.QuoteDocumentException invalid(
    Quote_Document_Watched_Field__mdt record,
    String detail
  ) {
    return new QuoteDocumentGenerator.QuoteDocumentException(
      'Subscriber watched field ' +
        (String.isBlank(record.DeveloperName)
          ? '(unnamed)'
          : record.DeveloperName) +
        ': ' +
        detail
    );
  }
}
