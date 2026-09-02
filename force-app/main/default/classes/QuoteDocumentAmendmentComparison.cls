/**
 * Compares an amendment quote against the subscriptions it amends.
 *
 * "You currently have 100 licences and a support package; this amendment takes
 * you to 150 and removes the support." The current side is the quote's own
 * lines; the baseline is what the customer already has, which lives in
 * SBQQ__Subscription__c.
 *
 * WHY THIS IS NOT QuoteDocumentSourceQuoteComparison
 * --------------------------------------------------
 * That one compares a revision against the quote it was revised from - two
 * proposals. This compares a proposal against a live contractual position. The
 * engine, the matching rules and the four outcomes are identical; only where
 * the baseline comes from differs, which is exactly why the baseline is an
 * interface.
 *
 * WHICH SUBSCRIPTIONS COUNT
 * -------------------------
 * Those on the contract the quote amends, where the quote names one, and
 * otherwise those on the quote's account. Terminated subscriptions are excluded
 * - a position that has already ended is not part of "what you have today", and
 * including it would report a removal the amendment is not making.
 *
 * PROVISIONAL, AND SAYING SO
 * --------------------------
 * QuoteDocumentLine.classify carries a standing warning that this org holds no
 * amendment or renewal quotes, so its transaction-type branches have never been
 * checked against production data. The same caution applies here: the shape is
 * tested against constructed subscriptions, not against a real CPQ amendment.
 * Before a customer-facing document depends on this, run it against a genuine
 * amendment and confirm the matching picks the positions a human would.
 *
 * See docs/quote-document-extension-recipes.md.
 */
public with sharing class QuoteDocumentAmendmentComparison
    implements QuoteDocumentComparisonSource {

    public static final String CODE = 'AMENDED_SUBSCRIPTION';

    public List<QuoteDocumentLine> baseline(QuoteDocumentComparison.Request request) {
        Map<String, Object> populated = request.quote.getPopulatedFieldsAsMap();

        String field = request.definition.comparisonSourceFieldOrDefault();
        Id accountId = populated.containsKey(field) ? (Id) populated.get(field) : null;

        if (accountId == null) {
            QuoteDocumentContributorError.fail(
                QuoteDocumentComparison.ERR_SOURCE_MISSING,
                'Table ' + request.definition.tableCode + ' compares against the customer existing '
                    + 'subscriptions, but ' + request.quote.Name + ' has nothing in ' + field + '. Without one there '
                    + 'is no "what you have today" to compare with, and an empty baseline would report '
                    + 'every line on this amendment as newly added.'
            );
        }

        List<QuoteDocumentLine> baseline = new List<QuoteDocumentLine>();
        for (SBQQ__Subscription__c subscription : [
            SELECT Id, SBQQ__Product__c, SBQQ__ProductName__c, SBQQ__Quantity__c, SBQQ__NetPrice__c,
                   SBQQ__ChargeType__c, SBQQ__SubscriptionStartDate__c, SBQQ__SubscriptionEndDate__c,
                   SBQQ__TerminatedDate__c
            FROM SBQQ__Subscription__c
            WHERE SBQQ__Account__c = :accountId
            WITH USER_MODE
            ORDER BY SBQQ__ProductName__c
        ]) {
            // An ended position is not part of what the customer has today, and
            // including it would report a removal this amendment is not making.
            if (subscription.SBQQ__TerminatedDate__c != null
                && subscription.SBQQ__TerminatedDate__c <= Date.today()) {
                continue;
            }
            baseline.add(QuoteDocumentLine.fromSubscription(subscription));
        }
        return baseline;
    }

    /**
     * Product plus charge type. Deliberately WITHOUT the subscription window,
     * unlike the quote-to-quote source: an amendment routinely changes the end
     * date of the very position it is amending, so including dates would report
     * every amended line as one removal and one addition.
     *
     * Where a customer genuinely holds the same product twice on different
     * terms, this key cannot tell them apart and QuoteDocumentComparison refuses
     * rather than pairing arbitrarily. That is the right failure: a human has
     * to say which position is being amended.
     */
    public String matchKey(QuoteDocumentLine line) {
        return String.valueOf(line.productId)
            + '|' + (line.chargeType == null ? '' : line.chargeType);
    }
}
