@IsTest
private class QuoteDocumentConditionTest {
  @TestSetup
  static void setupTestData() {
    QuoteDocumentTestData.setup();
  }

  @IsTest
  static void shouldKeepMatchingFamily_WhenEqualsConditionConfigured() {
    QuoteDocumentCondition.useConditions(
      new Map<String, List<QuoteDocumentCondition>>{
        'HARDWARE' => new List<QuoteDocumentCondition>{
          condition(
            1,
            1,
            'SBQQ__Product__r.Family',
            'Equals',
            'Hardware',
            'Text'
          )
        }
      }
    );

    Test.startTest();
    List<QuoteDocumentLine> kept = QuoteDocumentCondition.apply(
      'HARDWARE',
      sourceLines()
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      kept.size(),
      'Only the package and bundled Hardware component should match.'
    );
    for (QuoteDocumentLine line : kept) {
      Assert.areEqual(
        'Hardware',
        line.productFamily,
        'Every retained line must be Hardware.'
      );
    }
  }

  @IsTest
  static void shouldUseAndWithinSetAndOrAcrossSets_WhenSeveralSetsConfigured() {
    QuoteDocumentCondition.useConditions(
      new Map<String, List<QuoteDocumentCondition>>{
        'SELECTED' => new List<QuoteDocumentCondition>{
          condition(
            1,
            1,
            'SBQQ__Product__r.Family',
            'Equals',
            'Hardware',
            'Text'
          ),
          condition(1, 2, 'SBQQ__Optional__c', 'Equals', 'true', 'Boolean'),
          condition(
            2,
            1,
            'SBQQ__Product__r.Family',
            'Equals',
            'Software',
            'Text'
          )
        }
      }
    );

    Test.startTest();
    List<QuoteDocumentLine> kept = QuoteDocumentCondition.apply(
      'SELECTED',
      sourceLines()
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      kept.size(),
      'The first AND set matches nothing and the second set matches Software.'
    );
    Assert.areEqual(
      QuoteDocumentTestData.CODE_OPTIONAL,
      kept[0].productCode,
      'The optional Software product should satisfy the second condition set.'
    );
  }

  @IsTest
  static void shouldCompareNumbersAsNumbers_WhenGreaterThanConfigured() {
    QuoteDocumentCondition.useConditions(
      new Map<String, List<QuoteDocumentCondition>>{
        'VOLUME' => new List<QuoteDocumentCondition>{
          condition(1, 1, 'SBQQ__Quantity__c', 'Greater Than', '2', 'Number')
        }
      }
    );

    Test.startTest();
    List<QuoteDocumentLine> kept = QuoteDocumentCondition.apply(
      'VOLUME',
      sourceLines()
    );
    Test.stopTest();

    Assert.areEqual(
      2,
      kept.size(),
      'Both quantity-10 Hardware lines should compare above numeric 2.'
    );
  }

  @IsTest
  static void shouldRejectInvalidBoolean_WhenConfigurationLoads() {
    Test.startTest();
    try {
      condition(1, 1, 'SBQQ__Optional__c', 'Equals', 'yes', 'Boolean');
      Assert.fail(
        'Expected a non-Boolean comparison value to fail configuration validation.'
      );
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      Assert.isTrue(
        e.getMessage().contains('CONDITION_VALUE_INVALID'),
        'Wrong failure: ' + e.getMessage()
      );
    }
    Test.stopTest();
  }

  private static QuoteDocumentCondition condition(
    Integer setNumber,
    Integer sequence,
    String fieldPath,
    String operator,
    String value,
    String dataType
  ) {
    return QuoteDocumentCondition.forTest(
      setNumber,
      sequence,
      fieldPath,
      operator,
      value,
      dataType
    );
  }

  private static List<QuoteDocumentLine> sourceLines() {
    SBQQ__Quote__c quote = QuoteDocumentQuery.quotesWithLines(
      new Set<Id>{ QuoteDocumentTestData.quoteId() }
    )[0];
    List<QuoteDocumentLine> lines = new List<QuoteDocumentLine>();
    for (SBQQ__QuoteLine__c source : quote.SBQQ__LineItems__r) {
      lines.add(new QuoteDocumentLine(source, quote));
    }
    return lines;
  }
}
