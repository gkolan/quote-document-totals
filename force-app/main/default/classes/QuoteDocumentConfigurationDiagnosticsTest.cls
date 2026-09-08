@IsTest
private class QuoteDocumentConfigurationDiagnosticsTest {
  @IsTest
  static void currentConfigurationPassesReadOnlyInspection() {
    Integer dmlBefore = Limits.getDmlStatements();
    Test.startTest();
    QuoteDocumentConfigurationDiagnostics.Report report = QuoteDocumentConfigurationDiagnostics.inspect();
    Test.stopTest();

    Assert.isTrue(report.ready, JSON.serialize(report.issues));
    Assert.isTrue(
      report.activeTableDefinitions > 0,
      'The shipped source must expose at least one active table definition.'
    );
    Assert.isTrue(
      report.resolvedColumns >= report.activeTableDefinitions,
      'Every active table must resolve at least one checked column.'
    );
    Assert.isNotNull(
      report.checkedAt,
      'Diagnostics must timestamp their evidence.'
    );
    Assert.areEqual(
      dmlBefore,
      Limits.getDmlStatements(),
      'Configuration diagnostics must remain read-only.'
    );
  }

  @IsTest
  static void failuresHaveStableSupportFields() {
    QuoteDocumentConfigurationDiagnostics.Issue issue = QuoteDocumentConfigurationDiagnostics.configurationFailure(
      new QuoteDocumentGenerator.QuoteDocumentException('bad table')
    );

    Assert.areEqual('CONFIGURATION_INVALID', issue.code);
    Assert.areEqual('ERROR', issue.severity);
    Assert.areEqual('bad table', issue.message);
  }

  @IsTest
  static void invalidQuoteDependencyNamesTheBrokenSegment() {
    try {
      QuoteDocumentConfigurationDiagnostics.validateQuotePath(
        'Missing_Relationship__r.Value__c'
      );
      Assert.fail('An unknown Quote relationship must fail diagnostics.');
    } catch (QuoteDocumentGenerator.QuoteDocumentException failure) {
      Assert.isTrue(
        failure.getMessage().contains('Missing_Relationship__r'),
        failure.getMessage()
      );
    }
  }
}
