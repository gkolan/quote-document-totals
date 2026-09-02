/**
 * Explains a usage-priced line as the pricing tiers behind it.
 *
 * A quote prices 25,000 units through graduated tiers - the first 10,000 at one
 * rate, the rest at another. The single line says 25,000 and a total. This
 * expands it into one row per tier, each carrying that tier's band, its rate,
 * and its share of the money.
 *
 * IT CONSUMES CPQ'S OWN TIERS. IT NEVER RECOMPUTES THEM.
 * -----------------------------------------------------
 * The bands and rates come from SBQQ__QuoteLineConsumptionSchedule__c and its
 * SBQQ__QuoteLineConsumptionRate__c children - the records CPQ's own pricing
 * engine wrote when it priced the line. Re-deriving them here would eventually
 * disagree with the price the customer was quoted, and the document would be
 * the thing that was wrong.
 *
 * That principle has a consequence worth stating: the tier ROWS are an
 * explanation of an amount, not a recalculation of it. The shares are allocated
 * from the line's own quoted total using the tiers as WEIGHTS, so they sum back
 * to what the customer pays even where CPQ applied a discount, a rounding rule
 * or a manual override that this class has no knowledge of. A tier breakdown
 * that footed to a recomputed price rather than the quoted one would be a
 * second opinion about the deal.
 *
 * WEIGHTS ARE BAND WIDTH x RATE
 * -----------------------------
 * The natural relative worth of a tier: how many units fall in it, multiplied
 * by what they cost there. The last occupied band is truncated at the line's
 * actual quantity - a tier priced "10,001 and above" contributes the units the
 * customer actually bought, not an unbounded number.
 *
 * A LINE WITH NO SCHEDULE FAILS
 * -----------------------------
 * It does not fall back to a single row at the full amount. A table that
 * silently mixes tier-explained lines with unexplained ones invites a reader to
 * assume the unexplained ones have one tier, which is a claim about pricing
 * nobody made.
 *
 * See docs/quote-document-extension-recipes.md.
 */
