/**
 * Step 01A section 4 gate. The Flow contribution seam is designed around one
 * unproven assumption: that uninserted Quote_Document_Row__c records survive a
 * Flow.Interview round trip intact. The spec forbids building on it unproven,
 * so this class proves it - or fails loudly enough that the fallback (Apex
 * defined types, then JSON as last resort) gets chosen deliberately.
 *
 * Each test maps to one checkbox of the step 01A section 4 matrix. Names say
 * which. Nothing here is a contributor and nothing is registered; delete this
 * class only together with the gate it discharges.
 */
@IsTest
private class QuoteDocumentFlowRoundTripProbeTest {

    private static final String PROBE_FLOW = 'QuoteDocumentFlowRoundTripProbe';

    /**
     * Budgets for the 1000-row round trip, set against the measured cost
     * (685ms CPU, ~329KB heap on 2026-08-27) rather than against the governor
     * limits. Asserting below the platform ceiling - 10,000ms CPU, 6MB heap -
     * would be asserting nothing: Apex throws its own LimitException first, so
     * the test could never be the thing that failed.
     *
     * These leave roughly 4x CPU and 6x heap headroom, enough to absorb org
     * variance without letting an order-of-magnitude regression through.
     * Deliberately not tuned tight: this is a viability tripwire on the round
     * trip alone. The real budget, measured across whole generation at the
     * supported maximum, belongs to step 01A section 9 and spec section 8.7,
     * and should be stricter than anything here.
     */
    private static final Integer CPU_BUDGET_MS = 3000;
    private static final Integer HEAP_BUDGET_BYTES = 2000000;

    /** Mirrors what the bridge will pass, so the probe exercises the real input shape. */
    private static Map<String, Object> inputs(List<Quote_Document_Row__c> rows) {
        return new Map<String, Object>{
            'rows'            => rows,
            'quoteId'         => '0Q0000000000000AAA',
            'tableCode'       => 'PROBE_TABLE',
            'locale'          => 'en_US',
            'currencyIsoCode' => 'USD'
        };
    }

    private static List<Quote_Document_Row__c> runProbe(List<Quote_Document_Row__c> rows) {
        Flow.Interview interview = Flow.Interview.createInterview(PROBE_FLOW, inputs(rows));
        interview.start();
        return (List<Quote_Document_Row__c>) interview.getVariableValue('rows');
    }

    /**
     * Three rows whose values are chosen to catch coercion, not to be realistic:
     * a trailing-zero decimal (scale), a deliberately null measure (null vs 0),
     * both inclusion booleans in both states, and two fields core's builder
     * never populates - standing in for a subscriber-added field, since the
     * round trip has no notion of which fields core owns.
     */
    private static List<Quote_Document_Row__c> probeRows() {
        return new List<Quote_Document_Row__c>{
            new Quote_Document_Row__c(
                Row_Type__c = 'Detail',
                Group_Level__c = 1,
                Row_Key__c = 'R1',
                Display_Label__c = 'First',
                Display_Order__c = 10,
                Amount_Net__c = 1234.5600,
                Amount_List__c = null,
                Quantity__c = 3,
                Product_Code__c = 'SKU-1',
                Charge_Type__c = 'Recurring',
                Is_Displayed__c = true,
                Include_In_Subtotal__c = true,
                Include_In_Grand_Total__c = true
            ),
            new Quote_Document_Row__c(
                Row_Type__c = 'Subtotal',
                Group_Level__c = 1,
                Row_Key__c = 'R2',
                Display_Label__c = 'Second',
                Display_Order__c = 20,
                Amount_Net__c = 1234.5600,
                Is_Displayed__c = false,
                Include_In_Subtotal__c = false,
                Include_In_Grand_Total__c = false
            ),
            new Quote_Document_Row__c(
                Row_Type__c = 'Grand Total',
                Group_Level__c = 0,
                Row_Key__c = 'R3',
                Display_Label__c = 'Third',
                Display_Order__c = 30,
                Amount_Net__c = 2469.1200,
                Is_Displayed__c = true,
                Include_In_Subtotal__c = false,
                Include_In_Grand_Total__c = false
            )
        };
    }

