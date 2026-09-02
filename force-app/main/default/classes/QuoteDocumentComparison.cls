/**
 * Before, after, and the difference - built by pairing the quote's own lines
 * against a baseline set.
 *
 * Runs in the same place as expansion: before QuoteDocumentRowBuilder, handing
 * it a line list it cannot tell from any other. Grouping, subtotals, ordering
 * and verification are untouched.
 *
 * WHAT A COMPARISON ROW CARRIES
 * -----------------------------
 * The CHANGE measure set already means before-and-after, so no new row type
 * and almost no new field was needed:
 *
 *   Amount_Baseline__c    the BEFORE amount (added by this step - the set
 *                         could express the change and the result, but not
 *                         the starting point, and "after minus difference" is
 *                         a subtraction no renderer may perform)
 *   Amount_Final__c       the AFTER amount
 *   Amount_Net_Change__c  after minus before
 *   Amount_Net_New__c     the added amount, on a line that is new
 *   Amount_Cancellation__c the removed amount, negative, on a line that is gone
 *   Transaction_Type__c   Net New / Cancellation / Amended / Unchanged
 *
 * FOUR OUTCOMES, ALL OF THEM ROWS
 * -------------------------------
 *   matched and changed    one row, both sides, the difference
 *   matched and unchanged  one row, difference zero. Printed by default -
 *                          suppressing it is a Line_Filter__c decision, not a
 *                          matching one, and a customer scanning for what
 *                          moved is entitled to see what did not.
 *   only on the current    Net New. No baseline amounts.
 *   only on the baseline   Cancellation. No current amounts, negative change.
 *
 * AMBIGUITY FAILS
 * ---------------
 * Two lines sharing a match key on either side is refused with
 * COMPARISON_MATCH_AMBIGUOUS. Picking one silently would produce a difference
 * column that is confidently wrong, and the difference column is the number a
 * customer reading a change document trusts completely.
 *
 * See specs/row-generation-extensibility/steps/step-04-comparison-and-enrichment.md.
 */
