/**
 * Expands subscription lines into one row per month of the quote term, so a
 * document can print what the customer pays in each month rather than only
 * what they pay for the term.
 *
 * WHY THIS IS A CUSTOMIZER AND NOT A GROUPING
 * -------------------------------------------
 * Every declarative table shape in this framework GROUPS lines: one quote line
 * becomes exactly one Detail row, in exactly one bucket. A month breakdown
 * MULTIPLIES: a line running from month 7 to month 10 has to appear four
 * times, once in each month, each time carrying a quarter of its amount.
 * Quote_Document_Grouping__mdt cannot express that at any level, which is why
 * this is the one table whose rows are built here instead of by
 * QuoteDocumentRowBuilder. The builder's rows are discarded and replaced.
 *
 * THE RULES, STATED ONCE
 * ----------------------
 *   THE GRID    The months are the quote's own term: SBQQ__StartDate__c plus
 *               SBQQ__SubscriptionTerm__c months. If either is blank they are
 *               derived from the lines - earliest start, and enough months to
 *               reach the latest end. If neither can be resolved, generation
 *               fails; a monthly table with a guessed term is worse than none.
 *
 *   BUCKETS     Month N runs [start.addMonths(N-1), start.addMonths(N)) -
 *               anniversary months, not calendar months, so a term starting on
 *               the 15th has twelve whole months rather than thirteen partial
 *               ones.
 *
 *   OCCUPANCY   A line occupies every month its window touches, whole or
 *               partial: overlapping a month by one day puts the product in
 *               that month. A blank window on a line means the whole term,
 *               which is what CPQ's own SBQQ__EffectiveStartDate__c formula
 *               means by a blank SBQQ__StartDate__c.
 *
 *   QUANTITY    Money divides across the months; licences do not. A line of
 *               100 licences running all year shows 100 in EVERY month, and
 *               the grand total shows the peak month rather than the sum of
 *               them. See REPEATED_MEASURES - this was wrong first, dividing
 *               100 licences into 8.33 a month, and it is the reason
 *               nonAdditiveMeasures exists.
 *
 *   ALLOCATION  Each divisible measure is divided evenly across the months a line
 *               occupies. Even, not day-weighted: the business question this
 *               table answers is "what is running in month 7", and a customer
 *               reading two adjacent months does not expect the same product
 *               to cost different amounts because February is short.
 *
 *   ROUNDING    Shares are rounded to the cent and the LAST month a line
 *               occupies carries the residual, so the months always sum back
 *               to the line's quoted total exactly. This is not cosmetic:
 *               QuoteDocumentVerification checks this table's grand total
 *               against CPQ's own SBQQ__NetAmount__c to the cent, so an
 *               allocation that loses a penny fails generation.
 *
 *   EXCLUSIONS  Lines that do not count toward this table's totals - bundled
 *               components, whose price is already inside the package price -
 *               are left out entirely rather than printed at zero. A cost
 *               breakdown listing a component that costs nothing reads as an
 *               error to the customer.
 *
 *   THE NOTE    A Note row is appended after the grand total on every table
 *               that prints anything.
 *
 *               It was conditional first - only when a full-term line sat
 *               beside a shorter one - and that was wrong. Two three-month
 *               products with no annual line alongside them are still spread
 *               across months, still absent from the months they do not run
 *               in, and still need the sentence that says so. Any rule that
 *               sometimes withholds the explanation leaves a customer reading
 *               an allocated figure with nothing telling them it is allocated,
 *               and which quotes those are is not something anyone can predict
 *               from the table itself.
 */
