/**
 * Where the "before" side of a before-and-after table comes from.
 *
 * Every other table in this framework is built from one record set: the
 * quote's own lines. A comparison needs two, and the second one is never on
 * the quote - it is a previous revision, an amended subscription, an earlier
 * proposal. This interface is that second set, and nothing else.
 *
 * MATCHING IS THE HARD PART, AND IT BELONGS HERE
 * ----------------------------------------------
 * Product Id is the obvious key and is wrong often enough to matter: two lines
 * of the same product on different terms are two positions, not one. Only the
 * source knows what identity means for its own data, so matchKey is its
 * decision. QuoteDocumentComparison then refuses ambiguity rather than picking
 * one - a difference column is the number a customer trusts most in a change
 * document, and a confidently wrong one is worse than a failure.
 *
 * See specs/row-generation-extensibility/steps/step-04-comparison-and-enrichment.md.
 */
public interface QuoteDocumentComparisonSource {

    /**
     * The baseline lines - the "before" position.
     *
     * Returning an empty list is a legitimate answer (everything is new).
     * Failing to READ the baseline is not: throw
     * QuoteDocumentContributorError with ENRICHMENT_SOURCE_MISSING rather than
     * returning empty, because "nothing was there" and "I could not look"
     * produce the same document and mean opposite things.
     */
    List<QuoteDocumentLine> baseline(QuoteDocumentComparison.Request request);

    /**
     * What makes a current line and a baseline line the same position.
     *
     * Must be stable across both sides and must not be blank. Two lines
     * sharing a key on the same side is an ambiguity the engine refuses.
     */
    String matchKey(QuoteDocumentLine line);
}
