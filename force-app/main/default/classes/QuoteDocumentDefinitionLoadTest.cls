/**
 * The load-time rejections that live in QuoteDocumentTableDefinition.fromRecords.
 *
 * These are deliberately NOT reached through useDefinitions(): that helper
 * writes the `cached` field, and getAll() returns from cache before any of this
 * validation runs, so an injected definition proves nothing about whether a bad
 * metadata record would have been rejected. fromRecords is the seam that
 * actually runs the checks, and it takes raw __mdt records - which is what lets
 * these cases be tested without activating a broken record in the org, where a
 * single invalid active definition fails generation for every quote.
 *
 * Not covered here, because they already have tests on their own real paths:
 *   - a grouping with both, or neither, of Dimension and Field Path
 *     -> QuoteDocumentGroupingTest.toLevelsRejectsAGroupingWith...
 *   - an invalid grouping field path, which is rejected at generation time by
 *     QuoteDocumentQuery.validateFieldPath, NOT at load
 *     -> QuoteDocumentGroupingTest.anInvalidFieldPathIsRejectedBeforeTheQueryRuns
 *   - a blank Display_Title__c, which QuoteDocumentPresentationTest already
 *     feeds straight to validatePresentationConfig
 *     -> QuoteDocumentPresentationTest.anActiveDefinitionWithNoTitleFailsConfigLoad
 */
@IsTest
private class QuoteDocumentDefinitionLoadTest {
  private static Quote_Document_Table_Def__mdt def(String code) {
    return new Quote_Document_Table_Def__mdt(
      Table_Code__c = code,
      Table_Name__c = code,
      Display_Title__c = code,
      Amount_Basis__c = 'Final Value',
      Line_Filter__c = QuoteDocumentTableDefinition.FILTER_ALL,
      Measure_Set__c = QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL,
      Show_Details__c = true,
      Show_Section_Totals__c = false,
      Display_Order__c = 10
    );
  }

  /** One valid grouping, keyed under the null Id that in-memory __mdt records carry. */
  private static Map<Id, List<Quote_Document_Grouping__mdt>> oneGrouping() {
    return new Map<Id, List<Quote_Document_Grouping__mdt>>{
      null => new List<Quote_Document_Grouping__mdt>{
        new Quote_Document_Grouping__mdt(
          Dimension__c = QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY,
          Level__c = 1,
          Sequence__c = 1
        )
      }
    };
  }

  private static List<QuoteDocumentTableDefinition> load(
    List<Quote_Document_Table_Def__mdt> records,
    Map<Id, List<Quote_Document_Grouping__mdt>> groupings
  ) {
    return QuoteDocumentTableDefinition.fromRecords(records, groupings);
  }

  private static String messageFrom(
    List<Quote_Document_Table_Def__mdt> records,
    Map<Id, List<Quote_Document_Grouping__mdt>> groupings,
    String expectationDescription
  ) {
    try {
      load(records, groupings);
    } catch (Exception e) {
      return e.getMessage();
    }
    Assert.fail(expectationDescription);
    return null;
  }

  // ---------------------------------------------------------------------
  // The baseline: the same seam accepts a well-formed record, so a rejection
  // below is attributable to the thing under test and not to the fixture.
  // ---------------------------------------------------------------------

  @IsTest
  static void aWellFormedRecordLoads() {
    List<QuoteDocumentTableDefinition> definitions = load(
      new List<Quote_Document_Table_Def__mdt>{ def('LOAD_OK') },
      oneGrouping()
    );

    Assert.areEqual(
      1,
      definitions.size(),
      'A valid record must produce one definition'
    );
    Assert.areEqual(
      'LOAD_OK',
      definitions[0].tableCode,
      'The loaded definition must be the one passed in'
    );
  }

  // ---------------------------------------------------------------------
  // No grouping records. Rejected on its own, allowed when a contributor is
  // what builds the rows - the shape MONTHLY_SUBSCRIPTION_SUMMARY needs,
  // since no field on a quote line names the month a row belongs to.
  // ---------------------------------------------------------------------

  @IsTest
  static void aTableWithNoGroupingAndNothingToBuildItsRowsIsRejected() {
    String message = messageFrom(
      new List<Quote_Document_Table_Def__mdt>{ def('LOAD_NO_GROUPING') },
      new Map<Id, List<Quote_Document_Grouping__mdt>>(),
      'A table with neither a grouping nor a contributor can only emit a lone grand total.'
    );

    Assert.isTrue(
      message.contains('no grouping dimensions'),
      'The rejection must name what is missing: ' + message
    );
  }

