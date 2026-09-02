@IsTest
private class QuoteDocumentFactBuilderTest {
  @TestSetup
  static void setupTestData() {
    QuoteDocumentTestData.setup();

    Account account = [SELECT Id FROM Account LIMIT 1];
    account.BillingStreet = '100 Main Street';
    account.BillingCity = 'Chicago';
    account.BillingState = 'IL';
    account.BillingPostalCode = '60601';
    account.BillingCountry = 'USA';
    update account;

    SBQQ__Quote__c quote = [SELECT Id FROM SBQQ__Quote__c LIMIT 1];
    quote.SBQQ__ExpirationDate__c = Date.today().addDays(30);
    update quote;
  }

  @IsTest
  static void shouldBuildTypedStandardFacts_WhenQuoteHasHeaderData() {
    SBQQ__Quote__c quote = [
      SELECT
        Id,
        Name,
        SBQQ__ExpirationDate__c,
        SBQQ__Account__c,
        SBQQ__Account__r.Id,
        SBQQ__Account__r.Name,
        SBQQ__Account__r.BillingStreet,
        SBQQ__Account__r.BillingCity,
        SBQQ__Account__r.BillingState,
        SBQQ__Account__r.BillingPostalCode,
        SBQQ__Account__r.BillingCountry
      FROM SBQQ__Quote__c
      LIMIT 1
    ];

    Test.startTest();
    List<Quote_Document_Fact__c> facts = QuoteDocumentFactBuilder.build(
      quote,
      QuoteDocumentLabels.forLocale('en_US'),
      'USD'
    );
    Test.stopTest();

    Map<String, Quote_Document_Fact__c> factByCode = new Map<String, Quote_Document_Fact__c>();
    for (Quote_Document_Fact__c fact : facts) {
      factByCode.put(fact.Fact_Code__c, fact);
    }

    Assert.areEqual(
      4,
      facts.size(),
      'The standard Order Form header should contain four facts.'
    );
    Assert.areEqual(
      'Document Totals Test',
      factByCode.get(QuoteDocumentFactBuilder.CUSTOMER_NAME).Text_Value__c,
      'Customer Name must come from the Quote Account.'
    );
    Assert.areEqual(
      'Address',
      factByCode.get(QuoteDocumentFactBuilder.BILLING_ADDRESS).Data_Type__c,
      'Billing Address must retain its address meaning.'
    );
    Assert.areEqual(
      quote.SBQQ__ExpirationDate__c,
      factByCode.get(QuoteDocumentFactBuilder.QUOTE_EXPIRATION_DATE)
        .Date_Value__c,
      'Expiration must remain a Date rather than formatted text.'
    );
  }

  @IsTest
  static void shouldRejectDuplicateCode_WhenContributorReturnsAmbiguousFacts() {
    List<Quote_Document_Fact__c> facts = new List<Quote_Document_Fact__c>{
      textFact('CUSTOMER_NAME', 10),
      textFact('CUSTOMER_NAME', 20)
    };

    Test.startTest();
    try {
      QuoteDocumentFactBuilder.validate(facts);
      Assert.fail('Expected duplicate Fact codes to fail.');
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      Assert.isTrue(
        e.getMessage().contains('FACT_CODE_INVALID'),
        'Wrong failure: ' + e.getMessage()
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void shouldRejectMismatchedValue_WhenTypeAndValueDisagree() {
    Quote_Document_Fact__c fact = textFact('EXPIRATION', 10);
    fact.Data_Type__c = 'Date';

    Test.startTest();
    try {
      QuoteDocumentFactBuilder.validate(
        new List<Quote_Document_Fact__c>{ fact }
      );
      Assert.fail('Expected a Date Fact carrying text to fail.');
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      Assert.isTrue(
        e.getMessage().contains('FACT_VALUE_INVALID'),
        'Wrong failure: ' + e.getMessage()
      );
    }
    Test.stopTest();
  }

  @IsTest
  static void shouldAcceptFalse_WhenBooleanIsTheDeclaredType() {
    Quote_Document_Fact__c fact = new Quote_Document_Fact__c(
      Fact_Code__c = 'AUTO_RENEW',
      Display_Label__c = 'Auto Renew',
      Display_Order__c = 10,
      Data_Type__c = 'Boolean',
      Boolean_Value__c = false,
      Source_Identity__c = 'TEST:AUTO_RENEW'
    );

    Test.startTest();
    QuoteDocumentFactBuilder.validate(new List<Quote_Document_Fact__c>{ fact });
    Test.stopTest();

    Assert.areEqual(false, QuoteDocumentFactBuilder.valueFor(fact));
  }

  @IsTest
  static void shouldRejectTrueCheckbox_WhenTextIsTheDeclaredType() {
    Quote_Document_Fact__c fact = textFact('MIXED_VALUE', 10);
    fact.Boolean_Value__c = true;

    Test.startTest();
    try {
      QuoteDocumentFactBuilder.validate(
        new List<Quote_Document_Fact__c>{ fact }
      );
      Assert.fail('Expected a Text Fact carrying a true checkbox to fail.');
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      Assert.isTrue(e.getMessage().contains('FACT_VALUE_INVALID'));
    }
    Test.stopTest();
  }

  @IsTest
  static void shouldValidateAllFacts_WhenCollectionCrossesBatchBoundary() {
    List<Quote_Document_Fact__c> facts = new List<Quote_Document_Fact__c>();
    for (Integer index = 0; index < 251; index++) {
      facts.add(textFact('FACT_' + index, index));
    }

    Test.startTest();
    QuoteDocumentFactBuilder.validate(facts);
    Test.stopTest();

    Assert.areEqual(
      251,
      facts.size(),
      'Every supplied Fact should survive validation unchanged.'
    );
  }

  private static Quote_Document_Fact__c textFact(String code, Decimal order) {
    return new Quote_Document_Fact__c(
      Fact_Code__c = code,
      Display_Label__c = code,
      Display_Order__c = order,
      Data_Type__c = 'Text',
      Text_Value__c = 'Value ' + code,
      Source_Identity__c = 'TEST:' + code
    );
  }
}
