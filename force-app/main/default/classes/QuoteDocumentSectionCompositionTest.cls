@IsTest
private class QuoteDocumentSectionCompositionTest {
  @TestSetup
  static void setupData() {
    QuoteDocumentTestData.setup();
  }

  @IsTest
  static void apexComposerBuildsOnlyFamiliesThatHaveLines() {
    QuoteDocumentSectionComposition.useConfigs(
      new List<Quote_Document_Composer__mdt>{ apexConfig() }
    );
    SBQQ__Quote__c quote = quoteRecord();

    Test.startTest();
    QuoteDocumentSectionContributorOutput output = QuoteDocumentSectionComposition.compose(
      quote,
      QuoteDocumentTestData.normalizedLines(),
      new List<Quote_Document_Fact__c>(),
      'en_US',
      'USD'
    );
    QuoteDocumentSectionComposition.validate(
      output,
      quote.Id,
      new Set<String>(),
      new Set<String>()
    );
    Test.stopTest();

    Assert.isTrue(
      output.tables.size() > 0,
      'The Apex composer should build at least one applicable family Table.'
    );
    Assert.isTrue(
      output.columns.size() >= output.tables.size() * 7,
      'Every contributed Table must carry its own complete column contract.'
    );
    for (Quote_Document_Table__c table : output.tables) {
      Assert.isTrue(
        String.isNotBlank(table.Table_Key__c),
        'Every Table needs a stable key.'
      );
      Assert.areEqual(
        quote.Id,
        table.Quote__c,
        'Validation attaches every Table to the source Quote.'
      );
    }
  }

  @IsTest
  static void unknownParentKeyStopsCompositionBeforeDml() {
    QuoteDocumentSectionContributorOutput output = new QuoteDocumentSectionContributorOutput();
    output.rows.add(
      new Quote_Document_Row__c(
        Table_Key__c = 'MISSING',
        Row_Key__c = 'ROW:1',
        Row_Type__c = 'Detail',
        Display_Label__c = 'Invalid',
        Display_Order__c = 10,
        Group_Level__c = 0
      )
    );

    Test.startTest();
    Exception caught;
    try {
      QuoteDocumentSectionComposition.validate(
        output,
        QuoteDocumentTestData.quoteId(),
        new Set<String>(),
        new Set<String>()
      );
    } catch (Exception e) {
      caught = e;
    }
    Test.stopTest();

    Assert.isNotNull(
      caught,
      'A Row must not be silently attached to an arbitrary Table.'
    );
    Assert.isTrue(
      caught.getMessage().contains('DOCUMENT_ROW_TABLE_UNKNOWN'),
      caught.getMessage()
    );
  }

  @IsTest
  static void blockForAnOmittedRowIsAlsoOmitted() {
    QuoteDocumentSectionContributorOutput output = new QuoteDocumentSectionContributorOutput();
    output.blocks.add(
      new Quote_Document_Block__c(
        Block_Code__c = 'ROW_NOTE',
        Block_Type__c = 'Notice',
        Display_Order__c = 10,
        Locale__c = 'en_US',
        Body__c = 'This wording belongs only to the omitted Row.',
        Source_Version__c = '1',
        Approval_Identity__c = 'TEST:ROW_NOTE:1',
        Placement__c = 'After Row',
        Related_Table_Key__c = 'OMITTED_TABLE',
        Related_Row_Key__c = 'OMITTED_ROW'
      )
    );

    QuoteDocumentSectionComposition.validate(
      output,
      QuoteDocumentTestData.quoteId(),
      new Set<String>(),
      new Set<String>()
    );

    Assert.areEqual(
      0,
      output.blocks.size(),
      'Wording must not survive when its related Row is absent.'
    );
  }