public with sharing class QuoteDocumentMonthlyRowCustomizer implements QuoteDocumentRowCustomizer {

    /** Registered under this code in QuoteDocumentRowCustomizerRegistry. */
    public static final String CODE = 'MONTHLY_SUBSCRIPTION';

    /** '{0}' is the month ordinal. The word "Month", and where it sits relative to the number, belongs to the dictionary. */
    public static final String KEY_MONTH = 'MONTH_LABEL';

    /** The explanatory sentence printed under the grand total. */
    public static final String KEY_NOTE = 'MONTHLY_ALLOCATION_NOTE';

    public static final String DIMENSION = 'MONTH';

    /** A term this long is a configuration mistake, not a subscription. Bounds the grid-derivation loop. */
    private static final Integer MAX_MONTHS = 120;

    private static final String ERR_TERM = 'MONTHLY_TERM_UNRESOLVED';
    private static final String ERR_WINDOW = 'MONTHLY_WINDOW_INVALID';
    private static final String ERR_OUTSIDE = 'MONTHLY_LINE_OUTSIDE_TERM';
    private static final String ERR_MEASURES = 'MONTHLY_MEASURE_SET_UNSUPPORTED';

    // -----------------------------------------------------------------------
    // The month grid
    // -----------------------------------------------------------------------

    /**
     * The term expressed as a start date and a month count. Public so a test,
     * or a second table built on the same idea, can exercise the bucketing
     * without standing up a quote.
     */
    public class MonthGrid {
        public final Date startDate;
        public final Integer months;

        public MonthGrid(Date startDate, Integer months) {
            this.startDate = startDate;
            this.months = months;
        }

        /** Inclusive: the last day the term covers. */
        public Date endDate() {
            return startDate.addMonths(months).addDays(-1);
        }

        /** The 1-based month containing d, or null if d falls outside the term. */
        public Integer indexOf(Date d) {
            if (d == null || d < startDate || d > endDate()) {
                return null;
            }
            for (Integer i = 1; i <= months; i++) {
                if (d < startDate.addMonths(i)) {
                    return i;
                }
            }
            return months;
        }
    }

    /** The months one line occupies, 1-based and inclusive at both ends. */
    public class Occupancy {
        public final Integer firstMonth;
        public final Integer lastMonth;

        public Occupancy(Integer firstMonth, Integer lastMonth) {
            this.firstMonth = firstMonth;
            this.lastMonth = lastMonth;
        }

        public Integer monthCount() {
            return lastMonth - firstMonth + 1;
        }
    }

    public static MonthGrid resolveGrid(SBQQ__Quote__c quote, List<QuoteDocumentLine> lines) {
        Date earliest;
        Date latest;
        for (QuoteDocumentLine line : lines) {
            if (line.subscriptionStartDate != null && (earliest == null || line.subscriptionStartDate < earliest)) {
                earliest = line.subscriptionStartDate;
            }
            if (line.subscriptionEndDate != null && (latest == null || line.subscriptionEndDate > latest)) {
                latest = line.subscriptionEndDate;
            }
        }

        Date start = quote.SBQQ__StartDate__c == null ? earliest : quote.SBQQ__StartDate__c;
        if (start == null) {
            throw QuoteDocumentContributorError.build(
                ERR_TERM,
                'The monthly breakdown needs a term to divide into months, and neither the Quote start date '
                    + 'nor any line start date is set. Set SBQQ__StartDate__c on the quote, or date the '
                    + 'lines - a month grid guessed from nothing would put every product in a month nobody '
                    + 'chose.'
            );
        }

        Integer months = quote.SBQQ__SubscriptionTerm__c == null
            ? monthsToCover(start, latest)
            : Integer.valueOf(quote.SBQQ__SubscriptionTerm__c);

        if (months == null || months < 1) {
            throw QuoteDocumentContributorError.build(
                ERR_TERM,
                'The monthly breakdown resolved a term start of ' + String.valueOf(start) + ' but no usable '
                    + 'length: SBQQ__SubscriptionTerm__c is blank or not positive and no line carries an end '
                    + 'date to derive one from.'
            );
        }
        if (months > MAX_MONTHS) {
            throw QuoteDocumentContributorError.build(
                ERR_TERM,
                'The monthly breakdown resolved a term of ' + months + ' months, beyond the ' + MAX_MONTHS
                    + '-month ceiling. A term that long is a data error; a document with that many sections '
                    + 'is unreadable either way.'
            );
        }
        return new MonthGrid(start, months);
    }

    /** Whole months from start needed to reach latest, inclusive. Null when there is no end date to reach. */
    private static Integer monthsToCover(Date start, Date latest) {
        if (latest == null || latest < start) {
            return null;
        }
        Integer months = 1;
        while (months < MAX_MONTHS && start.addMonths(months).addDays(-1) < latest) {
            months++;
        }
        return months;
    }

    public static Occupancy occupancyOf(QuoteDocumentLine line, MonthGrid grid) {
        Date lineStart = line.subscriptionStartDate == null ? grid.startDate : line.subscriptionStartDate;
        Date lineEnd = line.subscriptionEndDate == null ? grid.endDate() : line.subscriptionEndDate;

        if (lineEnd < lineStart) {
            throw QuoteDocumentContributorError.build(
                ERR_WINDOW,
                'Line "' + line.productName + '" ends ' + String.valueOf(lineEnd) + ', before it starts '
                    + String.valueOf(lineStart) + '. There is no set of months to bill it in.'
            );
        }
        if (lineEnd < grid.startDate || lineStart > grid.endDate()) {
            throw QuoteDocumentContributorError.build(
                ERR_OUTSIDE,
                'Line "' + line.productName + '" runs ' + String.valueOf(lineStart) + ' to '
                    + String.valueOf(lineEnd) + ', entirely outside the quote term '
                    + String.valueOf(grid.startDate) + ' to ' + String.valueOf(grid.endDate())
                    + '. Its amount belongs to no month, so including it would leave the printed months short '
                    + 'of the quote total - and dropping it silently would do the same. Correct the dates, or '
                    + 'take the line off this quote.'
            );
        }

        Integer first = lineStart <= grid.startDate ? 1 : grid.indexOf(lineStart);
        Integer last = lineEnd >= grid.endDate() ? grid.months : grid.indexOf(lineEnd);
        return new Occupancy(first, last);
    }

    /**
     * Measures that REPEAT across the months a line runs in rather than being
     * divided among them.
     *
     * Money divides: a $1,200 annual subscription is $100 of value in each of
     * twelve months. Licences do not: a customer with 100 licences has 100 in
     * every month, not 8.33. Dividing them printed a quantity nobody has, on a
     * document a customer reads, and the grand total then claimed 1,200
     * licence-months as if they were licences.
     *
     * Consequences that come with being in this set, both handled below:
     * the month subtotal is still a SUM (two products active in the same month
     * really are 150 licences that month), but the grand total is the PEAK
     * month rather than the sum of every month. Declared to core through
     * context.nonAdditiveMeasures so verification checks it under that rule
     * instead of the additive one.
     */
    private static final Set<String> REPEATED_MEASURES = new Set<String>{ 'Quantity__c' };

    /** The same value in every month the line runs - see REPEATED_MEASURES. */
    public static List<Decimal> repeat(Decimal value, Integer parts) {
        List<Decimal> values = new List<Decimal>();
        for (Integer i = 0; i < parts; i++) {
            values.add(value == null ? 0 : value);
        }
        return values;
    }

    /**
     * Divides total into parts that sum back to total EXACTLY. Every part but
     * the last is the rounded even share; the last absorbs whatever rounding
     * left over. Rounding each part independently and hoping is what puts a
     * document a cent away from the quote it was generated from.
     */
    public static List<Decimal> allocate(Decimal total, Integer parts) {
        Decimal amount = total == null ? 0 : total;
        List<Decimal> shares = new List<Decimal>();
        Decimal share = (amount / parts).setScale(2, System.RoundingMode.HALF_UP);
        Decimal assigned = 0;
        for (Integer i = 0; i < parts - 1; i++) {
            shares.add(share);
            assigned += share;
        }
        shares.add(amount - assigned);
        return shares;
    }

    // -----------------------------------------------------------------------
    // Row construction
    // -----------------------------------------------------------------------

    public List<Quote_Document_Row__c> customize(QuoteDocumentRowCustomizerContext context) {
        QuoteDocumentTableDefinition definition = context.definition;

        if (definition.usesChangeMeasures()) {
            throw QuoteDocumentContributorError.build(
                ERR_MEASURES,
                'Table ' + definition.tableCode + ' declares the CHANGE measure set. The monthly breakdown '
                    + 'allocates the price waterfall; pointed at change measures it would print a table of '
                    + 'zeroes that still reconciled. Use PRICE_WATERFALL.'
            );
        }

        List<QuoteDocumentLine> counted = new List<QuoteDocumentLine>();
        for (QuoteDocumentLine line : context.lines) {
            if (line.countsIn(definition.lineFilter)) {
                counted.add(line);
            }
        }

        // Nothing to break down. The builder's grand total is already correct
        // and already zero; replacing it would only risk getting that wrong.
        if (counted.isEmpty()) {
            return context.rows;
        }

        MonthGrid grid = resolveGrid(context.quote, counted);
        if (grid.months > definition.maxGroups) {
            throw new QuoteDocumentGenerator.QuoteDocumentException(
                definition.tableCode + ': a ' + grid.months + '-month term produces ' + grid.months
                    + ' groups, more than the ' + definition.maxGroups + ' this table allows. Raise Max Groups'
                    + ' on the table definition if a document that long is really intended.'
            );
        }

        List<String> measures = QuoteDocumentTableDefinition.measureFields(definition.measureSet);

        for (String measure : measures) {
            if (REPEATED_MEASURES.contains(measure)) {
                context.nonAdditiveMeasures.add(measure);
            }
        }

        // Month to lines, and (month, line) to its allocated share - both
        // settled before any row exists, so the rows are a straight projection
        // of an allocation that already balances.
        Map<Integer, List<QuoteDocumentLine>> linesByMonth = new Map<Integer, List<QuoteDocumentLine>>();
        Map<String, Map<String, Decimal>> shareByCell = new Map<String, Map<String, Decimal>>();

        for (QuoteDocumentLine line : counted) {
            Occupancy occupancy = occupancyOf(line, grid);
            Map<String, List<Decimal>> sharesByMeasure = new Map<String, List<Decimal>>();
            for (String measure : measures) {
                Decimal value = measureOf(line, measure);
                sharesByMeasure.put(
                    measure,
                    REPEATED_MEASURES.contains(measure)
                        ? repeat(value, occupancy.monthCount())
                        : allocate(value, occupancy.monthCount())
                );
            }

            for (Integer month = occupancy.firstMonth; month <= occupancy.lastMonth; month++) {
                if (!linesByMonth.containsKey(month)) {
                    linesByMonth.put(month, new List<QuoteDocumentLine>());
                }
                linesByMonth.get(month).add(line);

                Map<String, Decimal> share = new Map<String, Decimal>();
                for (String measure : measures) {
                    share.put(measure, sharesByMeasure.get(measure)[month - occupancy.firstMonth]);
                }
                shareByCell.put(cellKey(month, line), share);
            }
        }

        context.rows.clear();

        Map<String, Decimal> grandTotal = zeroed(measures);

        for (Integer month = 1; month <= grid.months; month++) {
            String ordinal = String.valueOf(month);
            String monthLabel = context.labels.format(KEY_MONTH, new List<String>{ ordinal });
            String monthKey = 'MONTH:' + ordinal.leftPad(2, '0');

            Quote_Document_Row__c header = context.newRow('Group Header', 1, 'HEADER:' + monthKey, monthLabel);
            header.Label_Key__c = KEY_MONTH;
            header.Label_Arg_1__c = ordinal;
            stampGroup(header, monthKey, monthLabel);

            Map<String, Decimal> subtotal = zeroed(measures);

            List<QuoteDocumentLine> active = linesByMonth.containsKey(month)
                ? linesByMonth.get(month)
                : new List<QuoteDocumentLine>();

            for (QuoteDocumentLine line : active) {
                Map<String, Decimal> share = shareByCell.get(cellKey(month, line));

                for (String measure : measures) {
                    subtotal.put(measure, subtotal.get(measure) + share.get(measure));
                }

                if (!definition.showDetails) {
                    continue;
                }

                Quote_Document_Row__c detail = context.newRow(
                    'Detail', 2, 'DETAIL:' + monthKey + ':' + line.quoteLineId, line.productName
                );
                detail.Quote_Line__c = line.quoteLineId;
                detail.Product_Name__c = line.productName;
                detail.Product_Code__c = line.productCode;
                detail.Product_Family__c = line.productFamily;
                detail.Charge_Type__c = line.chargeType;
                detail.Is_Displayed__c = line.isDisplayed;
                stampGroup(detail, monthKey, monthLabel);
                write(detail, share, measures);
            }

            // Rolled up from the month rather than from each line, so an
            // additive measure is the sum of every month and a repeated one is
            // the largest month - the peak, not twelve times the peak.
            for (String measure : measures) {
                Decimal monthValue = subtotal.get(measure);
                if (REPEATED_MEASURES.contains(measure)) {
                    if (monthValue > grandTotal.get(measure)) {
                        grandTotal.put(measure, monthValue);
                    }
                } else {
                    grandTotal.put(measure, grandTotal.get(measure) + monthValue);
                }
            }

            Quote_Document_Row__c subtotalRow = context.newRow(
                'Subtotal', 1, 'SUBTOTAL:' + monthKey,
                context.labels.format(QuoteDocumentLabels.KEY_SUBTOTAL, new List<String>{ monthLabel })
            );
            subtotalRow.Label_Key__c = QuoteDocumentLabels.KEY_SUBTOTAL;
            subtotalRow.Label_Arg_1__c = monthLabel;
            stampGroup(subtotalRow, monthKey, monthLabel);
            write(subtotalRow, subtotal, measures);
        }

        Quote_Document_Row__c total = context.newRow(
            'Grand Total', 0, 'GRAND_TOTAL', context.labels.resolve(QuoteDocumentLabels.KEY_GRAND_TOTAL)
        );
        total.Label_Key__c = QuoteDocumentLabels.KEY_GRAND_TOTAL;
        write(total, grandTotal, measures);

        // Unconditional - see THE NOTE at the top of this class. The early
        // return above is the only path that skips it, and that is a table
        // with no lines to explain.
        Quote_Document_Row__c note = context.newRow(
            'Note', 0, 'NOTE:MONTHLY_ALLOCATION', context.labels.resolve(KEY_NOTE)
        );
        note.Label_Key__c = KEY_NOTE;

        return context.rows;
    }

    // -----------------------------------------------------------------------

    private static String cellKey(Integer month, QuoteDocumentLine line) {
        return month + ':' + line.quoteLineId;
    }

    private static void stampGroup(Quote_Document_Row__c row, String groupKey, String monthLabel) {
        row.Group_Dimension__c = DIMENSION;
        row.Group_Value__c = monthLabel;
        row.Group_Key__c = groupKey;
    }

    private static Map<String, Decimal> zeroed(List<String> measures) {
        Map<String, Decimal> totals = new Map<String, Decimal>();
        for (String measure : measures) {
            totals.put(measure, 0);
        }
        return totals;
    }

    private static void write(Quote_Document_Row__c row, Map<String, Decimal> values, List<String> measures) {
        for (String measure : measures) {
            row.put(measure, values.get(measure));
        }
    }

    /**
     * The line's own value for one price-waterfall measure. A map rather than
     * a switch so the caller can iterate whatever measureFields() returns; a
     * measure outside the waterfall reaches here only if the CHANGE guard
     * above was removed, and answers zero rather than silently allocating a
     * different measure's money.
     */
    private static Decimal measureOf(QuoteDocumentLine line, String measure) {
        Map<String, Decimal> values = new Map<String, Decimal>{
            'Amount_List__c' => line.amountList,
            'Amount_Regular__c' => line.amountRegular,
            'Amount_Discount__c' => line.amountDiscount,
            'Amount_Net__c' => line.amountNet,
            'Amount_Customer__c' => line.amountCustomer,
            'Quantity__c' => line.quantity
        };
        return values.containsKey(measure) ? values.get(measure) : 0;
    }
}
