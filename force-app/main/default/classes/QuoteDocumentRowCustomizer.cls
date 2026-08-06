/**
 * Extension point for table-specific row logic that the declarative
 * grouping/filter/measure config on Quote_Document_Table_Def__mdt cannot
 * express - e.g. injecting a row that isn't derived from any single quote
 * line, suppressing a row a generic filter can't target, or recalculating a
 * measure with logic specific to one table.
 *
 * Reference an implementing class through that table definition's
 * Row_Customizer_Code__c value, resolved by QuoteDocumentRowCustomizerRegistry.
 * QuoteDocumentGenerator calls customize() once per table, after
 * QuoteDocumentRowBuilder has produced the full row list (group headers,
 * subtotals, details, grand total) but before the rows are inserted - so a
 * customization still passes through the same unique-row-key and
 * grand-total-reconciliation checks every table is held to. A customizer
 * that removes a row, retotals a subtotal, or adds a row without updating
 * the grand total will fail generation there rather than shipping a
 * document with a number that doesn't add up.
 *
 * Implementations must be registered in QuoteDocumentRowCustomizerRegistry
 * under their code.
 *
 * THREE ROW TYPES THAT ONLY EXIST THROUGH THIS EXTENSION POINT
 * --------------------------------------------------------------
 * QuoteDocumentRowBuilder never emits these on its own - there is no
 * declarative config path to any of them:
 *
 *   Informational - a row with an amount that must NOT count toward any
 *     total (e.g. an estimated-tax line). See QuoteDocumentEstimatedTaxRowCustomizer.
 *   Discount      - a row with an amount that MUST count toward the total,
 *     typically tied to the one Quote_Line__c it discounts. Follows the same
 *     leaf-contribution rule as Detail; see verify()'s AGGREGATE_ROW_TYPES.
 *   Rounding      - a whole-table adjustment (Group_Level__c = 0, not tied to
 *     any line) that MUST count toward the grand total only, never a
 *     subtotal. See QuoteDocumentRoundingRowCustomizer for a full
 *     example, including why it must never appear on a table verify() checks
 *     against the Quote's own Net Amount.
 *   Note          - a row with no amount at all, for free-text content
 *     (disclaimers, terms). Unconstrained the same way Informational is.
 *
 * Any row your customizer adds that sets Include_In_Grand_Total__c = true is
 * automatically folded into verify()'s reconciliation as a leaf contribution,
 * whatever Row_Type__c you gave it - you do not need to touch
 * QuoteDocumentGenerator to introduce a new counted row type.
 */
public interface QuoteDocumentRowCustomizer {
    /**
     * Return the row list to persist. Most implementations mutate and return
     * context.rows; returning a different list is also honored. Returning
     * null is treated the same as returning context.rows unchanged.
     */
    List<Quote_Document_Row__c> customize(QuoteDocumentRowCustomizerContext context);
}
