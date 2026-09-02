/**
 * The three concurrency behaviours the runbook promised but nothing owned:
 * a generation stuck in Generating, a lock that will not come, and telling
 * a superseded worker it has lost.
 *
 * Each needed a DECISION before it could be built at all - how long, how
 * many, who retries. Those decisions are here, as configuration where an org
 * might reasonably differ and as constants where a different value would just
 * be a different bug.
 */
public with sharing class QuoteDocumentLifecycle {
  private static final String CONFIG_CATEGORY = 'LIFECYCLE';
  private static final String KEY_ABANDON_MINUTES = 'ABANDON_MINUTES';

  /**
   * The two rejections this class raises BEFORE anything has been published.
   *
   * Named as constants rather than typed at each site because the generator
   * has to recognise them in a catch block, and it recognised them by
   * searching the message text for one of the two strings - so the guard
   * added second was silently outside it. Anything added here is covered by
   * isNonMutatingRejection without touching the generator again.
   */
  public static final String CODE_ALREADY_RUNNING = 'GENERATION_ALREADY_RUNNING';
  public static final String CODE_SUPERSEDED = 'REQUEST_SUPERSEDED';

  private static final Set<String> NON_MUTATING_REJECTIONS = new Set<String>{
    CODE_ALREADY_RUNNING,
    CODE_SUPERSEDED
  };

  /**
   * Whether an exception is a lifecycle rejection that owns no bookkeeping.
   *
   * Neither of these attempts ever became the quote's live generation, so
   * neither has anything to record. Writing Failed for one replaces the
   * status, request Id and start time of the attempt that IS live - which
   * both clears the marker that caused the rejection and, for a supersede,
   * makes the winning worker fail its own ownership check at publication.
   * Neither attempt then publishes.
   *
   * Matched on the CODE PREFIX, not on a substring of the whole message:
   * `contains()` also fires on any message that merely quotes the code, and
   * QuoteDocumentContributorError always formats as `CODE: detail`. Same
   * technique QuoteDocumentError.codeOf uses, for the same reason.
   */
  public static Boolean isNonMutatingRejection(Exception e) {
    if (e == null || String.isBlank(e.getMessage())) {
      return false;
    }
    return NON_MUTATING_REJECTIONS.contains(
      e.getMessage().substringBefore(':').trim()
    );
  }

  /**
   * How long a request may sit in Generating before another may take it over.
   *
   * Configuration rather than a literal: the right value depends on how big
   * an org's quotes are, and a literal would make every tenant live with
   * whichever number happened to be typed here first. Thirty minutes is the
   * fallback - comfortably longer than any generation this framework can
   * legally run, since a Queueable cannot exceed its own limits for
   * anything like that long.
   */
  @TestVisible
  private static final Integer DEFAULT_ABANDON_MINUTES = 30;

  @TestVisible
  private static Integer abandonMinutes() {
    String configured = QuoteDocumentKeyValueMap.get(CONFIG_CATEGORY)
      .get(KEY_ABANDON_MINUTES);
    if (String.isBlank(configured)) {
      return DEFAULT_ABANDON_MINUTES;
    }
    try {
      Integer minutes = Integer.valueOf(configured.trim());
      return minutes > 0 ? minutes : DEFAULT_ABANDON_MINUTES;
    } catch (Exception e) {
      // A misconfigured window must not stop generation. Falling back is
      // safe in the direction that matters: a longer window only delays
      // a takeover, it never lets two workers publish.
      return DEFAULT_ABANDON_MINUTES;
    }
  }

  /**
   * Whether a Generating request may be taken over.
   *
   * ONE TIME SOURCE. The caller passes `now` and every comparison uses it,
   * so a Flow-supplied timestamp can never be compared against an Apex one
   * - which would make the boundary depend on which side asked.
   *
   * A NULL start time counts as abandoned. That state can only come from an
   * interrupted write, and treating it as eternally live would block the
   * quote forever; a takeover that turns out to be premature costs one
   * regeneration, which is the cheaper failure by a wide margin.
   */
  public static Boolean isAbandoned(
    String status,
    Datetime startedAt,
    Datetime now
  ) {
    if (!'Generating'.equals(status)) {
      return false;
    }
    if (startedAt == null) {
      return true;
    }
    Long elapsedMinutes = (now.getTime() - startedAt.getTime()) / (1000L * 60L);
    return elapsedMinutes >= abandonMinutes();
  }

  /**
   * Refuses to let a superseded worker publish.
   *
   * A taken-over request may still be running somewhere. If it finishes and
   * publishes, it overwrites a snapshot built from newer inputs with one
   * built from older ones - and nothing downstream could tell, because both
   * look like a complete, verified snapshot.
   *
   * Re-reading immediately before publication is what makes that impossible
   * rather than merely unlikely. The read is inside the same transaction
   * that holds the row under FOR UPDATE, so nothing can change between the
   * check and the write.
   */
  public static void assertStillOwns(Id quoteId, String requestId) {
    List<SBQQ__Quote__c> current = [
      SELECT Document_Data_Request_Id__c
      FROM SBQQ__Quote__c
      WHERE Id = :quoteId
    ];
    if (current.isEmpty()) {
      return;
    }

    String stored = current[0].Document_Data_Request_Id__c;
    if (String.isBlank(stored) || stored.equals(requestId)) {
      return;
    }

    throw QuoteDocumentContributorError.build(
      CODE_SUPERSEDED,
      'Request ' +
        requestId +
        ' finished, but request ' +
        stored +
        ' has since taken over quote ' +
        quoteId +
        '. Publishing now would overwrite a snapshot built from newer inputs with one ' +
        'built from older ones, and nothing downstream could tell the difference.'
    );
  }

  // -----------------------------------------------------------------------
  // Lock retry
  // -----------------------------------------------------------------------

  /**
   * At most three attempts. Beyond that a retry is no longer waiting out a
   * neighbour, it is queuing behind a real problem.
   */
  public static final Integer MAX_LOCK_ATTEMPTS = 3;

  /**
   * Only lock contention is retryable. Everything else is terminal on the
   * first failure - retrying a configuration error just produces the same
   * error three times and delays the report by however long the backoff is.
   */
  public static Boolean isRetryable(Exception e) {
    if (e == null) {
      return false;
    }
    String message = e.getMessage();
    if (String.isBlank(message)) {
      return false;
    }
    return message.contains('UNABLE_TO_LOCK_ROW') ||
      message.containsIgnoreCase('unable to obtain exclusive access') ||
      message.containsIgnoreCase('query timeout') ||
      message.containsIgnoreCase('lock timeout');
  }

  /**
   * Exponential with jitter. The jitter matters more than the exponent: two
   * jobs retrying on the same fixed schedule collide again on every attempt,
   * which is the failure the backoff was supposed to prevent.
   *
   * Returned as a value rather than slept on - Apex has no sleep, and a busy
   * wait would burn the CPU limit it is trying to protect. The caller uses
   * it to schedule the next attempt.
   */
  public static Integer backoffMinutes(Integer attempt) {
    // Computed in MINUTES, which is the only unit the scheduler has.
    // A seconds ladder was the original form, and every value it could
    // produce for the two attempts that actually retry (1-4 seconds)
    // divided down to the same one minute - so the delay had neither
    // growth nor jitter, which is the whole point of a backoff.
    Integer base = (Integer) Math.pow(2, Math.max(0, attempt - 1));
    Integer jitter = Math.mod(Math.abs(Crypto.getRandomInteger()), base + 1);
    // System.enqueueJob accepts 0-10 minutes and throws outside it, which
    // would turn a retry into a hard failure. At least one: a zero-delay
    // re-enqueue is a busy wait wearing a queue.
    return Math.min(10, Math.max(1, base + jitter));
  }

  /** The terminal code, so a runbook has one string to grep for. */
  public static QuoteDocumentGenerator.QuoteDocumentException lockTimeout(
    Id quoteId,
    Integer attempts
  ) {
    return QuoteDocumentContributorError.build(
      'GENERATION_LOCK_TIMEOUT',
      'Could not acquire a lock on quote ' +
        quoteId +
        ' after ' +
        attempts +
        ' attempts. No snapshot ' +
        'was changed and the quote status is untouched - nothing about the existing document ' +
        'is wrong, the generation simply did not run.'
    );
  }
}
