/**
 * Prints one quoted product as the several part numbers the customer buys it
 * under.
 *
 * A vendor quotes "Enterprise Platform Bundle". The customer's purchasing
 * system knows three part numbers, each with its own quantity, and will reject
 * a document that does not use them. This expands one quote line into one row
 * per mapped part number, with the line's amount and quantity divided among
 * them.
 *
 * WHY IT IS AN EXPANDER AND NOT A RENAME
 * --------------------------------------
 * An alternate label would be a rename: one row, different text. This is one
 * row becoming several, each carrying its own quantity and its own share of the
 * money - which is a different operation and the reason mapping could not be
 * done with a column binding.
 *
 * THE MAPPING IS AUTHORED, NOT DERIVED
 * ------------------------------------
 * Nothing on a quote says which customer part numbers a product corresponds to.
 * Quote_Document_Product_Alias__mdt holds that, keyed by the product code, in
 * the same ordered-child-metadata shape as the schedule and grouping objects.
 *
 * QUANTITIES DIVIDE HERE
 * ----------------------
 * dividesQuantity() is true, and deliberately: three part numbers are three
 * different physical things, so 100 of a bundle really is 100 of one part and
 * 200 of another where the mapping says so. That is the opposite of a period
 * axis, where the same licences are present in every month.
 *
 * A PRODUCT WITH NO MAPPING FAILS
 * -------------------------------
 * It does not fall through to its own product code. A document that silently
 * mixes customer part numbers with vendor ones is one the customer's system
 * rejects at the worst possible moment, and the failure is far away from the
 * cause. Map every product on the quote, or do not use this table for it.
 *
 * See specs/row-generation-extensibility/steps/step-04-comparison-and-enrichment.md
 * section 3.7.
 */
public with sharing class QuoteDocumentAliasExpander implements QuoteDocumentLineExpander {

    public static final String CODE = 'PRODUCT_ALIAS';

    public static final String ERR_UNMAPPED = 'ALIAS_PRODUCT_UNMAPPED';
    public static final String ERR_EMPTY = 'ALIAS_SET_NOT_FOUND';

    /** One customer part number a product maps to. Public so a test needs no metadata. */
    public class Alias {
        public String productCode;
        public String aliasCode;
        public Decimal weight;
        public Integer displayOrder;

        public Alias(String productCode, String aliasCode, Decimal weight, Integer displayOrder) {
            this.productCode = productCode;
            this.aliasCode = aliasCode;
            this.weight = weight;
            this.displayOrder = displayOrder;
        }
    }

    @TestVisible
    private static Map<String, List<Alias>> overrides;

    @TestVisible
    private static void useAliases(Map<String, List<Alias>> aliases) {
        overrides = aliases;
    }

    /**
     * Every part number any line on this quote maps to, ordered.
     *
     * Built from the lines rather than from the whole mapping table: a document
     * must not print a section for a part number nothing on this quote resolves
     * to.
     */
    public List<QuoteDocumentExpansion.Bucket> buckets(QuoteDocumentExpansion.Request request) {
        Map<String, Integer> orderByAlias = new Map<String, Integer>();

        for (QuoteDocumentLine line : request.lines) {
            for (Alias alias : aliasesFor(line, request)) {
                if (!orderByAlias.containsKey(alias.aliasCode)
                    || alias.displayOrder < orderByAlias.get(alias.aliasCode)) {
                    orderByAlias.put(alias.aliasCode, alias.displayOrder);
                }
            }
        }

        List<String> codes = new List<String>(orderByAlias.keySet());
        codes.sort();

        List<QuoteDocumentExpansion.Bucket> buckets = new List<QuoteDocumentExpansion.Bucket>();
        for (Integer i = 0; i < codes.size(); i++) {
            // The part number IS the printed text, and that is not a violation
            // of the no-English-in-Apex rule: it is customer data, like a
            // product name, not a phrase this framework composed. It is also
            // exactly the string the customer's system expects, so translating
            // or reformatting it would break the document's purpose.
            buckets.add(new QuoteDocumentExpansion.Bucket(
                codes[i], codes[i], orderByAlias.get(codes[i])
            ));
        }
        return buckets;
    }

    public List<QuoteDocumentExpansion.Placement> placements(
        QuoteDocumentLine line, QuoteDocumentExpansion.Request request
    ) {
        List<QuoteDocumentExpansion.Placement> placements =
            new List<QuoteDocumentExpansion.Placement>();

        for (Alias alias : aliasesFor(line, request)) {
            placements.add(new QuoteDocumentExpansion.Placement(
                alias.aliasCode, alias.weight == null ? 0 : alias.weight
            ));
        }
        return placements;
    }

    /** Three part numbers are three different things. */
    public Boolean dividesQuantity() {
        return true;
    }

    private static List<Alias> aliasesFor(
        QuoteDocumentLine line, QuoteDocumentExpansion.Request request
    ) {
        Map<String, List<Alias>> byProductCode = overrides == null ? fromMetadata() : overrides;

        if (byProductCode.isEmpty()) {
            QuoteDocumentContributorError.fail(
                ERR_EMPTY,
                'Table ' + request.definition.tableCode + ' maps products to customer part numbers, but '
                    + 'there are no active Quote_Document_Product_Alias__mdt records at all. The table '
                    + 'would be empty and the reason would not be visible anywhere.'
            );
        }

        List<Alias> aliases = byProductCode.get(line.productCode);
        if (aliases == null || aliases.isEmpty()) {
            QuoteDocumentContributorError.fail(
                ERR_UNMAPPED,
                'Product code "' + line.productCode + '" ("' + line.productName + '") has no customer part '
                    + 'number mapping. This fails rather than falling back to the vendor code: a document '
                    + 'that silently mixes the customer own part numbers with ours is one their purchasing '
                    + 'system rejects, and by then the cause is a long way away.'
            );
        }
        return aliases;
    }

    private static Map<String, List<Alias>> cached;

    private static Map<String, List<Alias>> fromMetadata() {
        if (cached == null) {
            cached = new Map<String, List<Alias>>();
            for (Quote_Document_Product_Alias__mdt record : [
                SELECT Product_Code__c, Alias_Code__c, Weight__c, Display_Order__c
                FROM Quote_Document_Product_Alias__mdt
                WHERE Is_Active__c = true
                ORDER BY Product_Code__c, Display_Order__c
            ]) {
                if (!cached.containsKey(record.Product_Code__c)) {
                    cached.put(record.Product_Code__c, new List<Alias>());
                }
                cached.get(record.Product_Code__c).add(new Alias(
                    record.Product_Code__c,
                    record.Alias_Code__c,
                    record.Weight__c,
                    record.Display_Order__c == null ? 0 : Integer.valueOf(record.Display_Order__c)
                ));
            }
        }
        return cached;
    }
}
