/**
 * Creates a Salesforce CPQ Quote and its Quote Lines on an Opportunity
 * from a JSON payload describing products, bundle options, and per-line
 * field values.
 *
 * SCOPE / KNOWN LIMITS
 *  - Does NOT invoke the CPQ Calculate API. Lines are inserted unpriced.
 *  - Supports one level of bundle options (parent -> options). Nested
 *    option groups are not handled.
 *  - Runs synchronously. The invocable enforces a line ceiling because a
 *    Flow-invoked transaction gets 10,000ms CPU, not the 60,000ms an
 *    async context would provide.
 */
public with sharing class CpqQuoteCreationService {

    public class QuoteCreationException extends Exception {}

    /**
     * Guardrail against CPU timeouts in synchronous Flow context.
     * This value is a PLACEHOLDER. Measure the real cost of a bulk
     * SBQQ__QuoteLine__c insert in your org (CPQ's managed triggers
     * dominate it) and lower this accordingly.
     */
    @TestVisible
    private static Integer maxLinesPerInvocation = 150;

    /** Fields this service owns. A payload must never set them. */
    private static final Set<String> BLOCKED_FIELDS = new Set<String>{
        'sbqq__quote__c', 'sbqq__product__c', 'sbqq__requiredby__c',
        'sbqq__productoption__c', 'sbqq__bundle__c', 'sbqq__pricebookentryid__c',
        'sbqq__opportunity2__c', 'sbqq__account__c', 'sbqq__primary__c',
        'sbqq__listprice__c', 'sbqq__netprice__c', 'sbqq__customerprice__c',
        'sbqq__regularprice__c', 'sbqq__specialprice__c', 'sbqq__nettotal__c'
    };

    private static Map<String, Map<String, Schema.SObjectField>> describeCache =
        new Map<String, Map<String, Schema.SObjectField>>();

    // ------------------------------------------------------------------
    // Payload shape
    // ------------------------------------------------------------------

    public class QuoteInput {
        public Map<String, Object> quoteFields;
        public List<LineInput> lines;
    }

    public class LineInput {
        public String productCode;
        public Decimal quantity;
        public Map<String, Object> fields;
        public List<LineInput> options;
    }

    // ------------------------------------------------------------------
    // Invocable entry point
    // ------------------------------------------------------------------

    public class Request {
        @InvocableVariable(label='Opportunity Id' required=true)
        public String opportunityId;

        @InvocableVariable(label='Quote Payload JSON' required=true)
        public String payloadJson;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Quote Id')
        public String quoteId;

        @InvocableVariable(label='Lines Created')
        public Integer lineCount;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    /**
     * Flow entry point. Failures are returned as Result records rather than
     * thrown, so a Flow can branch on success instead of faulting.
     *
     * Each request is independently atomic via its own savepoint. Note that
     * rolling back does NOT restore consumed governor limits, and each
     * setSavepoint() counts against the DML statement limit.
     */
    @InvocableMethod(
        label='Create CPQ Quote'
        description='Creates a CPQ quote and quote lines on an Opportunity from a JSON payload.'
        category='CPQ')
    public static List<Result> createQuotes(List<Request> requests) {
        List<Result> results = new List<Result>();
        Integer linesSoFar = 0;

        for (Request req : requests) {
            Result res = new Result();
            res.success = false;
            res.lineCount = 0;

            Savepoint sp = Database.setSavepoint();
            try {
                if (req == null || String.isBlank(req.opportunityId)) {
                    throw new QuoteCreationException('Opportunity Id is required.');
                }
                if (String.isBlank(req.payloadJson)) {
                    throw new QuoteCreationException('Payload JSON is required.');
                }

                QuoteInput input = parse(req.payloadJson);
                Integer lineCount = countLines(input);

                if (linesSoFar + lineCount > maxLinesPerInvocation) {
                    throw new QuoteCreationException(
                        'Aborted before insert: this request adds ' + lineCount +
                        ' lines to ' + linesSoFar + ' already processed in this transaction, ' +
                        'exceeding the synchronous ceiling of ' + maxLinesPerInvocation +
                        '. Move to an asynchronous path for volumes this size.');
                }

                res.quoteId = createInternal(toOpportunityId(req.opportunityId), input);
                res.lineCount = lineCount;
                res.success = true;
                linesSoFar += lineCount;

            } catch (Exception e) {
                Database.rollback(sp);
                res.quoteId = null;
                res.lineCount = 0;
                res.errorMessage = e.getTypeName() + ': ' + e.getMessage();
            }
            results.add(res);
        }
        return results;
    }

    // ------------------------------------------------------------------
    // Apex entry point
    // ------------------------------------------------------------------

    /** Throws QuoteCreationException on any validation or resolution failure. */
    public static Id create(Id opportunityId, String payloadJson) {
        if (opportunityId == null) {
            throw new QuoteCreationException('Opportunity Id is required.');
        }
        if (String.isBlank(payloadJson)) {
            throw new QuoteCreationException('Payload JSON is required.');
        }
        return createInternal(opportunityId, parse(payloadJson));
    }

    // ------------------------------------------------------------------
    // Core
    // ------------------------------------------------------------------

    private static Id createInternal(Id opportunityId, QuoteInput input) {
        Opportunity opp = getOpportunity(opportunityId);

        Set<String> codes = collectProductCodes(input);

        Map<String, Product2> productsByCode = resolveProducts(codes);
        Map<Id, Id> pbeByProduct = resolvePricebookEntries(productsByCode, opp.Pricebook2Id);
        Map<String, Id> optionByKey = resolveProductOptions(codes);

        SBQQ__Quote__c quote = (SBQQ__Quote__c) toSObject(
            'SBQQ__Quote__c', sanitize('SBQQ__Quote__c', input.quoteFields));
        quote.SBQQ__Opportunity2__c = opportunityId;
        quote.SBQQ__Account__c = opp.AccountId;
        quote.SBQQ__Primary__c = false;
        insert quote;

        List<SBQQ__QuoteLine__c> parents = new List<SBQQ__QuoteLine__c>();
        for (LineInput li : input.lines) {
            parents.add(buildLine(li, quote.Id, productsByCode, pbeByProduct, null, null));
        }
        insert parents;

        List<SBQQ__QuoteLine__c> optionLines = new List<SBQQ__QuoteLine__c>();
        for (Integer i = 0; i < input.lines.size(); i++) {
            LineInput parent = input.lines[i];
            if (parent.options == null || parent.options.isEmpty()) {
                continue;
            }
            for (LineInput o : parent.options) {
                String key = parent.productCode + '|' + o.productCode;
                Id optionId = optionByKey.get(key);
                if (optionId == null) {
                    throw new QuoteCreationException(
                        o.productCode + ' is not a configured option of ' + parent.productCode + '.');
                }
                optionLines.add(buildLine(
                    o, quote.Id, productsByCode, pbeByProduct, parents[i].Id, optionId));
            }
        }
        if (!optionLines.isEmpty()) {
            insert optionLines;
        }

        return quote.Id;
    }

    private static SBQQ__QuoteLine__c buildLine(
        LineInput li,
        Id quoteId,
        Map<String, Product2> products,
        Map<Id, Id> pbes,
        Id requiredById,
        Id productOptionId
    ) {
        Product2 p = products.get(li.productCode);

        SBQQ__QuoteLine__c line = (SBQQ__QuoteLine__c) toSObject(
            'SBQQ__QuoteLine__c', sanitize('SBQQ__QuoteLine__c', li.fields));

        line.SBQQ__Quote__c = quoteId;
        line.SBQQ__Product__c = p.Id;
        line.SBQQ__Quantity__c = (li.quantity == null) ? 1 : li.quantity;
        line.SBQQ__PricebookEntryId__c = pbes.get(p.Id);

        if (requiredById != null) {
            line.SBQQ__RequiredBy__c = requiredById;
        }
        if (productOptionId != null) {
            line.SBQQ__ProductOption__c = productOptionId;
        }
        if (li.options != null && !li.options.isEmpty()) {
            line.SBQQ__Bundle__c = true;
        }
        return line;
    }

    // ------------------------------------------------------------------
    // Resolution
    // ------------------------------------------------------------------

    private static Set<String> collectProductCodes(QuoteInput input) {
        Set<String> codes = new Set<String>();
        for (LineInput li : input.lines) {
            if (li == null || String.isBlank(li.productCode)) {
                throw new QuoteCreationException('Every line requires a productCode.');
            }
            codes.add(li.productCode);

            if (li.options != null) {
                for (LineInput o : li.options) {
                    if (o == null || String.isBlank(o.productCode)) {
                        throw new QuoteCreationException(
                            'Every option under ' + li.productCode + ' requires a productCode.');
                    }
                    codes.add(o.productCode);
                }
            }
        }
        if (codes.isEmpty()) {
            throw new QuoteCreationException('Payload contains no product codes.');
        }
        return codes;
    }

    private static Map<String, Product2> resolveProducts(Set<String> codes) {
        Map<String, Product2> productsByCode = new Map<String, Product2>();
        for (Product2 p : [
            SELECT Id, ProductCode
            FROM Product2
            WHERE ProductCode IN :codes
        ]) {
            productsByCode.put(p.ProductCode, p);
        }

        List<String> missing = new List<String>();
        for (String c : codes) {
            if (!productsByCode.containsKey(c)) {
                missing.add(c);
            }
        }
        if (!missing.isEmpty()) {
            throw new QuoteCreationException(
                'Unresolvable product codes: ' + String.join(missing, ', '));
        }
        return productsByCode;
    }

    private static Map<Id, Id> resolvePricebookEntries(
        Map<String, Product2> productsByCode,
        Id pricebookId
    ) {
        Map<Id, Id> pbeByProduct = new Map<Id, Id>();
        if (pricebookId == null) {
            return pbeByProduct;
        }
        for (PricebookEntry pbe : [
            SELECT Id, Product2Id
            FROM PricebookEntry
            WHERE Product2Id IN :productsByCode.values()
              AND Pricebook2Id = :pricebookId
              AND IsActive = true
        ]) {
            pbeByProduct.put(pbe.Product2Id, pbe.Id);
        }
        return pbeByProduct;
    }

    /**
     * Constrained on both sides so an option belonging to a DIFFERENT bundle
     * cannot accidentally match.
     */
    private static Map<String, Id> resolveProductOptions(Set<String> codes) {
        Map<String, Id> optionByKey = new Map<String, Id>();
        for (SBQQ__ProductOption__c po : [
            SELECT Id,
                   SBQQ__ConfiguredSKU__r.ProductCode,
                   SBQQ__OptionalSKU__r.ProductCode
            FROM SBQQ__ProductOption__c
            WHERE SBQQ__ConfiguredSKU__r.ProductCode IN :codes
              AND SBQQ__OptionalSKU__r.ProductCode IN :codes
        ]) {
            optionByKey.put(
                po.SBQQ__ConfiguredSKU__r.ProductCode + '|' + po.SBQQ__OptionalSKU__r.ProductCode,
                po.Id);
        }
        return optionByKey;
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private static Id toOpportunityId(String value) {
        try {
            Id result = (Id) value;
            if (result.getSObjectType() != Opportunity.SObjectType) {
                throw new QuoteCreationException('Not an Opportunity Id: ' + value);
            }
            return result;
        } catch (System.StringException e) {
            throw new QuoteCreationException('Not a valid Id: ' + value);
        }
    }

    private static QuoteInput parse(String payloadJson) {
        QuoteInput input;
        try {
            input = (QuoteInput) JSON.deserialize(payloadJson, QuoteInput.class);
        } catch (Exception e) {
            throw new QuoteCreationException('Payload is not valid JSON: ' + e.getMessage());
        }
        if (input == null || input.lines == null || input.lines.isEmpty()) {
            throw new QuoteCreationException('Payload contains no lines.');
        }
        return input;
    }

    private static Integer countLines(QuoteInput input) {
        Integer n = 0;
        for (LineInput li : input.lines) {
            n++;
            if (li != null && li.options != null) {
                n += li.options.size();
            }
        }
        return n;
    }

    private static Opportunity getOpportunity(Id opportunityId) {
        List<Opportunity> opps = [
            SELECT Id, AccountId, Pricebook2Id
            FROM Opportunity
            WHERE Id = :opportunityId
        ];
        if (opps.isEmpty()) {
            throw new QuoteCreationException(
                'Opportunity not found or not visible to the current user: ' + opportunityId);
        }
        return opps[0];
    }

    /**
     * Validates payload field keys against describe: the field must exist,
     * be updateable for the running user (this is the FLS check), and not be
     * one this service owns. Returns a map keyed by canonical API name.
     */
    private static Map<String, Object> sanitize(String objectApiName, Map<String, Object> fields) {
        Map<String, Object> clean = new Map<String, Object>();
        if (fields == null || fields.isEmpty()) {
            return clean;
        }

        Map<String, Schema.SObjectField> fieldMap = describeFields(objectApiName);

        for (String key : fields.keySet()) {
            String lower = (key == null) ? '' : key.toLowerCase();

            Schema.SObjectField f = fieldMap.get(lower);
            if (f == null) {
                throw new QuoteCreationException(
                    'Unknown field on ' + objectApiName + ': ' + key);
            }
            if (BLOCKED_FIELDS.contains(lower)) {
                throw new QuoteCreationException(
                    'Field is set by this service and cannot come from the payload: ' + key);
            }
            Schema.DescribeFieldResult d = f.getDescribe();
            if (!d.isUpdateable()) {
                throw new QuoteCreationException(
                    'Field is not writable for the running user: ' + key);
            }
            clean.put(d.getName(), fields.get(key));
        }
        return clean;
    }

    private static Map<String, Schema.SObjectField> describeFields(String objectApiName) {
        if (!describeCache.containsKey(objectApiName)) {
            describeCache.put(
                objectApiName,
                Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap());
        }
        return describeCache.get(objectApiName);
    }

    /**
     * Deserializing into an SObject handles type coercion for dates, numbers,
     * and booleans without a hand-written conversion layer.
     */
    private static SObject toSObject(String objectType, Map<String, Object> fields) {
        Map<String, Object> m = new Map<String, Object>(fields);
        m.put('attributes', new Map<String, String>{ 'type' => objectType });
        return (SObject) JSON.deserialize(JSON.serialize(m), SObject.class);
    }
}