public with sharing class QuoteDocumentComparison {

    public static final String ERR_AMBIGUOUS = 'COMPARISON_MATCH_AMBIGUOUS';
    public static final String ERR_SOURCE_MISSING = 'ENRICHMENT_SOURCE_MISSING';
    public static final String ERR_BLANK_KEY = 'COMPARISON_MATCH_KEY_BLANK';
    public static final String ERR_MEASURES = 'COMPARISON_MEASURE_SET_UNSUPPORTED';

    public static final String TYPE_ADDED = 'Net New';
    public static final String TYPE_REMOVED = 'Cancellation';
    public static final String TYPE_CHANGED = 'Amended';
    public static final String TYPE_UNCHANGED = 'Unchanged';

    /** Everything a source is allowed to see. */
    public class Request {
        public SBQQ__Quote__c quote;
        public QuoteDocumentTableDefinition definition;
        public List<QuoteDocumentLine> lines;

        public Request(
            SBQQ__Quote__c quote,
            QuoteDocumentTableDefinition definition,
            List<QuoteDocumentLine> lines
        ) {
            this.quote = quote;
            this.definition = definition;
            this.lines = lines;
        }
    }

    /**
     * Pairs the two sides and returns the merged line list.
     *
     * A comparison table must use the CHANGE measure set: pointed at the price
     * waterfall it would print a plausible table in which every difference was
     * silently zero.
     */
    public static List<QuoteDocumentLine> apply(
        QuoteDocumentComparisonSource source,
        SBQQ__Quote__c quote,
        QuoteDocumentTableDefinition definition,
        List<QuoteDocumentLine> lines
    ) {
        if (!definition.usesChangeMeasures()) {
            QuoteDocumentContributorError.fail(
                ERR_MEASURES,
                'Table ' + definition.tableCode + ' compares against a baseline but declares measure set '
                    + definition.measureSet + '. A comparison writes the CHANGE measures - before, after '
                    + 'and difference. Pointed at the price waterfall it would print a table whose '
                    + 'difference column was silently zero everywhere.'
            );
        }

        Request request = new Request(quote, definition, lines);
        List<QuoteDocumentLine> baseline = source.baseline(request);

        Map<String, QuoteDocumentLine> currentByKey = keyed(source, lines, 'current quote', definition);
        Map<String, QuoteDocumentLine> baselineByKey =
            keyed(source, baseline == null ? new List<QuoteDocumentLine>() : baseline, 'baseline', definition);

        List<QuoteDocumentLine> merged = new List<QuoteDocumentLine>();

        // Current side first, in the quote's own line order: a reader follows
        // the quote they are looking at, with what has gone appended after.
        for (QuoteDocumentLine line : lines) {
            String key = source.matchKey(line);
            QuoteDocumentLine before = baselineByKey.get(key);
            merged.add(compare(line, before));
        }

        for (String key : baselineByKey.keySet()) {
            if (!currentByKey.containsKey(key)) {
                merged.add(removed(baselineByKey.get(key)));
            }
        }

        return merged;
    }

    /**
     * One position, both sides. Mutates a copy rather than the line the caller
     * holds, so a second table built from the same lines is unaffected.
     */
    private static QuoteDocumentLine compare(QuoteDocumentLine current, QuoteDocumentLine before) {
        QuoteDocumentLine row = current.copyForComparison();

        Decimal after = current.amountNet;
        Decimal baselineAmount = before == null ? 0 : before.amountNet;

        row.amountBaseline = baselineAmount;
        row.amountFinal = after;
        row.amountNetChange = after - baselineAmount;

        row.amountNetNew = 0;
        row.amountCancellation = 0;
        row.amountReplacementRemoved = 0;
        row.amountReplacementAdded = 0;
        row.amountTermination = 0;

        if (before == null) {
            row.transactionType = TYPE_ADDED;
            row.amountNetNew = after;
        } else if (row.amountNetChange == 0) {
            row.transactionType = TYPE_UNCHANGED;
        } else {
            row.transactionType = TYPE_CHANGED;
        }
        return row;
    }

    /** A position that is on the baseline and not on the quote. */
    private static QuoteDocumentLine removed(QuoteDocumentLine before) {
        QuoteDocumentLine row = before.copyForComparison();

        row.amountBaseline = before.amountNet;
        row.amountFinal = 0;
        row.amountNetChange = -before.amountNet;
        row.amountNetNew = 0;
        row.amountCancellation = -Math.abs(before.amountNet);
        row.amountReplacementRemoved = 0;
        row.amountReplacementAdded = 0;
        row.amountTermination = 0;
        row.transactionType = TYPE_REMOVED;

        // The quantity is the position that is going, not a quantity the quote
        // still has. Left as the baseline's own so the row can say "50 licences
        // removed" rather than printing a blank beside a negative amount.
        return row;
    }

    private static Map<String, QuoteDocumentLine> keyed(
        QuoteDocumentComparisonSource source,
        List<QuoteDocumentLine> lines,
        String side,
        QuoteDocumentTableDefinition definition
    ) {
        Map<String, QuoteDocumentLine> byKey = new Map<String, QuoteDocumentLine>();

        for (QuoteDocumentLine line : lines) {
            String key = source.matchKey(line);

            if (String.isBlank(key)) {
                QuoteDocumentContributorError.fail(
                    ERR_BLANK_KEY,
                    'Table ' + definition.tableCode + ': the comparison source returned a blank match key '
                        + 'for "' + line.productName + '" on the ' + side + ' side. Every position needs an '
                        + 'identity, or it can only ever appear as both added and removed.'
                );
            }
            if (byKey.containsKey(key)) {
                QuoteDocumentContributorError.fail(
                    ERR_AMBIGUOUS,
                    'Table ' + definition.tableCode + ': two lines on the ' + side + ' side share the match '
                        + 'key "' + key + '" ("' + byKey.get(key).productName + '" and "' + line.productName
                        + '"). Pairing one of them arbitrarily would print a difference column that is '
                        + 'confidently wrong, which is the number a customer reading a change document '
                        + 'trusts most. Give the source a key that tells the two positions apart.'
                );
            }
            byKey.put(key, line);
        }
        return byKey;
    }
}
