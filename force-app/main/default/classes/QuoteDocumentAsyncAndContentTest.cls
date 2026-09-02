/**
 * The async job's decision branches, block ordering, and the locale fallbacks.
 *
 * The retry ENQUEUE inside QuoteDocumentGenerateJob is still not covered here,
 * and deliberately: reaching it needs a lock only a second concurrent
 * transaction can hold, and faking it would mean adding an exception-injection
 * seam to production code so a test could feel complete. The decision that
 * leads to it, the backoff it uses and the give-up path are all asserted -
 * see QuoteDocumentUncoveredPathsTest.
 */
@IsTest
private class QuoteDocumentAsyncAndContentTest {
  @TestSetup
  static void setup() {
    QuoteDocumentTestData.setup();
  }

  // -----------------------------------------------------------------------
  // QuoteDocumentGenerateJob - the skip-unless-stale contract
  // -----------------------------------------------------------------------

  /**
   * The one-argument constructor is the refresh triggered by a save: it must
   * do nothing when the snapshot is not Stale, or every save would regenerate
   * a document nobody asked to change.
   */
  @IsTest
  static void theRefreshJobDoesNothingWhenTheSnapshotIsNotStale() {
    Id quoteId = QuoteDocumentTestData.quoteId();

    Test.startTest();
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
    Test.stopTest();

    Datetime generatedBefore = [
      SELECT Document_Data_Generated_On__c
      FROM SBQQ__Quote__c
      WHERE Id = :quoteId
    ]
    .Document_Data_Generated_On__c;

    // Ready, not Stale - the refresh must decline.
    new QuoteDocumentGenerateJob(quoteId).execute((QueueableContext) null);

    Assert.areEqual(
      generatedBefore,
      [
        SELECT Document_Data_Generated_On__c
        FROM SBQQ__Quote__c
        WHERE Id = :quoteId
      ]
      .Document_Data_Generated_On__c,
      'A refresh of a Ready snapshot must not regenerate it - the timestamp proves nothing ran.'
    );
  }

  /**
   * The unconditional constructor is the backfill: it generates whether or
   * not the quote is Stale, because a backfill that skipped Not Generated
   * quotes would do nothing at all.
   */
  @IsTest
  static void theBackfillJobGeneratesRegardlessOfStaleness() {
    Id quoteId = QuoteDocumentTestData.quoteId();

    Test.startTest();
    new QuoteDocumentGenerateJob(quoteId, false)
      .execute((QueueableContext) null);
    Test.stopTest();

    Assert.areEqual(
      'Ready',
      [SELECT Document_Data_Status__c FROM SBQQ__Quote__c WHERE Id = :quoteId]
      .Document_Data_Status__c,
      'A backfill must generate a quote that had nothing generated behind it.'
    );
    Assert.isTrue(
      [SELECT COUNT() FROM Quote_Document_Table__c WHERE Quote__c = :quoteId] >
      0,
      'And it must actually produce tables.'
    );
  }

  /**
   * A configuration failure inside the job must be CAUGHT, not rethrown. The
   * generator writes Failed, the request Id and the error code in this same
   * transaction - letting the exception escape would roll that write back and
   * lose exactly the evidence the runbook promises is queryable.
   */
  @IsTest
  static void aFailedGenerationLeavesItsEvidenceOnTheQuote() {
    Id quoteId = QuoteDocumentTestData.quoteId();

    // A definition with no Display_Title__c: verification refuses to
    // publish it, inside generateOne's try block, with an allowlisted code.
    //
    // The previous version passed an EMPTY definition list, which
    // generateOne does not reject at all - it built nothing and recorded
    // Ready. Asserting only 'not Generating' then passed on a run that
    // never failed, which is the one thing this test exists to rule out.
    List<QuoteDocumentTableDefinition> definitions = QuoteDocumentTableDefinition.getAll();
    definitions[0].displayTitle = null;
    QuoteDocumentTableDefinition.useDefinitions(definitions);

    Test.startTest();
    new QuoteDocumentGenerateJob(quoteId, false)
      .execute((QueueableContext) null);
    Test.stopTest();

    SBQQ__Quote__c after = [
      SELECT
        Document_Data_Status__c,
        Document_Data_Error__c,
        Document_Data_Request_Id__c
      FROM SBQQ__Quote__c
      WHERE Id = :quoteId
    ];
    Assert.areEqual(
      'Failed',
      after.Document_Data_Status__c,
      'The generator writes Failed in the same transaction - if the job rethrew, this write ' +
      'would have rolled back and the status would still be what it was.'
    );
    Assert.isTrue(
      after.Document_Data_Error__c != null &&
      after.Document_Data_Error__c.contains('TABLE_TITLE_MISSING'),
      'The persisted error must carry the stable code a runbook greps for, not a flattened ' +
        'GENERATION_FAILED_UNEXPECTED: ' +
        after.Document_Data_Error__c
    );
    Assert.isTrue(
      String.isNotBlank(after.Document_Data_Request_Id__c),
      'A failed attempt must still name itself, or support cannot correlate it with a log.'
    );
  }

