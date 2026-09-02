/**
 * Step 01A section 5. One test per error code, each asserting the CODE and
 * the offending row or table - never merely that an exception was thrown,
 * which is the assertion that passes when the wrong thing fails.
 *
 * These run without a Quote: contributor output validation is a pure function
 * of the rows and the definition, so testing it through full generation would
 * hide which check fired behind a fixture.
 */
@IsTest
private class QuoteDocumentContributorOutputTest {

    private static QuoteDocumentTableDefinition definition(String measureSet) {
        QuoteDocumentTableDefinition def = QuoteDocumentTableDefinition.build(
            'OUTPUT_TEST',
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        def.measureSet = measureSet;
        return def;
    }

    private static QuoteDocumentTableDefinition definition() {
        return definition(QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL);
    }

    private static Quote_Document_Row__c row(String rowType, String key, Integer order) {
        return QuoteDocumentRowBuilder.defaultRow(rowType, 1, key, key, order);
    }

    /** The shape every test starts from: one detail row, one grand total, correctly ordered. */
    private static List<Quote_Document_Row__c> validRows() {
        return new List<Quote_Document_Row__c>{
            row('Detail', 'D1', 10),
            row('Grand Total', 'GT', 20)
        };
    }

    private static String failureFrom(List<Quote_Document_Row__c> rows, QuoteDocumentTableDefinition def) {
        try {
            QuoteDocumentContributorOutput.validate(rows, def);
            return null;
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            return e.getMessage();
        }
    }

    @IsTest
    static void validRowsPassSoTheOtherTestsProveSomething() {
        Assert.isNull(
            failureFrom(validRows(), definition()),
            'A correctly shaped table must pass, or every other assertion here is meaningless.'
        );
    }

    /**
     * A syntactically valid Id for a type without inserting anything. The key
     * prefix must match the SObject or Apex rejects the assignment, which is
     * why this is read from the describe rather than hard-coded - the prefix
     * differs between orgs.
     */
    private static Id fakeId(Schema.SObjectType type) {
        return Id.valueOf(type.getDescribe().getKeyPrefix() + '000000000001');
    }

    @IsTest
    static void aReturnedRowCarryingAnIdIsRejected() {
        List<Quote_Document_Row__c> rows = validRows();
        rows[0].Id = fakeId(Quote_Document_Row__c.SObjectType);

        String message = failureFrom(rows, definition());
        Assert.isNotNull(message, 'A persisted row must be rejected.');
        Assert.isTrue(
            message.contains(QuoteDocumentContributorError.RETURNED_PERSISTED_ROW),
            'Wrong code: ' + message
        );
        Assert.isTrue(message.contains('D1'), 'The message must name the offending row: ' + message);
    }

    @IsTest
    static void aRowStampedWithAnotherTableIsRejected() {
        List<Quote_Document_Row__c> rows = validRows();
        rows[0].Quote_Document_Table__c = fakeId(Quote_Document_Table__c.SObjectType);

        String message = failureFrom(rows, definition());
        Assert.isNotNull(message, 'A row with a parent table already set must be rejected.');
        Assert.isTrue(message.contains(QuoteDocumentContributorError.FOREIGN_TABLE), 'Wrong code: ' + message);
        Assert.isTrue(message.contains('D1'), 'The message must name the offending row: ' + message);
    }

    /**
     * The one QuoteDocumentVerification cannot catch: findGrandTotal returns
     * the first match, so a second grand total is not rejected there - it is
     * simply never looked at.
     */
    @IsTest
    static void twoGrandTotalsAreRejected() {
        List<Quote_Document_Row__c> rows = validRows();
        rows.add(row('Grand Total', 'GT2', 30));

        String message = failureFrom(rows, definition());
        Assert.isNotNull(message, 'Two grand totals must be rejected.');
        Assert.isTrue(
            message.contains(QuoteDocumentContributorError.MULTIPLE_GRAND_TOTALS),
            'Wrong code: ' + message
        );
        Assert.isTrue(message.contains('GT2'), 'The message must name both grand totals: ' + message);
    }

    @IsTest
    static void aNullDisplayOrderIsRejected() {
        List<Quote_Document_Row__c> rows = validRows();
        rows[0].Display_Order__c = null;

        String message = failureFrom(rows, definition());
        Assert.isNotNull(message, 'A null Display_Order__c must be rejected.');
        Assert.isTrue(
            message.contains(QuoteDocumentContributorError.DUPLICATE_DISPLAY_ORDER),
            'Wrong code: ' + message
        );
        Assert.isTrue(message.contains('D1'), 'The message must name the offending row: ' + message);
    }

    @IsTest
    static void aDuplicateDisplayOrderIsRejected() {
        List<Quote_Document_Row__c> rows = validRows();
        rows[0].Display_Order__c = 20;

        String message = failureFrom(rows, definition());
        Assert.isNotNull(message, 'Two rows sharing a Display_Order__c must be rejected.');
        Assert.isTrue(
            message.contains(QuoteDocumentContributorError.DUPLICATE_DISPLAY_ORDER),
            'Wrong code: ' + message
        );
        Assert.isTrue(
            message.contains('D1') && message.contains('GT'),
            'The message must name both colliding rows: ' + message
        );
    }

    @IsTest
    static void aDetailRowAfterTheGrandTotalIsRejected() {
        List<Quote_Document_Row__c> rows = validRows();
        rows.add(row('Detail', 'D_LATE', 30));

        String message = failureFrom(rows, definition());
        Assert.isNotNull(message, 'A Detail row below the Grand Total must be rejected.');
        Assert.isTrue(message.contains(QuoteDocumentContributorError.ROW_ORDER_INVALID), 'Wrong code: ' + message);
        Assert.isTrue(message.contains('D_LATE'), 'The message must name the offending row: ' + message);
    }

    /**
     * The counterpart, and the reason this check is narrow. Three shipped
     * customizers append an adjustment row below the total - Discount,
     * Rounding, EstimatedTax - because context.newRow() appends and verify()
     * reconciles on inclusion flags, not order. A stricter rule would fail
     * them, so it is pinned here rather than left to be "tidied up" later.
     */
    @IsTest
    static void adjustmentRowsMayPrintAfterTheGrandTotal() {
        for (String rowType : new List<String>{ 'Informational', 'Note', 'Rounding', 'Discount' }) {
            List<Quote_Document_Row__c> rows = validRows();
            rows.add(row(rowType, 'ADJ', 30));

            Assert.isNull(
                failureFrom(rows, definition()),
                rowType + ' must be allowed after the Grand Total - an adjustment printed under the total '
                    + 'it adjusts is ordinary document practice, and shipped customizers rely on it.'
            );
        }
    }

    @IsTest
    static void aMeasureOutsideTheTablesSetIsRejected() {
        List<Quote_Document_Row__c> rows = validRows();
        // Amount_Net_Change__c belongs to CHANGE; this table is PRICE_WATERFALL.
        rows[0].Amount_Net_Change__c = 25;

        String message = failureFrom(rows, definition());
        Assert.isNotNull(message, 'A measure outside the table\'s set must be rejected.');
        Assert.isTrue(message.contains(QuoteDocumentContributorError.ROW_MEASURE_MISMATCH), 'Wrong code: ' + message);
        Assert.isTrue(
            message.contains('Amount_Net_Change__c'),
            'The message must name the offending measure: ' + message
        );
    }

    @IsTest
    static void aMeasureInsideTheTablesSetIsAccepted() {
        List<Quote_Document_Row__c> rows = validRows();
        rows[0].Amount_Net__c = 25;

        Assert.isNull(
            failureFrom(rows, definition()),
            'Amount_Net__c is part of PRICE_WATERFALL and must be accepted.'
        );
    }

    /** No grand total at all stays QuoteDocumentVerification's error, so the two do not both claim it. */
    @IsTest
    static void aMissingGrandTotalIsLeftToVerification() {
        List<Quote_Document_Row__c> rows = new List<Quote_Document_Row__c>{ row('Detail', 'D1', 10) };

        Assert.isNull(
            failureFrom(rows, definition()),
            'A missing Grand Total is QuoteDocumentVerification\'s failure to report, with its own message. '
                + 'Two owners for one invariant means two messages that drift apart.'
        );
    }
}
