/**
 * The expansion stage: one quote line in, several stamped lines out, with its
 * money divided among them and its quantity divided or repeated.
 *
 * Runs between QuoteDocumentGenerator's line query and QuoteDocumentRowBuilder,
 * so everything after it - grouping, subtotals, ordering, labels, verification -
 * is code that already existed and did not change. The expanded lines are
 * ordinary QuoteDocumentLine instances carrying an expansionKey, which the
 * EXPANSION grouping dimension reads like any other.
 *
 * WHAT THIS OWNS AND WHAT IT DOES NOT
 * -----------------------------------
 * It owns: asking the expander for the axis and the placements, dividing every
 * measure, and proving the division adds back up. It does not own how the axis
 * is derived or which buckets a line belongs to - that is the expander's, and
 * the reason the two are separate classes is that the arithmetic here is
 * identical for months, milestones, departments and deliveries.
 *
 * ALLOCATE VERSUS REPEAT
 * ----------------------
 * Money divides; licences do not. A $1,200 subscription is $100 of value in
 * each of twelve months, but a customer with 100 licences has 100 in every one
 * of those months, not 8.33. Whether a quantity divides is the expander's
 * declaration (dividesQuantity), because only the dimension knows: deliveries
 * genuinely split 1,000 devices into 200/300/500, and months do not.
 *
 * A repeated measure is NOT additive across buckets, so it is declared to
 * verification through QuoteDocumentRowCustomizerContext.nonAdditiveMeasures
 * and checked under the sum-within-group, max-across-groups rule instead.
 *
 * See docs/quote-document-extension-recipes.md.
 */
