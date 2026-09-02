/**
 * Covers QuoteDocumentFingerprint's canonicalization/encoding directly (unit
 * level), and the reuse decision it enables in QuoteDocumentGenerator
 * (integration level, through generate() itself) - see specs/quote-docusign-
 * launch/spec.md Increment 2, acceptance criteria in §5.7.
 */
@IsTest
private class QuoteDocumentFingerprintTest {
  @TestSetup
  static void setup() {
    Account account = new Account(
      Name = 'Fingerprint Test',
      Industry = 'Technology'
    );
    insert account;

    Opportunity opportunity = new Opportunity(
      Name = 'Fingerprint Test',
      AccountId = account.Id,
      StageName = 'Prospecting',
      CloseDate = Date.today().addDays(30)
    );
    insert opportunity;

    List<Product2> products = new List<Product2>{
      new Product2(
        Name = 'Fingerprint Product',
        ProductCode = 'FINGERPRINT',
        Family = 'Hardware',
        IsActive = true
      ),
      new Product2(
        Name = 'Fingerprint Service',
        ProductCode = 'FINGERPRINT-SV',
        Family = 'Service',
        IsActive = true
      )
    };
    insert products;

    SBQQ__Quote__c quote = new SBQQ__Quote__c(
      SBQQ__Account__c = account.Id,
      SBQQ__Opportunity2__c = opportunity.Id,
      SBQQ__Type__c = 'Quote',
      SBQQ__Status__c = 'Draft'
    );
    insert quote;

    insert new List<SBQQ__QuoteLine__c>{
      new SBQQ__QuoteLine__c(
        SBQQ__Quote__c = quote.Id,
        SBQQ__Product__c = products[0].Id,
        SBQQ__Number__c = 1,
        SBQQ__Quantity__c = 2,
        SBQQ__ListPrice__c = 500,
        SBQQ__RegularPrice__c = 500,
        SBQQ__NetPrice__c = 450,
        SBQQ__CustomerPrice__c = 450
      ),
      new SBQQ__QuoteLine__c(
        SBQQ__Quote__c = quote.Id,
        SBQQ__Product__c = products[1].Id,
        SBQQ__Number__c = 2,
        SBQQ__Quantity__c = 1,
        SBQQ__ListPrice__c = 1200,
        SBQQ__RegularPrice__c = 1200,
        SBQQ__NetPrice__c = 1200,
        SBQQ__CustomerPrice__c = 1200
      )
    };
  }

  /**
   * Queried dynamically for the same reason QuoteDocumentQuery.quotesWithLines
   * builds its SELECT as a string: CurrencyIsoCode only exists as a field when
   * multi-currency is on, so a static reference will not compile in a
   * single-currency org - but the fingerprint canonicalizes it whenever the org
   * IS multi-currency, and a quote fetched without it throws SObjectException
   * there rather than hashing a null. Mirroring production's guard keeps this
   * helper working in both org shapes.
   */
  private static SBQQ__Quote__c quote() {
    String currencyField = UserInfo.isMultiCurrencyOrganization()
      ? ', CurrencyIsoCode'
      : '';
    return (SBQQ__Quote__c) Database.query(
      'SELECT Id, Name, SBQQ__NetAmount__c, AccountIndustry__c, ' +
        'Document_Data_Status__c, Document_Data_Generated_On__c, ' +
        'Document_Data_Fingerprint__c, SBQQ__StartDate__c, SBQQ__SubscriptionTerm__c' +
        currencyField +
        ' FROM SBQQ__Quote__c LIMIT 1'
    );
  }

  private static List<QuoteDocumentLine> normalizedLines(SBQQ__Quote__c q) {
    List<QuoteDocumentLine> lines = new List<QuoteDocumentLine>();
    for (SBQQ__QuoteLine__c raw : [
      SELECT
        Id,
        SBQQ__Number__c,
        SBQQ__Product__c,
        SBQQ__ProductName__c,
        SBQQ__ProductCode__c,
        SBQQ__Product__r.Family,
        SBQQ__ChargeType__c,
        SBQQ__Bundle__c,
        SBQQ__Bundled__c,
        SBQQ__Optional__c,
        SBQQ__OptionLevel__c,
        SBQQ__RequiredBy__c,
        SBQQ__RequiredBy__r.SBQQ__ProductName__c,
        SBQQ__Group__c,
        SBQQ__Group__r.Name,
        SBQQ__Quantity__c,
        SBQQ__ListTotal__c,
        SBQQ__RegularTotal__c,
        SBQQ__TotalDiscountAmount__c,
        SBQQ__NetTotal__c,
        SBQQ__CustomerTotal__c,
        SBQQ__NetPrice__c,
        SBQQ__Existing__c,
        SBQQ__PriorQuantity__c,
        SBQQ__UpgradedSubscription__c,
        SBQQ__RenewedSubscription__c,
        SBQQ__StartDate__c,
        SBQQ__EndDate__c
      FROM SBQQ__QuoteLine__c
      WHERE SBQQ__Quote__c = :q.Id
    ]) {
      lines.add(new QuoteDocumentLine(raw, q));
    }
    return lines;
  }

