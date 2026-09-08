/**
 * Release-gate coverage for defensive contracts that ordinary happy-path
 * generation cannot reach. Each test asserts a stable refusal or policy
 * decision used by installation, configuration, and support runbooks.
 */
@IsTest
private class QuoteDocumentReleaseCoverageTest {
  @TestSetup
  static void setupData() {
    QuoteDocumentTestData.setup();
  }

  @IsTest
  static void contributorOutputHandlesNullAndNullableLists() {
    QuoteDocumentSectionContributorOutput combined = new QuoteDocumentSectionContributorOutput();
    combined.addAll(null);
    Assert.isTrue(combined.isEmpty(), 'Null output adds no document content.');

    QuoteDocumentSectionContributorOutput other = new QuoteDocumentSectionContributorOutput();
    other.columns = null;
    other.tables.add(new Quote_Document_Table__c(Table_Key__c = 'T1'));
    combined.addAll(other);

    Assert.areEqual(1, combined.tables.size(), 'Non-null lists are copied.');
    Assert.areEqual(
      0,
      combined.columns.size(),
      'A nullable list is treated as empty.'
    );
    Assert.isFalse(
      combined.isEmpty(),
      'A contributed Table makes output non-empty.'
    );
  }

  @IsTest
  static void flowOutputAdaptersPreserveTypedListsAndNormalizeNulls() {
    Assert.areEqual(0, QuoteDocumentFlowSectionContributor.tables(null).size());
    Assert.areEqual(
      0,
      QuoteDocumentFlowSectionContributor.columns(null).size()
    );
    Assert.areEqual(0, QuoteDocumentFlowSectionContributor.rows(null).size());
    Assert.areEqual(0, QuoteDocumentFlowSectionContributor.blocks(null).size());
    Assert.areEqual(0, QuoteDocumentFlowSectionContributor.facts(null).size());

    Assert.areEqual(
      1,
      QuoteDocumentFlowSectionContributor.tables(
          new List<Quote_Document_Table__c>{ new Quote_Document_Table__c() }
        )
        .size()
    );
    Assert.areEqual(
      1,
      QuoteDocumentFlowSectionContributor.columns(
          new List<Quote_Document_Column__c>{ new Quote_Document_Column__c() }
        )
        .size()
    );
    Assert.areEqual(
      1,
      QuoteDocumentFlowSectionContributor.rows(
          new List<Quote_Document_Row__c>{ new Quote_Document_Row__c() }
        )
        .size()
    );
    Assert.areEqual(
      1,
      QuoteDocumentFlowSectionContributor.blocks(
          new List<Quote_Document_Block__c>{ new Quote_Document_Block__c() }
        )
        .size()
    );
    Assert.areEqual(
      1,
      QuoteDocumentFlowSectionContributor.facts(
          new List<Quote_Document_Fact__c>{ new Quote_Document_Fact__c() }
        )
        .size()
    );
  }

  @IsTest
  static void unknownApexComposerHasAStableConfigurationError() {
    try {
      QuoteDocumentSectionContributorRegistry.resolve('NOT_REGISTERED');
      Assert.fail('An unreviewed composer must not run.');
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      assertCode(e, 'DOCUMENT_COMPOSER_UNKNOWN');
    }
  }

  @IsTest
  static void invalidConditionDefinitionsFailWithSpecificCodes() {
    Integer verified = 0;
    assertInvalidCondition(
      0,
      1,
      'SBQQ__Quantity__c',
      'Equals',
      '1',
      'Number',
      'CONDITION_ORDER_INVALID'
    );
    verified++;
    assertInvalidCondition(
      1,
      1,
      null,
      'Equals',
      '1',
      'Number',
      'CONDITION_FIELD_MISSING'
    );
    verified++;
    assertInvalidCondition(
      1,
      1,
      'SBQQ__Quantity__c',
      'Contains',
      '1',
      'Number',
      'CONDITION_OPERATOR_UNSUPPORTED'
    );
    verified++;
    assertInvalidCondition(
      1,
      1,
      'SBQQ__Quantity__c',
      'Equals',
      '1',
      'Currency',
      'CONDITION_TYPE_UNSUPPORTED'
    );
    verified++;
    assertInvalidCondition(
      1,
      1,
      'SBQQ__Quantity__c',
      'Equals',
      null,
      'Number',
      'CONDITION_VALUE_MISSING'
    );
    verified++;
    assertInvalidCondition(
      1,
      1,
      'SBQQ__ProductCode__c',
      'Greater Than',
      'A',
      'Text',
      'CONDITION_COMPARISON_INVALID'
    );
    verified++;
    Assert.areEqual(6, verified, 'Every invalid configuration was rejected.');
  }

