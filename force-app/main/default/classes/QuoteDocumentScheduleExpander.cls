/**
 * Expands lines along a configured schedule: payment milestones, project
 * phases, departments, promotional periods - any axis whose buckets and
 * weights are authored rather than derived from the quote.
 *
 * WHY THIS IS THE SECOND EXPANDER
 * -------------------------------
 * QuoteDocumentPeriodExpander derives everything from the quote's own term. A
 * schedule cannot: nothing on a quote says "30% at signing". Those buckets and
 * their relative weights come from Quote_Document_Schedule__mdt, which is
 * ordered child metadata in exactly the shape Quote_Document_Grouping__mdt and
 * Quote_Document_Column_Def__mdt already use.
 *
 * Between the two, the four cases that motivated allocation are configuration
 * rather than code: installments, department splits, project phases, and
 * promotional pricing where some periods are free.
 *
 * WEIGHTS ARE RELATIVE, AND THAT IS LOAD-BEARING
 * ----------------------------------------------
 * 30/40/30 and 3/4/3 split identically, and 30/40/25 is a valid 32/42/26 split
 * rather than an error - QuoteDocumentAllocation cannot tell a deliberate ratio
 * from a typo, and neither can this. What it CAN see is a schedule whose
 * weights sum to neither 1 nor 100, which is usually a typo and occasionally
 * deliberate, so it warns in the generation log and still generates. Failing
 * would break the legitimate case; silence would hide the typo.
 *
 * A ZERO WEIGHT IS A FREE PERIOD, NOT AN ABSENT ONE
 * -------------------------------------------------
 * Months 1-2 free, 3-6 at half rate, 7-12 at full rate is weights 0,0,1,1,1,1,
 * 2,2,2,2,2,2. The free months print at exactly 0.00 and never absorb the
 * rounding residual - a promotional month showing a cent is the defect
 * QuoteDocumentAllocation's last-non-zero rule exists to prevent. They are
 * printed rather than omitted, because a missing month reads as a gap in
 * service.
 *
 * EVERY LINE OCCUPIES EVERY BUCKET
 * --------------------------------
 * A milestone is a slice of the whole quote, not of one product, so each line
 * contributes its share to each bucket. That is what makes an installment
 * table work without any expansion source on the line itself - the case
 * step 02 section 3.4 describes.
 *
 * See docs/quote-document-extension-recipes.md.
 */
