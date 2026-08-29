/**
 * The allocation arithmetic, with no org involved.
 *
 * Every case here is a business rule with a worked number behind it, and the
 * numbers are the ones from the specification's worked examples rather than
 * whatever the code happens to produce. The property test at the end is the one
 * that earns its keep: it covers the splits nobody thought to write down, and
 * it can only exist because the primitive is pure.
 */
@IsTest
private class QuoteDocumentAllocationTest {

    private static Decimal sum(List<Decimal> values) {
        Decimal total = 0;
        for (Decimal value : values) {
            total += value;
        }
        return total;
    }

    private static List<Decimal> weights(List<Decimal> values) {
        return values;
    }

    @IsTest
    static void anEvenSplitKeepsTheResidualInsteadOfLosingIt() {
        List<Decimal> shares = QuoteDocumentAllocation.split(100, weights(new List<Decimal>{ 1, 1, 1 }), 2);

        Assert.areEqual(33.33, shares[0], 'The first share rounds to the cent.');
        Assert.areEqual(33.33, shares[1], 'So does the second.');
        Assert.areEqual(33.34, shares[2], 'The last carries the residual.');
        Assert.areEqual(100, sum(shares), 'The shares sum back exactly.');
    }

    /** Use case 3: $60,000 payable 30% / 40% / 30%. */
    @IsTest
    static void aPaymentScheduleSplitsToTheCent() {
        List<Decimal> shares =
            QuoteDocumentAllocation.split(60000, weights(new List<Decimal>{ 30, 40, 30 }), 2);

        Assert.areEqual(18000, shares[0], 'Signing.');
        Assert.areEqual(24000, shares[1], 'Delivery.');
        Assert.areEqual(18000, shares[2], 'Acceptance.');
        Assert.areEqual(60000, sum(shares), 'The milestones foot to the quote.');
    }

    /** Use case 4: $120,000 allocated 50% / 30% / 20%. */
    @IsTest
    static void aDepartmentAllocationSplitsToTheCent() {
        List<Decimal> shares =
            QuoteDocumentAllocation.split(120000, weights(new List<Decimal>{ 50, 30, 20 }), 2);

        Assert.areEqual(60000, shares[0], 'Headquarters.');
        Assert.areEqual(36000, shares[1], 'West.');
        Assert.areEqual(24000, shares[2], 'East.');
    }

    /** Use case 10: you cannot deliver a third of a device. */
    @IsTest
    static void wholeUnitsAllocateAtScaleZero() {
        List<Decimal> shares =
            QuoteDocumentAllocation.split(1000, weights(new List<Decimal>{ 200, 300, 500 }), 0);

        Assert.areEqual(200, shares[0], 'September.');
        Assert.areEqual(300, shares[1], 'October.');
        Assert.areEqual(500, shares[2], 'November.');
        Assert.areEqual(1000, sum(shares), 'Every device is accounted for.');
    }

    @IsTest
    static void anAwkwardQuantitySplitStillSumsToWholeUnits() {
        List<Decimal> shares = QuoteDocumentAllocation.split(10, weights(new List<Decimal>{ 1, 1, 1 }), 0);

        Assert.areEqual(10, sum(shares), 'Ten units split three ways is still ten units.');
        for (Decimal share : shares) {
            Assert.areEqual(share.setScale(0), share, 'No fractional devices.');
        }
    }

    /**
     * Use case 8: a promotional free month must print 0.00. A free month
     * showing a cent because the rounding had to go somewhere is exactly the
     * defect the last-non-zero rule exists to prevent.
     */
    @IsTest
    static void aZeroWeightGetsZeroAndNeverTheResidual() {
        List<Decimal> shares =
            QuoteDocumentAllocation.split(100, weights(new List<Decimal>{ 0, 0, 1, 1, 1 }), 2);

        Assert.areEqual(0, shares[0], 'Month 1 is free.');
        Assert.areEqual(0, shares[1], 'Month 2 is free.');
        Assert.areEqual(33.34, shares[4], 'The residual lands in the last PAYING month.');
        Assert.areEqual(100, sum(shares), 'And the total is untouched.');
    }

    @IsTest
    static void weightsAreRelativeNotPercentages() {
        List<Decimal> asWhole =
            QuoteDocumentAllocation.split(1000, weights(new List<Decimal>{ 30, 40, 30 }), 2);
        List<Decimal> asFraction =
            QuoteDocumentAllocation.split(1000, weights(new List<Decimal>{ 0.3, 0.4, 0.3 }), 2);

        Assert.areEqual(asWhole, asFraction, 'Proportions, not percentages.');
    }