  @IsTest
  static void payableMustReconcileBeforeAnyRecordsAreSaved() {
    QuoteDocumentSectionComposition.useConfigs(
      new List<Quote_Document_Composer__mdt>{ apexConfig() }
    );
    SBQQ__Quote__c quote = quoteRecord();
    QuoteDocumentSectionContributorOutput output = QuoteDocumentSectionComposition.compose(
      quote,
      QuoteDocumentTestData.normalizedLines(),
      new List<Quote_Document_Fact__c>(),
      'en_US',
      'USD'
    );
    for (Quote_Document_Row__c row : output.rows) {
      if ('Payable'.equals(row.Total_Role__c)) {
        row.Amount_Net__c += 1;
        break;
      }
    }

    Exception caught;
    try {
      QuoteDocumentSectionComposition.validate(
        output,
        quote.Id,
        new Set<String>(),
        new Set<String>()
      );
    } catch (Exception e) {
      caught = e;
    }

    Assert.isNotNull(
      caught,
      'An incorrect Payable amount must stop generation.'
    );
    Assert.isTrue(
      caught.getMessage().contains('DOCUMENT_TABLE_PAYABLE_UNRECONCILED'),
      caught.getMessage()
    );
  }

  @IsTest
  static void flowComposerFailureUsesStableErrorCode() {
    Quote_Document_Composer__mdt flowConfig = new Quote_Document_Composer__mdt(
      DeveloperName = 'Missing_Flow',
      Is_Active__c = true,
      Flow_API_Name__c = 'Flow_That_Does_Not_Exist',
      Version__c = '1',
      Display_Order__c = 10
    );
    QuoteDocumentSectionComposition.useConfigs(
      new List<Quote_Document_Composer__mdt>{ flowConfig }
    );

    Test.startTest();
    Exception caught;
    try {
      QuoteDocumentSectionComposition.compose(
        quoteRecord(),
        QuoteDocumentTestData.normalizedLines(),
        new List<Quote_Document_Fact__c>(),
        'en_US',
        'USD'
      );
    } catch (Exception e) {
      caught = e;
    }
    Test.stopTest();

    Assert.isNotNull(caught, 'A missing Flow must stop generation.');
    Assert.isTrue(
      caught.getMessage().contains(QuoteDocumentContributorError.FLOW_FAULT),
      caught.getMessage()
    );
  }

  @IsTest
  static void generatorPersistsApexComposedTablesColumnsAndRows() {
    QuoteDocumentSectionComposition.useConfigs(
      new List<Quote_Document_Composer__mdt>{ apexConfig() }
    );
    Id quoteId = QuoteDocumentTestData.quoteId();

    Test.startTest();
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
    Test.stopTest();

    List<Quote_Document_Table__c> composed = [
      SELECT Id, Table_Key__c, Source_Identity__c, Source_Version__c
      FROM Quote_Document_Table__c
      WHERE
        Quote__c = :quoteId
        AND Source_Identity__c = 'APEX_COMPOSER:ORDER_FORM_FAMILIES'
    ];
    Assert.isTrue(
      !composed.isEmpty(),
      'The active Apex composer must add complete Tables to normal generation.'
    );
    Set<Id> tableIds = new Map<Id, Quote_Document_Table__c>(composed).keySet();
    Assert.isTrue(
      [
        SELECT COUNT()
        FROM Quote_Document_Column__c
        WHERE Quote_Document_Table__c IN :tableIds
      ] >= composed.size() * 7,
      'Every composed Table must persist at least its seven core Columns.'
    );
    Assert.isTrue(
      [
        SELECT COUNT()
        FROM Quote_Document_Row__c
        WHERE Quote_Document_Table__c IN :tableIds
      ] > composed.size(),
      'Every composed Table must persist at least one detail Row and one total Row.'
    );
  }