  @IsTest
  static void aTableWithNoGroupingLoadsWhenAContributorBuildsItsRows() {
    Quote_Document_Table_Def__mdt record = def('LOAD_CONTRIBUTOR_ONLY');
    record.Row_Customizer_Code__c = QuoteDocumentMonthlyRowCustomizer.CODE;
    record.Row_Customizer_Version__c = '1';
    record.Cache_Policy__c = QuoteDocumentTableDefinition.CACHE_STANDARD;

    List<QuoteDocumentTableDefinition> definitions = load(
      new List<Quote_Document_Table_Def__mdt>{ record },
      new Map<Id, List<Quote_Document_Grouping__mdt>>()
    );

    Assert.areEqual(
      1,
      definitions.size(),
      'A contributor-built table is valid config, not half-finished'
    );
    Assert.isTrue(
      definitions[0].groupBy.isEmpty(),
      'It must load with no levels rather than acquiring an invented one'
    );
  }

  @IsTest
  static void recordOrderIsPreserved() {
    List<QuoteDocumentTableDefinition> definitions = load(
      new List<Quote_Document_Table_Def__mdt>{ def('FIRST'), def('SECOND') },
      oneGrouping()
    );

    Assert.areEqual(2, definitions.size(), 'Both records must load');
    Assert.areEqual(
      'FIRST',
      definitions[0].tableCode,
      'fromRecords must preserve the order it was given - getAll supplies Display_Order__c order'
    );
    Assert.areEqual(
      'SECOND',
      definitions[1].tableCode,
      'Order must survive the second record too'
    );
  }

  // ---------------------------------------------------------------------
  // Duplicate Table_Code__c - unreachable through useDefinitions, since the
  // dedupe runs only while records are being turned into definitions.
  // ---------------------------------------------------------------------

  @IsTest
  static void twoRecordsSharingATableCodeAreRejected() {
    String message = messageFrom(
      new List<Quote_Document_Table_Def__mdt>{
        def('SAME_CODE'),
        def('SAME_CODE')
      },
      oneGrouping(),
      'Two records sharing Table_Code__c must be rejected at load'
    );

    Assert.isTrue(
      message.contains('SAME_CODE'),
      'The message must name the duplicated code so an admin knows which record to fix: ' +
      message
    );
    Assert.isTrue(
      message.contains('Table_Code__c'),
      'The message must name the field, not just the value: ' + message
    );
  }

  // ---------------------------------------------------------------------
  // A definition with no groupings.
  // ---------------------------------------------------------------------

  @IsTest
  static void aDefinitionWithNoGroupingsIsRejected() {
    String message = messageFrom(
      new List<Quote_Document_Table_Def__mdt>{ def('NO_GROUPINGS') },
      new Map<Id, List<Quote_Document_Grouping__mdt>>(),
      'A definition with no grouping records must be rejected at load'
    );

    Assert.isTrue(
      message.contains('NO_GROUPINGS'),
      'The message must name the table that has no groupings: ' + message
    );
    Assert.isTrue(
      message.contains('grouping'),
      'The message must say what is missing: ' + message
    );
  }

  // ---------------------------------------------------------------------
  // validateContributorConfig - five branches, none of them reachable before
  // this class: getAll only ran them against records already active in the
  // org, and useDefinitions skips them entirely.
  // ---------------------------------------------------------------------

  @IsTest
  static void anApexCustomizerWithoutAVersionIsRejected() {
    Quote_Document_Table_Def__mdt record = def('APEX_NO_VERSION');
    record.Row_Customizer_Code__c = 'QuoteDocumentDiscountRowCustomizer';
    record.Cache_Policy__c = QuoteDocumentTableDefinition.CACHE_STANDARD;

    String message = messageFrom(
      new List<Quote_Document_Table_Def__mdt>{ record },
      oneGrouping(),
      'An Apex customizer with a blank Row_Customizer_Version__c must be rejected'
    );

    Assert.isTrue(
      message.contains('Row_Customizer_Version__c'),
      'The message must name the blank field: ' + message
    );
    Assert.isTrue(
      message.contains(QuoteDocumentContributorError.VERSION_UNDECLARED),
      'It must carry the VERSION_UNDECLARED code, which is what the catalogue documents: ' +
      message
    );
  }

  @IsTest
  static void aFlowCustomizerWithoutAVersionIsRejected() {
    Quote_Document_Table_Def__mdt record = def('FLOW_NO_VERSION');
    record.Row_Customizer_Flow__c = 'QuoteDocumentSampleFlowContributor';
    record.Cache_Policy__c = QuoteDocumentTableDefinition.CACHE_STANDARD;

    String message = messageFrom(
      new List<Quote_Document_Table_Def__mdt>{ record },
      oneGrouping(),
      'A Flow customizer with a blank Row_Customizer_Flow_Version__c must be rejected'
    );

    Assert.isTrue(
      message.contains('Row_Customizer_Flow_Version__c'),
      'The message must name the blank field: ' + message
    );
    Assert.isTrue(
      message.contains(QuoteDocumentContributorError.VERSION_UNDECLARED),
      'It must carry the VERSION_UNDECLARED code: ' + message
    );
  }

