/**
 * Decides which single locale one generated snapshot is produced in.
 *
 * Resolution order, highest wins:
 *   1. an explicit locale supplied by the caller
 *   2. a configured, schema-validated field path on the Quote
 *   3. the org default
 *
 * ONE LOCALE PER SNAPSHOT. A mixed-locale document is not supported in v1,
 * and that is a contract statement rather than a limitation to work around:
 * the locale is part of the fingerprint, so "this snapshot, in this
 * language" is a single identity. A document with half its tables in French
 * would have no coherent fingerprint and no coherent review.
 *
 * DELIBERATELY NOT the running user's locale. That would make the snapshot
 * depend on who clicked generate, which breaks deterministic replay - the
 * same reason the generation persona question exists at all (spec.md 10).
 */
public with sharing class QuoteDocumentLocale {

    /**
     * Category and key of the configured Quote field path holding a locale,
     * so an org can drive language off Account country, a contract field, or
     * anything else without a code change.
     */
    private static final String CONFIG_CATEGORY = 'DOCUMENT_CONFIG';
    private static final String CONFIG_KEY = 'LOCALE_FIELD_PATH';

    @TestVisible
    private static String overrideLocale;

    /**
     * The org default, read from the platform rather than hardcoded to en_US.
     * A hardcoded default is invisible until the org is not American.
     */
    private static String orgDefault() {
        return UserInfo.getDefaultCurrency() == null
            ? 'en_US'
            : String.isBlank(UserInfo.getLocale()) ? 'en_US' : UserInfo.getLocale();
    }

    public static String resolve(SBQQ__Quote__c quote) {
        if (String.isNotBlank(overrideLocale)) {
            return overrideLocale;
        }

        String path = QuoteDocumentKeyValueMap.get(CONFIG_CATEGORY).get(CONFIG_KEY);
        if (String.isNotBlank(path)) {
            String configured = readPath(quote, path);
            if (String.isNotBlank(configured)) {
                return configured;
            }
            // A configured path that resolves to nothing on THIS quote is not
            // an error - a blank Account field is ordinary data. Falling back
            // to the org default is the documented behaviour; a missing FIELD
            // is different and fails at config load in QuoteDocumentQuery.
        }

        return orgDefault();
    }

    /** Same dot-path walk the fingerprint uses; null anywhere along it yields null, not an error. */
    private static String readPath(SObject record, String path) {
        List<String> segments = path.split('\\.');
        SObject current = record;

        for (Integer i = 0; i < segments.size() - 1; i++) {
            if (current == null) {
                return null;
            }
            try {
                current = current.getSObject(segments[i]);
            } catch (Exception e) {
                return null;
            }
        }
        if (current == null) {
            return null;
        }
        try {
            Object value = current.get(segments[segments.size() - 1]);
            return value == null ? null : String.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }
}
