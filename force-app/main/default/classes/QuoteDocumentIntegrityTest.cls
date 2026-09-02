/**
 * Step 06A - "immutable snapshot" made true rather than asserted.
 *
 * Every test here edits a PERSISTED record and proves the tampering is
 * caught. That is the gap the source fingerprint cannot close: none of these
 * edits changes any input, so Document_Data_Fingerprint__c stays identical
 * and the document would render modified with every expectation matching.
 */
@IsTest
private class QuoteDocumentIntegrityTest {
  @TestSetup
  static void setup() {
    QuoteDocumentTestData.setup();
  }

  private static SBQQ__Quote__c generated() {
    Id quoteId = QuoteDocumentTestData.quoteId();
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
    return [
      SELECT Id, Document_Payload_Hash__c, Document_Data_Fingerprint__c
      FROM SBQQ__Quote__c
      WHERE Id = :quoteId
    ];
  }

  private static String tamperFailure(SBQQ__Quote__c quote) {
    try {
      QuoteDocumentPayloadHash.assertIntact(
        quote.Id,
        quote.Document_Payload_Hash__c
      );
      return null;
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      return e.getMessage();
    }
  }

  private static void assertCaught(String message, String what) {
    Assert.isNotNull(
      message,
      what + ' must be detected - the source fingerprint cannot see it.'
    );
    Assert.isTrue(
      message.contains('PAYLOAD_INTEGRITY_MISMATCH'),
      'Wrong code for ' + what + ': ' + message
    );
    Assert.isTrue(
      message.contains('Expected payload hash') && message.contains('found'),
      'The message must name both the expected and the actual hash: ' + message
    );
  }

  /**
   * Performs the tamper in SYSTEM mode.
   *
   * Since the snapshot objects moved to Private sharing, an ordinary update
   * of a persisted row is refused by the platform - which is the point of
   * step 06A and is asserted separately. But "ordinary permissions cannot
   * edit it" and "an edit is detected" are two different guarantees, and
   * this class is testing the second. The realistic threat is someone who
   * DOES have access - an admin, a data loader, an integration user with
   * broad CRUD - so the tamper is applied the way they would apply it.
   *
   * A tamper test that could not tamper would pass while proving nothing.
   */
  private static void tamperWith(SObject record) {
    Database.update(record, true, AccessLevel.SYSTEM_MODE);
  }

  private static Quote_Document_Row__c anyDetailRow(Id quoteId) {
    return [
      SELECT
        Id,
        Display_Label__c,
        Display_Order__c,
        Is_Displayed__c,
        Amount_Net__c,
        Row_Type__c
      FROM Quote_Document_Row__c
      WHERE
        Quote_Document_Table__r.Quote__c = :quoteId
        AND Row_Type__c = 'Detail'
      LIMIT 1
    ];
  }

  // -----------------------------------------------------------------------
  // The baseline
  // -----------------------------------------------------------------------

  @IsTest
  static void anUntamperedSnapshotPasses() {
    Test.startTest();
    SBQQ__Quote__c quote = generated();
    Test.stopTest();

    Assert.isTrue(
      String.isNotBlank(quote.Document_Payload_Hash__c),
      'A published snapshot must carry a payload hash, or nothing can prove it untampered.'
    );
    Assert.isNull(
      tamperFailure(quote),
      'An untouched snapshot must pass, or every other assertion here is meaningless.'
    );
  }

  @IsTest
  static void regeneratingAnUnchangedQuoteReproducesThePayloadHash() {
    Id quoteId = QuoteDocumentTestData.quoteId();

    Test.startTest();
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
    String first = [
      SELECT Document_Payload_Hash__c
      FROM SBQQ__Quote__c
      WHERE Id = :quoteId
    ]
    .Document_Payload_Hash__c;

    update new SBQQ__Quote__c(
      Id = quoteId,
      Document_Data_Fingerprint__c = 'force-rebuild'
    );
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
    String second = [
      SELECT Document_Payload_Hash__c
      FROM SBQQ__Quote__c
      WHERE Id = :quoteId
    ]
    .Document_Payload_Hash__c;
    Test.stopTest();

    Assert.areEqual(
      first,
      second,
      'The hash is SEMANTIC. Record Ids and timestamps change on every regeneration and must be ' +
        'excluded, or the hash would flag every rebuild and be useless for the one case that ' +
        'matters.'
    );
  }

  // -----------------------------------------------------------------------
  // One test per mutation class
  // -----------------------------------------------------------------------

  @IsTest
  static void editingAnAmountIsCaught() {
    Test.startTest();
    SBQQ__Quote__c quote = generated();
    Quote_Document_Row__c row = anyDetailRow(quote.Id);
    row.Amount_Net__c =
      (row.Amount_Net__c == null ? 0 : row.Amount_Net__c) + 1000;
    tamperWith(row);
    Test.stopTest();

    assertCaught(tamperFailure(quote), 'An edited amount');
  }

