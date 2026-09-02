/**
 * Builds and validates typed document header facts before persistence.
 *
 * Facts carry semantic codes and typed values. A document output service can
 * therefore render customer, address, quote number, and expiration date
 * without knowing which Salesforce fields supplied them.
 */
public with sharing class QuoteDocumentFactBuilder {
  public static final String CUSTOMER_NAME = 'CUSTOMER_NAME';
  public static final String BILLING_ADDRESS = 'BILLING_ADDRESS';
  public static final String QUOTE_NUMBER = 'QUOTE_NUMBER';
  public static final String QUOTE_EXPIRATION_DATE = 'QUOTE_EXPIRATION_DATE';

  private static final Set<String> SUPPORTED_TYPES = new Set<String>{
    'Text',
    'Address',
    'Number',
    'Currency',
    'Date',
    'DateTime',
    'Boolean'
  };

  /**
   * Builds the standard facts available on every Quote snapshot.
   *
   * @param quote Source Quote with its Account relationship loaded.
   * @param labels Locale-specific label dictionary.
   * @param currencyIsoCode Currency code used by currency facts.
   * @return Complete, validated fact records ready for core persistence.
   */
  public static List<Quote_Document_Fact__c> build(
    SBQQ__Quote__c quote,
    QuoteDocumentLabels labels,
    String currencyIsoCode
  ) {
    if (quote == null || quote.Id == null) {
      throw QuoteDocumentContributorError.build(
        'FACT_QUOTE_MISSING',
        'Document facts require a saved Quote. A fact with no source Quote cannot belong to a snapshot.'
      );
    }
    if (labels == null) {
      throw QuoteDocumentContributorError.build(
        'FACT_LABELS_MISSING',
        'Document facts require the resolved document label dictionary.'
      );
    }

    List<Quote_Document_Fact__c> facts = new List<Quote_Document_Fact__c>();
    facts.add(
      textFact(
        quote.Id,
        QUOTE_NUMBER,
        labels.resolve(QUOTE_NUMBER),
        30,
        quote.Name,
        'QUOTE:' + quote.Id
      )
    );

    SObject account = quote.getSObject('SBQQ__Account__r');
    if (account != null) {
      facts.add(
        textFact(
          quote.Id,
          CUSTOMER_NAME,
          labels.resolve(CUSTOMER_NAME),
          10,
          (String) account.get('Name'),
          'ACCOUNT:' + account.get('Id')
        )
      );

      String address = addressOf(account);
      if (String.isNotBlank(address)) {
        Quote_Document_Fact__c addressFact = textFact(
          quote.Id,
          BILLING_ADDRESS,
          labels.resolve(BILLING_ADDRESS),
          20,
          address,
          'ACCOUNT:' + account.get('Id')
        );
        addressFact.Data_Type__c = 'Address';
        facts.add(addressFact);
      }
    }

    Date expiration = (Date) quote.get('SBQQ__ExpirationDate__c');
    if (expiration != null) {
      facts.add(
        new Quote_Document_Fact__c(
          Quote__c = quote.Id,
          Fact_Code__c = QUOTE_EXPIRATION_DATE,
          Display_Label__c = labels.resolve(QUOTE_EXPIRATION_DATE),
          Display_Order__c = 40,
          Data_Type__c = 'Date',
          Date_Value__c = expiration,
          Source_Identity__c = 'QUOTE:' + quote.Id
        )
      );
    }

    validate(facts);
    return facts;
  }

  /**
   * Validates identity, order, type, and the one-value rule for fact drafts.
   *
   * @param facts Fact records returned by core, Apex, or Flow composition.
   */
  public static void validate(List<Quote_Document_Fact__c> facts) {
    validateAll(facts, true);
  }

  /**
   * Validates Facts that core has already persisted.
   *
   * @param facts Persisted Fact records loaded for neutral projection.
   */
  public static void validatePersisted(List<Quote_Document_Fact__c> facts) {
    validateAll(facts, false);
  }

  private static void validateAll(
    List<Quote_Document_Fact__c> facts,
    Boolean requireUnsaved
  ) {
    Set<String> codes = new Set<String>();
    Set<Decimal> orders = new Set<Decimal>();

    for (
      Quote_Document_Fact__c fact : (facts == null
        ? new List<Quote_Document_Fact__c>()
        : facts)
    ) {
      if (requireUnsaved && fact.Id != null) {
        fail(
          'FACT_ALREADY_PERSISTED',
          fact,
          'A contributor returned a Fact that is already saved.'
        );
      }
      if (String.isBlank(fact.Fact_Code__c) || !codes.add(fact.Fact_Code__c)) {
        fail(
          'FACT_CODE_INVALID',
          fact,
          'Fact codes must be nonblank and unique in one document.'
        );
      }
      if (fact.Display_Order__c == null || !orders.add(fact.Display_Order__c)) {
        fail(
          'FACT_ORDER_INVALID',
          fact,
          'Fact display orders must be present and unique.'
        );
      }
      if (String.isBlank(fact.Display_Label__c)) {
        fail(
          'FACT_LABEL_MISSING',
          fact,
          'Every Fact must carry the customer-facing label resolved during generation.'
        );
      }
      if (String.isBlank(fact.Source_Identity__c)) {
        fail(
          'FACT_SOURCE_MISSING',
          fact,
          'Every Fact must identify the approved source that supplied its value.'
        );
      }
      if (!SUPPORTED_TYPES.contains(fact.Data_Type__c)) {
        fail(
          'FACT_TYPE_UNSUPPORTED',
          fact,
          'Data Type is not supported: ' + fact.Data_Type__c + '.'
        );
      }
      if (valueCount(fact) != 1 || valueFor(fact) == null) {
        fail(
          'FACT_VALUE_INVALID',
          fact,
          'Exactly one typed value must be populated and it must agree with Data Type.'
        );
      }
      if (
        'Currency'.equals(fact.Data_Type__c) &&
        String.isBlank(fact.Currency_Code__c)
      ) {
        fail(
          'FACT_CURRENCY_MISSING',
          fact,
          'A Currency Fact must carry its ISO currency code.'
        );
      }
    }
  }

  /**
   * Returns the typed value selected by Data Type.
   *
   * @param fact Persisted or draft fact.
   * @return The raw typed value, or null for an unsupported or empty fact.
   */
  public static Object valueFor(Quote_Document_Fact__c fact) {
    if (fact == null) {
      return null;
    }
    switch on fact.Data_Type__c {
      when 'Text', 'Address' {
        return fact.Text_Value__c;
      }
      when 'Number' {
        return fact.Number_Value__c;
      }
      when 'Currency' {
        return fact.Currency_Value__c;
      }
      when 'Date' {
        return fact.Date_Value__c;
      }
      when 'DateTime' {
        return fact.Datetime_Value__c;
      }
      when 'Boolean' {
        return fact.Boolean_Value__c;
      }
      when else {
        return null;
      }
    }
  }

  private static Quote_Document_Fact__c textFact(
    Id quoteId,
    String code,
    String label,
    Decimal order,
    String value,
    String sourceIdentity
  ) {
    return new Quote_Document_Fact__c(
      Quote__c = quoteId,
      Fact_Code__c = code,
      Display_Label__c = label,
      Display_Order__c = order,
      Data_Type__c = 'Text',
      Text_Value__c = value,
      Source_Identity__c = sourceIdentity
    );
  }

  private static String addressOf(SObject account) {
    List<String> lines = new List<String>();
    addIfPresent(lines, (String) account.get('BillingStreet'));

    List<String> cityLine = new List<String>();
    addIfPresent(cityLine, (String) account.get('BillingCity'));
    addIfPresent(cityLine, (String) account.get('BillingState'));
    addIfPresent(cityLine, (String) account.get('BillingPostalCode'));
    if (!cityLine.isEmpty()) {
      lines.add(String.join(cityLine, ' '));
    }
    addIfPresent(lines, (String) account.get('BillingCountry'));
    return String.join(lines, '\n');
  }

  private static void addIfPresent(List<String> values, String value) {
    if (String.isNotBlank(value)) {
      values.add(value.trim());
    }
  }

  private static Integer valueCount(Quote_Document_Fact__c fact) {
    Integer count = 0;
    count += fact.Text_Value__c == null ? 0 : 1;
    count += fact.Number_Value__c == null ? 0 : 1;
    count += fact.Currency_Value__c == null ? 0 : 1;
    count += fact.Date_Value__c == null ? 0 : 1;
    count += fact.Datetime_Value__c == null ? 0 : 1;
    // Salesforce checkbox fields always have a value. This field defaults to
    // false even on a Text, Date, or Currency Fact, so counting every false as
    // a populated second value would reject every non-Boolean Fact. Count the
    // checkbox when Boolean is the declared type, or when a true value makes
    // it an unmistakably populated value on another type.
    count += 'Boolean'.equals(fact.Data_Type__c) ||
      fact.Boolean_Value__c == true
      ? 1
      : 0;
    return count;
  }

  private static void fail(
    String code,
    Quote_Document_Fact__c fact,
    String detail
  ) {
    throw QuoteDocumentContributorError.build(
      code,
      'Fact ' + (fact == null ? '(null)' : fact.Fact_Code__c) + ': ' + detail
    );
  }
}
