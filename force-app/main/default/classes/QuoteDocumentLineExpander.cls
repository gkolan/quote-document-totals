/**
 * Turns one quote line into several document entries along a declared axis.
 *
 * WHY THIS EXISTS BESIDE QuoteDocumentRowCustomizer, NOT INSTEAD OF IT
 * -------------------------------------------------------------------
 * Every declarative table shape in this framework GROUPS: one quote line
 * becomes exactly one Detail row, in exactly one bucket. An expander
 * MULTIPLIES - a line running months 7 to 10 has to appear four times. That is
 * a different operation, and Quote_Document_Grouping__mdt cannot express it at
 * any level.
 *
 * An expander runs BEFORE QuoteDocumentRowBuilder and hands it a longer list
 * of lines, each stamped with the bucket it belongs to. Everything downstream -
 * grouping, subtotals, ordering, labels, verification - is untouched code.
 * QuoteDocumentMonthlyRowCustomizer took the other route, replacing the
 * builder's rows entirely, and paid for it by re-implementing grouping,
 * subtotals and ordering that already existed.
 *
 * The practical consequence: because the bucket is an ordinary grouping
 * dimension (EXPANSION), "year then product family" and "product family then
 * year" are both a metadata change, not a second class.
 *
 * WHY placements() RETURNS WEIGHTS AND NOT JUST KEYS
 * --------------------------------------------------
 * Weight is knowledge only the expander has: a promotional schedule's free
 * months, a delivery's 200/300/500 split, a phase's percentages. If this
 * returned bare bucket keys, allocation would have to re-derive the weights
 * from a field path that does not exist for half the dimensions - and the two
 * halves of one data flow would drift apart. The weight travels on the
 * placement that created it.
 *
 * Implementations register in QuoteDocumentExpanderRegistry under a code, and
 * a table definition names that code in Expander_Code__c.
 *
 * See docs/quote-document-extension-recipes.md.
 */
public interface QuoteDocumentLineExpander {

    /**
     * Every bucket this table prints, in order, whether or not any line
     * occupies it. A month with nothing running in it is still a month the
     * document shows - an absent month reads as a gap in service.
     *
     * Throw QuoteDocumentContributorError rather than returning an empty or
     * guessed axis. A grid derived from nothing puts every product in a period
     * nobody chose.
     */
    List<QuoteDocumentExpansion.Bucket> buckets(QuoteDocumentExpansion.Request request);

    /**
     * Which buckets this line occupies, and with what relative weight in each.
     *
     * Returning an empty list for a line that counts toward the table's totals
     * is an error, not an omission - its money would vanish from a table that
     * still claimed to reconcile. Say so by throwing.
     */
    List<QuoteDocumentExpansion.Placement> placements(
        QuoteDocumentLine line, QuoteDocumentExpansion.Request request
    );

    /**
     * Whether a quantity DIVIDES along this axis or REPEATS across it.
     *
     * 1,000 devices across three deliveries is 200/300/500 - genuinely
     * divided, because each delivery is a different set of physical objects.
     * 100 licences across twelve months is 100 every month, because it is the
     * same 100 licences. Only the dimension knows which it is, and getting it
     * wrong prints a quantity the customer can disprove by counting their own
     * users.
     */
    Boolean dividesQuantity();
}