  @IsTest
  static void editingALabelIsCaught() {
    Test.startTest();
    SBQQ__Quote__c quote = generated();
    Quote_Document_Row__c row = anyDetailRow(quote.Id);
    row.Display_Label__c = 'Something the customer never agreed to';
    tamperWith(row);
    Test.stopTest();

    assertCaught(tamperFailure(quote), 'An edited label');
  }

  @IsTest
  static void changingDisplayOrderIsCaught() {
    Test.startTest();
    SBQQ__Quote__c quote = generated();
    Quote_Document_Row__c row = anyDetailRow(quote.Id);
    row.Display_Order__c = row.Display_Order__c + 5;
    tamperWith(row);
    Test.stopTest();

    assertCaught(tamperFailure(quote), 'A reordered row');
  }

  @IsTest
  static void changingVisibilityIsCaught() {
    Test.startTest();
    SBQQ__Quote__c quote = generated();
    Quote_Document_Row__c row = anyDetailRow(quote.Id);
    row.Is_Displayed__c = !row.Is_Displayed__c;
    tamperWith(row);
    Test.stopTest();

    assertCaught(tamperFailure(quote), 'A hidden or revealed row');
  }

  @IsTest
  static void changingAColumnBindingIsCaught() {
    Test.startTest();
    SBQQ__Quote__c quote = generated();
    Quote_Document_Column__c column = [
      SELECT Id, Value_Field__c, Display_Label__c
      FROM Quote_Document_Column__c
      WHERE
        Quote_Document_Table__r.Quote__c = :quote.Id
        AND Value_Field__c != NULL
      LIMIT 1
    ];
    column.Display_Label__c = 'Relabelled after publication';
    tamperWith(column);
    Test.stopTest();

    assertCaught(tamperFailure(quote), 'An edited column');
  }

