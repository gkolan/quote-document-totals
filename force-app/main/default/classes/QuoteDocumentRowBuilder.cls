/**
 * Turns normalized lines into the flat, ordered row stream a document renders.
 *
 * One recursive grouping method handles no grouping, one dimension, or any
 * number of nested dimensions. There is no tree in the output: the document
 * reads Display_Order__c, Row_Type__c and Group_Level__c and renders top to
 * bottom. Asking a Word template to walk a hierarchy is how documents break.
 */
public with sharing class QuoteDocumentRowBuilder {

    /**
     * A running total across the thirteen measures.
     *
     * This is the one place the measure list is enumerated. Adding a measure
     * means touching add() and writeTo() and nothing else.
     */
    public class Measures {
        public Decimal amountList = 0;
        public Decimal amountRegular = 0;
        public Decimal amountDiscount = 0;
        public Decimal amountNet = 0;
        public Decimal amountCustomer = 0;
        public Decimal quantity = 0;
        public Decimal amountNetNew = 0;
        public Decimal amountCancellation = 0;
        public Decimal amountReplacementRemoved = 0;
        public Decimal amountReplacementAdded = 0;
        public Decimal amountTermination = 0;
        public Decimal amountNetChange = 0;
        public Decimal amountFinal = 0;

        public void add(QuoteDocumentLine line) {
            amountList += line.amountList;
            amountRegular += line.amountRegular;
            amountDiscount += line.amountDiscount;
            amountNet += line.amountNet;
            amountCustomer += line.amountCustomer;
            quantity += line.quantity;
            amountNetNew += line.amountNetNew;
            amountCancellation += line.amountCancellation;
            amountReplacementRemoved += line.amountReplacementRemoved;
            amountReplacementAdded += line.amountReplacementAdded;
            amountTermination += line.amountTermination;
            amountNetChange += line.amountNetChange;
            amountFinal += line.amountFinal;
        }

        /**
         * Writes onto a row or onto the table itself - the API names are the
         * same on both objects, which is why the measures were named that way.
         * Only the declared family is written; the other stays null.
         */
        public void writeTo(SObject target, String measureSet) {
            if (QuoteDocumentTableDefinition.MEASURES_CHANGE.equals(measureSet)) {
                target.put('Amount_Net_New__c', amountNetNew);
                target.put('Amount_Cancellation__c', amountCancellation);
                target.put('Amount_Replacement_Removed__c', amountReplacementRemoved);
                target.put('Amount_Replacement_Added__c', amountReplacementAdded);
                target.put('Amount_Termination__c', amountTermination);
                target.put('Amount_Net_Change__c', amountNetChange);
                target.put('Amount_Final__c', amountFinal);
            } else {
                target.put('Amount_List__c', amountList);
                target.put('Amount_Regular__c', amountRegular);
                target.put('Amount_Discount__c', amountDiscount);
                target.put('Amount_Net__c', amountNet);
                target.put('Amount_Customer__c', amountCustomer);
                target.put('Quantity__c', quantity);
            }
        }
    }

    /** A node in the grouping tree. Exists only during generation. */
    public class GroupNode {
        public String dimension;
        public String value;
        public String groupKey;
        public Integer level;
        /** Only a bundle grouping indents its details by CPQ's option level. */
        public Boolean isBundleLevel = false;
        public List<GroupNode> children = new List<GroupNode>();
        public List<QuoteDocumentLine> lines = new List<QuoteDocumentLine>();
    }

    private final QuoteDocumentTableDefinition definition;
    private final List<Quote_Document_Row__c> rows = new List<Quote_Document_Row__c>();
    private Integer nextOrder = 10;

    public QuoteDocumentRowBuilder(QuoteDocumentTableDefinition definition) {
        this.definition = definition;
    }

    /** Guards against a composite quietly producing an unreadable document. */
    private Integer groupCount = 0;

    /** The rows for one table, in the order a document must render them. */
    public List<Quote_Document_Row__c> build(List<QuoteDocumentLine> lines) {
        List<GroupNode> groups = groupLines(lines, definition.groupBy, 0, null);

        for (GroupNode g : groups) {
            emitGroup(g);
        }

        if (definition.showSectionTotals) {
            emitSectionTotals(lines);
        }

        emitGrandTotal(lines);
        return rows;
    }

    // -----------------------------------------------------------------------
    // Grouping
    // -----------------------------------------------------------------------

    /**
     * Groups lines by levels[levelIndex], then recurses into the next level.
     * Reordering the levels reorders the nesting; putting two dimensions on the
     * same level makes one composite bucket instead of two nested ones. That is
     * the entire mechanism behind every table shape.
     */
    private List<GroupNode> groupLines(
        List<QuoteDocumentLine> lines,
        List<QuoteDocumentTableDefinition.Level> levels,
        Integer levelIndex,
        String parentKey
    ) {
        List<GroupNode> groups = new List<GroupNode>();
        if (levelIndex >= levels.size()) {
            return groups;
        }

        QuoteDocumentTableDefinition.Level level = levels[levelIndex];
        String dimensionLabel = level.describe();

        Map<String, List<QuoteDocumentLine>> linesByValue = new Map<String, List<QuoteDocumentLine>>();
        Map<String, Integer> minSequenceByValue = new Map<String, Integer>();
        for (QuoteDocumentLine line : lines) {
            String value = line.getGroupingValue(level, definition.compositeSeparator);
            if (!linesByValue.containsKey(value)) {
                linesByValue.put(value, new List<QuoteDocumentLine>());
                minSequenceByValue.put(value, line.sequence);
            }
            linesByValue.get(value).add(line);
            if (line.sequence < minSequenceByValue.get(value)) {
                minSequenceByValue.put(value, line.sequence);
            }
        }

        // Checked as the tree is built rather than at the end, so a runaway
        // composite fails before it has allocated thousands of rows.
        groupCount += linesByValue.size();
        if (groupCount > definition.maxGroups) {
            throw new QuoteDocumentGenerator.QuoteDocumentException(
                definition.tableCode + ': grouping by ' + definition.groupDimensionsLabel()
                + ' produced more than ' + definition.maxGroups + ' groups.'
                + ' Raise Max Groups on the table definition, or group by fewer dimensions -'
                + ' a composite multiplies the values of its parts.'
            );
        }

        List<String> sortedValues = new List<String>(linesByValue.keySet());
        if (QuoteDocumentTableDefinition.SORT_LINE_SEQUENCE.equals(definition.sortGroupsBy)) {
            sortedValues = sortByMinSequence(sortedValues, minSequenceByValue);
        } else {
            sortedValues.sort();
        }

        for (String value : sortedValues) {
            GroupNode g = new GroupNode();
            g.dimension = dimensionLabel;
            g.value = value;
            g.level = levelIndex + 1;
            g.isBundleLevel = containsBundleDimension(level);
            g.groupKey = buildGroupKey(parentKey, dimensionLabel, value);
            g.lines = linesByValue.get(value);
            g.children = groupLines(g.lines, levels, levelIndex + 1, g.groupKey);
            groups.add(g);
        }

        return groups;
    }

    private static Boolean containsBundleDimension(QuoteDocumentTableDefinition.Level level) {
        for (QuoteDocumentTableDefinition.Part part : level.parts) {
            if (QuoteDocumentTableDefinition.DIM_BUNDLE.equals(part.dimension)) {
                return true;
            }
        }
        return false;
    }

    private static String buildGroupKey(String parentKey, String dimension, String value) {
        String segment = dimension + ':' + value.toUpperCase().replaceAll('[^A-Z0-9]+', '_');
        return String.isBlank(parentKey) ? segment : parentKey + '|' + segment;
    }

    // -----------------------------------------------------------------------
    // Emitting rows
    // -----------------------------------------------------------------------

    private void emitGroup(GroupNode g) {
        Quote_Document_Row__c header = newRow('Group Header', g.level, 'HEADER:' + g.groupKey, g.value);
        header.Group_Dimension__c = g.dimension;
        header.Group_Value__c = g.value;
        header.Group_Key__c = g.groupKey;

        if (g.children.isEmpty()) {
            // Innermost group - this is where detail rows belong.
            if (definition.showDetails) {
                for (QuoteDocumentLine line : sortedBySequence(g.lines)) {
                    emitDetail(line, g);
                }
            }
        } else {
            for (GroupNode child : g.children) {
                emitGroup(child);
            }
        }

        Measures subtotal = new Measures();
        for (QuoteDocumentLine line : g.lines) {
            if (line.countsIn(definition.lineFilter)) {
                subtotal.add(line);
            }
        }

        Quote_Document_Row__c row = newRow('Subtotal', g.level, 'SUBTOTAL:' + g.groupKey, g.value + ' Subtotal');
        row.Group_Dimension__c = g.dimension;
        row.Group_Value__c = g.value;
        row.Group_Key__c = g.groupKey;
        subtotal.writeTo(row, definition.measureSet);
    }

    private void emitDetail(QuoteDocumentLine line, GroupNode g) {
        Integer level = line.indentUnder(g.level, g.isBundleLevel);

        Quote_Document_Row__c row = newRow('Detail', level, 'DETAIL:' + g.groupKey + ':' + line.quoteLineId,
                                           line.productName);
        row.Quote_Line__c = line.quoteLineId;
        row.Group_Dimension__c = g.dimension;
        row.Group_Value__c = g.value;
        row.Group_Key__c = g.groupKey;
        row.Product_Name__c = line.productName;
        row.Product_Code__c = line.productCode;
        row.Product_Family__c = line.productFamily;
        row.Charge_Type__c = line.chargeType;
        Boolean counted = line.countsIn(definition.lineFilter);
        row.Is_Displayed__c = line.isDisplayed;
        row.Include_In_Subtotal__c = counted;
        row.Include_In_Grand_Total__c = counted;

        if (definition.usesChangeMeasures()) {
            row.Transaction_Type__c = line.transactionType;
        }

        Measures m = new Measures();
        m.add(line);
        m.writeTo(row, definition.measureSet);
    }

    /**
     * Section totals cut the same lines a second way - by charge type - and sit
     * alongside the group subtotals rather than beneath them. This is how a
     * document shows "Total Recurring" next to a family breakdown.
     */
    private void emitSectionTotals(List<QuoteDocumentLine> lines) {
        Map<String, Measures> byChargeType = new Map<String, Measures>();
        for (QuoteDocumentLine line : lines) {
            if (!line.countsIn(definition.lineFilter)) { continue; }
            String section = line.getGroupingValue(QuoteDocumentTableDefinition.DIM_CHARGE_TYPE);
            if (!byChargeType.containsKey(section)) {
                byChargeType.put(section, new Measures());
            }
            byChargeType.get(section).add(line);
        }

        List<String> sections = new List<String>(byChargeType.keySet());
        sections.sort();

        for (String section : sections) {
            Quote_Document_Row__c row = newRow('Section Total', 0, 'SECTION:CHARGE_TYPE:' + section,
                                               'Total ' + section + ' Charges');
            row.Group_Dimension__c = QuoteDocumentTableDefinition.DIM_CHARGE_TYPE;
            row.Group_Value__c = section;
            byChargeType.get(section).writeTo(row, definition.measureSet);
        }
    }

    private void emitGrandTotal(List<QuoteDocumentLine> lines) {
        Measures total = new Measures();
        for (QuoteDocumentLine line : lines) {
            if (line.countsIn(definition.lineFilter)) {
                total.add(line);
            }
        }

        Quote_Document_Row__c row = newRow('Grand Total', 0, 'GRAND_TOTAL', 'Total');
        total.writeTo(row, definition.measureSet);
    }

    // -----------------------------------------------------------------------

    private Quote_Document_Row__c newRow(String rowType, Integer level, String key, String label) {
        Quote_Document_Row__c row = defaultRow(rowType, level, key, label, nextOrder);
        nextOrder += 10;
        rows.add(row);
        return row;
    }

    /**
     * The field defaults every generated row starts from, shared with
     * QuoteDocumentRowCustomizerContext.newRow() so a customizer's rows carry
     * exactly the same defaults as the builder's own - one place to change
     * what "a new row" means, instead of two copies drifting apart.
     *
     * Aggregate rows carry both inclusion flags false. They are the output of
     * aggregation, never an input to it - counting one would double-count
     * everything beneath it. A validation rule enforces the same thing.
     */
    public static Quote_Document_Row__c defaultRow(String rowType, Integer level, String key, String label, Integer displayOrder) {
        Boolean isAggregate = rowType != 'Detail';

        return new Quote_Document_Row__c(
            Row_Type__c = rowType,
            Group_Level__c = level,
            Row_Key__c = String.isBlank(key) ? null : key.abbreviate(255),
            Display_Label__c = String.isBlank(label) ? '(unnamed)' : label.abbreviate(255),
            Display_Order__c = displayOrder,
            Is_Displayed__c = true,
            Include_In_Subtotal__c = !isAggregate,
            Include_In_Grand_Total__c = !isAggregate
        );
    }

    /**
     * Orders a level's group values by the lowest line sequence seen in each
     * group, rather than alphabetically - so whichever bundle was added to the
     * quote first prints first. Small lists, and Apex cannot sort a List of a
     * non-Comparable type without boilerplate, so this mirrors the insertion
     * sort already used by sortedBySequence rather than introducing a second
     * sorting style in the same class.
     */
    private static List<String> sortByMinSequence(List<String> values, Map<String, Integer> minSequenceByValue) {
        List<String> sorted = new List<String>(values);
        for (Integer i = 1; i < sorted.size(); i++) {
            String current = sorted[i];
            Integer j = i - 1;
            while (j >= 0 && minSequenceByValue.get(sorted[j]) > minSequenceByValue.get(current)) {
                sorted[j + 1] = sorted[j];
                j--;
            }
            sorted[j + 1] = current;
        }
        return sorted;
    }

    private static List<QuoteDocumentLine> sortedBySequence(List<QuoteDocumentLine> lines) {
        // Small lists, and Apex cannot sort a List of a non-Comparable class
        // without boilerplate. An insertion sort on quote-line order is enough.
        List<QuoteDocumentLine> sorted = new List<QuoteDocumentLine>(lines);
        for (Integer i = 1; i < sorted.size(); i++) {
            QuoteDocumentLine current = sorted[i];
            Integer j = i - 1;
            while (j >= 0 && sorted[j].sequence > current.sequence) {
                sorted[j + 1] = sorted[j];
                j--;
            }
            sorted[j + 1] = current;
        }
        return sorted;
    }
}

