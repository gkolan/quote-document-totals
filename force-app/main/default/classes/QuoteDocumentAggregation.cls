/**
 * Measures that do not add up.
 *
 * QuoteDocumentRowBuilder sums every measure into every aggregate row, because
 * every measure it was written for was additive. The moment a table carries an
 * effective discount percentage, the subtotal prints the SUM of the child
 * percentages - a number that can exceed 100 and means nothing. Nobody sees a
 * stack trace. verify() does not catch it either: it reconciles amounts, not
 * derived ratios.
 *
 * So a column declares how its measure aggregates, and this class computes the
 * aggregate rows afterwards, overwriting the sums the builder wrote.
 *
 * VALIDATED, NOT SKIPPED
 * ----------------------
 * The obvious move is to have verify() skip anything that is not a SUM. That is
 * exactly how a wrong number ships quietly, and quiet wrongness is the whole
 * reason this class exists. Every rule is re-checked under its own definition
 * instead - see verifyRules().
 *
 * COMPUTED BOTTOM-UP, NEVER FROM THE CHILD RESULTS
 * ------------------------------------------------
 * A RATIO at every level is that level own numerator over that level own
 * denominator. Averaging the child ratios is the trap: a 60% discount on
 * $1,000 beside a 10% discount on $100,000 blends to about 10.5%, not 35%.
 *
 * See specs/row-generation-extensibility/steps/step-03-non-additive-measures.md.
 */
