/**
 * Reference implementation of QuoteDocumentRowCustomizer, attached to the
 * INDUSTRY_ALLEGIANCE_EXAMPLE table definition. Walked through in full in
 * docs/quote-document-row-customizer-guide.md §12 - read that section before
 * using this class as a template for a real one.
 *
 * Demonstrates a shape the declarative grouping config on
 * Quote_Document_Table_Def__mdt cannot produce on its own: grouping by a
 * value that depends on the GROUP'S OWN TOTAL, which does not exist yet at
 * the time grouping normally happens. QuoteDocumentRowBuilder groups lines
 * before it totals them - there is no such thing as "group by a number you
 * haven't computed." A customizer runs after the totals exist, which is
 * exactly what makes this possible: it re-groups from scratch using the
 * already-computed line-level measures.
 *
 * THE RULE
 * --------
 * Each Product Name maps to one Industry Name via a Quote_Document_Key_Value__mdt
 * row in the "Industry Map" category (see QuoteDocumentKeyValueMap). The map
 * is an OVERRIDE, not a catalog - most products have no entry, and every
 * unmapped product defaults straight to the FALLBACK_INDUSTRY bucket.
 *
 * Lines are first bucketed by their mapped (or default) Industry Name, and
 * each bucket's Amount_Net__c is totalled. Then, in a SINGLE pass against
 * those pre-reassignment totals (never a cascade - a bucket that receives
 * reassigned lines is not itself re-evaluated, which keeps the outcome
 * deterministic and rules out a bucket bouncing between targets):
 *
 *   total == 0        -> the whole bucket moves to FALLBACK_INDUSTRY
 *   total > threshold  -> the whole bucket moves to OVERFLOW_INDUSTRY
 *   otherwise          -> the bucket keeps its mapped Industry Name
 *
 * The grand total row is left untouched: it already sums the same lines
 * under the same Line_Filter__c, so re-bucketing them cannot change it - the
 * usual grand-total-vs-subtotals reconciliation in
 * QuoteDocumentGenerator.verify() still has to pass, and does, because every
 * counted line lands in exactly one final bucket.
 */
public class QuoteDocumentIndustryRowCustomizer implements QuoteDocumentRowCustomizer {

    public static final String CATEGORY = 'Industry Map';
    public static final String FALLBACK_INDUSTRY = 'Other(s)';
    public static final String OVERFLOW_INDUSTRY = 'Key Accounts';

    @TestVisible
    private static final Decimal OVERFLOW_THRESHOLD = 1000;

    private class Bucket {
        String industryName;
        QuoteDocumentRowBuilder.Measures measures = new QuoteDocumentRowBuilder.Measures();
        List<QuoteDocumentLine> lines = new List<QuoteDocumentLine>();

        void addLine(QuoteDocumentLine line) {
            lines.add(line);
            measures.add(line);
        }
    }

    public List<Quote_Document_Row__c> customize(QuoteDocumentRowCustomizerContext context) {
        // Every reassignment decision below reads bucket.measures.amountNet,
        // which QuoteDocumentRowBuilder.Measures.writeTo() only ever fills in
        // for a PRICE_WATERFALL table (see its own measureSet branch). On a
        // CHANGE table amountNet is always zero, so every bucket would compare
        // as "zero total" and silently fall into FALLBACK_INDUSTRY - a table
        // that reports Complete while quietly discarding every real industry
        // mapping. Every other misconfiguration in this framework fails loudly
        // instead of producing a quietly wrong number; this one must too.
        if (!QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL.equals(context.definition.measureSet)) {
            throw new QuoteDocumentGenerator.QuoteDocumentException(
                context.definition.tableCode + ': QuoteDocumentIndustryRowCustomizer reassigns groups by '
                + 'each bucket\'s Amount_Net__c, which is only populated when Measure_Set__c is '
                + 'PRICE_WATERFALL - attached to a CHANGE table as configured here, every line would '
                + 'silently land in "' + FALLBACK_INDUSTRY + '" regardless of its real industry mapping. '
                + 'Set Measure_Set__c to PRICE_WATERFALL on this table definition, or extend this '
                + 'customizer to read the CHANGE measures if that combination is genuinely needed.'
            );
        }

        Map<String, String> industryByProductName = QuoteDocumentKeyValueMap.get(CATEGORY);

        Map<String, Bucket> initialBuckets = new Map<String, Bucket>();
        for (QuoteDocumentLine line : context.lines) {
            if (!line.countsIn(context.definition.lineFilter)) {
                continue;
            }
            String industryName = industryByProductName.containsKey(line.productName)
                ? industryByProductName.get(line.productName)
                : FALLBACK_INDUSTRY;
            bucketFor(initialBuckets, industryName).addLine(line);
        }

        Map<String, Bucket> finalBuckets = new Map<String, Bucket>();
        for (Bucket bucket : initialBuckets.values()) {
            String targetIndustry = bucket.industryName;
            if (bucket.measures.amountNet == 0) {
                targetIndustry = FALLBACK_INDUSTRY;
            } else if (bucket.measures.amountNet > OVERFLOW_THRESHOLD) {
                targetIndustry = OVERFLOW_INDUSTRY;
            }
            for (QuoteDocumentLine line : bucket.lines) {
                bucketFor(finalBuckets, targetIndustry).addLine(line);
            }
        }

        Quote_Document_Row__c grandTotal;
        for (Quote_Document_Row__c row : context.rows) {
            if (row.Row_Type__c == 'Grand Total') {
                grandTotal = row;
            }
        }
        context.rows.clear();

        List<String> industryNames = new List<String>(finalBuckets.keySet());
        industryNames.sort();
        for (String industryName : industryNames) {
            emitBucket(context, finalBuckets.get(industryName));
        }

        // The rebuilt rows were numbered from 10 up by context.newRow(), so the
        // grand total - discarded from the list and re-added last - needs a
        // fresh order higher than all of them to keep printing last.
        if (!context.rows.isEmpty()) {
            grandTotal.Display_Order__c = context.rows[context.rows.size() - 1].Display_Order__c + 10;
        }
        context.rows.add(grandTotal);

        return context.rows;
    }

    private Bucket bucketFor(Map<String, Bucket> buckets, String industryName) {
        if (!buckets.containsKey(industryName)) {
            Bucket bucket = new Bucket();
            bucket.industryName = industryName;
            buckets.put(industryName, bucket);
        }
        return buckets.get(industryName);
    }

    private void emitBucket(QuoteDocumentRowCustomizerContext context, Bucket bucket) {
        String key = bucket.industryName.toUpperCase().replaceAll('[^A-Z0-9]+', '_');

        Quote_Document_Row__c header = context.newRow(
            'Group Header', 1, 'HEADER:INDUSTRY:' + key, bucket.industryName
        );
        header.Group_Dimension__c = 'INDUSTRY_ALLEGIANCE';
        header.Group_Value__c = bucket.industryName;

        Quote_Document_Row__c subtotal = context.newRow(
            'Subtotal', 1, 'SUBTOTAL:INDUSTRY:' + key, bucket.industryName + ' Subtotal'
        );
        subtotal.Group_Dimension__c = 'INDUSTRY_ALLEGIANCE';
        subtotal.Group_Value__c = bucket.industryName;
        bucket.measures.writeTo(subtotal, context.definition.measureSet);
    }
}