  @IsTest
  static void conditionOperatorsRespectBlankListsRangesAndDates() {
    List<QuoteDocumentLine> lines = QuoteDocumentTestData.normalizedLines();
    Assert.areEqual(
      0,
      QuoteDocumentCondition.apply('NO_CONDITIONS', null).size()
    );

    useCondition('BLANK', 'SBQQ__StartDate__c', 'Is Blank', null, 'Date');
    Assert.areEqual(
      lines.size(),
      QuoteDocumentCondition.apply('BLANK', lines).size()
    );

    useCondition(
      'NOT_BLANK',
      'SBQQ__Quantity__c',
      'Is Not Blank',
      null,
      'Number'
    );
    Assert.areEqual(
      lines.size(),
      QuoteDocumentCondition.apply('NOT_BLANK', lines).size()
    );

    useCondition(
      'NULL_NOT_EQUAL',
      'SBQQ__StartDate__c',
      'Not Equals',
      '2026-01-01',
      'Date'
    );
    Assert.areEqual(
      lines.size(),
      QuoteDocumentCondition.apply('NULL_NOT_EQUAL', lines).size()
    );

    useCondition(
      'IN_SET',
      'SBQQ__Product__r.Family',
      'In',
      'Hardware; Software; ',
      'Text'
    );
    Assert.isTrue(QuoteDocumentCondition.apply('IN_SET', lines).size() > 0);

    useCondition('GTE', 'SBQQ__Quantity__c', 'Greater Or Equal', '1', 'Number');
    Assert.areEqual(
      lines.size(),
      QuoteDocumentCondition.apply('GTE', lines).size()
    );

    useCondition('LT', 'SBQQ__Quantity__c', 'Less Than', '1000', 'Number');
    Assert.areEqual(
      lines.size(),
      QuoteDocumentCondition.apply('LT', lines).size()
    );

    useCondition('LTE', 'SBQQ__Quantity__c', 'Less Or Equal', '1000', 'Number');
    Assert.areEqual(
      lines.size(),
      QuoteDocumentCondition.apply('LTE', lines).size()
    );

    List<SBQQ__QuoteLine__c> dated = [SELECT Id FROM SBQQ__QuoteLine__c];
    for (SBQQ__QuoteLine__c source : dated) {
      source.SBQQ__StartDate__c = Date.newInstance(2026, 1, 1);
    }
    update dated;
    lines = normalizedLinesFromOrg();
    useCondition(
      'DATE_GTE',
      'SBQQ__StartDate__c',
      'Greater Or Equal',
      '2025-12-31',
      'Date'
    );
    Assert.areEqual(
      lines.size(),
      QuoteDocumentCondition.apply('DATE_GTE', lines).size()
    );
  }

  @IsTest
  static void tierExpansionRejectsMissingUnpricedAndUnoccupiedBands() {
    QuoteDocumentLine line = QuoteDocumentTestData.normalizedLines()[0];
    QuoteDocumentExpansion.Request request = expansionRequest(
      new List<QuoteDocumentLine>{ line }
    );
    QuoteDocumentTierExpander expander = new QuoteDocumentTierExpander();
    Integer verified = 0;

    QuoteDocumentTierExpander.useTiers(
      new Map<Id, List<QuoteDocumentTierExpander.Tier>>()
    );
    assertTierFailure(
      expander,
      line,
      request,
      QuoteDocumentTierExpander.ERR_NO_SCHEDULE
    );
    verified++;

    QuoteDocumentTierExpander.useTiers(
      tiersFor(
        line,
        new QuoteDocumentTierExpander.Tier(
          line.quoteLineId,
          'ZERO',
          1,
          null,
          0,
          null
        )
      )
    );
    assertTierFailure(
      expander,
      line,
      request,
      QuoteDocumentTierExpander.ERR_UNPRICED
    );
    verified++;

    QuoteDocumentTierExpander.useTiers(
      tiersFor(
        line,
        new QuoteDocumentTierExpander.Tier(
          line.quoteLineId,
          'ABOVE_QUANTITY',
          line.quantity + 1,
          null,
          1,
          1
        )
      )
    );
    assertTierFailure(
      expander,
      line,
      request,
      QuoteDocumentTierExpander.ERR_NO_RATES
    );
    verified++;
    Assert.areEqual(3, verified, 'Every invalid tier shape was rejected.');
  }