  // -----------------------------------------------------------------------
  // QuoteDocumentBlockBuilder - one ordering sequence for blocks and tables
  // -----------------------------------------------------------------------

  /**
   * Blocks and tables share ONE document-wide ordering sequence, so a
   * collision is a real ambiguity: the renderer would have to choose, and two
   * renderers could legitimately choose differently.
   */
  @IsTest
  static void aBlockAndTableSharingADisplayOrderIsRejected() {
    List<Quote_Document_Table__c> tables = new List<Quote_Document_Table__c>{
      new Quote_Document_Table__c(
        Table_Code__c = 'TDX_ORDER',
        Display_Order__c = 30
      )
    };
    List<Quote_Document_Block__c> blocks = new List<Quote_Document_Block__c>{
      new Quote_Document_Block__c(
        Block_Code__c = 'TERMS',
        Display_Order__c = 30
      )
    };

    String message;
    try {
      QuoteDocumentBlockBuilder.assertOrderingIsUnambiguous(blocks, tables);
    } catch (Exception e) {
      message = e.getMessage();
    }

    Assert.isNotNull(
      message,
      'A block and a table cannot both claim order 30 - the renderer would have to choose.'
    );
    Assert.isTrue(message.contains('DOCUMENT_ORDER_DUPLICATE'), message);
  }

  /**
   * Two TABLES at one order, with no block anywhere near it - the case the
   * guard used to return clean on, because the table loop overwrote the owner
   * instead of looking first.
   */
  @IsTest
  static void twoTablesCannotShareOneOrder() {
    String message;
    try {
      QuoteDocumentBlockBuilder.assertOrderingIsUnambiguous(
        new List<Quote_Document_Block__c>(),
        new List<Quote_Document_Table__c>{
          new Quote_Document_Table__c(
            Table_Code__c = 'FIRST_TABLE',
            Display_Order__c = 70
          ),
          new Quote_Document_Table__c(
            Table_Code__c = 'SECOND_TABLE',
            Display_Order__c = 70
          )
        }
      );
    } catch (Exception e) {
      message = e.getMessage();
    }

    Assert.isNotNull(
      message,
      'Two tables at order 70 print in whichever order the query returned them.'
    );
    Assert.isTrue(message.contains('DOCUMENT_ORDER_DUPLICATE'), message);
    Assert.isTrue(message.contains('SECOND_TABLE'), message);
  }

  @IsTest
  static void distinctOrdersAcrossBlocksAndTablesAreAccepted() {
    QuoteDocumentBlockBuilder.assertOrderingIsUnambiguous(
      new List<Quote_Document_Block__c>{
        new Quote_Document_Block__c(
          Block_Code__c = 'TERMS',
          Display_Order__c = 40
        )
      },
      new List<Quote_Document_Table__c>{
        new Quote_Document_Table__c(
          Table_Code__c = 'TDX_ORDER',
          Display_Order__c = 30
        )
      }
    );
    // A block with no order at all is skipped rather than colliding at null.
    QuoteDocumentBlockBuilder.assertOrderingIsUnambiguous(
      new List<Quote_Document_Block__c>{
        new Quote_Document_Block__c(Block_Code__c = 'TERMS')
      },
      new List<Quote_Document_Table__c>{
        new Quote_Document_Table__c(
          Table_Code__c = 'TDX_ORDER',
          Display_Order__c = 30
        )
      }
    );
  }

  // -----------------------------------------------------------------------
  // QuoteDocumentLocale - every fallback rung
  // -----------------------------------------------------------------------

  /**
   * A hyphenated tag, a base-language tag and an unreadable path all have to
   * resolve to something a dictionary lookup can use, because a locale that
   * cannot be resolved must not take generation down with it.
   */
  @IsTest
  static void localeNormalizationCoversEveryFallbackRung() {
    Assert.areEqual(
      'en_US',
      QuoteDocumentLabels.normalize('en-US'),
      'A hyphenated tag is the same locale as an underscored one - CPQ writes both.'
    );
    Assert.areEqual(
      'fr',
      QuoteDocumentLabels.normalize('fr'),
      'A base language stays itself.'
    );

    SBQQ__Quote__c bare = new SBQQ__Quote__c();
    Assert.isNull(
      QuoteDocumentLocale.resolveForTest(
        bare,
        'SBQQ__Account__r.BillingCountry'
      ),
      'A null relationship resolves to null, not an exception.'
    );
    Assert.isNull(
      QuoteDocumentLocale.resolveForTest(bare, 'Nope__c'),
      'A field that does not exist resolves to null too.'
    );
    Assert.isNull(
      QuoteDocumentLocale.resolveForTest(bare, 'A__r.B__r.C__c'),
      'And so does a multi-hop path that goes nowhere.'
    );
  }
}
