/**
 * Fallbacks and refusals reached through the seams the classes already expose.
 *
 * Deliberately stops where covering a line would mean adding a seam to
 * production code for the test's convenience. The async retry branch in
 * QuoteDocumentGenerateJob is the honest example: driving it needs a lock
 * contention that only a second concurrent transaction can produce, and faking
 * it would mean injecting an exception source into the job. Its decision and
 * its backoff are asserted directly instead (QuoteDocumentUncoveredPathsTest);
 * the enqueue itself is left uncovered rather than papered over.
 */
@IsTest
private class QuoteDocumentFallbackPathsTest {
  // -----------------------------------------------------------------------
  // QuoteDocumentLifecycle - a misconfigured abandon window must not stop work
  // -----------------------------------------------------------------------

  /**
   * A takeover window that cannot be parsed falls back to the default. The
   * fallback direction is the point: a longer window only delays a takeover,
   * it never lets two workers publish.
   */
  @IsTest
  static void anUnparseableAbandonWindowFallsBackToTheDefault() {
    QuoteDocumentKeyValueMap.overrides.put(
      'LIFECYCLE',
      new Map<String, String>{ 'ABANDON_MINUTES' => 'thirty-ish' }
    );

    Assert.areEqual(
      QuoteDocumentLifecycle.DEFAULT_ABANDON_MINUTES,
      QuoteDocumentLifecycle.abandonMinutes(),
      'A window nobody can parse must not stop generation - it falls back.'
    );

    QuoteDocumentKeyValueMap.overrides.put(
      'LIFECYCLE',
      new Map<String, String>{ 'ABANDON_MINUTES' => '-5' }
    );
    Assert.areEqual(
      QuoteDocumentLifecycle.DEFAULT_ABANDON_MINUTES,
      QuoteDocumentLifecycle.abandonMinutes(),
      'A negative window is as unusable as an unparseable one.'
    );

    QuoteDocumentKeyValueMap.overrides.put(
      'LIFECYCLE',
      new Map<String, String>{ 'ABANDON_MINUTES' => '90' }
    );
    Assert.areEqual(
      90,
      QuoteDocumentLifecycle.abandonMinutes(),
      'And a good value is still honoured - the fallback must not swallow real config.'
    );

    QuoteDocumentKeyValueMap.overrides.clear();
  }

  @IsTest
  static void anAbandonWindowLeftBlankUsesTheDefault() {
    QuoteDocumentKeyValueMap.overrides.put(
      'LIFECYCLE',
      new Map<String, String>()
    );

    Assert.areEqual(
      QuoteDocumentLifecycle.DEFAULT_ABANDON_MINUTES,
      QuoteDocumentLifecycle.abandonMinutes(),
      'No configuration at all is the ordinary case, not an error.'
    );

    QuoteDocumentKeyValueMap.overrides.clear();
  }

  // -----------------------------------------------------------------------
  // QuoteDocumentQuery - unreadable configured paths fail before reuse decides
  // -----------------------------------------------------------------------

  /**
   * A declared dependency that cannot be read must fail at generation naming
   * the path. Canonicalizing it as null would silently narrow the fingerprint
   * to less than the contributor actually reads - reuse would then be decided
   * on a hash that no longer covers the data.
   */
  @IsTest
  static void anUnreadableDependencyPathIsRefusedAndNamed() {
    String message;
    try {
      QuoteDocumentQuery.validateDependencyPath(
        'SBQQ__Account__r.No_Such_Field__c'
      );
    } catch (Exception e) {
      message = e.getMessage();
    }

    Assert.isNotNull(
      message,
      'An unreadable dependency path must fail before the reuse decision.'
    );
    Assert.isTrue(
      message.contains('No_Such_Field__c'),
      'And the message must name the path so it can be fixed: ' + message
    );
  }

  @IsTest
  static void anUnreadableGroupingFieldPathIsRefusedAndNamed() {
    String message;
    try {
      QuoteDocumentQuery.validateFieldPath('SBQQ__Product__r.No_Such_Field__c');
    } catch (Exception e) {
      message = e.getMessage();
    }

    Assert.isNotNull(
      message,
      'A grouping bound to a field that does not exist must fail loudly.'
    );
    Assert.isTrue(message.contains('No_Such_Field__c'), message);
  }

  @IsTest
  static void aValidPathIsAccepted() {
    // The negative tests above prove nothing unless the validator also
    // accepts something: a rejector that rejects everything looks identical.
    QuoteDocumentQuery.validateFieldPath('SBQQ__Product__r.Family');
    QuoteDocumentQuery.validateDependencyPath('SBQQ__Account__r.Industry');
  }

  // -----------------------------------------------------------------------
  // QuoteDocumentBlockBuilder - markup detection
  // -----------------------------------------------------------------------

  /**
   * No vendor-neutral payload may carry markup, and the detection is
   * pattern-based rather than character-based so ordinary prose containing a
   * "<" still prints.
   */
  @IsTest
  static void markupIsRejectedButProseWithAngleBracketsIsNot() {
    Assert.isTrue(
      QuoteDocumentBlockBuilder.containsMarkup('<p>terms</p>'),
      'A paragraph tag is markup.'
    );
    Assert.isTrue(
      QuoteDocumentBlockBuilder.containsMarkup('text <br/> more'),
      'A self-closing tag is markup.'
    );
    Assert.isFalse(
      QuoteDocumentBlockBuilder.containsMarkup(
        'quantities < 10 are discounted'
      ),
      'Prose comparing quantities is not markup - rejecting it would refuse a legitimate clause.'
    );
    Assert.isFalse(
      QuoteDocumentBlockBuilder.containsMarkup(null),
      'No body is not markup.'
    );
  }
}