  @IsTest
  static void aContributorWithNoCachePolicyIsRejected() {
    Quote_Document_Table_Def__mdt record = def('NO_POLICY');
    record.Row_Customizer_Code__c = 'QuoteDocumentDiscountRowCustomizer';
    record.Row_Customizer_Version__c = 'v1';
    record.Cache_Policy__c = null;

    String message = messageFrom(
      new List<Quote_Document_Table_Def__mdt>{ record },
      oneGrouping(),
      'A contributor table with a blank Cache_Policy__c must be rejected - blank must not read as STANDARD'
    );

    Assert.isTrue(
      message.contains('Cache_Policy__c'),
      'The message must name the unset policy: ' + message
    );
    Assert.isTrue(
      message.contains(QuoteDocumentContributorError.DEPENDENCY_UNDECLARED),
      'It must carry the DEPENDENCY_UNDECLARED code: ' + message
    );
  }

  @IsTest
  static void declaredDependenciesWithAnEmptySetIsRejected() {
    Quote_Document_Table_Def__mdt record = def('EMPTY_DEPENDENCIES');
    record.Row_Customizer_Code__c = 'QuoteDocumentDiscountRowCustomizer';
    record.Row_Customizer_Version__c = 'v1';
    record.Cache_Policy__c = QuoteDocumentTableDefinition.CACHE_DECLARED_DEPENDENCIES;
    record.Contributor_Dependency_Set__c = null;

    String message = messageFrom(
      new List<Quote_Document_Table_Def__mdt>{ record },
      oneGrouping(),
      'DECLARED_DEPENDENCIES with an empty Contributor_Dependency_Set__c must be rejected'
    );

    Assert.isTrue(
      message.contains('Contributor_Dependency_Set__c'),
      'The message must name the empty set: ' + message
    );
    Assert.isTrue(
      message.contains(QuoteDocumentContributorError.DEPENDENCY_UNDECLARED),
      'It must carry the DEPENDENCY_UNDECLARED code: ' + message
    );
  }

  @IsTest
  static void dependencyPathsUnderANonMatchingPolicyAreRejected() {
    Quote_Document_Table_Def__mdt record = def('IGNORED_DEPENDENCIES');
    record.Row_Customizer_Code__c = 'QuoteDocumentDiscountRowCustomizer';
    record.Row_Customizer_Version__c = 'v1';
    record.Cache_Policy__c = QuoteDocumentTableDefinition.CACHE_STANDARD;
    record.Contributor_Dependency_Set__c = 'AccountIndustry__c';

    String message = messageFrom(
      new List<Quote_Document_Table_Def__mdt>{ record },
      oneGrouping(),
      'Dependency paths under STANDARD must be rejected rather than silently ignored'
    );

    Assert.isTrue(
      message.contains(QuoteDocumentTableDefinition.CACHE_STANDARD),
      'The message must name the policy that would ignore the paths: ' + message
    );
    Assert.isTrue(
      message.contains(QuoteDocumentContributorError.DEPENDENCY_UNDECLARED),
      'It must carry the DEPENDENCY_UNDECLARED code: ' + message
    );
  }

  /**
   * The mirror of the four rejections above: a fully declared contributor
   * loads. Without this, every assertion in this section would still pass if
   * validateContributorConfig had been changed to reject unconditionally.
   */
  @IsTest
  static void aFullyDeclaredContributorLoads() {
    Quote_Document_Table_Def__mdt record = def('DECLARED_OK');
    record.Row_Customizer_Code__c = 'QuoteDocumentDiscountRowCustomizer';
    record.Row_Customizer_Version__c = 'v1';
    record.Cache_Policy__c = QuoteDocumentTableDefinition.CACHE_DECLARED_DEPENDENCIES;
    record.Contributor_Dependency_Set__c = 'AccountIndustry__c';

    List<QuoteDocumentTableDefinition> definitions = load(
      new List<Quote_Document_Table_Def__mdt>{ record },
      oneGrouping()
    );

    Assert.areEqual(
      1,
      definitions.size(),
      'A fully declared contributor table must load'
    );
    Assert.areEqual(
      1,
      definitions[0].contributorDependencyPaths.size(),
      'The declared dependency path must survive the load'
    );
  }

  /**
   * A table with no contributor at all is allowed to leave Cache_Policy__c
   * blank - the "mid-edit" allowance the method documents. Asserted so that
   * tightening the contributor rules cannot accidentally start failing the
   * shipped tables that have no customizer.
   */
  @IsTest
  static void aTableWithNoContributorNeedsNoCachePolicy() {
    Quote_Document_Table_Def__mdt record = def('NO_CONTRIBUTOR');
    record.Cache_Policy__c = null;

    Assert.areEqual(
      1,
      load(new List<Quote_Document_Table_Def__mdt>{ record }, oneGrouping())
        .size(),
      'A table with no contributor must load without a cache policy'
    );
  }
}
