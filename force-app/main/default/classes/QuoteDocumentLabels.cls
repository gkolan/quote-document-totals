/**
 * Every printable string on a generated record, resolved once, centrally,
 * from a semantic key against a locale dictionary.
 *
 * The template was never the only place English was hardcoded.
 * QuoteDocumentRowBuilder concatenated `g.value + ' Subtotal'`, built
 * `'Total ' + section + ' Charges'`, emitted `'Total'`, and substituted
 * `'(unnamed)'`. Swapping the renderer would not have fixed any of them,
 * which is why localization is a generation stage here rather than something
 * a per-table customizer opts into.
 *
 * WORD ORDER IS THE TRANSLATOR'S DECISION
 * ---------------------------------------
 * `'{0} Subtotal'` is a template the dictionary owns, not a concatenation
 * Apex owns. In German the qualifier goes elsewhere; in French the adjective
 * follows the noun. Apex supplying `{0}` and the dictionary deciding where it
 * lands is the whole difference between translatable and merely externalised.
 *
 * THE DICTIONARY IS THE EXISTING ONE
 * ----------------------------------
 * Quote_Document_Key_Value__mdt with Category__c = 'LABELS_en_US'. It is
 * already exactly a keyed dictionary; a second Custom Metadata Type holding
 * the same shape would be duplication step 09 would have to explain away.
 * What is NOT reused is QuoteDocumentKeyValueMap.get(), whose duplicate
 * policy - first row wins, in query order - is right for a rate table and
 * wrong here: it would make printed wording depend on undefined query order.
 * Labels load through a strict path that fails on a duplicate instead.
 */
