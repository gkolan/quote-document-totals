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

            // Ordered grouping definitions - already ordered by Level then
            // Sequence inside groupBy/parts.
            for (QuoteDocumentTableDefinition.Level level : definition.groupBy) {
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

        // Quote-level values.
        parts.add(encodeDecimal(quote.SBQQ__NetAmount__c));
        parts.add(encodeString(quote.AccountIndustry__c));
        if (UserInfo.isMultiCurrencyOrganization()) {
            parts.add(encodeString((String) quote.get('CurrencyIsoCode')));
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