  @IsTest
  static void aliasExpansionRejectsAbsentAndIncompleteMappings() {
    QuoteDocumentLine line = QuoteDocumentTestData.normalizedLines()[0];
    QuoteDocumentExpansion.Request request = expansionRequest(
      new List<QuoteDocumentLine>{ line }
    );
    QuoteDocumentAliasExpander expander = new QuoteDocumentAliasExpander();
    Integer verified = 0;

    QuoteDocumentAliasExpander.useAliases(
      new Map<String, List<QuoteDocumentAliasExpander.Alias>>()
    );
    assertAliasFailure(expander, request, QuoteDocumentAliasExpander.ERR_EMPTY);
    verified++;

    QuoteDocumentAliasExpander.useAliases(
      new Map<String, List<QuoteDocumentAliasExpander.Alias>>{
        'ANOTHER_PRODUCT' => new List<QuoteDocumentAliasExpander.Alias>{
          new QuoteDocumentAliasExpander.Alias(
            'ANOTHER_PRODUCT',
            'CUSTOMER-1',
            1,
            1
          )
        }
      }
    );
    assertAliasFailure(
      expander,
      request,
      QuoteDocumentAliasExpander.ERR_UNMAPPED
    );
    verified++;
    Assert.areEqual(
      2,
      verified,
      'Both invalid alias configurations were rejected.'
    );
  }

  @IsTest
  static void expansionAndScheduleRequireDeclaredAxes() {
    QuoteDocumentLine line = QuoteDocumentTestData.normalizedLines()[0];
    QuoteDocumentExpansion.Request request = expansionRequest(
      new List<QuoteDocumentLine>{ line }
    );

    try {
      QuoteDocumentExpansion.apply(
        new EmptyAxisExpander(),
        request.quote,
        request.definition,
        request.lines,
        request.labels
      );
      Assert.fail('An expansion without buckets must fail.');
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      assertCode(e, QuoteDocumentExpansion.ERR_AXIS);
    }

    try {
      new QuoteDocumentScheduleExpander().buckets(request);
      Assert.fail('A schedule expander requires Schedule_Code__c.');
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      assertCode(e, QuoteDocumentScheduleExpander.ERR_UNDECLARED);
    }

    try {
      QuoteDocumentPeriodExpander.resolveAxis(
        new SBQQ__Quote__c(),
        new List<QuoteDocumentLine>(),
        12
      );
      Assert.fail('A period axis cannot be guessed without dates.');
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      assertCode(e, QuoteDocumentPeriodExpander.ERR_AXIS);
    }
  }

  @IsTest
  static void blockValidationRequiresIdentityProvenanceAndApproval() {
    Integer verified = 0;
    assertBlockFailure(
      new Quote_Document_Block__c(),
      'BLOCK_IDENTITY_INCOMPLETE'
    );
    verified++;

    Quote_Document_Block__c block = validBlock();
    block.Source_Identity__c = null;
    assertBlockFailure(block, 'BLOCK_SOURCE_MISSING');
    verified++;

    block = validBlock();
    block.Approval_Identity__c = null;
    assertBlockFailure(block, 'BLOCK_APPROVAL_MISSING');
    verified++;
    Assert.areEqual(3, verified, 'Every required block identity was enforced.');
  }