    /** Matrix: existing rows return in the same order. */
    @IsTest
    static void existingRowsReturnInTheSameOrder() {
        Test.startTest();
        List<Quote_Document_Row__c> out = runProbe(probeRows());
        Test.stopTest();

        Assert.isNotNull(out, 'The probe returned no rows collection at all - the seam cannot be built on Flow record collections.');
        Assert.areEqual(4, out.size(), 'Expected the three input rows plus the one the Flow created.');
        Assert.areEqual('R1', out[0].Row_Key__c, 'Input order was not preserved.');
        Assert.areEqual('R2', out[1].Row_Key__c, 'Input order was not preserved.');
        Assert.areEqual('R3', out[2].Row_Key__c, 'Input order was not preserved.');
    }

    /** Matrix: Decimal scale and nulls are preserved. A null measure must not come back as zero. */
    @IsTest
    static void decimalScaleAndNullsSurvive() {
        Test.startTest();
        List<Quote_Document_Row__c> out = runProbe(probeRows());
        Test.stopTest();

        Assert.areEqual(1234.5600, out[0].Amount_Net__c, 'Decimal value did not survive the round trip.');
        Assert.areEqual(
            String.valueOf(1234.5600),
            String.valueOf(out[0].Amount_Net__c),
            'Decimal scale changed across the round trip - a rendered amount would print with different precision than it was generated with.'
        );
        Assert.isNull(
            out[0].Amount_List__c,
            'A null measure came back non-null. Null and zero are different in this framework: zero counts toward a total, null means the measure does not apply.'
        );
        Assert.areEqual(3, out[0].Quantity__c, 'Quantity did not survive the round trip.');
    }

    /** Matrix: the inclusion and visibility booleans survive, in both states. */
    @IsTest
    static void inclusionFlagsSurviveInBothStates() {
        Test.startTest();
        List<Quote_Document_Row__c> out = runProbe(probeRows());
        Test.stopTest();

        Assert.isTrue(out[0].Is_Displayed__c, 'Is_Displayed__c true did not survive.');
        Assert.isTrue(out[0].Include_In_Subtotal__c, 'Include_In_Subtotal__c true did not survive.');
        Assert.isTrue(out[0].Include_In_Grand_Total__c, 'Include_In_Grand_Total__c true did not survive.');

        Assert.isFalse(out[1].Is_Displayed__c, 'Is_Displayed__c false did not survive.');
        Assert.isFalse(out[1].Include_In_Subtotal__c, 'Include_In_Subtotal__c false did not survive.');
        Assert.isFalse(out[1].Include_In_Grand_Total__c, 'Include_In_Grand_Total__c false did not survive.');
    }

    /**
     * Matrix: fields added to Quote_Document_Row__c outside core survive.
     * Product_Code__c and Charge_Type__c stand in - the round trip copies the
     * SObject, so whether core or a subscriber declared a field is not a
     * distinction the mechanism can make. If these survive, a subscriber field does.
     */
    @IsTest
    static void fieldsCoreDoesNotPopulateSurvive() {
        Test.startTest();
        List<Quote_Document_Row__c> out = runProbe(probeRows());
        Test.stopTest();

        Assert.areEqual('SKU-1', out[0].Product_Code__c, 'A field the builder never sets was dropped by the round trip.');
        Assert.areEqual('Recurring', out[0].Charge_Type__c, 'A field the builder never sets was dropped by the round trip.');
    }

    /** Matrix: a change made inside the Flow reaches Apex - otherwise the seam contributes nothing. */
    @IsTest
    static void mutationInsideTheFlowReachesApex() {
        Test.startTest();
        List<Quote_Document_Row__c> out = runProbe(probeRows());
        Test.stopTest();

        Assert.areEqual('First:FLOW', out[0].Display_Label__c, 'The Flow mutated a label and the change did not come back.');
        Assert.areEqual('Second:FLOW', out[1].Display_Label__c, 'The Flow mutated a label and the change did not come back.');
    }

