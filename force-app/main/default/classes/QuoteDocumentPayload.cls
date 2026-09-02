/**
 * The whole document, as typed, already-resolved data.
 *
 * Plain classes with public fields and no behaviour. Deliberately: the moment
 * a DTO grows a method, someone puts a decision in it, and the decision stops
 * being visible in the snapshot the customer's document was built from.
 *
 * WHAT IS NOT HERE, AND WHY
 * -------------------------
 * No formatted strings. Money arrives as Decimal and dates as Date, with
 * `locale` and `currencyIsoCode` alongside, because formatting is a renderer's
 * job and a pre-formatted "$1,234.00" is a decision this layer has no business
 * making on behalf of every renderer at once.
 *
 * No vendor vocabulary. Not a field name, not a comment, not a code. The
 * contract is only vendor-neutral if this file could be read by someone who
 * has never heard of the tool that renders it - and there is a test that
 * greps for exactly that.
 *
 * No behaviour that could drift from the records. Every value here was read
 * from a persisted row; nothing is computed, defaulted, translated or
 * constructed on the way through.
 */
public class QuoteDocumentPayload {
  /**
   * Bumped only when the SHAPE of this payload changes incompatibly.
   * Adapters deploy separately from core and may lag, so an adapter can
   * assert what it was built against instead of failing on a field it does
   * not recognise.
   */
  public static final String CONTRACT_VERSION = '2.0';

  public String contractVersion = CONTRACT_VERSION;
  public String requestId;
  public Id quoteId;
  public String quoteNumber;
  public String documentType;
  public Integer revision;
  public String priorDocumentReference;
  public String locale;
  public String currencyIsoCode;
  public Datetime generatedOn;
  public String fingerprint;
  public String contentVersion;
  public String status;
  public List<Fact> facts = new List<Fact>();

  /**
   * Tables and blocks interleaved in ONE ordering sequence. A renderer walks
   * this list and prints; it never decides what appears, in what order, or
   * whether a section belongs.
   */
  public List<Section> sections = new List<Section>();

  public class Section {
    /**
     * Which partition of its definition this section is - the scenario,
     * entity or department it covers - or null on an ordinary table.
     *
     * Carried as its own field rather than left inside the table key
     * because a composite key is an identity, not an API: a renderer
     * filtering to one entity's document should not have to parse one.
     */
    public String partitionValue;

    /**
     * Whether a total across the partitions of this section's definition
     * means anything: NONE or SUM, and null when it is not partitioned.
     * A renderer must not invent a spanning total where this says NONE.
     */
    public String crossPartitionTotal;
    /** 'Table' or 'Block'. A renderer switches styling on this, nothing more. */
    public String sectionType;
    public String key;
    public String code;
    public Decimal displayOrder;
    public String locale;
    public String currencyIsoCode;
    public String sourceVersion;
    public String sourceIdentity;
    public String approvalIdentity;
    public String relatedSectionKey;
    public String relatedRowKey;
    public String placement;

    // Table
    public String title;
    public String subtitle;
    public String introText;
    public String footerText;
    public List<Column> columns;
    public List<Row> rows;

    // Block
    public String heading;
    public String body;
    public String blockType;
  }

  public class Column {
    public String code;
    public String label;
    public Decimal displayOrder;

    /** How to format this column, so a renderer never inspects a value to guess. */
    public String dataType;
    public String formatRole;
    public String totalRule;
  }

  public class Row {
    public String key;
    public String rowType;
    public String totalRole;
    public Id sourceLineId;
    public Decimal groupLevel;
    public Decimal displayOrder;
    public String label;

    /**
     * The semantic key the label was resolved from, so styling and tests
     * key off meaning rather than off wording that changes with locale.
     */
    public String labelKey;

    /**
     * Keyed by Column.code, never by field API name. An adapter must never
     * need to know that COL_NET means Amount_Net__c - that indirection is
     * what lets a subscriber bind their own field without any adapter
     * learning about it.
     */
    public Map<String, Object> values = new Map<String, Object>();
    public List<Block> blocks = new List<Block>();
  }

  /** A typed header, party, reference, or date value. */
  public class Fact {
    public String code;
    public String label;
    public Decimal displayOrder;
    public String dataType;
    public Object value;
    public String currencyIsoCode;
    public String sourceIdentity;
  }

  /** Governed wording related to one commercial Row. */
  public class Block {
    public String code;
    public String blockType;
    public String heading;
    public String body;
    public Decimal displayOrder;
    public String locale;
    public String sourceVersion;
    public String sourceIdentity;
    public String approvalIdentity;
    public String placement;
  }

  /**
   * What an administrator gets when they need to look at a snapshot.
   *
   * Deliberately NOT a DocumentPayload and deliberately not convertible into
   * one. If diagnostics returned a payload, the first integration under
   * deadline would call the diagnostic instead of the launch contract, and
   * every guarantee that depends on binding to a request Id and fingerprint
   * would quietly stop holding.
   */
  public class SnapshotDescription {
    public Id quoteId;
    public String status;
    public String requestId;
    public String fingerprint;
    public String payloadHash;
    public String locale;
    public Integer tableCount;
    public Integer rowCount;
    public Integer columnCount;
    public Integer blockCount;
    public Integer factCount;
    public Datetime generatedOn;
  }

  /** One quote's retrieval, with its own expectations. There is no expectation-free form. */
  public class PayloadRequest {
    public Id quoteId;
    public String expectedRequestId;
    public String expectedFingerprint;

    public PayloadRequest() {
    }

    public PayloadRequest(
      Id quoteId,
      String expectedRequestId,
      String expectedFingerprint
    ) {
      this.quoteId = quoteId;
      this.expectedRequestId = expectedRequestId;
      this.expectedFingerprint = expectedFingerprint;
    }
  }

  /**
   * Per-request outcome, so one failure never degrades the rest of a batch
   * and a partial batch can never be mistaken for a whole one.
   */
  public class PayloadResult {
    public Id quoteId;
    public Boolean success;
    public QuoteDocumentPayload payload;
    public String errorCode;
    public String errorMessage;
  }
}
