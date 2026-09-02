/**
 * Expands lines along a period axis: months, quarters, years - whatever
 * Period_Months__c says. One expander rather than three, because the only
 * difference between a monthly schedule and an annual one is the length of a
 * bucket.
 *
 * THE AXIS
 * --------
 * The quote's own term: SBQQ__StartDate__c plus SBQQ__SubscriptionTerm__c
 * months, divided into buckets of Period_Months__c. If either is blank they are
 * derived from the lines - earliest start, and enough months to reach the
 * latest end. If neither can be resolved, generation FAILS: a schedule built on
 * a guessed term puts every product in a period nobody chose.
 *
 * A term that does not divide evenly gets a shorter final bucket rather than an
 * extra empty one - a 30-month term at 12 months a bucket is three periods, the
 * last of them six months long, which is what a customer signing a 30-month
 * deal expects to read.
 *
 * BUCKETS ARE ANNIVERSARY-BASED, NOT CALENDAR-BASED
 * -------------------------------------------------
 * Period N runs [start.addMonths((N-1)*len), start.addMonths(N*len)). A term
 * starting on the 15th has twelve whole months, not thirteen partial ones.
 *
 * OCCUPANCY - every case, because vague occupancy is where these tables go
 * wrong silently
 * ---------------------------------------------------------------------------
 *   Window inside the term      every period the window touches, whole or
 *                               partial: one day of overlap means the product
 *                               was running that period
 *   Blank start and blank end   every period - CPQ's own meaning for a blank
 *                               SBQQ__EffectiveStartDate__c
 *   Blank start, dated end      the first period through the end's period
 *   Dated start, blank end      the start's period through the last
 *   End before start            fails, EXPANSION_WINDOW_INVALID
 *   Entirely outside the term   fails, EXPANSION_LINE_OUTSIDE_AXIS - dropping
 *                               it silently would leave the printed periods
 *                               short of the quote total
 *   A ONE-TIME charge           see below
 *
 * ONE-TIME CHARGES DO NOT SPREAD BY DEFAULT
 * -----------------------------------------
 * A blank window on a one-time charge does NOT mean the whole term. Hardware
 * and setup are incurred once, and spreading a setup fee across twelve months
 * prints a recurring charge that does not exist. The default is therefore
 * FIRST_PERIOD, with EFFECTIVE_DATE and SPREAD available on the table
 * definition - SPREAD is the old behaviour and has to be chosen out loud,
 * because a prepaid annual support fee genuinely does spread and only the
 * author knows which case this is.
 *
 * QUANTITY REPEATS HERE
 * ---------------------
 * dividesQuantity() is false: a customer with 100 licences has 100 in every
 * month of the term, not 8.33. See QuoteDocumentExpansion.
 *
 * See docs/quote-document-extension-recipes.md.
 */
