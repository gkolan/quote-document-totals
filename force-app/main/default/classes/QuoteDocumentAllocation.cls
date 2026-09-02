/**
 * Splitting one amount across several rows, exactly.
 *
 * Every table that expands one quote line into many - months, milestones,
 * departments, deliveries - has to divide that line's money among them, and a
 * document whose rows do not add back to the line they came from is a document
 * that fails QuoteDocumentVerification, or worse, quietly does not.
 *
 * WHY THIS IS PURE
 * ----------------
 * No SObjects, no context, no DML, no queries. The hard part of allocation is
 * arithmetic, and arithmetic that can be tested without an org is arithmetic
 * that gets tested properly - QuoteDocumentAllocationTest runs thousands of
 * random splits in milliseconds and would not be written at all if it needed a
 * quote first.
 *
 * THE RULES, STATED ONCE
 * ----------------------
 *   RELATIVE     Weights are proportions, not percentages. [30,40,30] and
 *                [0.3,0.4,0.3] split identically, and [30,40,25] is a valid
 *                split into 32%/42%/26% rather than an error. Callers that
 *                mean percentages check that themselves; this cannot tell the
 *                difference between a deliberate ratio and a typo.
 *
 *   EXACT        The shares sum back to the total EXACTLY, at any scale. Each
 *                share is rounded down to scale and the accumulated rounding
 *                residual is carried into the LAST non-zero weight. Rounding
 *                each share independently and hoping is what puts a document a
 *                cent away from the quote it was generated from.
 *
 *   ZERO IS ZERO A zero weight gets exactly zero and never receives the
 *                residual. A promotional free month showing $0.01 is the
 *                defect this rule exists to prevent.
 *
 *   INVALID FAILS Empty weights, all-zero weights, or any negative weight
 *                throw. There is deliberately no "fall back to even": silently
 *                changing the basis is how a document becomes wrong without
 *                anything failing.
 *
 *   SIGNS        A negative total allocates negative shares and still sums
 *                back exactly. An amendment credit is a real input.
 *
 * See specs/row-generation-extensibility/steps/step-02-allocation-primitive.md.
 */
public with sharing class QuoteDocumentAllocation {

    public static final String ERR_WEIGHTS = 'ALLOCATION_WEIGHTS_INVALID';
    public static final String ERR_SOURCE = 'ALLOCATION_SOURCE_UNRECONCILED';

    /**
     * Splits total across weights, in order, rounded to scale, summing back to
     * total exactly.
     */
    public static List<Decimal> split(Decimal total, List<Decimal> weights, Integer scale) {
        validate(weights);

        Decimal amount = total == null ? 0 : total;
        Integer places = scale == null ? 2 : scale;

        Decimal weightTotal = 0;
        Integer lastNonZero = -1;
        for (Integer i = 0; i < weights.size(); i++) {
            Decimal weight = weights[i] == null ? 0 : weights[i];
            weightTotal += weight;
            if (weight != 0) {
                lastNonZero = i;
            }
        }

        List<Decimal> shares = new List<Decimal>();
        Decimal assigned = 0;

        for (Integer i = 0; i < weights.size(); i++) {
            Decimal weight = weights[i] == null ? 0 : weights[i];

            if (weight == 0) {
                // Never the residual, however the rounding falls elsewhere.
                shares.add(zeroAt(places));
                continue;
            }
            if (i == lastNonZero) {
                // Placeholder; the residual is settled below, after every
                // other share is known.
                shares.add(null);
                continue;
            }

            Decimal share = (amount * weight / weightTotal).setScale(places, System.RoundingMode.HALF_UP);
            shares.add(share);
            assigned += share;
        }

        shares[lastNonZero] = amount - assigned;
        return shares;
    }

    /** Even division: the same weight everywhere. */
    public static List<Decimal> splitEvenly(Decimal total, Integer parts, Integer scale) {
        List<Decimal> weights = new List<Decimal>();
        for (Integer i = 0; i < parts; i++) {
            weights.add(1);
        }
        return split(total, weights, scale);
    }

    /**
     * The check QuoteDocumentVerification structurally cannot make.
     *
     * verify() reconciles a TABLE total, once, with a cent of tolerance. That
     * is necessary and not sufficient for an allocation: it tolerates a lost
     * cent, and - worse - allocating line A's money into line B's buckets
     * reconciles perfectly while every printed row is wrong. A document whose
     * rows are wrong but whose total is right is worse than one that fails,
     * because it will be signed.
     *
     * So every allocation re-checks its own source, at ZERO tolerance. No
     * tolerance parameter is exposed: split() is exact by construction, so a
     * mismatch here is a bug in a caller, not a rounding artefact to absorb.
     */
    public static void reconcile(Decimal sourceValue, List<Decimal> shares, String describeSource) {
        Decimal expected = sourceValue == null ? 0 : sourceValue;
        Decimal actual = 0;
        for (Decimal share : shares) {
            actual += share == null ? 0 : share;
        }

        if (expected != actual) {
            QuoteDocumentContributorError.fail(
                ERR_SOURCE,
                describeSource + ' was allocated into ' + shares.size() + ' shares totalling ' + actual
                    + ', but its own value is ' + expected + '. The difference is ' + (expected - actual)
                    + '. A table total that still reconciles does not make this safe - the printed rows are '
                    + 'the numbers a customer reads, and one of them is wrong.'
            );
        }
    }

    private static void validate(List<Decimal> weights) {
        if (weights == null || weights.isEmpty()) {
            QuoteDocumentContributorError.fail(
                ERR_WEIGHTS,
                'An allocation was asked to split a value across no weights at all. There is no default '
                    + 'here: dividing evenly instead would silently change the basis of a document nobody '
                    + 'asked to change.'
            );
        }

        Decimal weightTotal = 0;
        for (Decimal weight : weights) {
            Decimal value = weight == null ? 0 : weight;
            if (value < 0) {
                QuoteDocumentContributorError.fail(
                    ERR_WEIGHTS,
                    'An allocation weight of ' + value + ' is negative. A share of a total cannot be '
                        + 'negative - to move money the other way, allocate a negative total.'
                );
            }
            weightTotal += value;
        }

        if (weightTotal == 0) {
            QuoteDocumentContributorError.fail(
                ERR_WEIGHTS,
                'Every allocation weight is zero, so there is no share for the money to land in. A table '
                    + 'where nothing is allocated anywhere is a configuration error, not an empty document.'
            );
        }
    }

    /** Zero, carrying the scale so a row reads 0.00 rather than 0. */
    private static Decimal zeroAt(Integer scale) {
        return Decimal.valueOf(0).setScale(scale);
    }
}
