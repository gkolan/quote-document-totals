/**
 * One Quote Line, normalized once.
 *
 * The raw CPQ line is inspected here and nowhere else. Everything downstream -
 * filtering, grouping, totalling - reads these properties instead of poking at
 * SBQQ__ fields, so the commercial rules live in one readable place.
 *
 * The three methods worth reading first are applyInclusionRules, classify and
 * getGroupingValue. Between them they decide what counts, why it counts, and
 * where it lands.
 *
 * Measures are explicit properties rather than a Map<String, Decimal>. A typo
 * in a map key silently returns zero; a typo in a property name is a compile
 * error, and a document with a silently-wrong total is the thing this whole
 * design exists to prevent.
 */
public with sharing class QuoteDocumentLine {

    private static final String NOT_SPECIFIED = 'Not Specified';
    private static final String STANDALONE = 'Uncategorized';

    public Id quoteLineId;
    public Id productId;
    public Integer sequence;

    // Snapshots - what the document prints, captured at generation time.
    public String productName;
    public String productCode;
    public String productFamily;
    public String chargeType;
    public String industry;
    public String quoteLineGroup;

    // Bundle context.
    public Boolean isPackage;
    public Boolean isBundledComponent;
    public Boolean isOptional;
    public Integer optionLevel;
    public String packageName;

    // Inclusion. Whether a line is shown is intrinsic; whether it counts also
    // depends on what the table is for - see countsIn().
    public Boolean isDisplayed;

    // Price waterfall.
    public Decimal amountList = 0;
    public Decimal amountRegular = 0;
    public Decimal amountDiscount = 0;
    public Decimal amountNet = 0;
    public Decimal amountCustomer = 0;
    public Decimal quantity = 0;

    // The subscription window this line is priced for. Blank means "the whole
    // quote term" - the same thing CPQ's own SBQQ__EffectiveStartDate__c
    // formula says. The writable pair is read rather than the formula pair so
    // a test can set a window without going through CPQ's calculator.
    public Date subscriptionStartDate;
    public Date subscriptionEndDate;

    // Change measures, decided by classify. Removals are always negative.
    public String transactionType;
    public Decimal amountNetNew = 0;
    public Decimal amountCancellation = 0;
    public Decimal amountReplacementRemoved = 0;
    public Decimal amountReplacementAdded = 0;
    public Decimal amountTermination = 0;
    public Decimal amountNetChange = 0;
    public Decimal amountFinal = 0;

    /** The BEFORE amount on a comparison row. Zero everywhere else. */
    public Decimal amountBaseline = 0;

    /**
     * The record this line was built from, kept so a configured field path can
     * be resolved without adding a property for every groupable field.
     */
    private SBQQ__QuoteLine__c raw;

    public QuoteDocumentLine(SBQQ__QuoteLine__c line, SBQQ__Quote__c quote) {
        raw = line;
        quoteLineId = line.Id;
        productId = line.SBQQ__Product__c;
        sequence = line.SBQQ__Number__c == null ? 0 : Integer.valueOf(line.SBQQ__Number__c);

        productName = line.SBQQ__ProductName__c;
        productCode = line.SBQQ__ProductCode__c;
        productFamily = line.SBQQ__Product__r == null ? null : line.SBQQ__Product__r.Family;
        chargeType = line.SBQQ__ChargeType__c;
        industry = quote.AccountIndustry__c;
        quoteLineGroup = line.SBQQ__Group__r == null ? null : line.SBQQ__Group__r.Name;

        isPackage = line.SBQQ__Bundle__c == true;
        isBundledComponent = line.SBQQ__Bundled__c == true;
        isOptional = line.SBQQ__Optional__c == true;
        optionLevel = line.SBQQ__OptionLevel__c == null ? 0 : Integer.valueOf(line.SBQQ__OptionLevel__c);
        packageName = line.SBQQ__RequiredBy__r == null ? null : line.SBQQ__RequiredBy__r.SBQQ__ProductName__c;

        amountList = zero(line.SBQQ__ListTotal__c);
        amountRegular = zero(line.SBQQ__RegularTotal__c);
        amountDiscount = zero(line.SBQQ__TotalDiscountAmount__c);
        amountNet = zero(line.SBQQ__NetTotal__c);
        amountCustomer = zero(line.SBQQ__CustomerTotal__c);
        quantity = zero(line.SBQQ__Quantity__c);

        subscriptionStartDate = line.SBQQ__StartDate__c;
        subscriptionEndDate = line.SBQQ__EndDate__c;

        isDisplayed = true;
        classify(line);
    }

    /**
     * Whether this line's amounts feed the totals of a table built with the
     * given filter. Counting is table-relative, which the two exclusions show:
     *
     *   A bundled component never counts anywhere - its price is already inside
     *   the package price, so counting it would double-count the package.
     *
     *   An optional product does not count in an ordinary table, because CPQ's
     *   own SBQQ__NetAmount__c roll-up excludes it and the document must agree
     *   with the Quote. It does count in the Optional Products table, whose
     *   entire subject is those lines - a zero total there would be absurd.
     */
    public Boolean countsIn(String lineFilter) {
        if (isBundledComponent) {
            return false;
        }
        if (isOptional) {
            return QuoteDocumentTableDefinition.FILTER_OPTIONAL_ONLY.equals(lineFilter);
        }
        return true;
    }

    /**
     * Which change measure this line feeds, and with what sign.
     *
     * PROVISIONAL. This org holds no amendment or renewal quotes, so every real
     * line lands on Net New and the other branches have never been checked
     * against production data. Confirm these rules against a genuine amendment
     * before a document depends on them.
     *
     * A cancellation is worth noting: the amended line ends at quantity zero,
     * so its own Net Total is zero. The value that leaves the deal is the prior
     * quantity at the current price, which is why this reads
     * SBQQ__PriorQuantity__c rather than the line total.
     */
    private void classify(SBQQ__QuoteLine__c line) {
        Boolean existing = line.SBQQ__Existing__c == true;
        Boolean replaced = line.SBQQ__UpgradedSubscription__c != null
                        || line.SBQQ__RenewedSubscription__c != null;

        Decimal priorValue = zero(line.SBQQ__PriorQuantity__c) * zero(line.SBQQ__NetPrice__c);

        if (replaced) {
            // A replacement is a pair: the old value leaves, the new arrives.
            // The leaving side is the one amended down to nothing - CPQ stores
            // a zero quantity rather than a negative total - so its value has
            // to come from the prior quantity.
            if (quantity == 0 || amountNet < 0) {
                transactionType = 'Replacement Removed';
                amountReplacementRemoved = negative(priorValue != 0 ? priorValue : amountNet);
            } else {
                transactionType = 'Replacement Added';
                amountReplacementAdded = amountNet;
            }
        } else if (existing && quantity == 0) {
            transactionType = 'Cancellation';
            amountCancellation = negative(priorValue);
        } else if (existing && amountNet < 0) {
            transactionType = 'Termination';
            amountTermination = negative(amountNet);
        } else {
            transactionType = 'Net New';
            amountNetNew = amountNet;
        }

        amountNetChange = amountNetNew + amountCancellation + amountReplacementRemoved
                        + amountReplacementAdded + amountTermination;
        amountFinal = amountNet;
    }

    /**
     * Where this line sits at one grouping level.
     *
     * One part gives a plain value. Several parts give a composite - the parts
     * joined by the table's separator, so "Hardware" and "Recurring" become the
     * single bucket "Hardware / Recurring" rather than one nested inside the
     * other.
     */
    public String getGroupingValue(QuoteDocumentTableDefinition.Level level, String separator) {
        if (level.parts.size() == 1) {
            return partValue(level.parts[0]);
        }

        List<String> values = new List<String>();
        for (QuoteDocumentTableDefinition.Part part : level.parts) {
            values.add(partValue(part));
        }
        return String.join(values, separator);
    }

    private String partValue(QuoteDocumentTableDefinition.Part part) {
        return part.isFieldPath() ? resolvePath(part.fieldPath) : getGroupingValue(part.dimension);
    }

    /** Public wrapper around resolvePath for callers outside this class, e.g. QuoteDocumentFingerprint. */
    public String fieldPathValue(String fieldPath) {
        return resolvePath(fieldPath);
    }

    /**
     * Reads a configured field path off the record, walking relationships.
     *
     * Unlike the measures - where a wrong key would put a silently wrong number
     * in a total - a wrong grouping is visible in the output or throws here, so
     * resolving dynamically is a fair trade for losing the developer from the
     * loop. The path is schema-validated when definitions load, so by the time
     * this runs the only realistic failure is a null along the way.
     */
    @TestVisible
    private String resolvePath(String fieldPath) {
        List<String> segments = fieldPath.split('\\.');
        SObject current = raw;

        for (Integer i = 0; i < segments.size() - 1; i++) {
            if (current == null) {
                return NOT_SPECIFIED;
            }
            current = current.getSObject(segments[i]);
        }

        if (current == null) {
            return NOT_SPECIFIED;
        }

        Object value = current.get(segments[segments.size() - 1]);
        return value == null ? NOT_SPECIFIED : normalize(String.valueOf(value));
    }

    /**
     * Where this line sits under a named dimension - one the generator computes
     * rather than reads. Anything that is a plain field should be configured as
     * a field path instead and never reach this switch.
     */
    public String getGroupingValue(String dimension) {
        switch on dimension {
            when 'PRODUCT_FAMILY' {
                return normalize(productFamily);
            }
            when 'CHARGE_TYPE' {
                // A blank charge type in CPQ means a one-off charge.
                return String.isBlank(chargeType) ? 'One-Time' : chargeType;
            }
            when 'QUOTE_LINE_GROUP' {
                return normalize(quoteLineGroup);
            }
            when 'BUNDLE' {
                if (String.isNotBlank(packageName)) { return packageName; }
                // normalize() like every sibling branch: a bundle parent whose
                // SBQQ__ProductName__c is null used to return null here, and the
                // null reached buildGroupKey's value.toUpperCase() as a
                // dereference - generation failing on a quote with a message
                // that explained nothing.
                return normalize(isPackage ? productName : STANDALONE);
            }
            when 'TRANSACTION_TYPE' {
                return normalize(transactionType);
            }
            when 'INDUSTRY' {
                return normalize(industry);
            }
            when 'EXPANSION' {
                // Already localized by the expander, which is the only thing
                // that knows what its own buckets are called. normalize() would
                // only ever fire on a line the expander failed to stamp, and
                // that is a bug worth seeing rather than papering over.
                if (String.isBlank(expansionValue)) {
                    throw new QuoteDocumentGenerator.QuoteDocumentException(
                        'A table grouped by EXPANSION contains a line that was never expanded ('
                        + productName + '). Set Expander_Code__c on the table definition, or group by '
                        + 'something the lines actually carry.'
                    );
                }
                return expansionValue;
            }
            when else {
                throw new QuoteDocumentGenerator.QuoteDocumentException(
                    'Unsupported grouping dimension: ' + dimension
                );
            }
        }
    }

    /**
     * Whether a table built with this filter should include this line at all.
     * Mirrors the filter fields on CPQ's own Template Section.
     */
    // -----------------------------------------------------------------------
    // Expansion - see QuoteDocumentLineExpander
    // -----------------------------------------------------------------------

    /**
     * The bucket this line was expanded into, or null on an ordinary line.
     *
     * Three fields rather than one because they answer three different
     * questions: the KEY is stable identity (row keys, fingerprints), the
     * VALUE is the already-localized text a group header prints, and the ORDER
     * is what stops month 10 sorting before month 2.
     */
    public String expansionKey;
    public String expansionValue;
    public Integer expansionOrder;

    public Boolean isExpanded() {
        return expansionKey != null;
    }

    /**
     * A copy carrying one bucket's share of this line.
     *
     * Everything identifying is shared with the original - same quote line Id,
     * same product, same filter behaviour - so a table can still group, filter
     * and indent an expanded line exactly as it would the line it came from.
     * Only the measures differ, and only because the caller overwrites them.
     */
    public QuoteDocumentLine copyInto(String bucketKey, String bucketValue, Integer bucketOrder) {
        QuoteDocumentLine copy = new QuoteDocumentLine(this);
        copy.expansionKey = bucketKey;
        copy.expansionValue = bucketValue;
        copy.expansionOrder = bucketOrder;
        return copy;
    }

    private QuoteDocumentLine(QuoteDocumentLine source) {
        raw = source.raw;
        quoteLineId = source.quoteLineId;
        productId = source.productId;
        sequence = source.sequence;
        productName = source.productName;
        productCode = source.productCode;
        productFamily = source.productFamily;
        chargeType = source.chargeType;
        industry = source.industry;
        quoteLineGroup = source.quoteLineGroup;
        isPackage = source.isPackage;
        isBundledComponent = source.isBundledComponent;
        isOptional = source.isOptional;
        optionLevel = source.optionLevel;
        packageName = source.packageName;
        isDisplayed = source.isDisplayed;
        amountList = source.amountList;
        amountRegular = source.amountRegular;
        amountDiscount = source.amountDiscount;
        amountNet = source.amountNet;
        amountCustomer = source.amountCustomer;
        quantity = source.quantity;
        subscriptionStartDate = source.subscriptionStartDate;
        subscriptionEndDate = source.subscriptionEndDate;
        transactionType = source.transactionType;
        amountNetNew = source.amountNetNew;
        amountCancellation = source.amountCancellation;
        amountReplacementRemoved = source.amountReplacementRemoved;
        amountReplacementAdded = source.amountReplacementAdded;
        amountTermination = source.amountTermination;
        amountNetChange = source.amountNetChange;
        amountFinal = source.amountFinal;
        amountBaseline = source.amountBaseline;
    }

    /**
     * A copy for a comparison row to overwrite. Same shape as the expansion
     * copy and for the same reason: two tables built from one line list must
     * not see each other's arithmetic.
     */
    public QuoteDocumentLine copyForComparison() {
        return new QuoteDocumentLine(this);
    }

    /**
     * One measure by its Quote_Document_Row__c API name, so allocation can
     * iterate whatever measureFields() returns rather than naming each measure
     * itself. An unknown field answers zero rather than silently reading a
     * different measure's money.
     */
    public Decimal measureValue(String field) {
        switch on field {
            when 'Amount_List__c'                { return amountList; }
            when 'Amount_Regular__c'             { return amountRegular; }
            when 'Amount_Discount__c'            { return amountDiscount; }
            when 'Amount_Net__c'                 { return amountNet; }
            when 'Amount_Customer__c'            { return amountCustomer; }
            when 'Quantity__c'                   { return quantity; }
            when 'Amount_Net_New__c'             { return amountNetNew; }
            when 'Amount_Cancellation__c'        { return amountCancellation; }
            when 'Amount_Replacement_Removed__c' { return amountReplacementRemoved; }
            when 'Amount_Replacement_Added__c'   { return amountReplacementAdded; }
            when 'Amount_Termination__c'         { return amountTermination; }
            when 'Amount_Net_Change__c'          { return amountNetChange; }
            when 'Amount_Baseline__c'            { return amountBaseline; }
            when 'Amount_Final__c'               { return amountFinal; }
            when else                            { return 0; }
        }
    }

    /** The setter half of measureValue. Same reasoning, same field names. */
    public void setMeasure(String field, Decimal value) {
        Decimal amount = value == null ? 0 : value;
        switch on field {
            when 'Amount_List__c'                { amountList = amount; }
            when 'Amount_Regular__c'             { amountRegular = amount; }
            when 'Amount_Discount__c'            { amountDiscount = amount; }
            when 'Amount_Net__c'                 { amountNet = amount; }
            when 'Amount_Customer__c'            { amountCustomer = amount; }
            when 'Quantity__c'                   { quantity = amount; }
            when 'Amount_Net_New__c'             { amountNetNew = amount; }
            when 'Amount_Cancellation__c'        { amountCancellation = amount; }
            when 'Amount_Replacement_Removed__c' { amountReplacementRemoved = amount; }
            when 'Amount_Replacement_Added__c'   { amountReplacementAdded = amount; }
            when 'Amount_Termination__c'         { amountTermination = amount; }
            when 'Amount_Net_Change__c'          { amountNetChange = amount; }
            when 'Amount_Baseline__c'            { amountBaseline = amount; }
            when 'Amount_Final__c'               { amountFinal = amount; }
            when else {
                throw new QuoteDocumentGenerator.QuoteDocumentException(
                    'Cannot allocate ' + field + ': it is not a measure this framework writes.'
                );
            }
        }
    }

    public Boolean matchesFilter(String filter) {
        switch on filter {
            when 'ALL' {
                return true;
            }
            when 'EXCLUDE_OPTIONAL' {
                return !isOptional;
            }
            when 'OPTIONAL_ONLY' {
                return isOptional;
            }
            when 'RECURRING_ONLY' {
                return 'Recurring'.equals(chargeType);
            }
            when 'ONE_TIME_ONLY' {
                return !'Recurring'.equals(chargeType);
            }
            when 'BUNDLE_PARENTS_ONLY' {
                return isPackage || !isBundledComponent;
            }
            when else {
                throw new QuoteDocumentGenerator.QuoteDocumentException(
                    'Unsupported line filter: ' + filter
                );
            }
        }
    }

    /**
     * How deep this line is drawn under its group header. Only the bundle view
     * indents, and it indents by CPQ's own option level.
     */
    public Integer indentUnder(Integer groupLevel, Boolean isBundleLevel) {
        if (isBundleLevel == true && optionLevel > 0) {
            return groupLevel + optionLevel;
        }
        return groupLevel;
    }

    private static Decimal zero(Decimal value) {
        return value == null ? 0 : value;
    }

    private static Decimal negative(Decimal value) {
        return value == null ? 0 : -Math.abs(value);
    }

    private static String normalize(String value) {
        return String.isBlank(value) ? NOT_SPECIFIED : value.trim();
    }
}
