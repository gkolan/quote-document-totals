/**
 * Builds the text that goes in SBQQ__Quote__c.Document_Data_Error__c.
 *
 * WHY THIS IS NOT JUST abbreviate(3000)
 * -------------------------------------
 * Abbreviation bounds LENGTH. It does not sanitize. Arbitrary exception text
 * fits well inside 3000 characters and can carry customer content: a DML
 * error echoes the field values it rejected, a contributor's own message can
 * quote a product description, a validation rule repeats whatever was typed
 * into the record. Document_Data_Error__c is a field on the Quote, readable
 * by anyone who can read the Quote, and it is the field a support team pastes
 * into a ticket.
 *
 * So persisted errors are ASSEMBLED from a stable code plus allowlisted
 * context, never copied from an exception. Raw exception detail belongs in a
 * debug log, which is access-controlled and retained briefly - not on a
 * business record forever.
 *
 * The allowlist is deliberately short and deliberately boring: identifiers an
 * admin needs to find the misconfiguration, and nothing that came from a
 * customer record.
 */
public with sharing class QuoteDocumentError {

    /**
     * Every stable code this framework can persist.
     *
     * Matching against a known list rather than parsing whatever prefix
     * happens to be present: an exception whose message merely LOOKS like it
     * starts with a code must not be able to smuggle its text through by
     * inventing one.
     */
    private static final Set<String> KNOWN_CODES = new Set<String>{
        QuoteDocumentContributorError.MULTIPLE_GRAND_TOTALS,
        QuoteDocumentContributorError.DUPLICATE_DISPLAY_ORDER,
        QuoteDocumentContributorError.ROW_ORDER_INVALID,
        QuoteDocumentContributorError.FOREIGN_TABLE,
        QuoteDocumentContributorError.ROW_MEASURE_MISMATCH,
        QuoteDocumentContributorError.RETURNED_PERSISTED_ROW,
        QuoteDocumentContributorError.NO_OUTPUT,
        QuoteDocumentContributorError.FLOW_FAULT,
        QuoteDocumentContributorError.FLOW_UNAVAILABLE,
        QuoteDocumentContributorError.DEPENDENCY_UNDECLARED,
        QuoteDocumentContributorError.VERSION_UNDECLARED,
        QuoteDocumentContributorError.DEPENDENCY_UNREADABLE,
        'COLUMN_CODE_MISSING', 'COLUMN_ORDER_MISSING', 'COLUMN_FIELD_UNKNOWN',
        'COLUMN_TYPE_UNSUPPORTED', 'COLUMN_TYPE_DECLARATION_MISMATCH',
        'COLUMN_MEASURE_MISMATCH', 'COLUMN_CODE_DUPLICATE', 'COLUMN_ORDER_DUPLICATE',
        'LABEL_KEY_MISSING', 'LABEL_KEY_DUPLICATE', 'LABEL_ARGUMENT_MISSING',
        'LABEL_ARGUMENT_UNSUPPORTED', 'LOCALE_UNRESOLVED', 'LOCALE_UNSUPPORTED',
        'BLOCK_BODY_EMPTY', 'BLOCK_BODY_MARKUP', 'BLOCK_VERSION_MISSING',
        'BLOCK_CODE_DUPLICATE', 'DOCUMENT_ORDER_DUPLICATE'
    };

    /** What a persisted error says when nothing more specific is known. */
    @TestVisible
    private static final String CODE_UNEXPECTED = 'GENERATION_FAILED_UNEXPECTED';

    /**
     * The code an exception carries, or the generic one.
     *
     * Codes are written by this framework as a `CODE: detail` prefix, so the
     * code is recoverable without keeping the detail.
     */
    @TestVisible
    private static String codeOf(Exception e) {
        if (e == null) {
            return CODE_UNEXPECTED;
        }
        String message = e.getMessage();
        if (String.isBlank(message) || !message.contains(':')) {
            return CODE_UNEXPECTED;
        }
        String candidate = message.substringBefore(':').trim();
        return KNOWN_CODES.contains(candidate) ? candidate : CODE_UNEXPECTED;
    }

    /**
     * The persisted message: a stable code, the request Id, and whatever
     * allowlisted context the caller could name. Nothing else.
     *
     * `context` values are supplied by core at the throw site - a table code,
     * a field API name, a semantic key, a locale. They are identifiers core
     * itself chose, never strings that arrived from a record.
     */
    public static String persistable(Exception e, String requestId, Map<String, String> context) {
        List<String> parts = new List<String>{ codeOf(e) };

        if (String.isNotBlank(requestId)) {
            parts.add('request=' + requestId);
        }

        if (context != null) {
            List<String> keys = new List<String>(context.keySet());
            keys.sort();
            for (String key : keys) {
                String value = context.get(key);
                if (String.isNotBlank(value)) {
                    parts.add(key + '=' + value.abbreviate(80));
                }
            }
        }

        parts.add(
            'Full detail is in the debug log for this request, deliberately not on the Quote - exception '
                + 'text can echo customer data and this field is readable by anyone who can read the Quote.'
        );

        return String.join(parts, ' | ').abbreviate(3000);
    }

    public static String persistable(Exception e, String requestId) {
        return persistable(e, requestId, null);
    }
}
