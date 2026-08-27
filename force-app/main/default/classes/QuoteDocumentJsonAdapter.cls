/**
 * Renders a published document as JSON.
 *
 * The entire class is a projection of the payload. It contains no SOQL, no
 * Custom Metadata read, no arithmetic, no translation, and no defaulting -
 * if it needed any of those, the contract would be incomplete and the fix
 * would belong upstream, not here.
 *
 * It takes its expectations from a preceding generate-or-reuse, like every
 * other caller. An adapter that could read a snapshot without them would be
 * the bypass the contract prohibits, wearing a renderer's clothes.
 */
public with sharing class QuoteDocumentJsonAdapter {

    public static String render(Id quoteId, String expectedRequestId, String expectedFingerprint) {
        return render(
            QuoteDocumentRenderService.getPayload(quoteId, expectedRequestId, expectedFingerprint)
        );
    }

    /**
     * Serializes the payload as it stands.
     *
     * Typed values survive as typed JSON: a Decimal is a number, not a
     * pre-formatted string. A consumer that wants "$1,234.00" has the locale
     * and the currency code to build it, and building it here would impose
     * one renderer's formatting choice on every consumer of this output.
     */
    public static String render(QuoteDocumentPayload payload) {
        return JSON.serializePretty(payload, true);
    }
}
