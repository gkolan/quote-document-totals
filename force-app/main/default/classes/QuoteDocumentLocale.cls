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
 * same reason generation is based on the Quote rather than the person who
 * starts it.
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

  private static final String CONFIG_KEY_DEFAULT_LOCALE = 'DEFAULT_LOCALE';

  /**
   * The org's documented default, and DELIBERATELY NOT UserInfo.getLocale().
   *
   * This method used to return the running user's locale, which contradicted
   * this class's own opening comment in the same file. The consequence was
   * concrete rather than stylistic: two sales users with different personal
   * locale settings would generate two different documents from the same
   * quote, and deterministic replay - which the fingerprint, the payload
   * hash and the whole reuse decision rest on - would silently not hold.
   *
   * It is org CONFIGURATION, read from the same key-value metadata as
   * everything else, falling back to a stable literal. A literal fallback is
   * defensible where the running user's locale is not, because it is the
   * same for everyone.
   */
  @TestVisible
  private static String orgDefault() {
    String configured = QuoteDocumentKeyValueMap.get(CONFIG_CATEGORY)
      .get(CONFIG_KEY_DEFAULT_LOCALE);
    return String.isBlank(configured) ? 'en_US' : configured.trim();
  }

  /**
   * NORMALIZED ON THE WAY OUT, exactly once, here.
   *
   * This used to return whatever the configured field held, and only one of
   * the three consumers normalized it: QuoteDocumentLabels rewrites `-` to
   * `_` and case-folds, while QuoteDocumentBlockBuilder and the table stamp
   * took the raw string. A quote holding the perfectly ordinary BCP-47 tag
   * `en-US` therefore resolved its LABELS correctly and then matched no
   * Quote_Document_Content__mdt at all - including the base-language
   * fallback, whose guard tests for `_`. Every block silently vanished from
   * the document and nothing failed, because zero blocks is a legal
   * snapshot.
   *
   * One tag, decided here, so the labels, the blocks, the stamped Locale__c
   * and the fingerprint cannot disagree about what locale this snapshot is.
   */
  public static String resolve(SBQQ__Quote__c quote) {
    return QuoteDocumentLabels.normalize(resolveRaw(quote));
  }

  private static String resolveRaw(SBQQ__Quote__c quote) {
    if (String.isNotBlank(overrideLocale)) {
      return overrideLocale;
    }

    String path = configuredPath();
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

  /**
   * The configured Quote field path holding a locale, or blank.
   *
   * Exposed so QuoteDocumentQuery can add it to the generation SELECT list.
   * Without that it was never queried, `readPath` always found nothing, and
   * every quote silently fell back to the default - which is
   * indistinguishable from "nobody configured a path". A configuration that
   * appears to be ignored is worse than one that fails.
   */
  public static String configuredPath() {
    return QuoteDocumentKeyValueMap.get(CONFIG_CATEGORY).get(CONFIG_KEY);
  }

  /** Same dot-path walk the fingerprint uses; null anywhere along it yields null, not an error. */
  /**
   * Test seam for readPath, whose whole job is to swallow describe failures so
   * a misconfigured locale path degrades to a fallback instead of taking down
   * generation. Those catch blocks are unreachable through resolve() with real
   * config, which is exactly why they were never covered.
   */
  @TestVisible
  private static String resolveForTest(SObject record, String path) {
    return readPath(record, path);
  }

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
