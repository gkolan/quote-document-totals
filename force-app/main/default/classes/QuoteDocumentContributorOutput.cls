/**
 * Validates what a contributor hands back, before those rows reach the
 * insert or QuoteDocumentVerification.
 *
 * Deliberately only the gaps. QuoteDocumentVerification already rejects
 * duplicate row keys, a missing grand total, and unbalanced subtotals, and
 * the Hidden_Row_Must_Count validation rule already rejects a hidden row that
 * counts toward nothing. Re-checking any of those here would be two places to
 * change and two places to drift. Step 01A section 5 lists exactly which
 * invariants had no owner; this class owns those and nothing else.
 *
 * WHAT THIS CANNOT DO
 * -------------------
 * This validates contributor OUTPUT. It cannot tell you what the contributor
 * DID - a Flow that inserts rows and returns different uninserted ones is
 * invisible here, as is one that updates the Quote or enqueues a Queueable.
 * That is why RETURNED_PERSISTED_ROW is named for what it observes, not for
 * what someone might wish it proved. See step 01A section 2.
 */
public with sharing class QuoteDocumentContributorOutput {

    private static final String GRAND_TOTAL = 'Grand Total';
    private static final String DETAIL = 'Detail';

    public static void validate(List<Quote_Document_Row__c> rows, QuoteDocumentTableDefinition definition) {
        String tableCode = definition.tableCode;

        assertNoPersistedRows(rows, tableCode);
        assertOwnTable(rows, tableCode);
        assertSingleGrandTotal(rows, tableCode);
        assertDisplayOrder(rows, tableCode);
        assertGrandTotalLast(rows, tableCode);
        assertMeasuresInSet(rows, definition);
    }

    /**
     * An Id proves the row is already persisted, which means the contributor
     * inserted it or pulled it back out of the database. Either way core no
     * longer owns the insert, and the savepoint no longer describes what will
     * survive a failure.
     */
    private static void assertNoPersistedRows(List<Quote_Document_Row__c> rows, String tableCode) {
        for (Quote_Document_Row__c row : rows) {
            if (row.Id != null) {
                QuoteDocumentContributorError.fail(
                    QuoteDocumentContributorError.RETURNED_PERSISTED_ROW,
                    'Table ' + tableCode + ': the contributor returned row "' + row.Row_Key__c
                        + '" carrying Id ' + row.Id + ', so it is already saved. Contributors build rows in '
                        + 'memory and core inserts them; a row that is already saved is outside the '
                        + 'transaction core can roll back.'
                );
            }
        }
    }

    /**
     * A contributor is handed one table's rows. Stamping a different table's
     * parent moves a row across tables, past every check scoped to this one.
     * Rows with a null parent are expected - core stamps it at insert.
     */
    private static void assertOwnTable(List<Quote_Document_Row__c> rows, String tableCode) {
        for (Quote_Document_Row__c row : rows) {
            if (row.Quote_Document_Table__c != null) {
                QuoteDocumentContributorError.fail(
                    QuoteDocumentContributorError.FOREIGN_TABLE,
                    'Table ' + tableCode + ': the contributor returned row "' + row.Row_Key__c
                        + '" with Quote_Document_Table__c already set to ' + row.Quote_Document_Table__c
                        + '. Core assigns the parent table at insert; setting it in a contributor either '
                        + 'moves the row to another table or pins it to a table this generation is about to '
                        + 'delete and replace.'
                );
            }
        }
    }

    /**
     * QuoteDocumentVerification.findGrandTotal returns the FIRST match, so a
     * second grand total is not merely redundant - it is invisible, and
     * reconciliation silently checks one of the two while the renderer prints
     * both.
     */
    private static void assertSingleGrandTotal(List<Quote_Document_Row__c> rows, String tableCode) {
        List<String> found = new List<String>();
        for (Quote_Document_Row__c row : rows) {
            if (GRAND_TOTAL.equals(row.Row_Type__c)) {
                found.add(row.Row_Key__c);
            }
        }
        if (found.size() > 1) {
            QuoteDocumentContributorError.fail(
                QuoteDocumentContributorError.MULTIPLE_GRAND_TOTALS,
                'Table ' + tableCode + ' has ' + found.size() + ' Grand Total rows after customization ('
                    + String.join(found, ', ') + '). Reconciliation only ever checks the first, so the '
                    + 'others would print unverified.'
            );
        }
    }

    /** Display_Order__c is the render contract's only ordering. A null or a tie makes the printed order arbitrary. */
    private static void assertDisplayOrder(List<Quote_Document_Row__c> rows, String tableCode) {
        Map<Decimal, String> keyByOrder = new Map<Decimal, String>();
        for (Quote_Document_Row__c row : rows) {
            if (row.Display_Order__c == null) {
                QuoteDocumentContributorError.fail(
                    QuoteDocumentContributorError.DUPLICATE_DISPLAY_ORDER,
                    'Table ' + tableCode + ': row "' + row.Row_Key__c + '" has no Display_Order__c. '
                        + 'Renderers print in Display_Order__c and nothing else, so a null makes this row\'s '
                        + 'position arbitrary. Use context.newRow(), which assigns one.'
                );
            }
            if (keyByOrder.containsKey(row.Display_Order__c)) {
                QuoteDocumentContributorError.fail(
                    QuoteDocumentContributorError.DUPLICATE_DISPLAY_ORDER,
                    'Table ' + tableCode + ': rows "' + keyByOrder.get(row.Display_Order__c) + '" and "'
                        + row.Row_Key__c + '" share Display_Order__c ' + row.Display_Order__c
                        + '. Their printed order would depend on query order, so two renderers could '
                        + 'legitimately print the same snapshot differently.'
                );
            }
            keyByOrder.put(row.Display_Order__c, row.Row_Key__c);
        }
    }

    /**
     * No DETAIL row may print after the Grand Total.
     *
     * Deliberately this narrow, and it took two wrong attempts to get here.
     *
     * "Nothing after the Grand Total" and then "nothing COUNTED after the
     * Grand Total" both looked more principled and both were wrong: they fail
     * three shipped, documented, tested customizers. Discount and Rounding
     * append counted adjustment rows below the total, and EstimatedTax appends
     * an uncounted one. That is not sloppiness - context.newRow() assigns
     * Display_Order__c after the current highest precisely so a contributor
     * appends, and verify() reconciles on the inclusion flags, never on order.
     * An adjustment printed under the total it adjusts is ordinary document
     * practice.
     *
     * What is genuinely wrong is a DETAIL row - a line item - stranded below
     * the total, which reads as an item the customer was not charged for.
     * Step 01A section 5 says "Detail after it" and means it literally.
     *
     * If a future table needs the stricter rule, it belongs in that table's
     * config, not here: a global invariant that contradicts the framework's
     * own append convention would just be switched off.
     */
    private static void assertGrandTotalLast(List<Quote_Document_Row__c> rows, String tableCode) {
        Decimal grandTotalOrder = null;
        String grandTotalKey = null;
        for (Quote_Document_Row__c row : rows) {
            if (GRAND_TOTAL.equals(row.Row_Type__c)) {
                grandTotalOrder = row.Display_Order__c;
                grandTotalKey = row.Row_Key__c;
            }
        }
        if (grandTotalOrder == null) {
            // No grand total at all is QuoteDocumentVerification's error to
            // raise, with its own message. Staying quiet here keeps one owner.
            return;
        }

        for (Quote_Document_Row__c row : rows) {
            if (DETAIL.equals(row.Row_Type__c) && row.Display_Order__c > grandTotalOrder) {
                QuoteDocumentContributorError.fail(
                    QuoteDocumentContributorError.ROW_ORDER_INVALID,
                    'Table ' + tableCode + ': Detail row "' + row.Row_Key__c + '" (Display_Order__c '
                        + row.Display_Order__c + ') prints after the Grand Total "' + grandTotalKey + '" ('
                        + grandTotalOrder + '). A line item below the total reads as something the customer '
                        + 'was not charged for. Adjustment rows - Discount, Rounding, Informational, Note - '
                        + 'may print after the total; Detail rows may not.'
                );
            }
        }
    }

    /**
     * A measure outside the table's set is written by nothing, reconciled by
     * nothing, and exposed as a column by nothing - so a contributor filling
     * one has done work that silently never appears. Checked against the
     * definition's own measure list, so the two cannot drift.
     */
    private static void assertMeasuresInSet(
        List<Quote_Document_Row__c> rows, QuoteDocumentTableDefinition definition
    ) {
        Set<String> allowed = new Set<String>(
            QuoteDocumentTableDefinition.measureFields(definition.measureSet)
        );
        Set<String> everyMeasure = new Set<String>(
            QuoteDocumentTableDefinition.measureFields(QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL)
        );
        everyMeasure.addAll(
            QuoteDocumentTableDefinition.measureFields(QuoteDocumentTableDefinition.MEASURES_CHANGE)
        );

        for (Quote_Document_Row__c row : rows) {
            for (String field : row.getPopulatedFieldsAsMap().keySet()) {
                if (everyMeasure.contains(field) && !allowed.contains(field)
                    && row.get(field) != null) {
                    QuoteDocumentContributorError.fail(
                        QuoteDocumentContributorError.ROW_MEASURE_MISMATCH,
                        'Table ' + definition.tableCode + ' uses measure set ' + definition.measureSet
                            + ', but row "' + row.Row_Key__c + '" sets ' + field + '. That measure is never '
                            + 'reconciled or printed for this table, so the value would be stored and then '
                            + 'silently ignored.'
                    );
                }
            }
        }
    }
}
