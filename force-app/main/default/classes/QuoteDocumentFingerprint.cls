/**
 * Computes a stable digest of everything that can change a Quote's document
 * tables' output, so QuoteDocumentGenerator can tell "nothing that matters
 * changed" apart from "something changed that no trigger caught" - the gap
 * trigger-based staleness (QuoteDocumentStaleness) cannot close on its own,
 * e.g. a Product2 field used in a grouping Field_Path__c.
 *
 * See specs/quote-docusign-launch/spec.md Increment 2. The canonical input
 * order and value encodings below are correctness-critical and follow that
 * spec's §5.2 exactly - any nondeterminism here (unsorted map iteration, a
 * locale- or timezone-dependent value, a missed field) makes the fingerprint
 * never match, which silently regenerates every time rather than failing
 * loudly.
 */
public with sharing class QuoteDocumentFingerprint {

    /**
     * Names this generation plan. Bump only if the *shape* of the canonical
     * input itself changes (a new section added, an encoding changed) - not
     * for ordinary config changes, which are already covered because the
     * definitions themselves are part of the input.
     */
    @TestVisible
    private static final String PLAN_IDENTITY = 'quote-docusign-launch-v1';

    public static String compute(
        SBQQ__Quote__c quote,
        List<QuoteDocumentLine> lines,
        List<QuoteDocumentTableDefinition> definitions
    ) {
        return digest(canonicalize(quote, lines, definitions));
    }

    /**
     * Reads a dot path off the queried Quote, as a string, for hashing only.
     *
     * Stringified deliberately: the fingerprint compares equality, never
     * magnitude, and a single encoding means a path whose TYPE changes moves
     * the canonical form - which is the correct outcome, since a contributor
     * reading a field that changed type is reading something different.
     *
     * A null relationship part way along a path yields null, which is a real
     * value here - "this quote has no account" is a legitimate input to hash,
     * distinct from "the field does not exist", which QuoteDocumentQuery has
     * already rejected at validation time with DEPENDENCY_UNREADABLE.
     */
    private static String resolvePath(SObject record, String path) {
        List<String> segments = path.split('\\.');
        SObject current = record;

        for (Integer i = 0; i < segments.size() - 1; i++) {
            if (current == null) {
                return null;
            }
            current = current.getSObject(segments[i]);
        }
        if (current == null) {
            return null;
        }

        Object value = current.get(segments[segments.size() - 1]);
        return value == null ? null : String.valueOf(value);
    }

    /**
     * One global content version, bumped whenever dictionary or clause text
     * changes. Deliberately global rather than per-key: blanket invalidation
     * is accepted policy for v1, and per-key dependency tracking is deferred
     * until blanket invalidation is measurably too costly rather than merely
     * inelegant.
     *
     * Absent means "never set", encoded as a stable literal rather than null,
     * so an org that has not adopted content versioning still produces a
     * deterministic hash.
     */
    public static String contentVersion() {
        String version = QuoteDocumentKeyValueMap.get('CONTENT').get('VERSION');
        return String.isBlank(version) ? 'UNVERSIONED' : version;
    }

    /** Ordered so the hash is deterministic; a Set or unordered query would make it drift. */
    private static List<Quote_Document_Content__mdt> orderedContent() {
        return [
            SELECT Block_Code__c, Locale__c, Version__c
            FROM Quote_Document_Content__mdt
            WHERE Is_Active__c = true
            ORDER BY Block_Code__c, Locale__c
        ];
    }

    @TestVisible
    private static String canonicalize(
        SBQQ__Quote__c quote,
        List<QuoteDocumentLine> lines,
        List<QuoteDocumentTableDefinition> definitions
    ) {
        List<String> parts = new List<String>();
        parts.add(encodeString(PLAN_IDENTITY));

        // Ordered table definitions - already ordered by Display_Order__c via
        // QuoteDocumentTableDefinition.getAll(). A deactivated table drops out
        // of this list entirely (Is_Active__c is a query filter, not a stored
        // property), which is what makes deactivating a table change the
        // fingerprint without needing a separate encoded flag for it.
        for (QuoteDocumentTableDefinition definition : definitions) {
            parts.add(encodeString(definition.tableCode));
            parts.add(encodeString(definition.lineFilter));
            parts.add(encodeString(definition.measureSet));
            parts.add(encodeBoolean(definition.showDetails));
            parts.add(encodeBoolean(definition.showSectionTotals));
            parts.add(encodeDecimal(definition.maxGroups));
            parts.add(encodeString(definition.compositeSeparator));
            parts.add(encodeDecimal(definition.displayOrder));
            parts.add(encodeString(definition.sortGroupsBy));
            parts.add(encodeString(definition.amountBasis));
            parts.add(encodeString(definition.rowCustomizerCode));

            // PRESENTATION TEXT - the words the customer actually reads.
            //
            // Omitting these was a real defect, found in review: an admin
            // could correct a heading, a subtitle, a disclaimer or a footer,
            // regenerate, and get the OLD wording back with the quote still
            // reporting Ready. It is the same class of failure the contributor
            // version tokens exist to prevent, introduced by the same step
            // that added the fields.
            parts.add(encodeString(definition.displayTitle));
            parts.add(encodeString(definition.displaySubtitle));
            parts.add(encodeString(definition.introText));
            parts.add(encodeString(definition.footerText));

            // Contributor CONTENT IDENTITY, not bookkeeping. canReuse returns
            // before customization runs, and the code and Flow API name above
            // are strings - they do not move when the logic behind them does.
            // Without these tokens, deploying a changed customizer or editing
            // a Flow leaves the fingerprint identical, the quote stays Ready,
            // and generation reuses a snapshot the new logic would never have
            // produced. Step 01A section 6.
            parts.add(encodeString(definition.rowCustomizerVersion));
            parts.add(encodeString(definition.rowCustomizerFlow));
            parts.add(encodeString(definition.rowCustomizerFlowVersion));

            // The policy itself is hashed so that changing it - which changes
            // whether reuse is legal at all - regenerates rather than being
            // invisible until the next unrelated edit.
            parts.add(encodeString(definition.cachePolicy));

            // Expansion changes how many rows exist and how the money is split
            // between them, all without touching a single quote field. Without
            // these tokens, adding an expander to a definition leaves the
            // fingerprint identical and every quote reuses a snapshot built the
            // old way. expanderVersion covers changed Apex behind an unchanged
            // code, exactly as rowCustomizerVersion does.
            parts.add(encodeString(definition.expanderCode));
            parts.add(encodeString(definition.expanderVersion));
            parts.add(encodeDecimal(definition.periodMonths));
            parts.add(encodeString(definition.periodOneTimePlacement));
            parts.add(encodeString(definition.allocationBasis));
            parts.add(encodeDecimal(definition.allocationScale));
            parts.add(encodeBoolean(definition.suppressAmounts));
            for (String path : definition.contributorDependencyPaths) {
                parts.add(encodeString(path));
            }

            // Ordered grouping definitions - already ordered by Level then
            // Sequence inside groupBy/parts.
            //
            // The STRUCTURE is hashed, not only the parts. Without the level
            // count and the per-level part count, "PRODUCT_FAMILY then
            // CHARGE_TYPE" (two nested levels) and "PRODUCT_FAMILY +
            // CHARGE_TYPE" (one composite level) flatten to an identical
            // fragment - yet QuoteDocumentRowBuilder treats them as completely
            // different documents, one nesting and one combining into single
            // buckets. Metadata edits fire no staleness trigger, so a Ready
            // quote under STANDARD caching would see an unchanged fingerprint
            // and reuse the old hierarchy, with payload integrity passing
            // because the stored output was never edited.
            parts.add('LEVELS:' + definition.groupBy.size());
            Integer levelIndex = 0;
            for (QuoteDocumentTableDefinition.Level level : definition.groupBy) {
                levelIndex++;
                parts.add('LEVEL:' + levelIndex + ':PARTS:' + level.parts.size());
                for (QuoteDocumentTableDefinition.Part part : level.parts) {
                    parts.add(encodeString(part.dimension));
                    parts.add(encodeString(part.fieldPath));
                }
            }
        }

        // Ordered required field paths - allFieldPaths() returns a Set, so it
        // has to be copied and sorted here; never iterate a Set/Map directly,
        // the same rule QuoteDocumentRowBuilder follows for group values.
        List<String> requiredPaths = new List<String>(QuoteDocumentTableDefinition.allFieldPaths());
        requiredPaths.sort();
        for (String path : requiredPaths) {
            parts.add(encodeString(path));
        }

        // Locale, content version, columns and blocks - the four inputs steps
        // 01 to 04 added that the original hash could not see. Without them a
        // translation fix or a clause edit would leave every existing snapshot
        // claiming to be current while printing the old wording.
        //
        // All four are derived here rather than passed in, so every existing
        // caller keeps working and no caller can accidentally omit one.
        parts.add(encodeString(QuoteDocumentLocale.resolve(quote)));
        parts.add(encodeString(contentVersion()));

        for (QuoteDocumentTableDefinition definition : definitions) {
            for (QuoteDocumentColumnDefinition column : QuoteDocumentColumnDefinition.forTable(definition)) {
                parts.add(encodeString(column.columnCode));
                parts.add(encodeDecimal(column.displayOrder));
                parts.add(encodeString(column.valueField));
                parts.add(encodeString(column.dataType));
                // A changed aggregation rule changes the printed numbers
                // without changing a single amount, which is exactly the case
                // canReuse would otherwise get wrong.
                parts.add(encodeString(column.aggregationRule));
                parts.add(encodeString(column.aggregationNumerator));
                parts.add(encodeString(column.aggregationDenominator));
            }
        }

        for (Quote_Document_Content__mdt content : orderedContent()) {
            parts.add(encodeString(content.Block_Code__c));
            parts.add(encodeString(content.Version__c));
        }

        // Quote-level values.
        parts.add(encodeDecimal(quote.SBQQ__NetAmount__c));
        parts.add(encodeString(quote.AccountIndustry__c));

        // The quote term defines the month grid MONTHLY_SUBSCRIPTION_SUMMARY
        // allocates into. Moving the start date or shortening the term
        // repositions every row of that table without moving a single amount,
        // so without these two an edited term reuses a snapshot built against
        // the old one.
        parts.add(encodeString(String.valueOf(quote.SBQQ__StartDate__c)));
        parts.add(encodeDecimal(quote.SBQQ__SubscriptionTerm__c));
        if (UserInfo.isMultiCurrencyOrganization()) {
            parts.add(encodeString((String) quote.get('CurrencyIsoCode')));
        }

        // Declared contributor dependency VALUES - the other half of section
        // 6a. A version token identifies the contributor's LOGIC; it says
        // nothing about the data that logic read. Nothing in this framework
        // watches anything outside the quote and its lines, so an Account
        // field a Flow reads can change with no trigger, no staleness, and an
        // unchanged fingerprint - and the document keeps printing the old
        // value. Hashing the declared values closes that, but only on the
        // next generate(): HASHING IS NOT INVALIDATION, which is why the
        // launch contract in step 01A section 6b requires every launch to
        // call generate-or-reuse rather than read a Ready snapshot directly.
        //
        // Read off the definitions PASSED IN, not the global config, so the
        // canonical form always describes the plan actually being generated -
        // the same reason every other section of this method walks the
        // argument rather than re-reading getAll().
        List<String> dependencyPaths = new List<String>();
        Set<String> seenPaths = new Set<String>();
        for (QuoteDocumentTableDefinition definition : definitions) {
            if (!QuoteDocumentTableDefinition.CACHE_DECLARED_DEPENDENCIES.equals(definition.cachePolicy)) {
                continue;
            }
            for (String path : definition.contributorDependencyPaths) {
                if (seenPaths.add(path)) {
                    dependencyPaths.add(path);
                }
            }
        }
        dependencyPaths.sort();

        for (String path : dependencyPaths) {
            parts.add(encodeString(path));
            parts.add(encodeString(resolvePath(quote, path)));
        }

        // Ordered Quote Line IDs.
        Map<Id, QuoteDocumentLine> lineById = new Map<Id, QuoteDocumentLine>();
        for (QuoteDocumentLine line : lines) {
            lineById.put(line.quoteLineId, line);
        }
        List<Id> orderedIds = new List<Id>(lineById.keySet());
        orderedIds.sort();
        for (Id lineId : orderedIds) {
            parts.add(encodeId(lineId));
        }

        // Typed field values per line, in the same order.
        for (Id lineId : orderedIds) {
            QuoteDocumentLine line = lineById.get(lineId);
            // Sequence, because it decides PRINTED ORDER: detail rows are
            // emitted in it, and LINE_SEQUENCE group ordering reads it. Swapping
            // two SBQQ__Number__c values changes the document without changing
            // any amount. The line trigger does mark the quote Stale eventually,
            // but that write is deferred to a future method - a generate-or-reuse
            // landing inside that window would otherwise reuse the old order,
            // which is exactly the gap the fingerprint exists to close
            // independently of eventual staleness.
            parts.add(encodeDecimal(line.sequence));
            parts.add(encodeString(line.productName));
            parts.add(encodeString(line.productCode));
            parts.add(encodeString(line.productFamily));
            parts.add(encodeString(line.chargeType));
            parts.add(encodeString(line.industry));
            parts.add(encodeString(line.quoteLineGroup));
            parts.add(encodeBoolean(line.isPackage));
            parts.add(encodeBoolean(line.isBundledComponent));
            parts.add(encodeBoolean(line.isOptional));
            parts.add(encodeDecimal(line.optionLevel));
            parts.add(encodeString(line.packageName));
            parts.add(encodeBoolean(line.isDisplayed));
            parts.add(encodeDecimal(line.amountList));
            parts.add(encodeDecimal(line.amountRegular));
            parts.add(encodeDecimal(line.amountDiscount));
            parts.add(encodeDecimal(line.amountNet));
            parts.add(encodeDecimal(line.amountCustomer));
            parts.add(encodeDecimal(line.quantity));

            // A line's own window decides which months it appears in. Nothing
            // else in the canonical form moves when only a date moves.
            parts.add(encodeString(String.valueOf(line.subscriptionStartDate)));
            parts.add(encodeString(String.valueOf(line.subscriptionEndDate)));

            parts.add(encodeString(line.transactionType));
            parts.add(encodeDecimal(line.amountNetNew));
            parts.add(encodeDecimal(line.amountCancellation));
            parts.add(encodeDecimal(line.amountReplacementRemoved));
            parts.add(encodeDecimal(line.amountReplacementAdded));
            parts.add(encodeDecimal(line.amountTermination));
            parts.add(encodeDecimal(line.amountNetChange));
            parts.add(encodeDecimal(line.amountFinal));

            // Resolved value of every configured field path, e.g. a Product2
            // field used in a grouping - this is what closes the gap
            // trigger-based staleness cannot see.
            for (String path : requiredPaths) {
                parts.add(encodeString(line.fieldPathValue(path)));
            }
        }

        return String.join(parts, '|');
    }

    private static String digest(String canonical) {
        Blob hash = Crypto.generateDigest('SHA-256', Blob.valueOf(canonical));
        return EncodingUtil.convertToHex(hash);
    }

    // -----------------------------------------------------------------------
    // Value encodings - unambiguous, locale-free. See spec §5.2.
    // -----------------------------------------------------------------------

    @TestVisible
    private static String encodeString(String value) {
        return value == null ? 'NULL' : 'STRING:' + value.length() + ':' + value;
    }

    /**
     * Fixed scale rather than stripped, so 10.5 and 10.50 - the same amount,
     * written with different precision - normalize to the same token instead
     * of producing different digests for no real change.
     */
    @TestVisible
    private static String encodeDecimalForTest(Decimal value) {
        return encodeDecimal(value);
    }

    @TestVisible
    private static String encodeStringForTest(String value) {
        return encodeString(value);
    }

    @TestVisible
    private static String encodeDecimal(Decimal value) {
        return value == null ? 'NULL' : 'DECIMAL:' + value.setScale(2).toPlainString();
    }

    @TestVisible
    private static String encodeBoolean(Boolean value) {
        return value == null ? 'NULL' : (value ? 'BOOLEAN:1' : 'BOOLEAN:0');
    }

    @TestVisible
    private static String encodeId(Id value) {
        // A queried Id is already 18 characters; String.valueOf normalizes a
        // 15-character Id assigned to an Id variable the same way.
        return value == null ? 'NULL' : 'ID:' + String.valueOf(value);
    }

    @TestVisible
    private static String encodeDate(Date value) {
        if (value == null) { return 'NULL'; }
        return 'DATE:' + value.year() + '-' + pad(value.month()) + '-' + pad(value.day());
    }

    /** Canonicalized to UTC, never the running user's timezone. */
    @TestVisible
    private static String encodeDateTime(Datetime value) {
        return value == null ? 'NULL' : 'DATETIME:' + value.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }

    private static String pad(Integer value) {
        return value < 10 ? '0' + value : String.valueOf(value);
    }
}
