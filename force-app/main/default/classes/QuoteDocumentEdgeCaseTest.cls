/**
 * Edge cases identified in review: the outcomes that are rare in practice but
 * decide whether a failure is loud or silent.
 *
 * Split out of QuoteDocumentGeneratorTest, which covers the ordinary path -
 * correct config, correct totals. What is here instead is the awkward middle
 * ground: a duplicate table code that slips past the primary guard, a table
 * whose filter legitimately excludes every line, and a customizer code that
 * names nothing. Each asserts the framework says so rather than quietly
 * producing something plausible.
 *
 * Fixture data comes from QuoteDocumentTestData, identical to every other
 * QuoteDocument suite.
 */
@IsTest
private class QuoteDocumentEdgeCaseTest {
  @TestSetup
  static void setup() {
    QuoteDocumentTestData.setup();
  }

  private static final String CODE_OPTIONAL = QuoteDocumentTestData.CODE_OPTIONAL;

  private static SBQQ__QuoteLine__c line(
    Id quoteId,
    Id productId,
    Integer lineNumber,
    Decimal quantity,
    Decimal listPrice,
    Decimal netPrice
  ) {
    return QuoteDocumentTestData.line(
      quoteId,
      productId,
      lineNumber,
      quantity,
      listPrice,
      netPrice
    );
  }

  private static Id quoteId() {
    return QuoteDocumentTestData.quoteId();
  }

  /**
   * Table_Key__c (Quote Id + Table_Code__c) is the only thing that stops two
   * tables from colliding, and it is enforced by the platform (External Id +
   * Unique on Quote_Document_Table__c) as a last-resort backstop.
   *
   * The primary defense now lives one step earlier: QuoteDocumentTableDefinition
   * .getAll() rejects two active Quote_Document_Table_Def__mdt records that
   * share a Table_Code__c with a named, readable error, the moment real
   * Custom Metadata is loaded - see the "seenTableCodes" check there. This
   * test cannot exercise that check directly: useDefinitions() (below)
   * injects definitions by setting getAll()'s cache straight, bypassing its
   * query loop entirely - the same reason getAll()'s sibling "no grouping
   * dimensions" check also has no direct unit test. Deploying two real
   * conflicting Quote_Document_Table_Def__mdt records just to cover that one
   * guard clause would mean shipping broken config permanently to test a
   * one-line check, which is worse than leaving it covered by inspection.
   *
   * What this test verifies instead - genuinely useful in its own right -
   * is defense in depth: even if two same-coded definitions somehow reached
   * the insert step (bypassing the getAll() guard, as this test does on
   * purpose), the platform's own uniqueness constraint still stops them,
   * rolls back cleanly, and leaves the Quote readably marked Failed rather
   * than silently overwriting one table with another.
   */
  @IsTest
  static void duplicateTableCodeReachingInsertIsStillCaughtByThePlatformAsABackstop() {
    QuoteDocumentTableDefinition first = QuoteDocumentTableDefinition.build(
      'DUPLICATE_CODE_PROBE',
      new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
      new List<Integer>{ 1 },
      QuoteDocumentTableDefinition.FILTER_ALL
    );
    QuoteDocumentTableDefinition second = QuoteDocumentTableDefinition.build(
      'DUPLICATE_CODE_PROBE',
      new List<String>{ QuoteDocumentTableDefinition.DIM_CHARGE_TYPE },
      new List<Integer>{ 1 },
      QuoteDocumentTableDefinition.FILTER_ALL
    );
    QuoteDocumentTableDefinition.useDefinitions(
      new List<QuoteDocumentTableDefinition>{ first, second }
    );

    Test.startTest();
    try {
      QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
      Assert.fail(
        'Two active definitions sharing one Table_Code__c must not both be inserted'
      );
    } catch (Exception e) {
      // Deliberately not asserting on e.getMessage() content - today
      // this is the platform's own DmlException text (something like
      // "duplicate value found: Table_Key__c"), not a message this
      // codebase composed, so pinning its exact wording would make the
      // test brittle to a Salesforce platform change rather than to a
      // change in this framework's own behavior.
      Assert.isInstanceOfType(
        e,
        QuoteDocumentGenerator.QuoteDocumentException.class,
        'generateOne wraps every DmlException as a QuoteDocumentException via fail(), never lets it escape raw'
      );
    }
    Test.stopTest();

    SBQQ__Quote__c quote = [
      SELECT Document_Data_Status__c
      FROM SBQQ__Quote__c
      WHERE Id = :quoteId()
    ];
    Assert.areEqual(
      'Failed',
      quote.Document_Data_Status__c,
      'A rolled-back generation must still leave the Quote readably marked Failed, never silently Ready'
    );
  }