  @IsTest
  static void composerConfigurationRejectsAmbiguityOrderAndBadVersions() {
    assertBadComposer(
      composer(null, null, '1', 10),
      'DOCUMENT_COMPOSER_TYPE_INVALID'
    );
    assertBadComposer(
      composer(null, 'Some_Flow', '1', null),
      'DOCUMENT_COMPOSER_ORDER_MISSING'
    );
    assertBadComposer(
      composer(null, 'Some_Flow', 'v1', 10),
      QuoteDocumentContributorError.VERSION_UNDECLARED
    );

    Quote_Document_Composer__mdt first = composer(null, 'Flow_One', '1', 10);
    Quote_Document_Composer__mdt second = composer(null, 'Flow_Two', '1', 10);
    QuoteDocumentSectionComposition.useConfigs(
      new List<Quote_Document_Composer__mdt>{ first, second }
    );
    try {
      QuoteDocumentSectionComposition.fingerprintParts();
      Assert.fail('Active composers must not share a display order.');
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      assertCode(e, 'DOCUMENT_COMPOSER_ORDER_DUPLICATE');
    }
  }

  @IsTest
  static void queueRetryPolicyIsBoundedAndUsesLifecycleBackoff() {
    QuoteDocumentGenerator.QuoteDocumentException contention = new QuoteDocumentGenerator.QuoteDocumentException(
      'UNABLE_TO_LOCK_ROW: synthetic contention'
    );
    Assert.isTrue(
      QuoteDocumentGenerateJob.shouldRetry(contention, 1),
      'Early lock contention is retryable.'
    );
    Assert.isFalse(
      QuoteDocumentGenerateJob.shouldRetry(
        contention,
        QuoteDocumentLifecycle.MAX_LOCK_ATTEMPTS
      ),
      'The retry limit is a hard boundary.'
    );
    Assert.isFalse(
      QuoteDocumentGenerateJob.shouldRetry(
        new QuoteDocumentGenerator.QuoteDocumentException(
          'CONFIGURATION_ERROR'
        ),
        1
      ),
      'Configuration failures cannot improve through retry.'
    );
    Integer delay = QuoteDocumentGenerateJob.retryDelay(2);
    Assert.isTrue(
      delay >= 2 && delay <= 4,
      'Attempt two uses the lifecycle policy: base two plus zero-to-two minutes of jitter. Actual: ' +
      delay
    );
  }

  @SuppressWarnings('PMD.ExcessiveParameterList')
  private static void assertInvalidCondition(
    Integer conditionSet,
    Integer sequence,
    String fieldPath,
    String operator,
    String compareValue,
    String dataType,
    String expectedCode
  ) {
    try {
      QuoteDocumentCondition.forTest(
        conditionSet,
        sequence,
        fieldPath,
        operator,
        compareValue,
        dataType
      );
      Assert.fail('Invalid condition must fail with ' + expectedCode + '.');
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      assertCode(e, expectedCode);
    }
  }

  @SuppressWarnings('PMD.ExcessiveParameterList')
  private static void useCondition(
    String tableCode,
    String fieldPath,
    String operator,
    String compareValue,
    String dataType
  ) {
    QuoteDocumentCondition.useConditions(
      new Map<String, List<QuoteDocumentCondition>>{
        tableCode => new List<QuoteDocumentCondition>{
          QuoteDocumentCondition.forTest(
            1,
            1,
            fieldPath,
            operator,
            compareValue,
            dataType
          )
        }
      }
    );
  }

  private static List<QuoteDocumentLine> normalizedLinesFromOrg() {
    SBQQ__Quote__c quote = QuoteDocumentQuery.quotesWithLines(
      new Set<Id>{ QuoteDocumentTestData.quoteId() }
    )[0];
    List<QuoteDocumentLine> lines = new List<QuoteDocumentLine>();
    for (SBQQ__QuoteLine__c source : quote.SBQQ__LineItems__r) {
      lines.add(new QuoteDocumentLine(source, quote));
    }
    return lines;
  }

