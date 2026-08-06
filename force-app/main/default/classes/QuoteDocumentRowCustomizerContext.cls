/**
 * Everything a QuoteDocumentRowCustomizer needs to decide what one table's
 * rows should look like. A plain, mutable data holder passed by reference -
 * not an API surface that needs guarding, since only generation code and the
 * customizer it invokes ever see an instance.
 */
public class QuoteDocumentRowCustomizerContext {

    /** The Quote being generated for, with its normalized SBQQ__QuoteLine__c children already queried. */
    public SBQQ__Quote__c quote;

    /** The table definition this customizer is attached to (Table_Code__c, Line_Filter__c, Measure_Set__c, ...). */
    public QuoteDocumentTableDefinition definition;

    /** Every line that survived this table's Line_Filter__c, in quote-line order. Read-only in practice - editing it after the fact has no effect, since grouping already ran. */
    public List<QuoteDocumentLine> lines;

    /**
     * The rows QuoteDocumentRowBuilder produced for this table, in render
     * order (group headers, subtotals, details, then the grand total last).
     * Modify in place - add, remove, or edit rows and their measure fields -
     * or return a different list from customize(). Two constraints still
     * apply after customize() runs: Row_Key__c must stay unique within the
     * table, and the list must contain exactly one Row_Type__c = 'Grand
     * Total' row. Use newRow() to add a row with the same defaults the
     * builder itself uses.
     */
    public List<Quote_Document_Row__c> rows;

    /**
     * Allocates a new row the same way QuoteDocumentRowBuilder does: detail
     * rows count toward subtotals and the grand total, every other row type
     * (Group Header, Subtotal, Section Total, Grand Total) does not, and
     * Display_Order__c is assigned after the current highest order in rows
     * so it prints last unless set explicitly afterward. The row is appended
     * to context.rows and returned so the caller can set measure fields,
     * Quote_Line__c, Group_Dimension__c, etc. before generation continues.
     */
    public Quote_Document_Row__c newRow(String rowType, Integer groupLevel, String rowKey, String displayLabel) {
        Quote_Document_Row__c row = QuoteDocumentRowBuilder.defaultRow(
            rowType, groupLevel, rowKey, displayLabel, nextDisplayOrder()
        );
        rows.add(row);
        return row;
    }

    private Integer nextDisplayOrder() {
        Decimal maxOrder = 0;
        for (Quote_Document_Row__c row : rows) {
            if (row.Display_Order__c != null && row.Display_Order__c > maxOrder) {
                maxOrder = row.Display_Order__c;
            }
        }
        return Integer.valueOf(maxOrder) + 10;
    }
}