    /** Matrix: rows created inside the Flow arrive back, carrying every field the Flow set. */
    @IsTest
    static void rowsCreatedInsideTheFlowArriveBack() {
        Test.startTest();
        List<Quote_Document_Row__c> out = runProbe(probeRows());
        Test.stopTest();

        Quote_Document_Row__c created = out[out.size() - 1];
        Assert.areEqual('FLOW_PROBE', created.Row_Key__c, 'The Flow-created row did not come back.');
        Assert.areEqual('Note', created.Row_Type__c, 'The Flow-created row lost its Row_Type__c.');
        Assert.areEqual('PROBE_TABLE', created.Display_Label__c, 'A scalar input variable did not reach the Flow.');
        Assert.areEqual(12.34, created.Amount_Net__c, 'The Flow-created row lost its measure.');
        Assert.areEqual(9990, created.Display_Order__c, 'The Flow-created row lost its Display_Order__c.');
        Assert.isNull(created.Id, 'The Flow-created row carries an Id, so the Flow inserted it. Core must own every row insert.');
    }

    /** Matrix: an empty input collection round trips without error and is distinguishable from null. */
    @IsTest
    static void emptyInputCollectionRoundTrips() {
        Test.startTest();
        List<Quote_Document_Row__c> out = runProbe(new List<Quote_Document_Row__c>());
        Test.stopTest();

        Assert.isNotNull(out, 'An empty input produced a null output; the bridge could not tell "no output" from "no rows".');
        Assert.areEqual(1, out.size(), 'Expected only the row the Flow created.');
    }

    /** Matrix: no input row is left carrying an Id, so nothing the Flow returns is already persisted. */
    @IsTest
    static void noReturnedRowIsPersisted() {
        Test.startTest();
        List<Quote_Document_Row__c> out = runProbe(probeRows());
        Test.stopTest();

        for (Quote_Document_Row__c row : out) {
            Assert.isNull(row.Id, 'A returned row carries an Id: ' + row.Row_Key__c);
        }
    }

    /**
     * Matrix: largest supported table, CPU and heap recorded against budget.
     * The budget is deliberately generous - this measures whether the round
     * trip is viable at all, not the final performance gate, which step 01A
     * section 9 owns. It fails only on an order-of-magnitude problem.
     */
    @IsTest
    static void largestSupportedTableStaysWithinBudget() {
        List<Quote_Document_Row__c> rows = new List<Quote_Document_Row__c>();
        for (Integer i = 0; i < 1000; i++) {
            rows.add(new Quote_Document_Row__c(
                Row_Type__c = 'Detail',
                Group_Level__c = 1,
                Row_Key__c = 'R' + i,
                Display_Label__c = 'Row ' + i,
                Display_Order__c = (i + 1) * 10,
                Amount_Net__c = 10.25,
                Is_Displayed__c = true,
                Include_In_Subtotal__c = true,
                Include_In_Grand_Total__c = true
            ));
        }

        Test.startTest();
        Integer cpuBefore = Limits.getCpuTime();
        Integer heapBefore = Limits.getHeapSize();
        List<Quote_Document_Row__c> out = runProbe(rows);
        Integer cpuUsed = Limits.getCpuTime() - cpuBefore;
        Integer heapUsed = Limits.getHeapSize() - heapBefore;
        Test.stopTest();

        Assert.areEqual(1001, out.size(), 'The large collection did not round trip completely.');
        System.debug(LoggingLevel.ERROR, 'FLOW_ROUND_TRIP_BUDGET rows=1000 cpuMs=' + cpuUsed + ' heapBytes=' + heapUsed);
        Assert.isTrue(
            cpuUsed < CPU_BUDGET_MS,
            'A 1000-row round trip used ' + cpuUsed + 'ms CPU against a ' + CPU_BUDGET_MS
                + 'ms budget, leaving too little headroom for generation itself.'
        );
        Assert.isTrue(
            heapUsed < HEAP_BUDGET_BYTES,
            'A 1000-row round trip used ' + heapUsed + ' bytes of heap against a ' + HEAP_BUDGET_BYTES + ' byte budget.'
        );
        Assert.isTrue(Limits.getQueries() < 10, 'The round trip consumed SOQL queries it should not need.');
    }
}