public with sharing class QuoteDocumentAggregation {

    public static final String SUM = 'SUM';
    public static final String RATIO = 'RATIO';
    public static final String MAX = 'MAX';
    public static final String SUM_THEN_MAX = 'SUM_THEN_MAX';
    public static final String LAST = 'LAST';
    public static final String NONE = 'NONE';

    public static final String ERR_UNVERIFIED = 'AGGREGATION_RESULT_UNVERIFIED';
    public static final String ERR_CYCLIC = 'AGGREGATION_RULE_CYCLIC';
    public static final String ERR_NEEDS_EXPANSION = 'SUM_THEN_MAX_REQUIRES_EXPANSION';
    public static final String ERR_UNKNOWN = 'AGGREGATION_RULE_UNKNOWN';

    private static final Set<String> KNOWN = new Set<String>{ SUM, RATIO, MAX, SUM_THEN_MAX, LAST, NONE };

    private static final Set<String> AGGREGATE_ROW_TYPES = new Set<String>{
        'Group Header', 'Subtotal', 'Section Total', 'Grand Total'
    };

    /** One column's rule, resolved and validated. */
    public class Rule {
        public String field;
        public String rule;
        public String numerator;
        public String denominator;

        public Rule(String field, String rule, String numerator, String denominator) {
            this.field = field;
            this.rule = rule;
            this.numerator = numerator;
            this.denominator = denominator;
        }
    }

    /**
     * Every non-SUM rule this table declares, keyed by the field it governs.
     *
     * `expansionNonAdditive` is what the expander already worked out - a
     * repeated quantity is SUM_THEN_MAX whether or not anybody configured it,
     * because the expander is the only thing that knows the same licences are
     * present in every period. Explicit configuration wins where both exist,
     * so an author can say so out loud without changing the behaviour.
     */
    public static Map<String, Rule> rulesFor(
        QuoteDocumentTableDefinition definition,
        List<QuoteDocumentColumnDefinition> columns,
        Set<String> expansionNonAdditive
    ) {
        Map<String, Rule> rules = new Map<String, Rule>();

        if (expansionNonAdditive != null) {
            for (String field : expansionNonAdditive) {
                rules.put(field, new Rule(field, SUM_THEN_MAX, null, null));
            }
        }

        for (QuoteDocumentColumnDefinition column : columns) {
            if (column.isLabelColumn() || String.isBlank(column.aggregationRule)) {
                continue;
            }
            String rule = column.aggregationRule.toUpperCase();

            if (!KNOWN.contains(rule)) {
                QuoteDocumentContributorError.fail(
                    ERR_UNKNOWN,
                    'Table ' + definition.tableCode + ', column ' + column.columnCode
                        + ' declares Aggregation_Rule__c "' + column.aggregationRule
                        + '". Use SUM, RATIO, MAX, SUM_THEN_MAX, LAST or NONE.'
                );
            }
            if (SUM.equals(rule)) {
                continue;
            }
            if (RATIO.equals(rule)) {
                validateRatio(definition, column);
            }
            if (SUM_THEN_MAX.equals(rule) && !definition.hasExpander()) {
                // Peaking across product families is not a peak of anything.
                QuoteDocumentContributorError.fail(
                    ERR_NEEDS_EXPANSION,
                    'Table ' + definition.tableCode + ', column ' + column.columnCode
                        + ' declares SUM_THEN_MAX, but this table has no expansion to peak across. The rule '
                        + 'sums within each group and takes the largest group - across product families '
                        + 'that is not a peak of anything, it is an accident of how the quote is grouped.'
                );
            }
            rules.put(column.valueField, new Rule(
                column.valueField, rule, column.aggregationNumerator, column.aggregationDenominator
            ));
        }
        return rules;
    }

    private static void validateRatio(
        QuoteDocumentTableDefinition definition, QuoteDocumentColumnDefinition column
    ) {
        if (String.isBlank(column.aggregationNumerator) || String.isBlank(column.aggregationDenominator)) {
            QuoteDocumentContributorError.fail(
                ERR_UNKNOWN,
                'Table ' + definition.tableCode + ', column ' + column.columnCode + ' declares RATIO but '
                    + 'leaves the numerator or denominator blank. A ratio of nothing over nothing is not a '
                    + 'value a document can print.'
            );
        }
        // One level of derivation only. A ratio of ratios would need dependency
        // ordering, and no use case in the spec asks for one.
        if (column.aggregationNumerator == column.valueField
            || column.aggregationDenominator == column.valueField) {
            QuoteDocumentContributorError.fail(
                ERR_CYCLIC,
                'Table ' + definition.tableCode + ', column ' + column.columnCode + ' declares a RATIO '
                    + 'whose numerator or denominator is the column own field. It would be defined in '
                    + 'terms of itself.'
            );
        }
    }

    /**
     * Overwrites the sums the builder wrote on every aggregate row, for every
     * field a non-SUM rule governs. Runs on rows already in memory, before
     * insert, so a wrong rule fails generation rather than reaching a document.
     */
    public static void apply(
        List<Quote_Document_Row__c> rows, Map<String, Rule> rules, QuoteDocumentTableDefinition definition
    ) {
        if (rules.isEmpty()) {
            return;
        }

        for (Quote_Document_Row__c row : rows) {
            if (!AGGREGATE_ROW_TYPES.contains(row.Row_Type__c) || 'Group Header'.equals(row.Row_Type__c)) {
                continue;
            }
            for (Rule rule : rules.values()) {
                row.put(rule.field, compute(rule, row, rows));
            }
        }

        // A leaf row's ratio is its own, not an aggregate - but it still has to
        // be computed, or the column prints blank on every detail line.
        for (Quote_Document_Row__c row : rows) {
            if (AGGREGATE_ROW_TYPES.contains(row.Row_Type__c)) {
                continue;
            }
            for (Rule rule : rules.values()) {
                if (RATIO.equals(rule.rule)) {
                    row.put(rule.field, ratioOf(row, rule));
                }
            }
        }
    }

    private static Decimal compute(
        Rule rule, Quote_Document_Row__c aggregate, List<Quote_Document_Row__c> rows
    ) {
        if (NONE.equals(rule.rule)) {
            return null;
        }
        if (RATIO.equals(rule.rule)) {
            return ratioOf(aggregate, rule);
        }

        List<Quote_Document_Row__c> contributors = contributorsTo(aggregate, rows);

        if (LAST.equals(rule.rule)) {
            Decimal last;
            Decimal lastOrder;
            for (Quote_Document_Row__c row : contributors) {
                Decimal order = row.Display_Order__c;
                if (order != null && (lastOrder == null || order > lastOrder)) {
                    lastOrder = order;
                    last = (Decimal) row.get(rule.field);
                }
            }
            return last;
        }

        if (SUM_THEN_MAX.equals(rule.rule) && 'Grand Total'.equals(aggregate.Row_Type__c)) {
            // Sum within each group happened already - the subtotals ARE those
            // sums. Reading them rather than recomputing keeps the total
            // agreeing with the rows a reader can see above it.
            Decimal peak;
            for (Quote_Document_Row__c row : rows) {
                if (!'Subtotal'.equals(row.Row_Type__c) || row.Group_Level__c != 1) {
                    continue;
                }
                Decimal value = (Decimal) row.get(rule.field);
                if (value != null && (peak == null || value > peak)) {
                    peak = value;
                }
            }
            return peak == null ? 0 : peak;
        }

        if (SUM_THEN_MAX.equals(rule.rule)) {
            // Within a group it is an ordinary sum: two products active in the
            // same period really are the sum of their quantities that period.
            Decimal total = 0;
            for (Quote_Document_Row__c row : contributors) {
                Decimal value = (Decimal) row.get(rule.field);
                total += value == null ? 0 : value;
            }
            return total;
        }

        // MAX
        Decimal largest;
        for (Quote_Document_Row__c row : contributors) {
            Decimal value = (Decimal) row.get(rule.field);
            if (value != null && (largest == null || value > largest)) {
                largest = value;
            }
        }
        return largest == null ? 0 : largest;
    }

    private static Decimal ratioOf(Quote_Document_Row__c row, Rule rule) {
        Decimal numerator = (Decimal) row.get(rule.numerator);
        Decimal denominator = (Decimal) row.get(rule.denominator);

        // Blank, not zero and not an error. A table with no quantity has no
        // blended price, and that is a legitimate document rather than a
        // failure - but printing 0.00 would state a price nobody offered.
        if (denominator == null || denominator == 0) {
            return null;
        }
        return ((numerator == null ? 0 : numerator) / denominator).setScale(4, System.RoundingMode.HALF_UP);
    }

    /**
     * The leaf rows one aggregate row covers.
     *
     * A grand total covers every counted leaf. A subtotal covers the leaves
     * inside its own group, which is a Group_Key__c prefix match - the key is
     * built as parent|child, so a prefix is exactly "inside this group".
     */
    private static List<Quote_Document_Row__c> contributorsTo(
        Quote_Document_Row__c aggregate, List<Quote_Document_Row__c> rows
    ) {
        List<Quote_Document_Row__c> contributors = new List<Quote_Document_Row__c>();
        Boolean isGrandTotal = 'Grand Total'.equals(aggregate.Row_Type__c);

        for (Quote_Document_Row__c row : rows) {
            if (AGGREGATE_ROW_TYPES.contains(row.Row_Type__c) || row.Include_In_Grand_Total__c != true) {
                continue;
            }
            if (isGrandTotal) {
                contributors.add(row);
            } else if (row.Group_Key__c != null && aggregate.Group_Key__c != null
                       && (row.Group_Key__c == aggregate.Group_Key__c
                           || row.Group_Key__c.startsWith(aggregate.Group_Key__c + '|'))) {
                contributors.add(row);
            }
        }
        return contributors;
    }

    /**
     * Re-checks every aggregate row against the rule that produced it.
     *
     * Called from QuoteDocumentVerification, which excuses these fields from
     * its own additive reconciliation - so without this pass they would be the
     * only numbers in the snapshot nothing checks.
     */
    public static void verifyRules(
        List<Quote_Document_Row__c> rows,
        Map<String, Rule> rules,
        Quote_Document_Table__c table
    ) {
        for (Quote_Document_Row__c row : rows) {
            if (!AGGREGATE_ROW_TYPES.contains(row.Row_Type__c) || 'Group Header'.equals(row.Row_Type__c)) {
                continue;
            }
            for (Rule rule : rules.values()) {
                Decimal stated = (Decimal) row.get(rule.field);
                Decimal expected = compute(rule, row, rows);

                Boolean agrees = stated == null ? expected == null : stated == expected;
                if (!agrees) {
                    table.Status__c = 'Failed';
                    QuoteDocumentContributorError.fail(
                        ERR_UNVERIFIED,
                        table.Table_Code__c + ': row "' + row.Row_Key__c + '" states ' + rule.field + ' = '
                            + stated + ', but its declared rule ' + rule.rule + ' gives ' + expected
                            + '. A measure nothing checks is a measure nothing catches, which is why this '
                            + 'is verified rather than skipped.'
                    );
                }
            }
        }
    }
}
