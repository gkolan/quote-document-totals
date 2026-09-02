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
     * The locale this table is being generated for, passed through to a Flow
     * contributor so it can pick the right wording without reading the running
     * user's locale - which would make the snapshot depend on who clicked
     * generate, and it must not.
     *
     * Null until step 03 resolves locale per quote. Contributors must treat
     * null as "not yet configured" and fall back to the org default, never
     * blank the text.
     */
    public String locale;

    /** The quote's currency, or null in a single-currency org. Contributors format with it; they must not re-derive it. */
    public String currencyIsoCode;

    /**
     * The label dictionary for this snapshot's locale.
     *
     * Contributors are held to the same rule as core: no printable string is
     * built by concatenation. Without this the seam would quietly reintroduce
     * the hardcoded English step 03 exists to remove - and a shipped
     * customizer did exactly that until this was added.
     */
    public QuoteDocumentLabels labels;

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
     * Measures this table's rows carry that must NOT be summed into the grand
     * total - declared by the contributor, because only the contributor knows
     * what its rows mean.
     *
     * The case this exists for: a monthly breakdown repeats the same licence
     * count in every month it is active, so the licences are not twelve
     * separate quantities to be added. Summing them prints "1,200 licences"
     * for a customer who has 100. Left additive, QuoteDocumentVerification
     * would also reject the correct answer, since a peak of 100 does not equal
     * the 1,200 its leaf rows sum to.
     *
     * A measure named here is verified under the sum-within-group,
     * max-across-groups rule instead of the additive one - it is checked
     * differently, never left unchecked. An unverified measure is exactly
     * where a wrong number ships quietly.
     *
     * See docs/quote-document-extension-recipes.md.
     */
    public Set<String> nonAdditiveMeasures = new Set<String>();

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