public with sharing class QuoteDocumentTierExpander implements QuoteDocumentLineExpander {
  public static final String CODE = 'CONSUMPTION_TIER';

  public static final String ERR_NO_SCHEDULE = 'TIER_SCHEDULE_MISSING';
  public static final String ERR_NO_RATES = 'TIER_RATES_MISSING';
  public static final String ERR_UNPRICED = 'TIER_BANDS_UNPRICED';

  /** One tier of one line: the band, the rate, and how much of the line falls in it. */
  public class Tier {
    public Id quoteLineId;
    public String bucketCode;
    public Decimal lowerBound;
    public Decimal upperBound;
    public Decimal price;
    public Decimal unitsInBand;
    public Integer displayOrder;

    public Tier(
      Id quoteLineId,
      String bucketCode,
      Decimal lowerBound,
      Decimal upperBound,
      Decimal price,
      Integer displayOrder
    ) {
      this.quoteLineId = quoteLineId;
      this.bucketCode = bucketCode;
      this.lowerBound = lowerBound;
      this.upperBound = upperBound;
      this.price = price;
      this.displayOrder = displayOrder;
    }

    public Decimal weight() {
      Decimal units = unitsInBand == null ? 0 : unitsInBand;
      Decimal rate = price == null ? 0 : price;
      return units * rate;
    }
  }

  @TestVisible
  private static Map<Id, List<Tier>> overrides;

  @TestVisible
  private static void useTiers(Map<Id, List<Tier>> tiers) {
    overrides = tiers;
  }

  public List<QuoteDocumentExpansion.Bucket> buckets(
    QuoteDocumentExpansion.Request request
  ) {
    Map<String, Integer> orderByCode = new Map<String, Integer>();

    for (QuoteDocumentLine line : request.lines) {
      for (Tier tier : tiersFor(line, request)) {
        Integer order = tier.displayOrder == null ? 0 : tier.displayOrder;
        if (
          !orderByCode.containsKey(tier.bucketCode) ||
          order < orderByCode.get(tier.bucketCode)
        ) {
          orderByCode.put(tier.bucketCode, order);
        }
      }
    }

    List<String> codes = new List<String>(orderByCode.keySet());
    codes.sort();

    List<QuoteDocumentExpansion.Bucket> buckets = new List<QuoteDocumentExpansion.Bucket>();
    for (String code : codes) {
      // The band is the heading, and it is data - "10,001 - 25,000" comes
      // from the rate records CPQ wrote, not from a phrase composed here.
      buckets.add(
        new QuoteDocumentExpansion.Bucket(code, code, orderByCode.get(code))
      );
    }
    return buckets;
  }

  public List<QuoteDocumentExpansion.Placement> placements(
    QuoteDocumentLine line,
    QuoteDocumentExpansion.Request request
  ) {
    List<Tier> tiers = tiersFor(line, request);

    Decimal total = 0;
    for (Tier tier : tiers) {
      total += tier.weight();
    }
    if (total == 0) {
      QuoteDocumentContributorError.fail(
        ERR_UNPRICED,
        'Line "' +
          line.productName +
          '" has consumption tiers whose bands and rates multiply out ' +
          'to nothing, so there is no basis on which to divide its amount. Either every rate ' +
          'is zero, or the quantity falls below the first band.'
      );
    }

    List<QuoteDocumentExpansion.Placement> placements = new List<QuoteDocumentExpansion.Placement>();
    for (Tier tier : tiers) {
      // Money follows units x rate; units follow units. Dividing the
      // quantity by the money weights put 90 of 1,500 units in a band
      // whose own heading said it held 500 - the one number on the row a
      // reader checks against the band beside it.
      placements.add(
        new QuoteDocumentExpansion.Placement(
          tier.bucketCode,
          tier.weight(),
          tier.unitsInBand == null ? 0 : tier.unitsInBand
        )
      );
    }
    return placements;
  }

  /**
   * Units in a band are genuinely different units from the units in the next
   * one, so a quantity divides here.
   */
  public Boolean dividesQuantity() {
    return true;
  }

  // -----------------------------------------------------------------------

  private static Map<Id, List<Tier>> cached;

  private static List<Tier> tiersFor(
    QuoteDocumentLine line,
    QuoteDocumentExpansion.Request request
  ) {
    Map<Id, List<Tier>> byLine = overrides == null
      ? fromCpq(request)
      : overrides;

    List<Tier> tiers = byLine.get(line.quoteLineId);
    if (tiers == null || tiers.isEmpty()) {
      QuoteDocumentContributorError.fail(
        ERR_NO_SCHEDULE,
        'Line "' +
          line.productName +
          '" has no consumption schedule, so its tiers cannot be ' +
          'explained. This fails rather than printing it as a single unexplained row: a table ' +
          'that mixes explained and unexplained lines invites a reader to assume the ' +
          'unexplained ones have one tier, which is a claim about pricing nobody made.'
      );
    }
    return withUnitsAllocated(tiers, line);
  }

  /**
   * How many units of this line fall in each band, with the last occupied
   * band truncated at the line's actual quantity.
   *
   * A tier priced "10,001 and above" has no upper bound in the data; it
   * contributes the units the customer actually bought, not an unbounded
   * number, or one open-ended tier would swamp every weight.
   */
  private static List<Tier> withUnitsAllocated(
    List<Tier> tiers,
    QuoteDocumentLine line
  ) {
    Decimal quantity = line.quantity == null ? 0 : line.quantity;
    List<Tier> occupied = new List<Tier>();

    for (Tier tier : tiers) {
      Decimal lower = tier.lowerBound == null ? 1 : tier.lowerBound;
      if (quantity < lower) {
        // The customer never reached this band. Omitted rather than
        // printed at zero: a tier nobody bought into is not part of
        // this deal's explanation.
        continue;
      }
      Decimal upper = tier.upperBound == null ? quantity : tier.upperBound;
      if (upper > quantity) {
        upper = quantity;
      }
      tier.unitsInBand = upper - lower + 1;
      occupied.add(tier);
    }

    if (occupied.isEmpty()) {
      QuoteDocumentContributorError.fail(
        ERR_NO_RATES,
        'Line "' +
          line.productName +
          '" has a quantity of ' +
          quantity +
          ', which falls into none ' +
          'of its consumption bands. The tiers and the quantity disagree, and printing either ' +
          'one alone would hide that.'
      );
    }
    return occupied;
  }

  /**
   * The tiers CPQ's own pricing engine recorded, read once per transaction.
   *
   * Queried here rather than through QuoteDocumentQuery because this is a
   * contributor read: it belongs to the one table that asks for it, and a
   * definition using this expander declares it through Cache_Policy__c like
   * any other external dependency.
   */
  private static Map<Id, List<Tier>> fromCpq(
    QuoteDocumentExpansion.Request request
  ) {
    if (cached != null) {
      return cached;
    }
    cached = new Map<Id, List<Tier>>();

    Set<Id> lineIds = new Set<Id>();
    for (QuoteDocumentLine line : request.lines) {
      lineIds.add(line.quoteLineId);
    }

    Map<Id, Id> lineByScheduleId = new Map<Id, Id>();
    for (SBQQ__QuoteLineConsumptionSchedule__c schedule : [
      SELECT Id, SBQQ__QuoteLine__c
      FROM SBQQ__QuoteLineConsumptionSchedule__c
      WHERE SBQQ__QuoteLine__c IN :lineIds
      WITH USER_MODE
    ]) {
      lineByScheduleId.put(schedule.Id, schedule.SBQQ__QuoteLine__c);
    }

    for (SBQQ__QuoteLineConsumptionRate__c rate : [
      SELECT
        SBQQ__QuoteLineConsumptionSchedule__c,
        SBQQ__LowerBound__c,
        SBQQ__UpperBound__c,
        SBQQ__Price__c,
        SBQQ__ProcessingOrder__c
      FROM SBQQ__QuoteLineConsumptionRate__c
      WHERE SBQQ__QuoteLineConsumptionSchedule__c IN :lineByScheduleId.keySet()
      WITH USER_MODE
      ORDER BY SBQQ__ProcessingOrder__c, SBQQ__LowerBound__c
    ]) {
      Id lineId = lineByScheduleId.get(
        rate.SBQQ__QuoteLineConsumptionSchedule__c
      );
      if (!cached.containsKey(lineId)) {
        cached.put(lineId, new List<Tier>());
      }
      Integer order = rate.SBQQ__ProcessingOrder__c == null
        ? cached.get(lineId).size() + 1
        : Integer.valueOf(rate.SBQQ__ProcessingOrder__c);

      cached.get(lineId)
        .add(
          new Tier(
            lineId,
            bandLabel(rate.SBQQ__LowerBound__c, rate.SBQQ__UpperBound__c),
            rate.SBQQ__LowerBound__c,
            rate.SBQQ__UpperBound__c,
            rate.SBQQ__Price__c,
            order
          )
        );
    }
    return cached;
  }

  /**
   * The band, as the customer's own pricing states it. Numbers and a
   * separator - no word this framework chose, so nothing here needs
   * translating.
   */
  @TestVisible
  private static String bandLabel(Decimal lowerBound, Decimal upperBound) {
    Decimal lower = lowerBound == null ? 1 : lowerBound;
    String prefix = String.valueOf(lower.setScale(0));
    return upperBound == null
      ? prefix + '+'
      : prefix + '-' + String.valueOf(upperBound.setScale(0));
  }
}
