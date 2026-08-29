/**
 * The checks that stop a signed document carrying a wrong number.
 *
 * No validation rule can see sibling records, so anything that has to compare
 * a row against its siblings - or a table against what CPQ itself rolled up -
 * lives here rather than in a declarative rule. Split out of
 * QuoteDocumentGenerator: generation orchestrates, this decides whether the
 * result is allowed to reach Complete.
 *
 * Every failure path sets Status__c = 'Failed' on the table before throwing,
 * so the record carries the verdict even though the transaction rolls back and
 * the caller records the message on the Quote.
 */
public with sharing class QuoteDocumentVerification {

    /** Amounts are compared to the cent, not exactly - these are Currency(16,2). */
    private static final Decimal TOLERANCE = 0.01;

    /**
     * Row types that are themselves the OUTPUT of aggregation - a Group
     * Header, Subtotal, Section Total or Grand Total never represents money
     * that exists independently of the rows beneath it. Everything else
     * (Detail, and any customizer-added type such as Discount or Rounding)
     * is a LEAF contribution: real money that has to be accounted for in
     * verify()'s two independent reconciliation paths. This is what lets a
     * customizer introduce a new counted row type without touching verify()
     * itself.
     */
    private static final Set<String> AGGREGATE_ROW_TYPES = new Set<String>{
        'Group Header', 'Subtotal', 'Section Total', 'Grand Total'
    };

    /**
     * Public rather than @TestVisible private: the generator calls this across
     * a class boundary now, which @TestVisible does not permit.
     */
    public static void verify(
        SBQQ__Quote__c quote,
        Quote_Document_Table__c table,
        QuoteDocumentTableDefinition definition,
        List<Quote_Document_Row__c> rows
    ) {
        verify(quote, table, definition, rows, new Set<String>());
    }

    /**
     * As above, with the measures a contributor declared non-additive - see
     * QuoteDocumentRowCustomizerContext.nonAdditiveMeasures. Those are held to
     * the sum-within-group, max-across-groups rule below instead of the
     * additive one. They are never simply skipped: a measure nothing checks is
     * a measure nothing catches.
     */
    public static void verify(
        SBQQ__Quote__c quote,
        Quote_Document_Table__c table,
        QuoteDocumentTableDefinition definition,
        List<Quote_Document_Row__c> rows,
        Set<String> nonAdditiveMeasures
    ) {
        Quote_Document_Row__c grandTotal = findGrandTotal(rows);
        List<String> fields = QuoteDocumentTableDefinition.measureFields(definition.measureSet);
        Set<String> nonAdditive = nonAdditiveMeasures == null ? new Set<String>() : nonAdditiveMeasures;

        // 0. Row_Key__c is only meaningful if it is actually unique within this
        //    table. The field itself cannot enforce that declaratively - the
        //    same key text (e.g. GRAND_TOTAL) is legitimately reused across
        //    different Quotes' tables, so the field is externalId but not
        //    unique - which means nothing stops two different group values
        //    from sanitizing to the same key (buildGroupKey uppercases and
        //    strips to [A-Z0-9_], so "R&D" and "R D" both become "R_D") and
        //    silently inserting as two rows sharing one key. Caught here,
        //    before Complete, rather than discovered later as a row a
        //    consuming template can no longer address unambiguously.
        assertUniqueRowKeys(rows, table);


        // 1. The grand total equals the sum of the included detail rows.
        // 2. It also equals the sum of the outermost subtotals. Two independent
        //    paths to the same number; if they disagree, the grouping dropped
        //    or duplicated a line.
        for (String field : fields) {
            if (nonAdditive.contains(field)) {
                assertSumWithinGroupsMaxAcross(rows, grandTotal, table, definition, field);
                continue;
            }

            Decimal fromDetails = 0;
            Decimal fromSubtotals = 0;

            for (Quote_Document_Row__c row : rows) {
                Decimal value = (Decimal) row.get(field);
                if (value == null) { continue; }

                // A leaf contribution always feeds the detail-rows path. A
                // Detail row also always sits inside a group, so it reaches
                // the subtotal path through that group's own Subtotal row -
                // counting it again here would double it. A leaf with no
                // group of its own (Group_Level__c 0 - a table-wide
                // adjustment such as a Rounding row) has no Subtotal to be
                // captured by, so it has to feed both paths directly or the
                // two paths would never agree.
                Boolean isLeaf = !AGGREGATE_ROW_TYPES.contains(row.Row_Type__c) && row.Include_In_Grand_Total__c;

                if (isLeaf) {
                    fromDetails += value;
                }
                if ((row.Row_Type__c == 'Subtotal' && row.Group_Level__c == 1)
                    || (isLeaf && row.Group_Level__c == 0)) {
                    fromSubtotals += value;
                }
            }

            Decimal stated = (Decimal) grandTotal.get(field);
            stated = stated == null ? 0 : stated;

            if (definition.showDetails) {
                assertClose(stated, fromDetails, table, field + ' grand total vs detail rows');
            }
            assertClose(stated, fromSubtotals, table, field + ' grand total vs level-1 subtotals');
        }

        // 3. The table's own measures match its grand total row.
        for (String field : fields) {
            assertClose((Decimal) table.get(field), (Decimal) grandTotal.get(field),
                        table, field + ' table measure vs grand total row');
        }

        // 4. The check that matters commercially: a price-waterfall table built
        //    from everything except optional products has to land on the same
        //    Net Amount that CPQ itself rolled up onto the Quote.
        Boolean reconcilesToQuote =
            QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL.equals(definition.measureSet)
            && QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL.equals(definition.lineFilter);

        if (reconcilesToQuote) {
            // CPQ's own SBQQ__NetAmount__c has no idea a Discount, Rounding,
            // or any other synthetic row exists - it only knows about real
            // quote lines. A counted row that is not a real line's own
            // Detail row can only ever pull this table's total away from
            // CPQ's, on the one table where the two are required to match
            // to the cent. Caught here rather than left to surface as a
            // baffling one-cent-off failure in the assertion below.
            assertNoSyntheticCountedRows(rows, table);

            if (quote.SBQQ__NetAmount__c != null) {
                assertClose(quote.SBQQ__NetAmount__c, (Decimal) grandTotal.get('Amount_Net__c'),
                            table, 'grand total vs Quote Net Amount');
            }
        }

        // 5. Presentation completeness - step 06 condition 2.
        //
        //    Deliberately LAST. A table whose money does not add up and whose
        //    title is missing has two problems, and the money is the one worth
        //    reporting first: it is the more serious failure and the one a
        //    reader will act on. Running this earlier made a reconciliation
        //    test report a missing title instead, which is exactly the
        //    inversion to avoid.
        //
        //    It belongs in verify() at all for the same reason the money
        //    assertions do: the whole value of the contract is that a renderer
        //    can be dumb, and that only holds while the payload is guaranteed
        //    complete. The moment a title can be blank, the first adapter adds
        //    "if blank, use the table code" and the logic starts leaking back
        //    out one fallback at a time.
        assertPresentationComplete(table);
    }

    /**
     * The rule for a measure that repeats rather than divides: within one
     * group it is a sum, across groups it is a maximum.
     *
     * Licences make it concrete. Two products active in the same month, 100
     * and 50, are 150 licences that month - so the month's subtotal is a sum.
     * The same 150 licences in the next month are not another 150, so the
     * grand total is the largest month, not the sum of them. Taking a maximum
     * over the detail rows instead would answer 100 and understate the peak,
     * which is the wrong direction to be wrong in a document a customer signs.
     */
    private static void assertSumWithinGroupsMaxAcross(
        List<Quote_Document_Row__c> rows,
        Quote_Document_Row__c grandTotal,
        Quote_Document_Table__c table,
        QuoteDocumentTableDefinition definition,
        String field
    ) {
        Map<String, Decimal> leavesByGroup = new Map<String, Decimal>();
        Map<String, Decimal> subtotalByGroup = new Map<String, Decimal>();

        for (Quote_Document_Row__c row : rows) {
            Decimal value = (Decimal) row.get(field);
            if (value == null) { continue; }

            String key = row.Group_Key__c == null ? '' : row.Group_Key__c;

            if (!AGGREGATE_ROW_TYPES.contains(row.Row_Type__c) && row.Include_In_Grand_Total__c) {
                Decimal running = leavesByGroup.containsKey(key) ? leavesByGroup.get(key) : 0;
                leavesByGroup.put(key, running + value);
            } else if (row.Row_Type__c == 'Subtotal' && row.Group_Level__c == 1) {
                subtotalByGroup.put(key, value);
            }
        }

        Decimal peak;
        for (String key : subtotalByGroup.keySet()) {
            Decimal stated = subtotalByGroup.get(key);

            // Only meaningful where the details are actually printed; a
            // summary table has nothing for the subtotal to be a sum OF.
            if (definition.showDetails) {
                Decimal leaves = leavesByGroup.containsKey(key) ? leavesByGroup.get(key) : 0;
                assertClose(stated, leaves, table, field + ' subtotal vs its own rows in group ' + key);
            }
            if (peak == null || stated > peak) { peak = stated; }
        }

        // No level-1 subtotals at all: the leaf groups are the only grouping
        // there is, so they are what the maximum is taken over.
        if (subtotalByGroup.isEmpty()) {
            for (Decimal leaves : leavesByGroup.values()) {
                if (peak == null || leaves > peak) { peak = leaves; }
            }
        }

        Decimal stated = (Decimal) grandTotal.get(field);
        assertClose(stated == null ? 0 : stated, peak == null ? 0 : peak,
                    table, field + ' grand total vs the largest group (non-additive measure)');
    }

    /**
     * A published table must carry everything a renderer needs to print it
     * without asking anything else: a heading, and the locale that heading was
     * resolved for.
     *
     * Columns are deliberately NOT checked here. They are inserted after the
     * table row is stamped but before publication, and re-querying them per
     * table inside verification would add a SOQL call per table to prove
     * something the generator already guarantees structurally - it builds
     * columns for every definition it builds a table for, from the same list.
     * The retrieval-side check in step 07 is where a missing column set is
     * caught, because that is where it would actually do harm.
     */
    private static void assertPresentationComplete(Quote_Document_Table__c table) {
        if (String.isBlank(table.Display_Title__c)) {
            throw QuoteDocumentContributorError.build(
                'TABLE_TITLE_MISSING',
                'Table ' + table.Table_Code__c + ' has no Display_Title__c and cannot be published. A '
                    + 'renderer prints this heading verbatim; there is deliberately no fallback to '
                    + 'Table_Name__c, which is an internal label nobody reviewed for a customer.'
            );
        }
        if (String.isBlank(table.Locale__c)) {
            throw QuoteDocumentContributorError.build(
                'TABLE_LOCALE_MISSING',
                'Table ' + table.Table_Code__c + ' has no Locale__c. Without it nothing can tell which '
                    + 'language this snapshot was resolved in, so a re-render in another locale could not '
                    + 'know it had to regenerate.'
            );
        }
    }

    private static void assertNoSyntheticCountedRows(List<Quote_Document_Row__c> rows, Quote_Document_Table__c table) {
        for (Quote_Document_Row__c row : rows) {
            Boolean isSyntheticCountedLeaf = !AGGREGATE_ROW_TYPES.contains(row.Row_Type__c)
                && row.Row_Type__c != 'Detail'
                && row.Include_In_Grand_Total__c;
            if (isSyntheticCountedLeaf) {
                table.Status__c = 'Failed';
                throw new QuoteDocumentGenerator.QuoteDocumentException(
                    table.Table_Code__c + ': a ' + row.Row_Type__c + ' row ("' + row.Display_Label__c
                    + '") counts toward the grand total, but this table is checked against the Quote '
                    + 'Net Amount - CPQ has no knowledge of that row, so the two can never agree. Keep '
                    + 'Discount, Rounding or other synthetic counted rows off the PRICE_WATERFALL + '
                    + 'EXCLUDE_OPTIONAL table, or set Include_In_Grand_Total__c to false on them.'
                );
            }
        }
    }

    private static void assertUniqueRowKeys(List<Quote_Document_Row__c> rows, Quote_Document_Table__c table) {
        Set<String> seen = new Set<String>();
        for (Quote_Document_Row__c row : rows) {
            if (!seen.add(row.Row_Key__c)) {
                table.Status__c = 'Failed';
                throw new QuoteDocumentGenerator.QuoteDocumentException(
                    table.Table_Code__c + ': duplicate Row_Key__c "' + row.Row_Key__c + '" - '
                    + 'two different rows produced the same key, most likely two grouping values '
                    + 'that sanitize to the same text (e.g. "R&D" and "R D" both become "R_D"). '
                    + 'Adjust the grouping value or the table\'s field path so the two are distinguishable.'
                );
            }
        }
    }

    private static void assertClose(Decimal expected, Decimal actual, Quote_Document_Table__c table, String what) {
        Decimal a = expected == null ? 0 : expected;
        Decimal b = actual == null ? 0 : actual;
        if (Math.abs(a - b) > TOLERANCE) {
            table.Status__c = 'Failed';
            throw new QuoteDocumentGenerator.QuoteDocumentException(
                table.Table_Code__c + ': ' + what + ' - expected ' + a + ', got ' + b
            );
        }
    }

    /**
     * Shared with QuoteDocumentGenerator's stampTable, which writes the grand
     * total's measures onto the table so the two can never disagree.
     */
    public static Quote_Document_Row__c findGrandTotal(List<Quote_Document_Row__c> rows) {
        for (Quote_Document_Row__c row : rows) {
            if (row.Row_Type__c == 'Grand Total') {
                return row;
            }
        }
        throw new QuoteDocumentGenerator.QuoteDocumentException('Table was built without a Grand Total row.');
    }
}