  /**
   * Every table in the shared setup data always has at least one counted
   * line, so no existing test proves what happens when a table's own
   * Line_Filter__c legitimately excludes every single line on the quote -
   * plausible in production the moment a rep marks every line on a quote as
   * Optional and a customer views a table that only shows non-optional
   * charges. This is not an error case: a quote can genuinely have nothing
   * to show in one particular table while still being perfectly valid
   * overall. Composition must omit the inapplicable section while allowing
   * the rest of the document generation to complete.
   */
  @IsTest
  static void tableWithEveryLineFilteredOutIsOmitted() {
    Account account = [SELECT Id FROM Account LIMIT 1];
    Opportunity opportunity = [SELECT Id FROM Opportunity LIMIT 1];

    SBQQ__Quote__c allOptionalQuote = new SBQQ__Quote__c(
      SBQQ__Account__c = account.Id,
      SBQQ__Opportunity2__c = opportunity.Id,
      SBQQ__Primary__c = false,
      SBQQ__Type__c = 'Quote'
    );
    insert allOptionalQuote;

    Product2 onlyProduct = [
      SELECT Id
      FROM Product2
      WHERE ProductCode = :CODE_OPTIONAL
      LIMIT 1
    ];
    SBQQ__QuoteLine__c onlyLine = line(
      allOptionalQuote.Id,
      onlyProduct.Id,
      1,
      1,
      100,
      100
    );
    onlyLine.SBQQ__Optional__c = true;
    insert onlyLine;

    QuoteDocumentTableDefinition excludeOptionalOnly = QuoteDocumentTableDefinition.build(
      'EMPTY_AFTER_FILTER_PROBE',
      new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
      new List<Integer>{ 1 },
      QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
    );
    QuoteDocumentTableDefinition.useDefinitions(
      new List<QuoteDocumentTableDefinition>{ excludeOptionalOnly }
    );

    Test.startTest();
    QuoteDocumentGenerator.generate(new Set<Id>{ allOptionalQuote.Id });
    Test.stopTest();

    List<Quote_Document_Row__c> rows = [
      SELECT Id
      FROM Quote_Document_Row__c
      WHERE Quote_Document_Table__r.Quote__c = :allOptionalQuote.Id
    ];
    Assert.areEqual(
      0,
      rows.size(),
      'An omitted Table must not leave synthetic total Rows behind.'
    );

    List<Quote_Document_Table__c> generatedTables = [
      SELECT Id
      FROM Quote_Document_Table__c
      WHERE Quote__c = :allOptionalQuote.Id
    ];
    Assert.areEqual(
      0,
      generatedTables.size(),
      'A definition with no matching lines must contribute no persisted Table.'
    );

    SBQQ__Quote__c generatedQuote = [
      SELECT Document_Data_Status__c
      FROM SBQQ__Quote__c
      WHERE Id = :allOptionalQuote.Id
    ];
    Assert.areEqual(
      'Ready',
      generatedQuote.Document_Data_Status__c,
      'Omitting one inapplicable section is a successful composition outcome.'
    );
  }

  /**
   * Row_Customizer_Code__c is free text on the metadata (see
   * docs/quote-document-extension-recipes.md) but the registry it feeds is
   * a closed Apex switch
   * statement - see QuoteDocumentRowCustomizerRegistry. A code that doesn't
   * match any registered customizer (a typo, or a customizer that was
   * removed from the registry but not from the metadata) must fail
   * generation loudly and name the bad code, not silently build the table
   * with no customization applied - the latter would mean a table quietly
   * stops carrying whatever the customizer was responsible for (a rounding
   * row, an estimated tax line) with no signal to anyone that it happened.
   */
  @IsTest
  static void unknownRowCustomizerCodeFailsGenerationRatherThanSkippingCustomizationSilently() {
    QuoteDocumentTableDefinition brokenCustomizer = QuoteDocumentTableDefinition.build(
      'BROKEN_CUSTOMIZER_PROBE',
      new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
      new List<Integer>{ 1 },
      QuoteDocumentTableDefinition.FILTER_ALL
    );
    brokenCustomizer.rowCustomizerCode = 'THIS_CODE_WAS_NEVER_REGISTERED';
    QuoteDocumentTableDefinition.useDefinitions(
      new List<QuoteDocumentTableDefinition>{ brokenCustomizer }
    );

    Test.startTest();
    try {
      QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
      Assert.fail(
        'An unregistered Row_Customizer_Code__c must not be silently ignored'
      );
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      Assert.isTrue(
        e.getMessage().contains('THIS_CODE_WAS_NEVER_REGISTERED'),
        'The error should name the exact bad code so an admin can find it in the metadata: ' +
        e.getMessage()
      );
    }
    Test.stopTest();
  }
}