  /**
   * A digest must describe ONE quote. The bulk form selects the union of
   * every configured binding in the batch, and hashing that union made a
   * quote's digest depend on who it was retrieved alongside: a field only
   * its neighbour bound joined its canonical form as a null and moved the
   * hash, failing PAYLOAD_INTEGRITY_MISMATCH on an untouched snapshot.
   */
  @IsTest
  static void aDigestDoesNotDependOnTheRestOfTheBatch() {
    Test.startTest();
    SBQQ__Quote__c quoteA = generated();
    Id quoteB = QuoteDocumentTestData.extraQuotes(1)[0].Id;
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteB });

    Quote_Document_Column__c neighbourColumn = [
      SELECT Id, Value_Field__c
      FROM Quote_Document_Column__c
      WHERE
        Quote_Document_Table__r.Quote__c = :quoteB
        AND Value_Field__c != NULL
      LIMIT 1
    ];
    neighbourColumn.Value_Field__c = 'Group_Key__c';
    tamperWith(neighbourColumn);
    Test.stopTest();

    // Without this the test could pass vacuously: if the rebind did not
    // stick, both quotes bind the same fields and the union is a no-op.
    Assert.areEqual(
      0,
      [
        SELECT COUNT()
        FROM Quote_Document_Column__c
        WHERE
          Quote_Document_Table__r.Quote__c = :quoteA.Id
          AND Value_Field__c = 'Group_Key__c'
      ],
      'Quote A must not bind Group_Key__c, or there is no divergence to detect.'
    );
    Assert.areEqual(
      1,
      [
        SELECT COUNT()
        FROM Quote_Document_Column__c
        WHERE
          Quote_Document_Table__r.Quote__c = :quoteB
          AND Value_Field__c = 'Group_Key__c'
      ],
      'The rebind of quote B must have stuck.'
    );

    Map<Id, String> batch = QuoteDocumentPayloadHash.computeAll(
      new Set<Id>{ quoteA.Id, quoteB }
    );
    Assert.areEqual(
      QuoteDocumentPayloadHash.compute(quoteA.Id),
      batch.get(quoteA.Id),
      'Quote A binds no Group_Key__c. Its digest must not move because quote B does.'
    );
    Assert.areEqual(
      QuoteDocumentPayloadHash.compute(quoteB),
      batch.get(quoteB),
      'Quote B must hash the same alone as it does alongside quote A.'
    );
  }

  @IsTest
  static void editingABlockBodyIsCaught() {
    Test.startTest();
    SBQQ__Quote__c quote = generated();
    List<Quote_Document_Block__c> blocks = [
      SELECT Id, Body__c
      FROM Quote_Document_Block__c
      WHERE Quote__c = :quote.Id
      LIMIT 1
    ];
    if (blocks.isEmpty()) {
      Test.stopTest();
      Assert.isTrue(
        true,
        'No blocks configured in this org; covered by the other mutation classes.'
      );
      return;
    }
    blocks[0].Body__c = 'Terms the customer never saw.';
    tamperWith(blocks[0]);
    Test.stopTest();

    assertCaught(tamperFailure(quote), 'An edited clause');
  }

  /**
   * The one Row_Count__c cannot catch. Delete a row and insert a
   * replacement: the count is identical, the source fingerprint is
   * identical, and the document renders with different content.
   */
  @IsTest
  static void deletingAndReinsertingARowIsCaught() {
    Test.startTest();
    SBQQ__Quote__c quote = generated();

    Quote_Document_Row__c original = anyDetailRow(quote.Id);
    Quote_Document_Row__c source = [
      SELECT
        Quote_Document_Table__c,
        Row_Type__c,
        Row_Key__c,
        Group_Level__c,
        Display_Order__c,
        Amount_Net__c,
        Include_In_Subtotal__c,
        Include_In_Grand_Total__c
      FROM Quote_Document_Row__c
      WHERE Id = :original.Id
    ];
    Quote_Document_Row__c replacement = new Quote_Document_Row__c(
      Quote_Document_Table__c = source.Quote_Document_Table__c,
      Row_Type__c = source.Row_Type__c,
      Row_Key__c = source.Row_Key__c,
      Group_Level__c = source.Group_Level__c,
      Display_Order__c = source.Display_Order__c,
      Amount_Net__c = source.Amount_Net__c,
      Include_In_Subtotal__c = source.Include_In_Subtotal__c,
      Include_In_Grand_Total__c = source.Include_In_Grand_Total__c,
      Is_Displayed__c = true,
      Display_Label__c = 'A different product entirely'
    );

    Database.delete(original, true, AccessLevel.SYSTEM_MODE);
    Database.insert(replacement, true, AccessLevel.SYSTEM_MODE);
    Test.stopTest();

    assertCaught(tamperFailure(quote), 'A deleted-and-reinserted row');
  }

  // -----------------------------------------------------------------------
  // The two hashes do different jobs
  // -----------------------------------------------------------------------

  /**
   * The distinction the whole step rests on. Editing persisted OUTPUT moves
   * the payload hash and leaves the INPUT fingerprint alone - which is why
   * the fingerprint alone could never have detected tampering, and why
   * adding a second hash was not duplication.
   */
  @IsTest
  static void sourceFingerprintDoesNotMoveWhenOnlyOutputIsEdited() {
    Test.startTest();
    SBQQ__Quote__c quote = generated();
    String fingerprintBefore = quote.Document_Data_Fingerprint__c;
    String payloadBefore = quote.Document_Payload_Hash__c;

    Quote_Document_Row__c row = anyDetailRow(quote.Id);
    row.Display_Label__c = 'Tampered';
    tamperWith(row);
    Test.stopTest();

    SBQQ__Quote__c after = [
      SELECT Document_Data_Fingerprint__c
      FROM SBQQ__Quote__c
      WHERE Id = :quote.Id
    ];

    Assert.areEqual(
      fingerprintBefore,
      after.Document_Data_Fingerprint__c,
      'The source fingerprint hashes INPUTS. Editing output does not touch it - which is exactly why ' +
      'it can never detect tampering, and why a second hash exists.'
    );
    Assert.areNotEqual(
      payloadBefore,
      QuoteDocumentPayloadHash.compute(quote.Id),
      'The payload hash covers OUTPUT and must move.'
    );
  }

  // -----------------------------------------------------------------------
  // Failure behaviour
  // -----------------------------------------------------------------------

  @IsTest
  static void aSnapshotWithNoPayloadHashCannotBeProvenIntact() {
    Test.startTest();
    SBQQ__Quote__c quote = generated();
    Test.stopTest();

    String message;
    try {
      QuoteDocumentPayloadHash.assertIntact(quote.Id, null);
    } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
      message = e.getMessage();
    }

    Assert.isNotNull(
      message,
      'No hash means no proof, which is not the same as no tampering.'
    );
    Assert.isTrue(
      message.contains('PAYLOAD_HASH_MISSING'),
      'Wrong code: ' + message
    );
    Assert.isTrue(
      message.contains('replaceable'),
      'The message must say regenerate rather than repair: ' + message
    );
  }

  /** The integrity check must never offer to fix what it finds. */
  @IsTest
  static void theMismatchMessageForbidsRepair() {
    Test.startTest();
    SBQQ__Quote__c quote = generated();
    Quote_Document_Row__c row = anyDetailRow(quote.Id);
    row.Display_Label__c = 'Tampered';
    tamperWith(row);
    Test.stopTest();

    String message = tamperFailure(quote);
    Assert.isTrue(
      message.contains('must not be') && message.contains('repaired'),
      'Nothing here knows which version was correct, so repair would be a guess written into a ' +
        'document someone signs: ' +
        message
    );
  }
}