public with sharing class QuoteDocumentLabels {

    private static final String CATEGORY_PREFIX = 'LABELS_';

    /** Semantic keys core itself resolves. Subscribers add their own freely. */
    public static final String KEY_GRAND_TOTAL = 'GRAND_TOTAL';
    public static final String KEY_SUBTOTAL = 'SUBTOTAL';
    public static final String KEY_SECTION_TOTAL = 'SECTION_TOTAL';
    public static final String KEY_GROUP_UNNAMED = 'GROUP_UNNAMED';
    public static final String KEY_COLUMN_LABEL = 'COL_LABEL';

    private final String locale;
    private final Map<String, String> entries;

    private static Map<String, QuoteDocumentLabels> byLocale = new Map<String, QuoteDocumentLabels>();

    private QuoteDocumentLabels(String locale, Map<String, String> entries) {
        this.locale = locale;
        this.entries = entries;
    }

    public String getLocale() {
        return locale;
    }

    // -----------------------------------------------------------------------
    // Locale tags
    // -----------------------------------------------------------------------

    /**
     * Normalised once, on the way in, so `EN_us`, `en_US` and `en-US` cannot
     * become three different cache entries pointing at the same dictionary -
     * or worse, two of them missing and silently falling through.
     *
     * Documented rule for the `fr` / `fr_FR` case: an exact match wins; a
     * region-qualified tag falls back to its base language; a base language
     * NEVER expands to a region. `fr_FR` may use `LABELS_fr`, but `fr` never
     * silently picks up `LABELS_fr_CA` - guessing a region is how a Canadian
     * price list ends up in a French document.
     */
    @TestVisible
    private static String normalize(String rawLocale) {
        if (String.isBlank(rawLocale)) {
            return null;
        }
        String tag = rawLocale.trim().replace('-', '_');
        List<String> parts = tag.split('_');
        String language = parts[0].toLowerCase();
        if (parts.size() == 1) {
            return language;
        }
        return language + '_' + parts[1].toUpperCase();
    }

    /**
     * Loads one category per locale per transaction.
     *
     * An unsupported locale FAILS. Falling through to English by accident is
     * the one outcome nobody would notice in testing and everybody would
     * notice in a signed document.
     */
    public static QuoteDocumentLabels forLocale(String rawLocale) {
        String tag = normalize(rawLocale);
        if (tag == null) {
            throw QuoteDocumentContributorError.build(
                'LOCALE_UNRESOLVED',
                'No locale was supplied for label resolution. Every generated snapshot carries exactly one '
                    + 'locale; there is no implicit default, because an implicit default is invisible until '
                    + 'it is wrong.'
            );
        }
        if (byLocale.containsKey(tag)) {
            return byLocale.get(tag);
        }

        Map<String, String> entries = loadStrict(CATEGORY_PREFIX + tag);

        // Region-qualified falls back to base language; never the reverse.
        if (entries.isEmpty() && tag.contains('_')) {
            String base = tag.split('_')[0];
            entries = loadStrict(CATEGORY_PREFIX + base);
        }

        if (entries.isEmpty()) {
            throw QuoteDocumentContributorError.build(
                'LOCALE_UNSUPPORTED',
                'No label dictionary exists for locale "' + tag + '". Expected Quote_Document_Key_Value__mdt '
                    + 'records with Category__c = "' + CATEGORY_PREFIX + tag + '". Generation fails rather '
                    + 'than falling through to another language, which would print a document nobody '
                    + 'reviewed in a language nobody chose.'
            );
        }

        QuoteDocumentLabels labels = new QuoteDocumentLabels(tag, entries);
        byLocale.put(tag, labels);
        return labels;
    }

    /**
     * Strict load: a duplicate key in one category fails, naming it.
     *
     * QuoteDocumentKeyValueMap keeps the first row in query order, which is
     * correct for a rate table and unacceptable here - it would mean the
     * printed wording of a customer document depends on an order the platform
     * does not guarantee.
     */
    private static Map<String, String> loadStrict(String category) {
        Map<String, String> result = new Map<String, String>();
        for (Quote_Document_Key_Value__mdt row : [
            SELECT DeveloperName, Key__c, Value__c
            FROM Quote_Document_Key_Value__mdt
            WHERE Category__c = :category
        ]) {
            if (result.containsKey(row.Key__c)) {
                throw QuoteDocumentContributorError.build(
                    'LABEL_KEY_DUPLICATE',
                    'Category ' + category + ' defines key "' + row.Key__c + '" more than once (see record '
                        + row.DeveloperName + '). Which wording printed would depend on query order, which '
                        + 'the platform does not guarantee.'
                );
            }
            result.put(row.Key__c, row.Value__c);

            assertSupportedPlaceholders(category, row.Key__c, row.Value__c);
        }
        return result;
    }

    /**
     * Only {0} and {1} exist, and that is checked at dictionary LOAD rather
     * than at render - a translator who writes {2} finds out on deployment,
     * not when the one quote that exercises that table reaches a customer.
     */
    private static void assertSupportedPlaceholders(String category, String key, String template) {
        if (String.isBlank(template)) {
            return;
        }
        for (Integer index = 2; index <= 9; index++) {
            if (template.contains('{' + index + '}')) {
                throw QuoteDocumentContributorError.build(
                    'LABEL_ARGUMENT_UNSUPPORTED',
                    'Category ' + category + ', key "' + key + '" references {' + index + '}. Only {0} and '
                        + '{1} are supported, matching Label_Arg_1__c and Label_Arg_2__c on the row.'
                );
            }
        }
    }

    // -----------------------------------------------------------------------
    // Resolution
    // -----------------------------------------------------------------------

    /** Required text. A missing key fails generation, naming key and locale. Never blanks. */
    public String resolve(String key) {
        String value = entries.get(key);
        if (value == null) {
            throw QuoteDocumentContributorError.build(
                'LABEL_KEY_MISSING',
                'No label for key "' + key + '" in locale "' + locale + '". This is required text: '
                    + 'generation fails rather than printing a blank where a heading or a total label '
                    + 'should be.'
            );
        }
        return value;
    }

    /** Optional text. The caller supplies what absence means; absence is never a silent blank. */
    public String resolve(String key, String fallback) {
        String value = entries.get(key);
        return value == null ? fallback : value;
    }

    public Boolean has(String key) {
        return entries.containsKey(key);
    }

    /**
     * Substitutes {0} and {1}, literally and exactly once.
     *
     * Substitution is NOT recursive and NOT regex-based. A product named
     * "Widget {0}" or "GRAND_TOTAL" is data, and data must never be
     * re-resolved as a key or re-scanned as a placeholder - that is how a
     * customer's product name silently becomes a total label. Braces,
     * apostrophes, ampersands, Unicode and newlines all pass through
     * untouched for the same reason.
     */
    public String format(String key, List<String> args) {
        return substitute(resolve(key), key, args);
    }

    @TestVisible
    private String substitute(String template, String key, List<String> args) {
        List<String> safeArgs = args == null ? new List<String>() : args;

        // Split-and-join rather than replace(), so a substituted value
        // containing "{1}" is never treated as a placeholder on the next pass.
        List<String> pieces = new List<String>();
        String remaining = template;
        Integer guard = 0;

        while (guard < 20) {
            guard++;
            Integer open = remaining.indexOf('{');
            if (open == -1) {
                break;
            }
            Integer close = remaining.indexOf('}', open);
            if (close == -1) {
                break;
            }

            String token = remaining.substring(open + 1, close);
            if (!token.isNumeric()) {
                // A literal brace in the wording, not a placeholder.
                pieces.add(remaining.substring(0, close + 1));
                remaining = remaining.substring(close + 1);
                continue;
            }

            Integer index = Integer.valueOf(token);
            if (index >= safeArgs.size() || safeArgs[index] == null) {
                throw QuoteDocumentContributorError.build(
                    'LABEL_ARGUMENT_MISSING',
                    'Label "' + key + '" in locale "' + locale + '" references {' + index + '}, but no '
                        + 'argument was supplied at that index. It must never render as the literal "null" '
                        + 'or as an empty gap in a customer-facing sentence.'
                );
            }

            pieces.add(remaining.substring(0, open));
            pieces.add(safeArgs[index]);
            remaining = remaining.substring(close + 1);
        }
        pieces.add(remaining);

        return String.join(pieces, '');
    }

    @TestVisible
    private static void reset() {
        byLocale = new Map<String, QuoteDocumentLabels>();
    }

    @TestVisible
    private static void useLabels(String locale, Map<String, String> entries) {
        String tag = normalize(locale);
        byLocale.put(tag, new QuoteDocumentLabels(tag, entries));
    }
}