  // -----------------------------------------------------------------------
  // canonicalize()/compute() - determinism and change-sensitivity
  // -----------------------------------------------------------------------

  @IsTest
  static void identicalInputsProduceAnIdenticalDigestAcrossTwoComputations() {
    SBQQ__Quote__c q = quote();
    List<QuoteDocumentLine> lines = normalizedLines(q);
    List<QuoteDocumentTableDefinition> definitions = QuoteDocumentTableDefinition.getAll();

    String first = QuoteDocumentFingerprint.compute(q, lines, definitions);
    String second = QuoteDocumentFingerprint.compute(
      q,
      normalizedLines(q),
      definitions
    );

    Assert.areEqual(
      first,
      second,
      'The same inputs, read again independently, must produce the same digest'
    );
    Assert.areEqual(
      64,
      first.length(),
      'A SHA-256 hex digest is always 64 characters'
    );
  }

  @IsTest
  static void aDeactivatedTableDefinitionChangesTheDigest() {
    SBQQ__Quote__c q = quote();
    List<QuoteDocumentLine> lines = normalizedLines(q);
    List<QuoteDocumentTableDefinition> withExtra = QuoteDocumentTableDefinition.getAll();

    QuoteDocumentTableDefinition extra = QuoteDocumentTableDefinition.build(
      'FINGERPRINT_EXTRA_PROBE',
      new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
      new List<Integer>{ 1 },
      QuoteDocumentTableDefinition.FILTER_ALL
    );
    List<QuoteDocumentTableDefinition> withoutExtra = new List<QuoteDocumentTableDefinition>(
      withExtra
    );
    List<QuoteDocumentTableDefinition> plusOne = new List<QuoteDocumentTableDefinition>(
      withExtra
    );
    plusOne.add(extra);

    String digestWithout = QuoteDocumentFingerprint.compute(
      q,
      lines,
      withoutExtra
    );
    String digestWith = QuoteDocumentFingerprint.compute(q, lines, plusOne);

    Assert.areNotEqual(
      digestWithout,
      digestWith,
      'A table dropping out of the active definition list (what deactivation does) must change the digest'
    );
  }

  // -----------------------------------------------------------------------
  // Value encodings - §5.2
  // -----------------------------------------------------------------------

  @IsTest
  static void nullAndEmptyStringProduceDifferentTokens() {
    Assert.areNotEqual(
      QuoteDocumentFingerprint.encodeString(null),
      QuoteDocumentFingerprint.encodeString(''),
      'NULL and empty string are different values and must not collide'
    );
  }

  @IsTest
  static void decimalScaleVariationsNormalizeToTheSameToken() {
    Assert.areEqual(
      QuoteDocumentFingerprint.encodeDecimal(10.5),
      QuoteDocumentFingerprint.encodeDecimal(10.50),
      '10.5 and 10.50 are the same amount written with different precision'
    );
    Assert.areEqual(
      QuoteDocumentFingerprint.encodeDecimal(10.5),
      QuoteDocumentFingerprint.encodeDecimal(10.500000),
      'Scale must be normalized regardless of how many trailing zeros are supplied'
    );
  }

  @IsTest
  static void decimalNullDiffersFromZero() {
    Assert.areNotEqual(
      QuoteDocumentFingerprint.encodeDecimal(null),
      QuoteDocumentFingerprint.encodeDecimal(0),
      'A measure that was never set is not the same input as a measure of zero'
    );
  }

  @IsTest
  static void dateTimeAlwaysCanonicalizesToUtc() {
    Datetime dt = Datetime.newInstanceGmt(2024, 6, 15, 10, 30, 0);
    Assert.areEqual(
      'DATETIME:2024-06-15T10:30:00Z',
      QuoteDocumentFingerprint.encodeDateTime(dt),
      'DateTime must format in GMT/UTC, never the running user\'s timezone'
    );
  }

  @IsTest
  static void dateEncodesAsPlainIsoRegardlessOfLocale() {
    Assert.areEqual(
      'DATE:2024-06-05',
      QuoteDocumentFingerprint.encodeDate(Date.newInstance(2024, 6, 5)),
      'A single-digit month/day must still be zero-padded for a stable token'
    );
  }

  @IsTest
  static void idsAlwaysEncodeAsEighteenCharacters() {
    Id fifteenChar = Id.valueOf('001000000000001');
    String encoded = QuoteDocumentFingerprint.encodeId(fifteenChar);
    Assert.areEqual('ID:' + String.valueOf(fifteenChar), encoded);
    Assert.areEqual(
      21,
      encoded.length(),
      '"ID:" plus an 18-character Id is always 21 characters'
    );
  }