public with sharing class QuoteDocumentPeriodExpander implements QuoteDocumentLineExpander {

    public static final String CODE = 'PERIOD';

    /** '{0}' is the period ordinal. The word, and where it sits relative to the number, is the dictionary's. */
    public static final String KEY_MONTH = 'MONTH_LABEL';
    public static final String KEY_YEAR = 'YEAR_LABEL';
    public static final String KEY_PERIOD = 'PERIOD_LABEL';

    public static final String PLACE_FIRST = 'FIRST_PERIOD';
    public static final String PLACE_EFFECTIVE = 'EFFECTIVE_DATE';
    public static final String PLACE_SPREAD = 'SPREAD';

    public static final String ERR_AXIS = 'EXPANSION_AXIS_UNRESOLVED';
    public static final String ERR_WINDOW = 'EXPANSION_WINDOW_INVALID';
    public static final String ERR_OUTSIDE = 'EXPANSION_LINE_OUTSIDE_AXIS';

    /** A term this long is a configuration mistake, not a subscription. Bounds the derivation loop. */
    private static final Integer MAX_MONTHS = 120;

    /**
     * The axis as a start date and a bucket count. Public so a test can
     * exercise the bucketing without standing up a quote - the arithmetic is
     * where these tables actually break.
     */
    public class Axis {
        public final Date startDate;
        public final Integer periodMonths;
        public final Integer periods;
        public final Integer termMonths;

        public Axis(Date startDate, Integer termMonths, Integer periodMonths) {
            this.startDate = startDate;
            this.termMonths = termMonths;
            this.periodMonths = periodMonths;
            // A remainder gets a shorter last bucket, never an empty extra one.
            this.periods = (termMonths + periodMonths - 1) / periodMonths;
        }

        /** Inclusive: the last day the term covers. */
        public Date endDate() {
            return startDate.addMonths(termMonths).addDays(-1);
        }

        /** The first day of period n, 1-based. */
        public Date startOf(Integer n) {
            return startDate.addMonths((n - 1) * periodMonths);
        }

        /** The 1-based period containing d, or null if d falls outside the term. */
        public Integer indexOf(Date d) {
            if (d == null || d < startDate || d > endDate()) {
                return null;
            }
            for (Integer i = 1; i <= periods; i++) {
                if (d < startOf(i + 1)) {
                    return i;
                }
            }
            return periods;
        }
    }

    public static Axis resolveAxis(
        SBQQ__Quote__c quote, List<QuoteDocumentLine> lines, Integer periodMonths
    ) {
        Date earliest;
        Date latest;
        for (QuoteDocumentLine line : lines) {
            if (line.subscriptionStartDate != null
                && (earliest == null || line.subscriptionStartDate < earliest)) {
                earliest = line.subscriptionStartDate;
            }
            if (line.subscriptionEndDate != null
                && (latest == null || line.subscriptionEndDate > latest)) {
                latest = line.subscriptionEndDate;
            }
        }

        Date start = quote.SBQQ__StartDate__c == null ? earliest : quote.SBQQ__StartDate__c;
        if (start == null) {
            QuoteDocumentContributorError.fail(
                ERR_AXIS,
                'A period breakdown needs a term to divide, and neither the Quote start date nor any line '
                    + 'start date is set. Set SBQQ__StartDate__c on the quote, or date the lines - an axis '
                    + 'guessed from nothing would put every product in a period nobody chose.'
            );
        }

        Integer months = quote.SBQQ__SubscriptionTerm__c == null
            ? monthsToCover(start, latest)
            : Integer.valueOf(quote.SBQQ__SubscriptionTerm__c);

        if (months == null || months < 1) {
            QuoteDocumentContributorError.fail(
                ERR_AXIS,
                'A period breakdown resolved a term start of ' + String.valueOf(start) + ' but no usable '
                    + 'length: SBQQ__SubscriptionTerm__c is blank or not positive, and no line carries an '
                    + 'end date to derive one from.'
            );
        }
        if (months > MAX_MONTHS) {
            QuoteDocumentContributorError.fail(
                ERR_AXIS,
                'A period breakdown resolved a term of ' + months + ' months, beyond the ' + MAX_MONTHS
                    + '-month ceiling. A term that long is a data error.'
            );
        }
        return new Axis(start, months, periodMonths);
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

    // -----------------------------------------------------------------------
    // The contract
    // -----------------------------------------------------------------------

    public List<QuoteDocumentExpansion.Bucket> buckets(QuoteDocumentExpansion.Request request) {
        Axis axis = axisFor(request);
        String key = labelKeyFor(axis.periodMonths);

        List<QuoteDocumentExpansion.Bucket> buckets = new List<QuoteDocumentExpansion.Bucket>();
        for (Integer i = 1; i <= axis.periods; i++) {
            String ordinal = String.valueOf(i);
            QuoteDocumentExpansion.Bucket bucket = new QuoteDocumentExpansion.Bucket(
                bucketKey(i),
                request.labels.format(key, new List<String>{ ordinal }),
                i
            );
            bucket.labelKey = key;
            bucket.labelArg1 = ordinal;
            buckets.add(bucket);
        }
        return buckets;
    }

    public List<QuoteDocumentExpansion.Placement> placements(
        QuoteDocumentLine line, QuoteDocumentExpansion.Request request
    ) {
        Axis axis = axisFor(request);

        if (isOneTime(line) && !PLACE_SPREAD.equals(placementFor(request))) {
            return new List<QuoteDocumentExpansion.Placement>{
                new QuoteDocumentExpansion.Placement(bucketKey(oneTimePeriod(line, axis, request)), 1)
            };
        }

        Date lineStart = line.subscriptionStartDate == null ? axis.startDate : line.subscriptionStartDate;
        Date lineEnd = line.subscriptionEndDate == null ? axis.endDate() : line.subscriptionEndDate;

        if (lineEnd < lineStart) {
            QuoteDocumentContributorError.fail(
                ERR_WINDOW,
                'Line "' + line.productName + '" ends ' + String.valueOf(lineEnd) + ', before it starts '
                    + String.valueOf(lineStart) + '. There is no set of periods to spread it over.'
            );
        }
        if (lineEnd < axis.startDate || lineStart > axis.endDate()) {
            QuoteDocumentContributorError.fail(
                ERR_OUTSIDE,
                'Line "' + line.productName + '" runs ' + String.valueOf(lineStart) + ' to '
                    + String.valueOf(lineEnd) + ', entirely outside the term '
                    + String.valueOf(axis.startDate) + ' to ' + String.valueOf(axis.endDate())
                    + '. Its amount belongs to no period, so including it would leave the printed periods '
                    + 'short of the quote total - and dropping it silently would do the same.'
            );
        }

        Integer first = lineStart <= axis.startDate ? 1 : axis.indexOf(lineStart);
        Integer last = lineEnd >= axis.endDate() ? axis.periods : axis.indexOf(lineEnd);

        List<QuoteDocumentExpansion.Placement> placements = new List<QuoteDocumentExpansion.Placement>();
        for (Integer i = first; i <= last; i++) {
            // Even, not day-weighted: a customer reading two adjacent months
            // does not expect the same product to cost less because February
            // is short.
            placements.add(new QuoteDocumentExpansion.Placement(bucketKey(i), 1));
        }
        return placements;
    }

    /** Months repeat a quantity - the same licences, period after period. */
    public Boolean dividesQuantity() {
        return false;
    }

    // -----------------------------------------------------------------------

    /**
     * CPQ leaves the charge type blank for a one-off charge, which is the same
     * convention QuoteDocumentLine.getGroupingValue reads.
     */
    private static Boolean isOneTime(QuoteDocumentLine line) {
        return !'Recurring'.equals(line.chargeType);
    }

    private static Integer oneTimePeriod(
        QuoteDocumentLine line, Axis axis, QuoteDocumentExpansion.Request request
    ) {
        if (PLACE_EFFECTIVE.equals(placementFor(request)) && line.subscriptionStartDate != null) {
            Integer index = axis.indexOf(line.subscriptionStartDate);
            if (index == null) {
                QuoteDocumentContributorError.fail(
                    ERR_OUTSIDE,
                    'One-time charge "' + line.productName + '" is dated '
                        + String.valueOf(line.subscriptionStartDate) + ', outside the term '
                        + String.valueOf(axis.startDate) + ' to ' + String.valueOf(axis.endDate()) + '.'
                );
            }
            return index;
        }
        return 1;
    }

    private static String placementFor(QuoteDocumentExpansion.Request request) {
        return String.isBlank(request.definition.periodOneTimePlacement)
            ? PLACE_FIRST
            : request.definition.periodOneTimePlacement;
    }

    private static Axis axisFor(QuoteDocumentExpansion.Request request) {
        Integer length = request.definition.periodMonths == null ? 1 : request.definition.periodMonths;
        return resolveAxis(request.quote, request.lines, length);
    }

    /**
     * Zero-padded so the key sorts the same way the axis does even where
     * something orders keys as text.
     */
    private static String bucketKey(Integer period) {
        return 'PERIOD:' + String.valueOf(period).leftPad(3, '0');
    }

    /**
     * Months and years get their own dictionary entries because "Month 3" and
     * "Year 3" are different words in every language, and a generic "Period 3"
     * for a monthly schedule would read as a translation nobody finished.
     */
    private static String labelKeyFor(Integer periodMonths) {
        if (periodMonths == 1)  { return KEY_MONTH; }
        if (periodMonths == 12) { return KEY_YEAR; }
        return KEY_PERIOD;
    }
}
