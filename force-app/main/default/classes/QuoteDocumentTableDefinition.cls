/**
 * What tables to generate, and how each one differs.
 *
 * Every table comes out of the same generator. A definition changes only three
 * things: which lines it starts from (the filter), how those lines are grouped,
 * and which family of measures it fills in.
 *
 * GROUPING SHAPE
 * --------------
 * Grouping is a list of LEVELS, outermost first. Each level is a list of PARTS.
 *
 *   Different Level  -> nesting.   Phase 1 > Hardware > detail rows
 *   Same Level       -> composite. One "Hardware / Recurring" bucket
 *
 * A part is either a named dimension the generator computes (BUNDLE and
 * TRANSACTION_TYPE have no single field behind them) or a field path read
 * straight off the quote line, which is how a new grouping ships without Apex.
 *
 * Definitions live in Custom Metadata. The generator only ever sees this
 * object, so the storage could change again without touching generation logic.
 */
public with sharing class QuoteDocumentTableDefinition {
  // Named dimensions. QuoteDocumentLine.namedValue resolves each one.
  public static final String DIM_PRODUCT_FAMILY = 'PRODUCT_FAMILY';
  public static final String DIM_CHARGE_TYPE = 'CHARGE_TYPE';
  public static final String DIM_QUOTE_LINE_GROUP = 'QUOTE_LINE_GROUP';
  public static final String DIM_BUNDLE = 'BUNDLE';
  public static final String DIM_TRANSACTION_TYPE = 'TRANSACTION_TYPE';
  public static final String DIM_INDUSTRY = 'INDUSTRY';

  /**
   * The bucket an expander put a line in. Unlike every dimension above it is
   * not read off the line's own data - it is stamped on during expansion -
   * but it is an ordinary grouping dimension everywhere else, which is the
   * whole point: "year then family" and "family then year" are both a
   * metadata change rather than a second class.
   */
  public static final String DIM_EXPANSION = 'EXPANSION';

  // Line filters. QuoteDocumentLine.matchesFilter applies each one.
  public static final String FILTER_ALL = 'ALL';
  public static final String FILTER_EXCLUDE_OPTIONAL = 'EXCLUDE_OPTIONAL';
  public static final String FILTER_OPTIONAL_ONLY = 'OPTIONAL_ONLY';
  public static final String FILTER_RECURRING_ONLY = 'RECURRING_ONLY';
  public static final String FILTER_ONE_TIME_ONLY = 'ONE_TIME_ONLY';
  public static final String FILTER_BUNDLE_PARENTS_ONLY = 'BUNDLE_PARENTS_ONLY';

  public static final String MEASURES_PRICE_WATERFALL = 'PRICE_WATERFALL';
  public static final String MEASURES_CHANGE = 'CHANGE';

  // How top-level groups are ordered. ALPHABETICAL (the default) sorts by
  // the group's own label; LINE_SEQUENCE sorts by the lowest SBQQ__Number__c
  // among the lines in that group, so whichever bundle was quoted first
  // prints first, regardless of its name.
  public static final String SORT_ALPHABETICAL = 'ALPHABETICAL';
  public static final String SORT_LINE_SEQUENCE = 'LINE_SEQUENCE';

  /**
   * Sorts groups by the expansion bucket's own order. Required on a period
   * table: sorted alphabetically, "Month 10" prints before "Month 2".
   */
  public static final String SORT_EXPANSION_ORDER = 'EXPANSION_ORDER';

  private static final String DEFAULT_SEPARATOR = ' / ';
  private static final Integer DEFAULT_MAX_GROUPS = 50;

  /** One component of a grouping level. */
  public class Part {
    public String dimension; // named and computed, or
    public String fieldPath; // read from the record

    public Boolean isFieldPath() {
      return String.isNotBlank(fieldPath);
    }

    public String describe() {
      return isFieldPath() ? fieldPath : dimension;
    }
  }

  /** One nesting level. More than one part means a composite bucket. */
  public class Level {
    public List<Part> parts = new List<Part>();

    public Boolean isComposite() {
      return parts.size() > 1;
    }

    public String describe() {
      List<String> names = new List<String>();
      for (Part part : parts) {
        names.add(part.describe());
      }
      return String.join(names, ' + ');
    }
  }

  public String tableCode;
  public String tableName;
  public String amountBasis;
  public List<Level> groupBy;
  public String lineFilter;
  public String measureSet;
  public String compositeSeparator;
  public Integer maxGroups;
  public Boolean showDetails;
  public Boolean showSectionTotals;
  public Integer displayOrder;
  public String sortGroupsBy;

  // Kept for the versioned Custom Object template configuration. These
  // describe how often a template table may appear and what to do when it has
  // no rows; the current Custom Metadata generator does not need them.
  public String cardinality;
  public String emptyBehavior;

  /** Registry code for QuoteDocumentRowCustomizerRegistry.resolve(), or blank if this table uses only declarative config. */
  public String rowCustomizerCode;

  /**
   * Content-identity tokens for the two contributors. Not documentation:
   * QuoteDocumentGenerator.canReuse returns BEFORE customization runs, and
   * the fingerprint hashes the customizer code - the string, not the
   * behaviour behind it. Deploying changed Apex or editing a Flow leaves
   * both unchanged, so without these the fingerprint matches, the quote
   * stays Ready, and generation reuses a snapshot the new logic would never
   * have produced. See step 01A section 6.
   */
  public String rowCustomizerVersion;
  public String rowCustomizerFlow;
  public String rowCustomizerFlowVersion;

  /**
   * Printable presentation, snapshotted onto every generated table.
   *
   * displayTitle is NOT tableName. tableName is the admin-facing name that
   * makes a metadata record findable; the title is what a customer reads.
   * Conflating them is how a document ends up printing an internal label
   * nobody reviewed, so there is deliberately no fallback between them.
   */
  public String displayTitle;
  public String displaySubtitle;
  public String introText;
  public String footerText;

  // What the contributor reads beyond the quote and its lines. See step 01A section 6a.
  /**
   * The baseline this table compares against, if it compares at all. Blank
   * is every table that existed before comparison did.
   */
  /**
   * Splits this definition into separate tables, one per distinct value.
   *
   * Not a grouping level. Grouping nests rows inside ONE table under one
   * grand total; partitioning produces several tables, each reconciling
   * against its own share, with nothing spanning them unless the author says
   * a spanning total is meaningful.
   */
  /**
   * A narrative block this table cannot be published without. See
   * QuoteDocumentGenerator.assertAssumptionsPresent - an estimate printed
   * without its assumptions is a number a reader will act on and a caveat
   * nobody attached.
   */
  public String assumptionsBlockCode;

  public String partitionDimension;
  public String crossPartitionTotal;

  public Boolean isPartitioned() {
    return String.isNotBlank(partitionDimension);
  }

  public String comparisonSourceCode;
  public String comparisonSourceVersion;
  public String comparisonSourceField;

  public Boolean hasComparison() {
    return String.isNotBlank(comparisonSourceCode);
  }

  /**
   * The quote field this table's baseline is reached through.
   *
   * Each comparison source has its own natural one - a revision link for a
   * quote-to-quote comparison, the Account for an amendment against live
   * subscriptions - and an author can override it. Whichever it is, it goes
   * through allDependencyPaths(), so the field is SELECTed and its VALUE is
   * hashed: re-pointing a quote at a different source or a different account
   * is a different baseline, and nothing else in the fingerprint would see it.
   */
  public String comparisonSourceFieldOrDefault() {
    if (String.isNotBlank(comparisonSourceField)) {
      return comparisonSourceField;
    }
    return QuoteDocumentAmendmentComparison.CODE.equals(comparisonSourceCode)
      ? 'SBQQ__Account__c'
      : QuoteDocumentSourceQuoteComparison.DEFAULT_SOURCE_FIELD;
  }

  public String cachePolicy;
  public List<String> contributorDependencyPaths;

  public static final String ALLOCATION_NONE = 'NONE';
  public static final String ALLOCATION_EVEN = 'EVEN';

  /**
   * Expansion and allocation. Set together or not at all: an expansion that
   * neither allocates nor suppresses amounts would print each line's full
   * value in every bucket it occupies, and the grand total would be wrong by
   * a factor of the bucket count.
   */
  public String expanderCode;
  public String expanderVersion;
  public Integer periodMonths;
  public String periodOneTimePlacement;
  public String scheduleCode;
  public Boolean scheduleDividesQuantity = false;
  public String allocationBasis;
  public Integer allocationScale;
  public Boolean suppressAmounts = false;

  public Boolean hasExpander() {
    return String.isNotBlank(expanderCode);
  }

  public static final String CACHE_STANDARD = 'STANDARD';
  public static final String CACHE_DECLARED_DEPENDENCIES = 'DECLARED_DEPENDENCIES';
  public static final String CACHE_ALWAYS_REBUILD = 'ALWAYS_REBUILD';

  public Boolean hasContributor() {
    return String.isNotBlank(rowCustomizerCode) ||
      String.isNotBlank(rowCustomizerFlow);
  }

  public Boolean alwaysRebuilds() {
    return CACHE_ALWAYS_REBUILD.equals(cachePolicy);
  }

  @TestVisible
  private QuoteDocumentTableDefinition() {
    groupBy = new List<Level>();
    compositeSeparator = DEFAULT_SEPARATOR;
    maxGroups = DEFAULT_MAX_GROUPS;
    sortGroupsBy = SORT_ALPHABETICAL;
    contributorDependencyPaths = new List<String>();
  }

  private QuoteDocumentTableDefinition(
    Quote_Document_Table_Def__mdt record,
    List<Level> levels
  ) {
    tableCode = record.Table_Code__c;
    tableName = record.Table_Name__c;
    amountBasis = record.Amount_Basis__c;
    lineFilter = record.Line_Filter__c;
    measureSet = record.Measure_Set__c;
    showDetails = record.Show_Details__c;
    showSectionTotals = record.Show_Section_Totals__c;
    displayOrder = Integer.valueOf(record.Display_Order__c);
    compositeSeparator = String.isBlank(record.Composite_Separator__c)
      ? DEFAULT_SEPARATOR
      : record.Composite_Separator__c;
    maxGroups = record.Max_Groups__c == null
      ? DEFAULT_MAX_GROUPS
      : Integer.valueOf(record.Max_Groups__c);
    sortGroupsBy = String.isBlank(record.Sort_Groups_By__c)
      ? SORT_ALPHABETICAL
      : record.Sort_Groups_By__c;
    rowCustomizerCode = record.Row_Customizer_Code__c;
    rowCustomizerVersion = record.Row_Customizer_Version__c;
    rowCustomizerFlow = record.Row_Customizer_Flow__c;
    rowCustomizerFlowVersion = record.Row_Customizer_Flow_Version__c;
    displayTitle = record.Display_Title__c;
    displaySubtitle = record.Display_Subtitle__c;
    introText = record.Intro_Text__c;
    footerText = record.Footer_Text__c;
    cachePolicy = record.Cache_Policy__c;
    assumptionsBlockCode = record.Assumptions_Block_Code__c;
    partitionDimension = record.Partition_Dimension__c;
    crossPartitionTotal = record.Cross_Partition_Total__c;
    comparisonSourceCode = record.Comparison_Source_Code__c;
    comparisonSourceVersion = record.Comparison_Source_Version__c;
    comparisonSourceField = record.Comparison_Source_Field__c;
    contributorDependencyPaths = splitPaths(
      record.Contributor_Dependency_Set__c
    );
    expanderCode = record.Expander_Code__c;
    expanderVersion = record.Expander_Version__c;
    periodMonths = record.Period_Months__c == null
      ? null
      : Integer.valueOf(record.Period_Months__c);
    periodOneTimePlacement = record.Period_One_Time_Placement__c;
    scheduleCode = record.Schedule_Code__c;
    scheduleDividesQuantity = record.Schedule_Divides_Quantity__c == true;
    allocationBasis = record.Allocation_Basis__c;
    allocationScale = record.Allocation_Scale__c == null
      ? null
      : Integer.valueOf(record.Allocation_Scale__c);
    suppressAmounts = record.Suppress_Amounts__c == true;
    groupBy = levels;
  }

  /** Comma-separated, blank entries dropped, order preserved so the fingerprint stays deterministic. */
  private static List<String> splitPaths(String raw) {
    List<String> paths = new List<String>();
    if (String.isBlank(raw)) {
      return paths;
    }
    for (String candidate : raw.split(',')) {
      String trimmed = candidate.trim();
      if (String.isNotBlank(trimmed)) {
        paths.add(trimmed);
      }
    }
    return paths;
  }

  /**
   * An active definition must carry its own printable title.
   *
   * Deliberately no fallback to Table_Name__c. A fallback would make every
   * unconfigured table silently print an admin-facing name - the failure
   * would reach a customer's document rather than a deployment log, and it
   * would reach every table at once. spec.md section 4 removes the fallback
   * for exactly this reason.
   *
   * Only ACTIVE definitions are loaded here, so an inactive example record
   * can sit half-configured without blocking anyone.
   */
  @TestVisible
  private void validatePresentationConfig() {
    if (String.isBlank(displayTitle)) {
      throw new QuoteDocumentGenerator.QuoteDocumentException(
        'Active table definition ' +
          tableCode +
          ' has no Display_Title__c. Every active definition ' +
          'must carry the heading its table prints. Table_Name__c is the admin-facing name and is ' +
          'deliberately not used as a fallback - it would print an internal label to a customer.'
      );
    }
  }

  /**
   * Everything a contributor must declare before it is allowed to run.
   *
   * All of it fails at CONFIG LOAD rather than mid-generation, so a
   * half-configured table is caught by the first generation attempt on any
   * quote instead of by the one quote that happens to exercise it. None of
   * these can be enforced declaratively: they are conditional on another
   * field being set, and a Custom Metadata field cannot be conditionally
   * required.
   */
  private void validateContributorConfig() {
    if (!hasContributor()) {
      // No contributor, nothing to declare. A cache policy on a table
      // with no contributor is harmless and deliberately not an error -
      // it is the shape you get mid-edit, and failing on it would punish
      // someone for configuring in the wrong order.
      return;
    }

    if (
      String.isNotBlank(rowCustomizerCode) &&
      String.isBlank(rowCustomizerVersion)
    ) {
      QuoteDocumentContributorError.fail(
        QuoteDocumentContributorError.VERSION_UNDECLARED,
        'Table ' +
          tableCode +
          ' sets Row_Customizer_Code__c "' +
          rowCustomizerCode +
          '" but leaves Row_Customizer_Version__c blank. The version is content identity, not ' +
          'documentation: without it, deploying changed customizer Apex leaves the fingerprint ' +
          'identical and quotes silently reuse a snapshot the new code would not have produced.'
      );
    }

    if (
      String.isNotBlank(rowCustomizerFlow) &&
      String.isBlank(rowCustomizerFlowVersion)
    ) {
      QuoteDocumentContributorError.fail(
        QuoteDocumentContributorError.VERSION_UNDECLARED,
        'Table ' +
          tableCode +
          ' sets Row_Customizer_Flow__c "' +
          rowCustomizerFlow +
          '" but leaves Row_Customizer_Flow_Version__c blank. Editing a Flow does not change its ' +
          'API name, so without this token the fingerprint cannot see the change and quotes ' +
          'reuse a stale snapshot.'
      );
    }

    // Blank must not be readable as STANDARD. "Nobody chose" and "chose
    // the option that declares no external reads" have the same output and
    // completely different reliability, which is exactly why step 01A
    // section 6a specifies a picklist rather than a checkbox.
    if (String.isBlank(cachePolicy)) {
      QuoteDocumentContributorError.fail(
        QuoteDocumentContributorError.DEPENDENCY_UNDECLARED,
        'Table ' +
          tableCode +
          ' has a contributor but no Cache_Policy__c. Choose STANDARD (reads ' +
          'only the quote and its lines), DECLARED_DEPENDENCIES (also reads the field paths in ' +
          'Contributor_Dependency_Set__c), or ALWAYS_REBUILD (reads data it cannot enumerate). ' +
          'There is no default: a contributor that reads external data under an assumed ' +
          'STANDARD produces a confidently wrong document.'
      );
    }

    if (
      CACHE_DECLARED_DEPENDENCIES.equals(cachePolicy) &&
      contributorDependencyPaths.isEmpty()
    ) {
      QuoteDocumentContributorError.fail(
        QuoteDocumentContributorError.DEPENDENCY_UNDECLARED,
        'Table ' +
          tableCode +
          ' declares Cache_Policy__c = DECLARED_DEPENDENCIES but ' +
          'Contributor_Dependency_Set__c is empty. List the field paths the contributor reads ' +
          'beyond the quote and its lines, or choose STANDARD or ALWAYS_REBUILD instead.'
      );
    }

    if (
      !CACHE_DECLARED_DEPENDENCIES.equals(cachePolicy) &&
      !contributorDependencyPaths.isEmpty()
    ) {
      QuoteDocumentContributorError.fail(
        QuoteDocumentContributorError.DEPENDENCY_UNDECLARED,
        'Table ' +
          tableCode +
          ' lists Contributor_Dependency_Set__c paths but its Cache_Policy__c is ' +
          cachePolicy +
          ', under which those paths are never hashed. Either set the policy to ' +
          'DECLARED_DEPENDENCIES so the paths take effect, or clear them - silently ignoring a ' +
          'declared dependency is how a stale document gets shipped.'
      );
    }
  }

  /**
   * Everything an expanded table must declare, checked at CONFIG LOAD rather
   * than mid-generation so a half-configured table fails on the first quote
   * anyone generates instead of the one quote that happens to exercise it.
   */
  @TestVisible
  private void validateExpansionConfig() {
    if (!hasExpander()) {
      if (
        String.isNotBlank(allocationBasis) &&
        !ALLOCATION_NONE.equals(allocationBasis)
      ) {
        throw new QuoteDocumentGenerator.QuoteDocumentException(
          'Table ' +
            tableCode +
            ' sets Allocation_Basis__c = ' +
            allocationBasis +
            ' but names no Expander_Code__c. There is nothing to allocate across: allocation ' +
            'divides a line among the buckets an expansion put it in.'
        );
      }
      return;
    }

    if (String.isBlank(expanderVersion)) {
      QuoteDocumentContributorError.fail(
        QuoteDocumentContributorError.VERSION_UNDECLARED,
        'Table ' +
          tableCode +
          ' sets Expander_Code__c "' +
          expanderCode +
          '" but leaves ' +
          'Expander_Version__c blank. The version is content identity, not documentation: ' +
          'without it, deploying changed expander Apex leaves the fingerprint identical and ' +
          'quotes reuse a snapshot the new code would not have produced.'
      );
    }

    // The trap this exists to close: expansion multiplies rows, so without
    // allocation every bucket carries the line's FULL amount and the grand
    // total is wrong by a factor of the bucket count. verify() would catch
    // it, but at generation time on somebody's quote rather than here.
    Boolean allocates =
      String.isNotBlank(allocationBasis) &&
      !ALLOCATION_NONE.equals(allocationBasis);
    if (!allocates && !suppressAmounts) {
      throw new QuoteDocumentGenerator.QuoteDocumentException(
        'Table ' +
          tableCode +
          ' expands its lines with ' +
          expanderCode +
          ' but sets no ' +
          'Allocation_Basis__c. Each line would then print its whole amount in every bucket it ' +
          'occupies, and the total would be wrong by a factor of the bucket count. Set ' +
          'Allocation_Basis__c = EVEN, or tick Suppress_Amounts__c if this table carries no money.'
      );
    }

    if (allocates && !ALLOCATION_EVEN.equals(allocationBasis)) {
      throw new QuoteDocumentGenerator.QuoteDocumentException(
        'Table ' +
          tableCode +
          ' sets Allocation_Basis__c = ' +
          allocationBasis +
          ', which is not a basis this framework implements. EVEN is the one that ships; ' +
          'anything else needs its own weighting source and its own step.'
      );
    }

    // Section totals cut the same lines a SECOND way, by charge type,
    // across every bucket at once. On an expanded table that second cut has
    // no agreed meaning - a repeated quantity summed across periods is the
    // 1,200-licences defect again, and there is no "peak" to take across
    // charge types either. Refused rather than guessed at.
    if (showSectionTotals == true) {
      throw new QuoteDocumentGenerator.QuoteDocumentException(
        'Table ' +
          tableCode +
          ' both expands its lines and shows section totals. A section total ' +
          'cuts across every bucket at once, which has no defined meaning on an expanded table. ' +
          'Turn off Show_Section_Totals__c, or drop the expansion.'
      );
    }

    if (
      QuoteDocumentScheduleExpander.CODE.equals(expanderCode) &&
      String.isBlank(scheduleCode)
    ) {
      throw new QuoteDocumentGenerator.QuoteDocumentException(
        'Table ' +
          tableCode +
          ' uses the SCHEDULE expander but names no Schedule_Code__c. Its ' +
          'sections and their weights are authored in Quote_Document_Schedule__mdt - there is ' +
          'nothing on a quote that says "30% at signing".'
      );
    }

    if (QuoteDocumentPeriodExpander.CODE.equals(expanderCode)) {
      if (periodMonths == null || periodMonths < 1) {
        throw new QuoteDocumentGenerator.QuoteDocumentException(
          'Table ' +
            tableCode +
            ' uses the PERIOD expander but sets no positive ' +
            'Period_Months__c. 1 is monthly, 12 is annual - there is no default, because a ' +
            'schedule at the wrong granularity looks plausible and is wrong throughout.'
        );
      }
      Boolean known =
        String.isBlank(periodOneTimePlacement) ||
        QuoteDocumentPeriodExpander.PLACE_FIRST.equals(
          periodOneTimePlacement
        ) ||
        QuoteDocumentPeriodExpander.PLACE_EFFECTIVE.equals(
          periodOneTimePlacement
        ) ||
        QuoteDocumentPeriodExpander.PLACE_SPREAD.equals(periodOneTimePlacement);
      if (!known) {
        throw new QuoteDocumentGenerator.QuoteDocumentException(
          'Table ' +
            tableCode +
            ' sets Period_One_Time_Placement__c = ' +
            periodOneTimePlacement +
            '. Use FIRST_PERIOD, EFFECTIVE_DATE or SPREAD.'
        );
      }
    }
  }

  /**
   * A comparison must declare its content identity, and must not be combined
   * with an expansion.
   *
   * Comparing and expanding at once would ask what one line's third month
   * looked like on a baseline that may not contain that line at all. There
   * is a defensible answer, but nobody has defined it, and inventing one
   * inside a money table is not the place to start.
   */
  @TestVisible
  private void validateComparisonConfig() {
    if (!hasComparison()) {
      return;
    }

    if (String.isBlank(comparisonSourceVersion)) {
      QuoteDocumentContributorError.fail(
        QuoteDocumentContributorError.VERSION_UNDECLARED,
        'Table ' +
          tableCode +
          ' sets Comparison_Source_Code__c "' +
          comparisonSourceCode +
          '" but leaves Comparison_Source_Version__c blank. Changed matching logic under an ' +
          'unchanged code is invisible to the fingerprint, so quotes would reuse a comparison ' +
          'the new logic would never have produced.'
      );
    }

    if (hasExpander()) {
      throw new QuoteDocumentGenerator.QuoteDocumentException(
        'Table ' +
          tableCode +
          ' both compares against a baseline and expands its lines. What one ' +
          'line third period looked like on a baseline that may not contain that line has no ' +
          'agreed answer. Choose one.'
      );
    }
  }

  public static final String CROSS_PARTITION_NONE = 'NONE';
  public static final String CROSS_PARTITION_SUM = 'SUM';

  /** At most nine, because Display_Order__c is a whole number and definitions are spaced by ten. */
  public static final Integer MAX_PARTITIONS = 9;

  /**
   * A partitioned definition must say whether a total across its partitions
   * means anything.
   *
   * There is deliberately no default. Alternatives and scenarios are
   * mutually exclusive, and summing them states a number the customer is not
   * being asked to pay; departments and entities are complementary, and
   * refusing to sum them hides the deal. Only the author knows which, and
   * making them choose is the whole safeguard.
   */
  @TestVisible
  private void validatePartitionConfig() {
    if (!isPartitioned()) {
      if (String.isNotBlank(crossPartitionTotal)) {
        throw new QuoteDocumentGenerator.QuoteDocumentException(
          'Table ' +
            tableCode +
            ' sets Cross_Partition_Total__c but has no ' +
            'Partition_Dimension__c. There are no partitions for a total to span.'
        );
      }
      return;
    }

    if (String.isBlank(crossPartitionTotal)) {
      throw new QuoteDocumentGenerator.QuoteDocumentException(
        'Table ' +
          tableCode +
          ' is partitioned but does not say whether a total across its ' +
          'partitions is meaningful. Set Cross_Partition_Total__c to NONE for mutually exclusive ' +
          'partitions - alternatives, scenarios - or SUM where they are complementary parts of one ' +
          'whole. There is no default: the wrong one prints a number the customer is not being ' +
          'asked to pay.'
      );
    }

    if (
      !CROSS_PARTITION_NONE.equals(crossPartitionTotal) &&
      !CROSS_PARTITION_SUM.equals(crossPartitionTotal)
    ) {
      throw new QuoteDocumentGenerator.QuoteDocumentException(
        'Table ' +
          tableCode +
          ' sets Cross_Partition_Total__c = ' +
          crossPartitionTotal +
          '. Use NONE or SUM.'
      );
    }

    if (hasComparison()) {
      throw new QuoteDocumentGenerator.QuoteDocumentException(
        'Table ' +
          tableCode +
          ' both partitions and compares against a baseline. Which partition ' +
          'a baseline line belongs to has no agreed answer, and a change document is the last ' +
          'place to guess.'
      );
    }

    // The third pair. Comparison was guarded against both of the others
    // and this one was not, so a definition could expand AND partition -
    // the generator partitions unexpanded lines and expands inside each
    // partition, which is a coherent shape nobody chose. Nothing says what
    // a repeated measure peaks across when the partitions have different
    // terms, and Cross_Partition_Total__c = SUM cannot be true of a
    // measure that is not summed in the first place.
    if (hasExpander()) {
      throw new QuoteDocumentGenerator.QuoteDocumentException(
        'Table ' +
          tableCode +
          ' both partitions and expands. Each partition would get its own ' +
          'axis, and a measure that repeats across buckets - a licence count in every month - has ' +
          'no agreed meaning across partitions that do not share one. Split it into two ' +
          'definitions: partition one, expand the other.'
      );
    }
  }

  public Boolean usesChangeMeasures() {
    return MEASURES_CHANGE.equals(measureSet);
  }

  /**
   * The measure fields a given set writes. Lives here rather than in the
   * generator because it is purely a function of the measure set, which this
   * class already owns the constants for - both the persistence step that
   * stamps a table and the verification step that reconciles it read the
   * same list from here, so the two can never drift apart.
   */
  public static List<String> measureFields(String measureSet) {
    if (MEASURES_CHANGE.equals(measureSet)) {
      return new List<String>{
        'Amount_Net_New__c',
        'Amount_Cancellation__c',
        'Amount_Replacement_Removed__c',
        'Amount_Replacement_Added__c',
        'Amount_Termination__c',
        'Amount_Net_Change__c',
        'Amount_Baseline__c',
        'Amount_Final__c'
      };
    }
    return new List<String>{
      'Amount_List__c',
      'Amount_Regular__c',
      'Amount_Discount__c',
      'Amount_Net__c',
      'Amount_Customer__c',
      'Quantity__c'
    };
  }

  public String groupDimensionsLabel() {
    List<String> names = new List<String>();
    for (Level level : groupBy) {
      names.add(level.describe());
    }
    return String.join(names, ' > ');
  }

  // -----------------------------------------------------------------------
  // Loading
  // -----------------------------------------------------------------------

  @TestVisible
  private static void validateUniqueTableCode(
    Set<String> seenTableCodes,
    String tableCode
  ) {
    if (seenTableCodes == null || !seenTableCodes.add(tableCode)) {
      throw new QuoteDocumentGenerator.QuoteDocumentException(
        'Table Code must be unique across active table definitions: ' +
        tableCode
      );
    }
  }

  private static List<QuoteDocumentTableDefinition> cached;

  public static List<QuoteDocumentTableDefinition> getAll() {
    if (cached != null) {
      return cached;
    }

    // Ordered by Level then Sequence, so both the nesting order and the
    // order of parts within a composite are settled before anything reads
    // them. A metadata relationship cannot be ordered by a parent field,
    // so groupings are fetched separately and keyed up.
    Map<Id, List<Quote_Document_Grouping__mdt>> byDefinition = new Map<Id, List<Quote_Document_Grouping__mdt>>();

    for (Quote_Document_Grouping__mdt grouping : [
      SELECT
        Table_Definition__c,
        Dimension__c,
        Field_Path__c,
        Level__c,
        Sequence__c
      FROM Quote_Document_Grouping__mdt
      WITH USER_MODE
      ORDER BY Level__c, Sequence__c
    ]) {
      if (!byDefinition.containsKey(grouping.Table_Definition__c)) {
        byDefinition.put(
          grouping.Table_Definition__c,
          new List<Quote_Document_Grouping__mdt>()
        );
      }
      byDefinition.get(grouping.Table_Definition__c).add(grouping);
    }

    cached = fromRecords(
      [
        SELECT
          Id,
          Table_Code__c,
          Table_Name__c,
          Amount_Basis__c,
          Line_Filter__c,
          Measure_Set__c,
          Show_Details__c,
          Show_Section_Totals__c,
          Display_Order__c,
          Composite_Separator__c,
          Max_Groups__c,
          Sort_Groups_By__c,
          Row_Customizer_Code__c,
          Row_Customizer_Version__c,
          Row_Customizer_Flow__c,
          Row_Customizer_Flow_Version__c,
          Cache_Policy__c,
          Contributor_Dependency_Set__c,
          Display_Title__c,
          Display_Subtitle__c,
          Intro_Text__c,
          Footer_Text__c,
          Expander_Code__c,
          Expander_Version__c,
          Period_Months__c,
          Period_One_Time_Placement__c,
          Allocation_Basis__c,
          Allocation_Scale__c,
          Schedule_Code__c,
          Schedule_Divides_Quantity__c,
          Suppress_Amounts__c,
          Comparison_Source_Code__c,
          Comparison_Source_Version__c,
          Comparison_Source_Field__c,
          Partition_Dimension__c,
          Cross_Partition_Total__c,
          Assumptions_Block_Code__c
        FROM Quote_Document_Table_Def__mdt
        WHERE Is_Active__c = TRUE
        WITH USER_MODE
        ORDER BY Display_Order__c
      ],
      byDefinition
    );
    return cached;
  }

  /**
   * The record-to-definition pass, split out of getAll so the load-time
   * rejections it owns - duplicate codes, a definition with no groupings,
   * and everything the two validate* methods check - can be reached from a
   * test without activating a broken metadata record in the org, which would
   * fail every generation for every quote until it was deactivated again.
   *
   * Takes the records already ordered by Display_Order__c and the groupings
   * already keyed and ordered by Level then Sequence; it does no querying and
   * no caching of its own, so getAll keeps sole ownership of both.
   */
  @TestVisible
  private static List<QuoteDocumentTableDefinition> fromRecords(
    List<Quote_Document_Table_Def__mdt> records,
    Map<Id, List<Quote_Document_Grouping__mdt>> groupingsByDefinition
  ) {
    List<QuoteDocumentTableDefinition> definitions = new List<QuoteDocumentTableDefinition>();

    // Table_Code__c has no declarative uniqueness constraint of its own -
    // the platform-enforced uniqueness lives one step downstream, on
    // Quote_Document_Table__c.Table_Key__c (Quote Id + Table_Code__c).
    // Two active definitions sharing a code would otherwise surface as a
    // bare DML "duplicate value found" error deep inside generation,
    // naming a field an admin has never heard of instead of naming the
    // metadata record that actually needs fixing. Caught here instead,
    // at the same load-time validation pass as the "no grouping
    // dimensions" check below, so every config problem fails the same way.
    Set<String> seenTableCodes = new Set<String>();

    for (Quote_Document_Table_Def__mdt record : records) {
      if (!seenTableCodes.add(record.Table_Code__c)) {
        throw new QuoteDocumentGenerator.QuoteDocumentException(
          'Two active Quote_Document_Table_Def__mdt records both use Table_Code__c "' +
            record.Table_Code__c +
            '". Table_Code__c must be unique across every active ' +
            'table definition - rename one of the two records (or deactivate the one that ' +
            'is no longer needed) before generating.'
        );
      }

      List<Quote_Document_Grouping__mdt> groupings = groupingsByDefinition.containsKey(
          record.Id
        )
        ? groupingsByDefinition.get(record.Id)
        : new List<Quote_Document_Grouping__mdt>();

      Boolean hasContributor =
        String.isNotBlank(record.Row_Customizer_Code__c) ||
        String.isNotBlank(record.Row_Customizer_Flow__c);

      if (groupings.isEmpty() && !hasContributor) {
        // A table with no grouping emits only a grand total, which is
        // almost certainly half-finished config rather than intent.
        //
        // Unless a contributor builds the rows itself. Then there is
        // genuinely nothing to group by, and demanding a grouping would
        // force config that describes rows the builder is about to
        // discard - MONTHLY_SUBSCRIPTION_SUMMARY sections a quote by the
        // months each line runs in, and no field on the line names a
        // month for a Dimension__c or Field_Path__c to point at.
        throw new QuoteDocumentGenerator.QuoteDocumentException(
          'Table definition ' +
            record.Table_Code__c +
            ' has no grouping dimensions, and no ' +
            'row customizer to build its rows instead. Add a Quote_Document_Grouping__mdt ' +
            'record for it, or set Row_Customizer_Code__c / Row_Customizer_Flow__c if the ' +
            'rows are meant to come from a contributor.'
        );
      }

      QuoteDocumentTableDefinition definition = new QuoteDocumentTableDefinition(
        record,
        toLevels(record.Table_Code__c, groupings)
      );
      definition.validatePresentationConfig();
      definition.validateContributorConfig();
      definition.validateExpansionConfig();
      definition.validateComparisonConfig();
      definition.validatePartitionConfig();
      definitions.add(definition);
    }

    return definitions;
  }

  /** Collapses the flat grouping records into levels, preserving order. */
  @TestVisible
  private static List<Level> toLevels(
    String tableCode,
    List<Quote_Document_Grouping__mdt> groupings
  ) {
    Map<Decimal, Level> byLevel = new Map<Decimal, Level>();
    List<Decimal> order = new List<Decimal>();

    for (Quote_Document_Grouping__mdt grouping : groupings) {
      Boolean hasDimension = String.isNotBlank(grouping.Dimension__c);
      Boolean hasPath = String.isNotBlank(grouping.Field_Path__c);

      if (hasDimension == hasPath) {
        throw new QuoteDocumentGenerator.QuoteDocumentException(
          tableCode +
            ': a grouping must set exactly one of Dimension or Field Path' +
            ' (found dimension=' +
            grouping.Dimension__c +
            ', path=' +
            grouping.Field_Path__c +
            ')'
        );
      }

      Part part = new Part();
      part.dimension = hasDimension ? grouping.Dimension__c : null;
      part.fieldPath = hasPath ? grouping.Field_Path__c : null;

      Decimal levelNumber = grouping.Level__c == null ? 1 : grouping.Level__c;
      if (!byLevel.containsKey(levelNumber)) {
        byLevel.put(levelNumber, new Level());
        order.add(levelNumber);
      }
      byLevel.get(levelNumber).parts.add(part);
    }

    order.sort();
    List<Level> levels = new List<Level>();
    for (Decimal levelNumber : order) {
      levels.add(byLevel.get(levelNumber));
    }
    return levels;
  }

  /**
   * Every configured field path across every active definition, so the
   * generator can add them to its query in one pass.
   */
  public static Set<String> allFieldPaths() {
    Set<String> paths = new Set<String>();
    for (QuoteDocumentTableDefinition definition : getAll()) {
      for (Level level : definition.groupBy) {
        for (Part part : level.parts) {
          if (part.isFieldPath()) {
            paths.add(part.fieldPath);
          }
        }
      }
    }
    paths.addAll(QuoteDocumentCondition.allFieldPaths());
    return paths;
  }

  /**
   * Every declared contributor dependency path across every active
   * definition, so the query can fetch them in one pass and the fingerprint
   * can hash their values. Sorted, because the fingerprint's determinism
   * depends on iteration order and a Set has none.
   */
  public static List<String> allDependencyPaths() {
    Set<String> paths = new Set<String>();
    for (QuoteDocumentTableDefinition definition : getAll()) {
      if (CACHE_DECLARED_DEPENDENCIES.equals(definition.cachePolicy)) {
        paths.addAll(definition.contributorDependencyPaths);
      }
      // A comparison reads the lookup naming its baseline, so that field
      // has to be SELECTed like any other dependency - and, by arriving
      // here, its VALUE is hashed too. That is not incidental: pointing a
      // revision at a different source quote is a different document, and
      // nothing else in the fingerprint would notice.
      if (definition.hasComparison()) {
        paths.add(definition.comparisonSourceFieldOrDefault());
      }
    }
    List<String> sorted = new List<String>(paths);
    sorted.sort();
    return sorted;
  }

  @TestVisible
  private static void useDefinitions(
    List<QuoteDocumentTableDefinition> definitions
  ) {
    cached = definitions;
  }

  /** Test helper: build a definition in memory without metadata records. */
  @TestVisible
  private static QuoteDocumentTableDefinition build(
    String tableCode,
    List<String> dimensionsOrPaths,
    List<Integer> levels,
    String filter
  ) {
    QuoteDocumentTableDefinition definition = new QuoteDocumentTableDefinition();
    definition.tableCode = tableCode;
    definition.tableName = tableCode;
    // A fixture must build a VALID definition, and since step 01 a valid
    // definition carries a printable title - verification refuses to
    // publish a table without one. Deriving it from the code keeps every
    // existing fixture working without each one having to know that.
    definition.displayTitle = tableCode;
    definition.amountBasis = 'Final Value';
    definition.lineFilter = filter;
    definition.measureSet = MEASURES_PRICE_WATERFALL;
    definition.showDetails = true;
    definition.showSectionTotals = false;
    definition.displayOrder = 10;

    Map<Integer, Level> byLevel = new Map<Integer, Level>();
    List<Integer> order = new List<Integer>();
    for (Integer i = 0; i < dimensionsOrPaths.size(); i++) {
      String value = dimensionsOrPaths[i];
      Part part = new Part();
      if (value.contains('.') || value.endsWith('__c')) {
        part.fieldPath = value;
      } else {
        part.dimension = value;
      }
      Integer levelNumber = levels[i];
      if (!byLevel.containsKey(levelNumber)) {
        byLevel.put(levelNumber, new Level());
        order.add(levelNumber);
      }
      byLevel.get(levelNumber).parts.add(part);
    }
    order.sort();
    for (Integer levelNumber : order) {
      definition.groupBy.add(byLevel.get(levelNumber));
    }
    return definition;
  }
}
