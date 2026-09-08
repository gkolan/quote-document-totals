@IsTest
private class QuoteDocumentSubscriberFieldsTest {
  @TestSetup
  static void setup() {
    QuoteDocumentTestData.setup();
  }

  private static Quote_Document_Watched_Field__mdt watched(
    String developerName,
    String fieldName,
    String version
  ) {
    return new Quote_Document_Watched_Field__mdt(
      DeveloperName = developerName,
      MasterLabel = developerName,
      Field_API_Name__c = fieldName,
      Is_Active__c = true,
      Version__c = version
    );
  }

  @IsTest
  static void noSubscriberRecordsLeaveStockBehaviorUnchanged() {
    QuoteDocumentSubscriberFields.testRecords = new List<Quote_Document_Watched_Field__mdt>();
    Assert.areEqual(0, QuoteDocumentSubscriberFields.quoteFieldPaths().size());
    Assert.areEqual(
      0,
      QuoteDocumentSubscriberFields.fingerprintParts(new SBQQ__Quote__c())
        .size()
    );
  }

  @IsTest
  static void activeFieldsAreOrderedSelectedAndFingerprintTheirValues() {
    QuoteDocumentSubscriberFields.testRecords = new List<Quote_Document_Watched_Field__mdt>{
      watched('SUB_STATUS', 'SBQQ__Status__c', '1')
    };
    Id quoteId = QuoteDocumentTestData.quoteId();
    SBQQ__Quote__c quote = QuoteDocumentQuery.quotesWithLinesReadOnly(
      new Set<Id>{ quoteId }
    )[0];
    Assert.isTrue(
      quote.getPopulatedFieldsAsMap().containsKey('SBQQ__Status__c'),
      'The generation query must select every active subscriber dependency.'
    );

    List<QuoteDocumentLine> lines = new List<QuoteDocumentLine>();
    for (SBQQ__QuoteLine__c line : quote.SBQQ__LineItems__r) {
      lines.add(new QuoteDocumentLine(line, quote));
    }
    List<QuoteDocumentTableDefinition> definitions = QuoteDocumentTableDefinition.getAll();
    String beforeFingerprint = QuoteDocumentFingerprint.compute(
      quote,
      lines,
      definitions
    );
    quote.put('SBQQ__Status__c', 'Approved');
    String afterFingerprint = QuoteDocumentFingerprint.compute(
      quote,
      lines,
      definitions
    );

    Assert.areNotEqual(
      beforeFingerprint,
      afterFingerprint,
      'A changed subscriber field value must prevent reuse.'
    );
  }

  @IsTest
  static void subscriberFieldsAppendToTriggerStaleness() {
    QuoteDocumentSubscriberFields.testRecords = new List<Quote_Document_Watched_Field__mdt>{
      watched('SUB_STATUS', 'SBQQ__Status__c', '1')
    };
    SBQQ__Quote__c before = new SBQQ__Quote__c(
      Id = QuoteDocumentTestData.quoteId(),
      SBQQ__Status__c = 'Draft'
    );
    SBQQ__Quote__c after = before.clone(true, false, false, false);
    after.SBQQ__Status__c = 'Approved';

    Assert.isTrue(
      QuoteDocumentStaleness.hasRelevantQuoteChange(after, before),
      'The subscriber field must append to the core trigger watch set.'
    );
  }

  @IsTest
  static void versionChangesMoveFingerprintEvenWhenValueDoesNot() {
    SBQQ__Quote__c quote = new SBQQ__Quote__c(SBQQ__Status__c = 'Draft');
    QuoteDocumentSubscriberFields.testRecords = new List<Quote_Document_Watched_Field__mdt>{
      watched('SUB_STATUS', 'SBQQ__Status__c', '1')
    };
    String first = QuoteDocumentSubscriberFields.fingerprintParts(quote)[0];
    QuoteDocumentSubscriberFields.testRecords = new List<Quote_Document_Watched_Field__mdt>{
      watched('SUB_STATUS', 'SBQQ__Status__c', '2')
    };
    String second = QuoteDocumentSubscriberFields.fingerprintParts(quote)[0];
    Assert.areNotEqual(first, second);
  }

  @IsTest
  static void invalidSubscriberRecordsFailBeforeGeneration() {
    List<Quote_Document_Watched_Field__mdt> invalid = new List<Quote_Document_Watched_Field__mdt>{
      watched('WRONG_PREFIX', 'SBQQ__Status__c', '1'),
      watched('SUB_RELATIONSHIP', 'SBQQ__Account__r.Name', '1'),
      watched('SUB_MISSING', 'Missing_Field__c', '1'),
      watched('SUB_LIFECYCLE', 'document_data_status__c', '1'),
      watched('SUB_VERSION', 'SBQQ__Status__c', '')
    };
    for (Quote_Document_Watched_Field__mdt record : invalid) {
      QuoteDocumentSubscriberFields.testRecords = new List<Quote_Document_Watched_Field__mdt>{
        record
      };
      try {
        QuoteDocumentSubscriberFields.quoteFieldPaths();
        Assert.fail(
          'Invalid subscriber metadata must fail: ' + record.DeveloperName
        );
      } catch (QuoteDocumentGenerator.QuoteDocumentException expected) {
        Assert.isTrue(expected.getMessage().contains(record.DeveloperName));
      }
    }
  }

  @IsTest
  static void duplicateFieldsCannotCreateAmbiguousPrecedence() {
    QuoteDocumentSubscriberFields.testRecords = new List<Quote_Document_Watched_Field__mdt>{
      watched('SUB_STATUS_ONE', 'SBQQ__Status__c', '1'),
      watched('SUB_STATUS_TWO', 'sbqq__status__c', '1')
    };
    try {
      QuoteDocumentSubscriberFields.quoteFieldPaths();
      Assert.fail('Duplicate field paths must be rejected.');
    } catch (QuoteDocumentGenerator.QuoteDocumentException expected) {
      Assert.isTrue(expected.getMessage().contains('duplicates'));
    }
  }

  @IsTest
  static void diagnosticsExposeInvalidSubscriberMetadata() {
    QuoteDocumentSubscriberFields.testRecords = new List<Quote_Document_Watched_Field__mdt>{
      watched('SUB_BAD', 'Missing_Field__c', '1')
    };
    QuoteDocumentConfigurationDiagnostics.Report report = QuoteDocumentConfigurationDiagnostics.inspect();
    Assert.isFalse(report.ready);
    Assert.areEqual('CONFIGURATION_INVALID', report.issues[0].code);
    Assert.isTrue(report.issues[0].message.contains('SUB_BAD'));
  }
}