public with sharing class QuoteDocumentScheduleExpander implements QuoteDocumentLineExpander {

    public static final String CODE = 'SCHEDULE';

    public static final String ERR_UNDECLARED = 'SCHEDULE_CODE_UNDECLARED';
    public static final String ERR_EMPTY = 'SCHEDULE_NOT_FOUND';
    public static final String ERR_WEIGHTS = 'SCHEDULE_WEIGHTS_INVALID';
    public static final String ERR_LABEL_ARG = 'SCHEDULE_LABEL_ARGUMENT_MISSING';

    /** One authored bucket. Public so a test can build a schedule without metadata. */
    public class Entry {
        public String bucketCode;
        public String labelKey;
        public String labelArg1;
        public Decimal weight;
        public Integer displayOrder;

        public Entry(String bucketCode, String labelKey, Decimal weight, Integer displayOrder) {
            this(bucketCode, labelKey, null, weight, displayOrder);
        }

        /**
         * With an argument, so one parameterised dictionary entry can serve a
         * whole schedule - twelve promotional months share MONTH_LABEL and
         * supply 1..12 rather than needing twelve entries of their own.
         */
        public Entry(
            String bucketCode, String labelKey, String labelArg1, Decimal weight, Integer displayOrder
        ) {
            this.bucketCode = bucketCode;
            this.labelKey = labelKey;
            this.labelArg1 = labelArg1;
            this.weight = weight;
            this.displayOrder = displayOrder;
        }
    }

    /** Test seam, mirroring QuoteDocumentTableDefinition.useDefinitions. */
    @TestVisible
    private static Map<String, List<Entry>> overrides;

    @TestVisible
    private static void useSchedules(Map<String, List<Entry>> schedules) {
        overrides = schedules;
    }

    public List<QuoteDocumentExpansion.Bucket> buckets(QuoteDocumentExpansion.Request request) {
        List<Entry> entries = entriesFor(request.definition);

        List<QuoteDocumentExpansion.Bucket> buckets = new List<QuoteDocumentExpansion.Bucket>();
        Decimal total = 0;

        for (Integer i = 0; i < entries.size(); i++) {
            Entry entry = entries[i];
            total += entry.weight == null ? 0 : entry.weight;

            String label = String.isBlank(entry.labelArg1)
                ? request.labels.resolve(entry.labelKey)
                : request.labels.format(entry.labelKey, new List<String>{ entry.labelArg1 });

            // A parameterised key resolved with no argument keeps its "{0}",
            // which makes every bucket in the schedule print - and KEY - the
            // same text. The builder catches the resulting duplicate row key,
            // but only after generation has done all its work, and the message
            // it gives blames the grouping rather than the schedule. Caught
            // here instead, naming the row that is actually wrong.
            if (label != null && label.contains('{')) {
                QuoteDocumentContributorError.fail(
                    ERR_LABEL_ARG,
                    'Schedule ' + request.definition.scheduleCode + ', section ' + entry.bucketCode
                        + ' uses dictionary key ' + entry.labelKey + ', which expects an argument, but '
                        + 'sets no Label_Arg_1__c. Every section would print the same heading and they '
                        + 'would collide.'
                );
            }

            QuoteDocumentExpansion.Bucket bucket = new QuoteDocumentExpansion.Bucket(
                entry.bucketCode, label, i + 1
            );
            bucket.labelKey = entry.labelKey;
            bucket.labelArg1 = entry.labelArg1;
            buckets.add(bucket);
        }

        if (total == 0) {
            QuoteDocumentContributorError.fail(
                ERR_WEIGHTS,
                'Schedule ' + request.definition.scheduleCode + ' has no positive weight anywhere, so '
                    + 'there is nowhere for the money to land. A table where nothing is allocated is a '
                    + 'configuration error, not an empty document.'
            );
        }

        // Neither a failure nor silence. An author who meant percentages and
        // typed 30/40/25 has quietly reallocated the quote; an author who meant
        // a ratio is entirely correct. Only one of them can be told from here.
        if (total != 1 && total != 100) {
            System.debug(
                LoggingLevel.WARN,
                'Schedule ' + request.definition.scheduleCode + ' weights sum to ' + total
                    + ', which is neither 1 nor 100. They are being treated as RELATIVE proportions, so '
                    + 'the whole amount is still allocated. If these were meant as percentages, one of '
                    + 'them is wrong.'
            );
        }
        return buckets;
    }

    /**
     * Every line, in every bucket, at that bucket's weight. A milestone is a
     * slice of the quote rather than of one product.
     */
    public List<QuoteDocumentExpansion.Placement> placements(
        QuoteDocumentLine line, QuoteDocumentExpansion.Request request
    ) {
        List<QuoteDocumentExpansion.Placement> placements =
            new List<QuoteDocumentExpansion.Placement>();

        for (Entry entry : entriesFor(request.definition)) {
            placements.add(new QuoteDocumentExpansion.Placement(
                entry.bucketCode, entry.weight == null ? 0 : entry.weight
            ));
        }
        return placements;
    }

    /**
     * Configurable, because the two shapes this expander serves disagree.
     *
     * A department split divides quantity - each department gets its own share
     * of the seats, and they are different seats. A payment schedule does not:
     * the same products are covered by every milestone, so repeating is right
     * and dividing would print a third of a licence per instalment.
     */
    public Boolean dividesQuantity() {
        return dividesQuantityForCurrentDefinition;
    }

    /**
     * Set immediately before use by entriesFor, which is the only method with
     * the definition in hand. Instances are created per table by the registry
     * and never shared across them.
     */
    private Boolean dividesQuantityForCurrentDefinition = false;

    private List<Entry> entriesFor(QuoteDocumentTableDefinition definition) {
        dividesQuantityForCurrentDefinition = definition.scheduleDividesQuantity == true;

        if (String.isBlank(definition.scheduleCode)) {
            QuoteDocumentContributorError.fail(
                ERR_UNDECLARED,
                'Table ' + definition.tableCode + ' uses the SCHEDULE expander but names no '
                    + 'Schedule_Code__c. The buckets and their weights are authored, not derived - there '
                    + 'is nothing on a quote that says "30% at signing".'
            );
        }

        List<Entry> entries = overrides != null
            ? overrides.get(definition.scheduleCode)
            : fromMetadata(definition.scheduleCode);

        if (entries == null || entries.isEmpty()) {
            QuoteDocumentContributorError.fail(
                ERR_EMPTY,
                'Table ' + definition.tableCode + ' names schedule "' + definition.scheduleCode
                    + '", which has no active Quote_Document_Schedule__mdt records. An empty schedule '
                    + 'would produce a table with no sections and a total nobody can check.'
            );
        }
        return entries;
    }

    private static Map<String, List<Entry>> cached;

    private static List<Entry> fromMetadata(String scheduleCode) {
        if (cached == null) {
            cached = new Map<String, List<Entry>>();
            for (Quote_Document_Schedule__mdt record : [
                SELECT Schedule_Code__c, Bucket_Code__c, Label_Key__c, Label_Arg_1__c,
                       Weight__c, Display_Order__c
                FROM Quote_Document_Schedule__mdt
                WHERE Is_Active__c = true
                ORDER BY Schedule_Code__c, Display_Order__c
            ]) {
                if (!cached.containsKey(record.Schedule_Code__c)) {
                    cached.put(record.Schedule_Code__c, new List<Entry>());
                }
                cached.get(record.Schedule_Code__c).add(new Entry(
                    record.Bucket_Code__c,
                    record.Label_Key__c,
                    record.Label_Arg_1__c,
                    record.Weight__c,
                    record.Display_Order__c == null ? 0 : Integer.valueOf(record.Display_Order__c)
                ));
            }
        }
        return cached.get(scheduleCode);
    }
}