  @IsTest
  static void orderFormFamiliesUseIndependentColumnShapes() {
    List<QuoteDocumentLine> lines = QuoteDocumentTestData.normalizedLines();
    Assert.isTrue(lines.size() >= 3, 'The shared fixture needs three lines.');
    lines[0].productFamily = 'Hardware';
    lines[1].productFamily = 'Software';
    lines[2].productFamily = 'Services';
    for (Integer i = 0; i < 3; i++) {
      lines[i].isBundledComponent = false;
      lines[i].isDisplayed = true;
      lines[i].isOptional = false;
    }
    lines[2].subscriptionStartDate = Date.newInstance(2026, 10, 1);
    lines[2].subscriptionEndDate = Date.newInstance(2026, 12, 15);

    QuoteDocumentSectionContributorOutput output = new QuoteDocumentOrderFormSectionContributor()
      .compose(
        new QuoteDocumentSectionContributorContext(
          quoteRecord(),
          new List<QuoteDocumentLine>{ lines[0], lines[1], lines[2] },
          new List<Quote_Document_Fact__c>(),
          'en_US',
          'USD',
          'ORDER_FORM_FAMILIES',
          '1'
        )
      );

    Map<String, Set<String>> columnsByTable = new Map<String, Set<String>>();
    for (Quote_Document_Column__c column : output.columns) {
      if (!columnsByTable.containsKey(column.Table_Key__c)) {
        columnsByTable.put(column.Table_Key__c, new Set<String>());
      }
      columnsByTable.get(column.Table_Key__c).add(column.Column_Code__c);
    }
    Assert.areEqual(
      3,
      output.tables.size(),
      'All three present families emit Tables.'
    );
    Assert.isFalse(
      columnsByTable.get('ORDER_FORM:HARDWARE').contains('START_DATE'),
      'Hardware does not inherit service-only dates.'
    );
    Assert.isFalse(
      columnsByTable.get('ORDER_FORM:SOFTWARE_SUBSCRIPTIONS')
        .contains('START_DATE'),
      'Software does not inherit service-only dates.'
    );
    Assert.isTrue(
      columnsByTable.get('ORDER_FORM:SERVICES_SCHEDULE').contains('START_DATE'),
      'Services owns its Start Date Column.'
    );
    Assert.isTrue(
      columnsByTable.get('ORDER_FORM:SERVICES_SCHEDULE').contains('END_DATE'),
      'Services owns its End Date Column.'
    );

    lines.remove(0);
    QuoteDocumentSectionContributorOutput withoutHardware = new QuoteDocumentOrderFormSectionContributor()
      .compose(
        new QuoteDocumentSectionContributorContext(
          quoteRecord(),
          new List<QuoteDocumentLine>{ lines[0], lines[1] },
          new List<Quote_Document_Fact__c>(),
          'en_US',
          'USD',
          'ORDER_FORM_FAMILIES',
          '1'
        )
      );
    Set<String> remainingKeys = new Set<String>();
    for (Quote_Document_Table__c table : withoutHardware.tables) {
      remainingKeys.add(table.Table_Key__c);
    }
    Assert.isFalse(
      remainingKeys.contains('ORDER_FORM:HARDWARE'),
      'Removing Hardware must emit no Hardware Table at all.'
    );
  }

  @IsTest
  static void orderFormComposerCanReturnZeroSections() {
    List<QuoteDocumentLine> lines = QuoteDocumentTestData.normalizedLines();
    for (QuoteDocumentLine line : lines) {
      line.isOptional = true;
      line.isBundledComponent = false;
      line.isDisplayed = true;
    }

    QuoteDocumentSectionContributorOutput output = new QuoteDocumentOrderFormSectionContributor()
      .compose(
        new QuoteDocumentSectionContributorContext(
          quoteRecord(),
          lines,
          new List<Quote_Document_Fact__c>(),
          'en_US',
          'USD',
          'ORDER_FORM_FAMILIES',
          '1'
        )
      );

    Assert.areEqual(
      0,
      output.tables.size(),
      'A contributor may return no section when none of its payable lines apply.'
    );
    Assert.areEqual(
      0,
      output.rows.size(),
      'No hidden Rows should be returned.'
    );
  }

  @IsTest
  static void composedSectionsRenderThroughJsonAndHtmlWithoutRecomposition() {
    QuoteDocumentSectionComposition.useConfigs(
      new List<Quote_Document_Composer__mdt>{ apexConfig() }
    );
    Id quoteId = QuoteDocumentTestData.quoteId();

    QuoteDocumentGenerator.GenerationOutcome outcome = QuoteDocumentGenerator.generate(
      new Set<Id>{ quoteId }
    )[0];
    String jsonOutput = QuoteDocumentJsonAdapter.render(
      quoteId,
      outcome.requestId,
      outcome.fingerprint
    );
    String htmlOutput = QuoteDocumentHtmlAdapter.render(
      quoteId,
      outcome.requestId,
      outcome.fingerprint
    );

    for (Quote_Document_Table__c table : [
      SELECT Table_Code__c
      FROM Quote_Document_Table__c
      WHERE
        Quote__c = :quoteId
        AND Source_Identity__c = 'APEX_COMPOSER:ORDER_FORM_FAMILIES'
    ]) {
      Assert.isTrue(
        jsonOutput.contains(table.Table_Code__c),
        'JSON must render the already-composed Table code.'
      );
      Assert.isTrue(
        htmlOutput.contains(table.Table_Code__c),
        'HTML must render the same already-composed Table code.'
      );
    }
  }