    @IsTest
    static void weightsThatDoNotSumToOneHundredStillAllocateTheWholeTotal() {
        List<Decimal> shares =
            QuoteDocumentAllocation.split(60000, weights(new List<Decimal>{ 30, 40, 25 }), 2);

        Assert.areEqual(60000, sum(shares),
                        'A relative split still allocates everything - it does not leave 5% behind.');
    }

    @IsTest
    static void aNegativeTotalAllocatesExactly() {
        List<Decimal> shares = QuoteDocumentAllocation.split(-100, weights(new List<Decimal>{ 1, 1, 1 }), 2);

        Assert.areEqual(-100, sum(shares), 'An amendment credit is a real input.');
    }

    @IsTest
    static void aSingleBucketGetsEverything() {
        List<Decimal> shares = QuoteDocumentAllocation.split(1234.56, weights(new List<Decimal>{ 1 }), 2);

        Assert.areEqual(1, shares.size(), 'One weight, one share.');
        Assert.areEqual(1234.56, shares[0], 'And it is the whole amount.');
    }

    @IsTest
    static void emptyWeightsFail() {
        try {
            QuoteDocumentAllocation.split(100, new List<Decimal>(), 2);
            Assert.fail('An allocation across no buckets must fail rather than default to even.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(QuoteDocumentAllocation.ERR_WEIGHTS),
                          'Coded failure: ' + e.getMessage());
        }
    }

    @IsTest
    static void allZeroWeightsFail() {
        try {
            QuoteDocumentAllocation.split(100, weights(new List<Decimal>{ 0, 0 }), 2);
            Assert.fail('There is nowhere for the money to land.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(QuoteDocumentAllocation.ERR_WEIGHTS),
                          'Coded failure: ' + e.getMessage());
        }
    }

    @IsTest
    static void aNegativeWeightFails() {
        try {
            QuoteDocumentAllocation.split(100, weights(new List<Decimal>{ 1, -1, 1 }), 2);
            Assert.fail('A share of a total cannot be negative.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(QuoteDocumentAllocation.ERR_WEIGHTS),
                          'Coded failure: ' + e.getMessage());
        }
    }

    @IsTest
    static void reconcileAcceptsAnExactSplitAndRejectsALostCent() {
        List<Decimal> shares = QuoteDocumentAllocation.split(100, weights(new List<Decimal>{ 1, 1, 1 }), 2);
        QuoteDocumentAllocation.reconcile(100, shares, 'a good split');

        shares[2] = shares[2] - 0.01;
        try {
            QuoteDocumentAllocation.reconcile(100, shares, 'a split missing a cent');
            Assert.fail('A cent is exactly what verify()\'s tolerance would have let through.');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains(QuoteDocumentAllocation.ERR_SOURCE),
                          'Coded failure: ' + e.getMessage());
        }
    }

    /**
     * The case for randomization: exactness is a property, and the splits that
     * break it are the ones nobody would think to write down. Deterministic
     * inputs so a failure is reproducible - a random seed in a test that guards
     * money is a failure you cannot investigate.
     */
    @IsTest
    static void everySplitSumsBackExactly() {
        List<Decimal> totals = new List<Decimal>{
            0, 0.01, 1, 7, 99.99, 100, 1000, 1234.56, 60000, 1000000, -0.01, -1234.56
        };
        List<Integer> scales = new List<Integer>{ 0, 2 };
        Integer checked = 0;

        for (Decimal total : totals) {
            for (Integer scale : scales) {
                for (Integer parts = 1; parts <= 13; parts++) {
                    // Uneven, zero-containing, and even weightings in one pass:
                    // weight i is (i * 7) mod 5, which is 0 for one part in five.
                    List<Decimal> w = new List<Decimal>();
                    Boolean anyNonZero = false;
                    for (Integer i = 0; i < parts; i++) {
                        Decimal weight = Math.mod(i * 7, 5);
                        anyNonZero = anyNonZero || weight != 0;
                        w.add(weight);
                    }
                    if (!anyNonZero) {
                        w[0] = 1;
                    }

                    List<Decimal> shares = QuoteDocumentAllocation.split(total, w, scale);
                    Assert.areEqual(
                        total, sum(shares),
                        'total=' + total + ' parts=' + parts + ' scale=' + scale + ' must sum back exactly'
                    );
                    for (Integer i = 0; i < parts; i++) {
                        if (w[i] == 0) {
                            Assert.areEqual(0, shares[i],
                                            'A zero weight must stay zero: total=' + total + ' i=' + i);
                        }
                    }
                    checked++;
                }
            }
        }

        Assert.areEqual(312, checked, 'Every combination ran.');
    }
}
