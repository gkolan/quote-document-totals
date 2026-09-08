/**
 * Read-only setup health for administrators and release automation.
 *
 * It loads the same active definitions and registries generation uses, but
 * never queries a Quote and never writes generated records. A failure is
 * returned as data so an admin can fix configuration before a customer run.
 */
public with sharing class QuoteDocumentConfigurationDiagnostics {
  public class Issue {
    @AuraEnabled
    public String code;
    @AuraEnabled
    public String severity;
    @AuraEnabled
    public String message;

    private Issue(String code, String severity, String message) {
      this.code = code;
      this.severity = severity;
      this.message = message;
    }
  }

  public class Report {
    @AuraEnabled
    public Boolean ready;
    @AuraEnabled
    public Datetime checkedAt;
    @AuraEnabled
    public Integer activeTableDefinitions = 0;
    @AuraEnabled
    public Integer resolvedColumns = 0;
    @AuraEnabled
    public Integer activeComposers = 0;
    @AuraEnabled
    public Integer activeSubscriberWatchedFields = 0;
    @AuraEnabled
    public List<Issue> issues = new List<Issue>();
  }

  /** Returns setup health without changing metadata, Quotes, or snapshots. */
  @AuraEnabled(cacheable=true)
  public static Report inspect() {
    Report report = new Report();
    report.checkedAt = System.now();
    try {
      List<QuoteDocumentTableDefinition> definitions = QuoteDocumentTableDefinition.getAll();
      report.activeTableDefinitions = definitions.size();
      if (definitions.isEmpty()) {
        report.issues.add(
          new Issue(
            'NO_ACTIVE_TABLE_DEFINITIONS',
            'ERROR',
            'No active Quote Document Table Definition is available.'
          )
        );
      }
      for (QuoteDocumentTableDefinition definition : definitions) {
        validateDefinition(definition, report);
      }
      String localePath = QuoteDocumentLocale.configuredPath();
      if (String.isNotBlank(localePath)) {
        validateQuotePath(localePath);
      }
      report.activeSubscriberWatchedFields = QuoteDocumentSubscriberFields.quoteFieldPaths()
        .size();
      validateComposers(report);
    } catch (Exception failure) {
      report.issues.add(configurationFailure(failure));
    }
    report.ready = report.issues.isEmpty();
    return report;
  }

  private static void validateDefinition(
    QuoteDocumentTableDefinition definition,
    Report report
  ) {
    report.resolvedColumns += QuoteDocumentColumnDefinition.forTable(definition)
      .size();
    for (QuoteDocumentTableDefinition.Level level : definition.groupBy) {
      for (QuoteDocumentTableDefinition.Part part : level.parts) {
        if (part.isFieldPath()) {
          QuoteDocumentQuery.validateLineFieldPath(part.fieldPath);
        }
      }
    }
    for (String path : definition.contributorDependencyPaths) {
      validateQuotePath(path);
    }
    if (String.isNotBlank(definition.rowCustomizerCode)) {
      QuoteDocumentRowCustomizerRegistry.resolve(definition.rowCustomizerCode);
    }
    if (definition.hasExpander()) {
      QuoteDocumentExpanderRegistry.resolve(definition.expanderCode);
    }
    if (definition.hasComparison()) {
      QuoteDocumentComparisonRegistry.resolve(definition.comparisonSourceCode);
      validateQuotePath(definition.comparisonSourceFieldOrDefault());
    }
  }

  private static void validateComposers(Report report) {
    // This call owns duplicate-order, type, and version validation.
    QuoteDocumentSectionComposition.fingerprintParts();
    List<Quote_Document_Composer__mdt> composers = [
      SELECT
        Composer_Code__c,
        Flow_API_Name__c,
        Quote_Dependency_Paths__c,
        Line_Dependency_Paths__c
      FROM Quote_Document_Composer__mdt
      WHERE Is_Active__c = TRUE
      WITH USER_MODE
    ];
    report.activeComposers = composers.size();
    for (Quote_Document_Composer__mdt composer : composers) {
      if (String.isNotBlank(composer.Composer_Code__c)) {
        QuoteDocumentSectionContributorRegistry.resolve(
          composer.Composer_Code__c
        );
      }
      for (String path : splitPaths(composer.Quote_Dependency_Paths__c)) {
        validateQuotePath(path);
      }
      for (String path : splitPaths(composer.Line_Dependency_Paths__c)) {
        QuoteDocumentQuery.validateLineFieldPath(path);
      }
    }
  }

  private static List<String> splitPaths(String raw) {
    List<String> paths = new List<String>();
    if (String.isBlank(raw)) {
      return paths;
    }
    for (String candidate : raw.split('[,;\\n\\r]+')) {
      if (String.isNotBlank(candidate)) {
        paths.add(candidate.trim());
      }
    }
    return paths;
  }

  @TestVisible
  private static void validateQuotePath(String path) {
    Schema.SObjectType current = SBQQ__Quote__c.SObjectType;
    List<String> segments = path.split('\\.');
    for (Integer index = 0; index < segments.size(); index++) {
      String segment = segments[index];
      Boolean isLast = index == segments.size() - 1;
      current = validatePathSegment(current, segment, isLast);
    }
  }

  private static Schema.SObjectType validatePathSegment(
    Schema.SObjectType current,
    String segment,
    Boolean isLast
  ) {
    String fieldName = isLast ? segment : segment.replace('__r', '__c');
    Map<String, Schema.SObjectField> fields = current.getDescribe()
      .fields.getMap();
    Schema.SObjectField field = fields.get(fieldName.toLowerCase());
    if (field == null && !isLast) {
      field = fields.get((segment + 'Id').toLowerCase());
    }
    if (field == null) {
      throw new QuoteDocumentGenerator.QuoteDocumentException(
        'Quote dependency field path is invalid at "' + segment + '".'
      );
    }
    if (isLast) {
      return current;
    }
    List<Schema.SObjectType> references = field.getDescribe().getReferenceTo();
    if (references.isEmpty()) {
      throw new QuoteDocumentGenerator.QuoteDocumentException(
        'Quote dependency field path cannot traverse "' + segment + '".'
      );
    }
    return references[0];
  }

  @TestVisible
  private static Issue configurationFailure(Exception failure) {
    return new Issue(
      'CONFIGURATION_INVALID',
      'ERROR',
      String.isBlank(failure.getMessage())
        ? 'Configuration validation failed without a message.'
        : failure.getMessage()
    );
  }
}