  @IsTest
  static void composerDependenciesChangeTheFingerprint() {
    Quote_Document_Composer__mdt config = apexConfig();
    config.Quote_Dependency_Paths__c = 'Document_Data_Status__c';
    config.Line_Dependency_Paths__c = 'SBQQ__ListPrice__c';
    QuoteDocumentSectionComposition.useConfigs(
      new List<Quote_Document_Composer__mdt>{ config }
    );

    SBQQ__Quote__c quote = quoteRecord();
    List<QuoteDocumentLine> originalLines = documentLines(quote);
    String original = QuoteDocumentFingerprint.canonicalize(
      quote,
      originalLines,
      new List<QuoteDocumentTableDefinition>()
    );

    SBQQ__Quote__c changedQuote = quote.clone(true, true, false, false);
    changedQuote.Document_Data_Status__c = 'Stale';
    String changedQuoteFingerprint = QuoteDocumentFingerprint.canonicalize(
      changedQuote,
      originalLines,
      new List<QuoteDocumentTableDefinition>()
    );
    Assert.areNotEqual(
      original,
      changedQuoteFingerprint,
      'A declared Quote dependency must participate in change detection.'
    );

    SBQQ__Quote__c lineChangedQuote = quote.clone(true, true, false, false);
    lineChangedQuote.SBQQ__LineItems__r[0].SBQQ__ListPrice__c += 1;
    String changedLineFingerprint = QuoteDocumentFingerprint.canonicalize(
      lineChangedQuote,
      documentLines(lineChangedQuote),
      new List<QuoteDocumentTableDefinition>()
    );
    Assert.areNotEqual(
      original,
      changedLineFingerprint,
      'A declared Quote Line dependency must participate in change detection.'
    );
  }

  @IsTest
  static void composerVersionMustBeAPositiveWholeNumber() {
    Quote_Document_Composer__mdt config = apexConfig();
    config.Version__c = '1.5';
    QuoteDocumentSectionComposition.useConfigs(
      new List<Quote_Document_Composer__mdt>{ config }
    );

    Exception caught;
    try {
      QuoteDocumentSectionComposition.fingerprintParts();
    } catch (Exception e) {
      caught = e;
    }

    Assert.isNotNull(caught, 'A decimal composer version must be rejected.');
    Assert.isTrue(
      caught.getMessage()
        .contains(QuoteDocumentContributorError.VERSION_UNDECLARED),
      caught.getMessage()
    );
  }

  @IsTest
  static void contributorContextCopiesInputCollections() {
    List<QuoteDocumentLine> lines = QuoteDocumentTestData.normalizedLines();
    QuoteDocumentSectionContributorContext context = new QuoteDocumentSectionContributorContext(
      quoteRecord(),
      lines,
      new List<Quote_Document_Fact__c>(),
      'en_US',
      'USD',
      'ORDER_FORM_FAMILIES',
      '1'
    );
    Integer suppliedSize = lines.size();

    lines.clear();

    Assert.areEqual(
      suppliedSize,
      context.lines.size(),
      'The caller cannot replace the contributor context by mutating its source List.'
    );
  }

  private static Quote_Document_Composer__mdt apexConfig() {
    return new Quote_Document_Composer__mdt(
      DeveloperName = 'Order_Form_Families',
      Is_Active__c = true,
      Composer_Code__c = 'ORDER_FORM_FAMILIES',
      Version__c = '1',
      Display_Order__c = 10
    );
  }

  private static SBQQ__Quote__c quoteRecord() {
    return QuoteDocumentQuery.quotesWithLinesReadOnly(
      new Set<Id>{ QuoteDocumentTestData.quoteId() }
    )[0];
  }

  private static List<QuoteDocumentLine> documentLines(SBQQ__Quote__c quote) {
    List<QuoteDocumentLine> lines = new List<QuoteDocumentLine>();
    for (SBQQ__QuoteLine__c rawLine : quote.SBQQ__LineItems__r) {
      lines.add(new QuoteDocumentLine(rawLine, quote));
    }
    return lines;
  }
}