public with sharing class QuoteDocumentExpansion {
  public static final String ERR_AXIS = 'EXPANSION_AXIS_UNRESOLVED';
  public static final String ERR_TOO_MANY = 'EXPANSION_TOO_MANY_BUCKETS';
  public static final String ERR_NO_PLACEMENT = 'EXPANSION_LINE_OUTSIDE_AXIS';
  public static final String ERR_UNKNOWN_BUCKET = 'EXPANSION_BUCKET_UNKNOWN';

  /**
   * An axis this long is a data error, not a document. Mirrors the ceiling
   * QuoteDocumentMonthlyRowCustomizer already applies to months, for the same
   * reason: a table with hundreds of sections is unreadable either way, and
   * lines x buckets is what actually blows a governor limit.
   */
  public static final Integer MAX_BUCKETS = 120;

  /** Everything an expander is allowed to see. A narrow surface on purpose. */
  public class Request {
    public SBQQ__Quote__c quote;
    public QuoteDocumentTableDefinition definition;
    public List<QuoteDocumentLine> lines;
    public QuoteDocumentLabels labels;

    public Request(
      SBQQ__Quote__c quote,
      QuoteDocumentTableDefinition definition,
      List<QuoteDocumentLine> lines,
      QuoteDocumentLabels labels
    ) {
      this.quote = quote;
      this.definition = definition;
      this.lines = lines;
      this.labels = labels;
    }
  }

  /**
   * One section of the axis. The key is identity, the label is what prints,
   * and the order is what stops bucket 10 sorting before bucket 2.
   */
  public class Bucket {
    public String key;
    public String label;
    public String labelKey;
    public String labelArg1;
    public Integer order;

    public Bucket(String key, String label, Integer order) {
      this.key = key;
      this.label = label;
      this.order = order;
    }
  }

  /**
   * One line's presence in one bucket, and its share of that line.
   *
   * quantityWeight is optional and exists for one case: a bucket whose share
   * of the money is not its share of the units. A usage tier is exactly that
   * - the top band can hold half the units and a tenth of the money - and
   * dividing the units by the money weights printed a unit count that
   * contradicted the band heading next to it. Leave it null and the quantity
   * follows the money, which is right for every other axis.
   */
  public class Placement {
    public String bucketKey;
    public Decimal weight;
    public Decimal quantityWeight;

    public Placement(String bucketKey, Decimal weight) {
      this.bucketKey = bucketKey;
      this.weight = weight;
    }

    public Placement(String bucketKey, Decimal weight, Decimal quantityWeight) {
      this(bucketKey, weight);
      this.quantityWeight = quantityWeight;
    }
  }

  /** What the generator gets back: the new line list, and what it must tell verification. */
  public class Result {
    public List<QuoteDocumentLine> lines = new List<QuoteDocumentLine>();
    public Set<String> nonAdditiveMeasures = new Set<String>();
    public List<Bucket> buckets = new List<Bucket>();
  }

  /**
   * Expands every line, allocating as it goes.
   *
   * Lines that do not count toward this table's totals (a bundled component,
   * whose price is already inside the package price) are expanded for display
   * but are never asked to reconcile - there is no money of their own to
   * divide.
   */
  public static Result apply(
    QuoteDocumentLineExpander expander,
    SBQQ__Quote__c quote,
    QuoteDocumentTableDefinition definition,
    List<QuoteDocumentLine> lines,
    QuoteDocumentLabels labels
  ) {
    Request request = new Request(quote, definition, lines, labels);
    Result result = new Result();

    List<Bucket> buckets = expander.buckets(request);
    if (buckets == null || buckets.isEmpty()) {
      QuoteDocumentContributorError.fail(
        ERR_AXIS,
        'Table ' +
          definition.tableCode +
          ' declares expander ' +
          definition.expanderCode +
          ', which resolved no buckets at all. An expansion with no axis has nothing to divide ' +
          'the quote into; a guessed axis would be worse.'
      );
    }
    if (buckets.size() > MAX_BUCKETS) {
      QuoteDocumentContributorError.fail(
        ERR_TOO_MANY,
        'Table ' +
          definition.tableCode +
          ' resolved ' +
          buckets.size() +
          ' buckets, beyond the ' +
          MAX_BUCKETS +
          ' ceiling. A document with that many sections is unreadable, and the ' +
          'row count is what exhausts the transaction.'
      );
    }
    result.buckets = buckets;

    Map<String, Bucket> byKey = new Map<String, Bucket>();
    for (Bucket bucket : buckets) {
      byKey.put(bucket.key, bucket);
    }

    List<String> measures = QuoteDocumentTableDefinition.measureFields(
      definition.measureSet
    );
    Boolean quantityRepeats = !expander.dividesQuantity();
    if (quantityRepeats) {
      for (String measure : measures) {
        if ('Quantity__c'.equals(measure)) {
          result.nonAdditiveMeasures.add(measure);
        }
      }
    }

    Integer scale = definition.allocationScale == null
      ? 2
      : definition.allocationScale;

    for (QuoteDocumentLine line : lines) {
      List<Placement> placements = expander.placements(line, request);

      if (placements == null || placements.isEmpty()) {
        QuoteDocumentContributorError.fail(
          ERR_NO_PLACEMENT,
          'Line "' +
            line.productName +
            '" was placed in no bucket of table ' +
            definition.tableCode +
            '. Its amount would vanish from a table that still ' +
            'claimed to reconcile, so this fails rather than dropping the line. Correct the ' +
            'line, or filter it off this table deliberately.'
        );
      }

      List<Decimal> weights = new List<Decimal>();
      List<Decimal> quantityWeights = new List<Decimal>();
      Boolean quantityHasOwnWeights = false;
      for (Placement placement : placements) {
        if (!byKey.containsKey(placement.bucketKey)) {
          QuoteDocumentContributorError.fail(
            ERR_UNKNOWN_BUCKET,
            'Line "' +
              line.productName +
              '" was placed in bucket "' +
              placement.bucketKey +
              '", which is not on the axis this expander published. A row in a section the ' +
              'document does not print is a row nobody would ever see.'
          );
        }
        weights.add(placement.weight);
        quantityHasOwnWeights =
          quantityHasOwnWeights || placement.quantityWeight != null;
        quantityWeights.add(
          placement.quantityWeight == null ? 0 : placement.quantityWeight
        );
      }

      // Every allocated measure uses the SAME weights. Allocating the net
      // amount but not the list amount produces a table whose discount
      // percentage is nonsense, and a discount column is on most of these.
      Map<String, List<Decimal>> sharesByMeasure = new Map<String, List<Decimal>>();
      for (String measure : measures) {
        Decimal value = line.measureValue(measure);
        Boolean repeats = quantityRepeats && 'Quantity__c'.equals(measure);

        if (repeats) {
          List<Decimal> repeated = new List<Decimal>();
          for (Integer i = 0; i < placements.size(); i++) {
            repeated.add(value);
          }
          sharesByMeasure.put(measure, repeated);
          continue;
        }

        Boolean isQuantity = 'Quantity__c'.equals(measure);
        Integer measureScale = isQuantity ? 0 : scale;
        List<Decimal> shares = QuoteDocumentAllocation.split(
          value,
          isQuantity && quantityHasOwnWeights ? quantityWeights : weights,
          measureScale
        );

        // The check QuoteDocumentVerification structurally cannot make -
        // it reconciles the TABLE, with a cent of tolerance, and cannot
        // see that one line's money landed in another line's buckets.
        if (line.countsIn(definition.lineFilter)) {
          QuoteDocumentAllocation.reconcile(
            value,
            shares,
            'Line "' + line.productName + '" measure ' + measure
          );
        }
        sharesByMeasure.put(measure, shares);
      }

      for (Integer i = 0; i < placements.size(); i++) {
        Bucket bucket = byKey.get(placements[i].bucketKey);
        QuoteDocumentLine expanded = line.copyInto(
          bucket.key,
          bucket.label,
          bucket.order
        );
        for (String measure : measures) {
          expanded.setMeasure(measure, sharesByMeasure.get(measure)[i]);
        }
        result.lines.add(expanded);
      }
    }

    return result;
  }
}
