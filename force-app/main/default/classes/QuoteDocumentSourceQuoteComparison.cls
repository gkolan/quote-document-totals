/**
 * Compares this quote against the quote it came from.
 *
 * CPQ already records that relationship: SBQQ__Source__c on a revision points
 * at the quote it was revised from. That makes "what changed since the version
 * we sent last week" a question the data can already answer, with no new
 * object and no snapshot retention.
 *
 * WHY NOT THE PREVIOUS SNAPSHOT
 * -----------------------------
 * The obvious design - compare against this quote's own previous
 * Quote_Document_Table__c rows - cannot work today.
 * QuoteDocumentGenerator deletes every table for the quote before rebuilding,
 * so by the time a comparison could read the old snapshot it is already gone.
 * Comparing snapshots needs generation versioning, which is planned elsewhere
 * and not built. Comparing quotes needs nothing that does not already exist,
 * which is why this ships and that does not.
 *
 * THE MATCH KEY
 * -------------
 * Product plus charge type plus the subscription window. Product alone is
 * wrong often enough to matter: the same product quoted for two different
 * terms is two positions, and pairing them would report a change that is
 * really two separate lines. Where that key is still ambiguous - genuinely two
 * identical lines - QuoteDocumentComparison refuses rather than guessing.
 *
 * ACCESS
 * ------
 * The baseline is read `with sharing`, like everything else here. A user who
 * cannot see the source quote gets a coded failure rather than an empty
 * baseline, because an empty baseline prints "everything is new" - a confident
 * statement built on a permission error.
 */
public with sharing class QuoteDocumentSourceQuoteComparison implements QuoteDocumentComparisonSource {

    public static final String CODE = 'SOURCE_QUOTE';

    /** CPQ's own link from a revision back to the quote it was revised from. */
    public static final String DEFAULT_SOURCE_FIELD = 'SBQQ__Source__c';

    public List<QuoteDocumentLine> baseline(QuoteDocumentComparison.Request request) {
        String field = request.definition.comparisonSourceFieldOrDefault();

        Id sourceId = sourceQuoteId(request, field);

        List<SBQQ__Quote__c> sources = QuoteDocumentQuery.quotesWithLinesReadOnly(new Set<Id>{ sourceId });
        if (sources.isEmpty()) {
            QuoteDocumentContributorError.fail(
                QuoteDocumentComparison.ERR_SOURCE_MISSING,
                'Table ' + request.definition.tableCode + ' compares against the quote named by ' + field
                    + ', but that quote could not be read. It has been deleted, or the running user cannot '
                    + 'see it. Either way this fails rather than printing an empty baseline, which would '
                    + 'state that every product on this quote is new.'
            );
        }

        SBQQ__Quote__c source = sources[0];
        List<QuoteDocumentLine> lines = new List<QuoteDocumentLine>();
        for (SBQQ__QuoteLine__c raw : source.SBQQ__LineItems__r) {
            QuoteDocumentLine line = new QuoteDocumentLine(raw, source);
            // The baseline is filtered the same way the current side is, or
            // the two sides would be answering different questions.
            if (line.matchesFilter(request.definition.lineFilter)) {
                lines.add(line);
            }
        }
        return lines;
    }

    public String matchKey(QuoteDocumentLine line) {
        return String.valueOf(line.productId)
            + '|' + (line.chargeType == null ? '' : line.chargeType)
            + '|' + (line.subscriptionStartDate == null ? '' : String.valueOf(line.subscriptionStartDate))
            + '|' + (line.subscriptionEndDate == null ? '' : String.valueOf(line.subscriptionEndDate));
    }

    private static Id sourceQuoteId(QuoteDocumentComparison.Request request, String field) {
        Map<String, Object> populated = request.quote.getPopulatedFieldsAsMap();

        if (!populated.containsKey(field) || populated.get(field) == null) {
            QuoteDocumentContributorError.fail(
                QuoteDocumentComparison.ERR_SOURCE_MISSING,
                'Table ' + request.definition.tableCode + ' compares against the quote named by ' + field
                    + ', but that field is blank on ' + request.quote.Name + '. A comparison with nothing '
                    + 'to compare against is not an empty table - it is a table that would report every '
                    + 'line as newly added. Generate this table only on a revision, or clear the '
                    + 'comparison source from the definition.'
            );
        }
        return (Id) populated.get(field);
    }
}