  // -----------------------------------------------------------------------
  // Reuse decision, through the real generator - §5.3, §5.7
  // -----------------------------------------------------------------------

  @IsTest
  static void aSecondGenerateWithNoChangesReusesRatherThanRegenerates() {
    Id quoteId = quote().Id;
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });

    Map<Id, Datetime> generatedOnByTableId = new Map<Id, Datetime>();
    for (Quote_Document_Table__c t : [
      SELECT Id, Generated_On__c
      FROM Quote_Document_Table__c
      WHERE Quote__c = :quoteId
    ]) {
      generatedOnByTableId.put(t.Id, t.Generated_On__c);
    }
    Assert.isFalse(
      generatedOnByTableId.isEmpty(),
      'Precondition: first generation produced tables'
    );

    Test.startTest();
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
    Test.stopTest();

    Map<Id, Datetime> generatedOnAfterSecondCall = new Map<Id, Datetime>();
    for (Quote_Document_Table__c t : [
      SELECT Id, Generated_On__c
      FROM Quote_Document_Table__c
      WHERE Quote__c = :quoteId
    ]) {
      generatedOnAfterSecondCall.put(t.Id, t.Generated_On__c);
    }

    Assert.areEqual(
      generatedOnByTableId.keySet(),
      generatedOnAfterSecondCall.keySet(),
      'Reuse must not delete and reinsert - the table Ids must be exactly the same records'
    );
    for (Id tableId : generatedOnByTableId.keySet()) {
      Assert.areEqual(
        generatedOnByTableId.get(tableId),
        generatedOnAfterSecondCall.get(tableId),
        'A reused table must keep its original Generated_On__c timestamp, proving it was not rebuilt'
      );
    }
  }

  @IsTest
  static void aProductFamilyChangeWithNoQuoteOrLineDmlForcesRegeneration() {
    Id quoteId = quote().Id;
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
    String firstFingerprint = quote().Document_Data_Fingerprint__c;

    Product2 product = [
      SELECT Id, Family
      FROM Product2
      WHERE ProductCode = 'FINGERPRINT'
      LIMIT 1
    ];
    product.Family = 'Hardware - Renamed';
    update product;

    Test.startTest();
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
    Test.stopTest();

    String secondFingerprint = quote().Document_Data_Fingerprint__c;
    Assert.areNotEqual(
      firstFingerprint,
      secondFingerprint,
      'A Product2 field used as a snapshot value changed with no Quote or Quote Line DML at all - ' +
      'trigger-based staleness cannot see this, only the fingerprint can'
    );
  }

  @IsTest
  static void manuallyDeletingOneTableForcesRegenerationDespiteAMatchingFingerprint() {
    Id quoteId = quote().Id;
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });

    Integer tableCountBefore = [
      SELECT COUNT()
      FROM Quote_Document_Table__c
      WHERE Quote__c = :quoteId
    ];
    Assert.isTrue(
      tableCountBefore > 1,
      'Precondition: more than one table exists to delete from'
    );

    // Quote_Document_Table__c OWD is Public Read/Write - simulating exactly
    // the risk spec §5.3 calls out: the fingerprint still matches, but the
    // snapshot is now incomplete.
    delete [
      SELECT Id
      FROM Quote_Document_Table__c
      WHERE Quote__c = :quoteId
      LIMIT 1
    ];
    Assert.areEqual(
      'Ready',
      quote().Document_Data_Status__c,
      'A direct delete of a child table does not touch the Quote, so the gate stays open (Ready) - ' +
        'the fingerprint alone cannot see the snapshot is now incomplete, which is exactly why the ' +
        'table-existence check in canReuse exists'
    );

    Test.startTest();
    QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
    Test.stopTest();

    Assert.areEqual(
      tableCountBefore,
      [SELECT COUNT() FROM Quote_Document_Table__c WHERE Quote__c = :quoteId],
      'Regeneration must have restored the full set of tables'
    );
  }

  @IsTest
  static void canReuseIsFalseWhenStatusIsNotReadyEvenIfTheFingerprintMatches() {
    SBQQ__Quote__c q = quote();
    List<QuoteDocumentTableDefinition> definitions = QuoteDocumentTableDefinition.getAll();
    String fingerprint = QuoteDocumentFingerprint.compute(
      q,
      normalizedLines(q),
      definitions
    );

    q.Document_Data_Status__c = 'Stale';
    q.Document_Data_Fingerprint__c = fingerprint;

    Boolean reuse = QuoteDocumentGenerator.canReuse(
      q,
      fingerprint,
      definitions,
      new List<QuoteDocumentLine>(),
      new List<Quote_Document_Fact__c>()
    );
    Assert.isFalse(
      reuse,
      'Only a Ready quote is safe to reuse, whatever the fingerprint says'
    );
  }
}
