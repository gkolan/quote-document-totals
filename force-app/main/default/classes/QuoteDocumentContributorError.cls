/**
 * The stable error codes a contributor - Apex customizer or Flow - can fail
 * with, and the one place that formats them.
 *
 * Codes exist so a failure is greppable, testable, and the same string in a
 * log, a test assertion and a support ticket. spec.md section 8.4 forbids the
 * alternative: no blank output, no silent substitution, and never an exception
 * whose only content is that something went wrong.
 *
 * Deliberately not a new exception hierarchy. Every class in this framework
 * already throws QuoteDocumentGenerator.QuoteDocumentException and every test
 * already catches it; a second exception type would be caught by nothing and
 * would make the savepoint rollback path harder to reason about, in exchange
 * for information the code prefix already carries.
 *
 * Every message must name the offending thing - the table, the row key, the
 * Flow API name - not merely the rule that was broken. "ROW_ORDER_INVALID" on
 * its own sends someone reading 400 rows by hand.
 */
public with sharing class QuoteDocumentContributorError {

    // Contributor output - section 5 of step 01A.
    public static final String MULTIPLE_GRAND_TOTALS = 'CONTRIBUTOR_MULTIPLE_GRAND_TOTALS';
    public static final String DUPLICATE_DISPLAY_ORDER = 'CONTRIBUTOR_DUPLICATE_DISPLAY_ORDER';
    public static final String ROW_ORDER_INVALID = 'ROW_ORDER_INVALID';
    public static final String FOREIGN_TABLE = 'CONTRIBUTOR_FOREIGN_TABLE';
    public static final String ROW_MEASURE_MISMATCH = 'ROW_MEASURE_MISMATCH';
    public static final String RETURNED_PERSISTED_ROW = 'CONTRIBUTOR_RETURNED_PERSISTED_ROW';

    // Flow bridge - section 4 of step 01A.
    public static final String NO_OUTPUT = 'CONTRIBUTOR_NO_OUTPUT';
    public static final String FLOW_FAULT = 'CONTRIBUTOR_FLOW_FAULT';
    public static final String FLOW_UNAVAILABLE = 'CONTRIBUTOR_FLOW_UNAVAILABLE';

    // Configuration - section 6 and 6a of step 01A.
    public static final String DEPENDENCY_UNDECLARED = 'CONTRIBUTOR_DEPENDENCY_UNDECLARED';
    public static final String VERSION_UNDECLARED = 'CONTRIBUTOR_VERSION_UNDECLARED';
    public static final String DEPENDENCY_UNREADABLE = 'DEPENDENCY_UNREADABLE';

    /** Builds the exception rather than throwing it, so callers keep their own throw sites. */
    public static QuoteDocumentGenerator.QuoteDocumentException build(String code, String detail) {
        return new QuoteDocumentGenerator.QuoteDocumentException(code + ': ' + detail);
    }

    public static void fail(String code, String detail) {
        throw build(code, detail);
    }
}