  private static QuoteDocumentExpansion.Request expansionRequest(
    List<QuoteDocumentLine> lines
  ) {
    QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
      'RELEASE_COVERAGE',
      new List<String>{ QuoteDocumentTableDefinition.DIM_EXPANSION },
      new List<Integer>{ 1 },
      QuoteDocumentTableDefinition.FILTER_ALL
    );
    definition.expanderCode = 'TEST_EXPANDER';
    definition.scheduleCode = null;
    return new QuoteDocumentExpansion.Request(
      new SBQQ__Quote__c(
        Id = QuoteDocumentTestData.quoteId(),
        SBQQ__StartDate__c = Date.newInstance(2026, 1, 1),
        SBQQ__SubscriptionTerm__c = 12
      ),
      definition,
      lines,
      QuoteDocumentLabels.forLocale('en_US')
    );
  }

  private static Map<Id, List<QuoteDocumentTierExpander.Tier>> tiersFor(
    QuoteDocumentLine line,
    QuoteDocumentTierExpander.Tier tier
  ) {
    return new Map<Id, List<QuoteDocumentTierExpander.Tier>>{
      line.quoteLineId => new List<QuoteDocumentTierExpander.Tier>{ tier }
    };
  }

  @SuppressWarnings('PMD.ExcessiveParameterList')
  private static void assertTierFailure(
    QuoteDocumentTierExpander expander,
    QuoteDocumentLine line,
    QuoteDocumentExpansion.Request request,
    String expectedCode
  ) {
    try {
      expander.placements(line, request);
      Assert.fail('Invalid tier data must fail with ' + expectedCode + '.');
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      assertCode(e, expectedCode);
    }
  }

  private static void assertAliasFailure(
    QuoteDocumentAliasExpander expander,
    QuoteDocumentExpansion.Request request,
    String expectedCode
  ) {
    try {
      expander.buckets(request);
      Assert.fail('Invalid alias data must fail with ' + expectedCode + '.');
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      assertCode(e, expectedCode);
    }
  }

  private static Quote_Document_Block__c validBlock() {
    return new Quote_Document_Block__c(
      Block_Code__c = 'RELEASE_COVERAGE',
      Block_Type__c = 'Paragraph',
      Display_Order__c = 10,
      Locale__c = 'en_US',
      Body__c = 'Approved plain text.',
      Source_Version__c = '1',
      Source_Identity__c = 'TEST:SOURCE',
      Approval_Identity__c = 'TEST:APPROVAL',
      Placement__c = 'Document Level'
    );
  }

  private static void assertBlockFailure(
    Quote_Document_Block__c block,
    String expectedCode
  ) {
    try {
      QuoteDocumentBlockBuilder.validate(block);
      Assert.fail('Invalid block must fail with ' + expectedCode + '.');
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      assertCode(e, expectedCode);
    }
  }

  @SuppressWarnings('PMD.ExcessiveParameterList')
  private static Quote_Document_Composer__mdt composer(
    String apexCode,
    String flowName,
    String version,
    Decimal displayOrder
  ) {
    return new Quote_Document_Composer__mdt(
      DeveloperName = 'Release_Coverage_' + String.valueOf(displayOrder),
      Is_Active__c = true,
      Composer_Code__c = apexCode,
      Flow_API_Name__c = flowName,
      Version__c = version,
      Display_Order__c = displayOrder
    );
  }

  private static void assertBadComposer(
    Quote_Document_Composer__mdt config,
    String expectedCode
  ) {
    QuoteDocumentSectionComposition.useConfigs(
      new List<Quote_Document_Composer__mdt>{ config }
    );
    try {
      QuoteDocumentSectionComposition.fingerprintParts();
      Assert.fail('Invalid composer must fail with ' + expectedCode + '.');
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      assertCode(e, expectedCode);
    }
  }

  private static void assertCode(Exception failure, String expectedCode) {
    Assert.isTrue(
      failure.getMessage().contains(expectedCode),
      'Expected ' + expectedCode + ', received: ' + failure.getMessage()
    );
  }

  private class EmptyAxisExpander implements QuoteDocumentLineExpander {
    public List<QuoteDocumentExpansion.Bucket> buckets(
      QuoteDocumentExpansion.Request request
    ) {
      return new List<QuoteDocumentExpansion.Bucket>();
    }

    public List<QuoteDocumentExpansion.Placement> placements(
      QuoteDocumentLine line,
      QuoteDocumentExpansion.Request request
    ) {
      return new List<QuoteDocumentExpansion.Placement>();
    }

    public Boolean dividesQuantity() {
      return false;
    }
  }
}
