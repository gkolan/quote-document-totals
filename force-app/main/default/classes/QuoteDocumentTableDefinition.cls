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
    public static final String DIM_PRODUCT_FAMILY   = 'PRODUCT_FAMILY';
    public static final String DIM_CHARGE_TYPE      = 'CHARGE_TYPE';
    public static final String DIM_QUOTE_LINE_GROUP = 'QUOTE_LINE_GROUP';
    public static final String DIM_BUNDLE           = 'BUNDLE';
    public static final String DIM_TRANSACTION_TYPE = 'TRANSACTION_TYPE';
    public static final String DIM_INDUSTRY         = 'INDUSTRY';

    // Line filters. QuoteDocumentLine.matchesFilter applies each one.
    public static final String FILTER_ALL                 = 'ALL';
    public static final String FILTER_EXCLUDE_OPTIONAL    = 'EXCLUDE_OPTIONAL';
    public static final String FILTER_OPTIONAL_ONLY       = 'OPTIONAL_ONLY';
    public static final String FILTER_RECURRING_ONLY      = 'RECURRING_ONLY';
    public static final String FILTER_ONE_TIME_ONLY       = 'ONE_TIME_ONLY';
    public static final String FILTER_BUNDLE_PARENTS_ONLY = 'BUNDLE_PARENTS_ONLY';

    public static final String MEASURES_PRICE_WATERFALL = 'PRICE_WATERFALL';
    public static final String MEASURES_CHANGE          = 'CHANGE';

    // How top-level groups are ordered. ALPHABETICAL (the default) sorts by
    // the group's own label; LINE_SEQUENCE sorts by the lowest SBQQ__Number__c
    // among the lines in that group, so whichever bundle was quoted first
    // prints first, regardless of its name.
    public static final String SORT_ALPHABETICAL  = 'ALPHABETICAL';
    public static final String SORT_LINE_SEQUENCE = 'LINE_SEQUENCE';

    private static final String DEFAULT_SEPARATOR = ' / ';
    private static final Integer DEFAULT_MAX_GROUPS = 50;

    /** One component of a grouping level. */
    public class Part {
        public String dimension;   // named and computed, or
        public String fieldPath;   // read from the record

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

    /** Registry code for QuoteDocumentRowCustomizerRegistry.resolve(), or blank if this table uses only declarative config. */
    public String rowCustomizerCode;

    @TestVisible
    private QuoteDocumentTableDefinition() {
        groupBy = new List<Level>();
        compositeSeparator = DEFAULT_SEPARATOR;
        maxGroups = DEFAULT_MAX_GROUPS;
        sortGroupsBy = SORT_ALPHABETICAL;
    }

    private QuoteDocumentTableDefinition(Quote_Document_Table_Def__mdt record, List<Level> levels) {
        tableCode = record.Table_Code__c;
        tableName = record.Table_Name__c;
        amountBasis = record.Amount_Basis__c;
        lineFilter = record.Line_Filter__c;
        measureSet = record.Measure_Set__c;
        showDetails = record.Show_Details__c;
        showSectionTotals = record.Show_Section_Totals__c;
        displayOrder = Integer.valueOf(record.Display_Order__c);
        compositeSeparator = String.isBlank(record.Composite_Separator__c)
            ? DEFAULT_SEPARATOR : record.Composite_Separator__c;
        maxGroups = record.Max_Groups__c == null
            ? DEFAULT_MAX_GROUPS : Integer.valueOf(record.Max_Groups__c);
        sortGroupsBy = String.isBlank(record.Sort_Groups_By__c)
            ? SORT_ALPHABETICAL : record.Sort_Groups_By__c;
        rowCustomizerCode = record.Row_Customizer_Code__c;
        groupBy = levels;
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
                'Amount_Net_New__c', 'Amount_Cancellation__c', 'Amount_Replacement_Removed__c',
                'Amount_Replacement_Added__c', 'Amount_Termination__c', 'Amount_Net_Change__c',
                'Amount_Final__c'
            };
        }
        return new List<String>{
            'Amount_List__c', 'Amount_Regular__c', 'Amount_Discount__c',
            'Amount_Net__c', 'Amount_Customer__c', 'Quantity__c'
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

    private static List<QuoteDocumentTableDefinition> cached;

    public static List<QuoteDocumentTableDefinition> getAll() {
        if (cached != null) {
            return cached;
        }

        // Ordered by Level then Sequence, so both the nesting order and the
        // order of parts within a composite are settled before anything reads
        // them. A metadata relationship cannot be ordered by a parent field,
        // so groupings are fetched separately and keyed up.
        Map<Id, List<Quote_Document_Grouping__mdt>> byDefinition =
            new Map<Id, List<Quote_Document_Grouping__mdt>>();

        for (Quote_Document_Grouping__mdt grouping : [
            SELECT Table_Definition__c, Dimension__c, Field_Path__c, Level__c, Sequence__c
            FROM Quote_Document_Grouping__mdt
            ORDER BY Level__c, Sequence__c
        ]) {
            if (!byDefinition.containsKey(grouping.Table_Definition__c)) {
                byDefinition.put(grouping.Table_Definition__c, new List<Quote_Document_Grouping__mdt>());
            }
            byDefinition.get(grouping.Table_Definition__c).add(grouping);
        }

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

        for (Quote_Document_Table_Def__mdt record : [
            SELECT Id, Table_Code__c, Table_Name__c, Amount_Basis__c, Line_Filter__c,
                   Measure_Set__c, Show_Details__c, Show_Section_Totals__c, Display_Order__c,
                   Composite_Separator__c, Max_Groups__c, Sort_Groups_By__c, Row_Customizer_Code__c
            FROM Quote_Document_Table_Def__mdt
            WHERE Is_Active__c = true
            ORDER BY Display_Order__c
        ]) {
            if (!seenTableCodes.add(record.Table_Code__c)) {
                throw new QuoteDocumentGenerator.QuoteDocumentException(
                    'Two active Quote_Document_Table_Def__mdt records both use Table_Code__c "'
                    + record.Table_Code__c + '". Table_Code__c must be unique across every active '
                    + 'table definition - rename one of the two records (or deactivate the one that '
                    + 'is no longer needed) before generating.'
                );
            }

            List<Quote_Document_Grouping__mdt> groupings = byDefinition.containsKey(record.Id)
                ? byDefinition.get(record.Id)
                : new List<Quote_Document_Grouping__mdt>();

            if (groupings.isEmpty()) {
                // A table with no grouping emits only a grand total, which is
                // almost certainly half-finished config rather than intent.
                throw new QuoteDocumentGenerator.QuoteDocumentException(
                    'Table definition ' + record.Table_Code__c + ' has no grouping dimensions.'
                );
            }

            definitions.add(new QuoteDocumentTableDefinition(record, toLevels(record.Table_Code__c, groupings)));
        }

        cached = definitions;
        return cached;
    }

    /** Collapses the flat grouping records into levels, preserving order. */
    @TestVisible
    private static List<Level> toLevels(String tableCode, List<Quote_Document_Grouping__mdt> groupings) {
        Map<Decimal, Level> byLevel = new Map<Decimal, Level>();
        List<Decimal> order = new List<Decimal>();

        for (Quote_Document_Grouping__mdt grouping : groupings) {
            Boolean hasDimension = String.isNotBlank(grouping.Dimension__c);
            Boolean hasPath = String.isNotBlank(grouping.Field_Path__c);

            if (hasDimension == hasPath) {
                throw new QuoteDocumentGenerator.QuoteDocumentException(
                    tableCode + ': a grouping must set exactly one of Dimension or Field Path'
                    + ' (found dimension=' + grouping.Dimension__c + ', path=' + grouping.Field_Path__c + ')'
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
        return paths;
    }

    @TestVisible
    private static void useDefinitions(List<QuoteDocumentTableDefinition> definitions) {
        cached = definitions;
    }

    /** Test helper: build a definition in memory without metadata records. */
    @TestVisible
    private static QuoteDocumentTableDefinition build(
        String tableCode, List<String> dimensionsOrPaths, List<Integer> levels, String filter
    ) {
        QuoteDocumentTableDefinition definition = new QuoteDocumentTableDefinition();
        definition.tableCode = tableCode;
        definition.tableName = tableCode;
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
