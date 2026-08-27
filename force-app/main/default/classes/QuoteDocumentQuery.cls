/**
 * Reads the Quotes and Quote Lines a generation run works from.
 *
 * Split out of QuoteDocumentGenerator so the dynamic SOQL and the schema
 * validation that makes it safe sit together: every configured field path is
 * validated field-by-field against the describe layer BEFORE it is
 * concatenated into the query string, which is what makes the interpolation
 * below safe. A static analyser flags the concatenation without being able to
 * see that guarantee - it is stated here so the next reader does not have to
 * re-derive it.
 */
public with sharing class QuoteDocumentQuery {

    /**
     * Fields QuoteDocumentLine always reads, whatever the configuration says.
     */
    private static final List<String> BASE_LINE_FIELDS = new List<String>{
        'Id', 'SBQQ__Number__c', 'SBQQ__Product__c', 'SBQQ__ProductName__c',
        'SBQQ__ProductCode__c', 'SBQQ__Product__r.Family', 'SBQQ__ChargeType__c',
        'SBQQ__Bundle__c', 'SBQQ__Bundled__c', 'SBQQ__Optional__c', 'SBQQ__OptionLevel__c',
        'SBQQ__RequiredBy__c', 'SBQQ__RequiredBy__r.SBQQ__ProductName__c',
        'SBQQ__Group__c', 'SBQQ__Group__r.Name', 'SBQQ__Quantity__c',
        'SBQQ__ListTotal__c', 'SBQQ__RegularTotal__c', 'SBQQ__TotalDiscountAmount__c',
        'SBQQ__NetTotal__c', 'SBQQ__CustomerTotal__c', 'SBQQ__NetPrice__c',
        'SBQQ__Existing__c', 'SBQQ__PriorQuantity__c',
        'SBQQ__UpgradedSubscription__c', 'SBQQ__RenewedSubscription__c'
    };

    /**
     * Built dynamically so a grouping configured as a field path is fetched
     * without an Apex change. Every configured path is validated against the
     * schema first, so a typo fails here with a readable message instead of an
     * opaque QueryException, and USER_MODE means a configured path cannot be
     * used to read a field the running user has no access to.
     *
     * FOR UPDATE locks the Quote row for the rest of this transaction. Without
     * it, two near-simultaneous generation requests for the same Quote (a
     * doubled button click, or two platform-event-driven refreshes once
     * automatic generation ships) can interleave: both read the same starting
     * state, both delete, both insert, and the second writer's commit is the
     * only one anyone can trust - but nothing stops the first writer's
     * in-flight DML from also landing. The lock serializes them: the second
     * transaction blocks until the first commits or rolls back, then proceeds
     * against post-commit state. SOQL rejects an explicit ORDER BY combined
     * with FOR UPDATE - lock acquisition order is Id order automatically -
     * which is exactly the property that avoids a deadlock between two
     * transactions each locking a different subset of the same two Quotes in
     * opposite order.
     */
    public static List<SBQQ__Quote__c> quotesWithLines(Set<Id> quoteIds) {
        Set<String> lineFields = new Set<String>(BASE_LINE_FIELDS);

        for (String path : QuoteDocumentTableDefinition.allFieldPaths()) {
            validateFieldPath(path);
            lineFields.add(path);
        }

        // CurrencyIsoCode only exists as a field when multi-currency is on, and
        // a static reference to it will not compile in a single-currency org -
        // same guard as copyCurrency, applied to the SELECT list instead.
        String currencyField = UserInfo.isMultiCurrencyOrganization() ? ', CurrencyIsoCode' : '';

        // Safe interpolation: every element of lineFields is either a literal
        // from BASE_LINE_FIELDS or a path that validateFieldPath just proved
        // exists on the schema. Nothing user-supplied reaches this string
        // unvalidated.
        String soql =
            'SELECT Id, Name, SBQQ__NetAmount__c, AccountIndustry__c, Document_Data_Status__c, '
            + 'Document_Data_Fingerprint__c, Document_Data_Request_Id__c' + currencyField + ', '
            + '(SELECT ' + String.join(new List<String>(lineFields), ', ')
            + ' FROM SBQQ__LineItems__r ORDER BY SBQQ__Number__c) '
            + 'FROM SBQQ__Quote__c WHERE Id IN :quoteIds WITH USER_MODE FOR UPDATE';

        return Database.query(soql);
    }

    /**
     * Walks a dot path through the describe layer so a bad configuration is
     * caught at generation time, naming the segment that does not exist.
     */
    @TestVisible
    private static void validateFieldPath(String path) {
        SObjectType current = SBQQ__QuoteLine__c.SObjectType;
        List<String> segments = path.split('\\.');

        for (Integer i = 0; i < segments.size(); i++) {
            String segment = segments[i];
            Boolean isLast = (i == segments.size() - 1);
            String fieldName = isLast ? segment : segment.replace('__r', '__c');

            Map<String, SObjectField> fields = current.getDescribe().fields.getMap();
            SObjectField field = fields.get(fieldName.toLowerCase());

            // Standard relationships such as Account or Owner end in Id rather
            // than __c, so fall back before giving up.
            if (field == null && !isLast) {
                field = fields.get((segment + 'Id').toLowerCase());
            }

            if (field == null) {
                throw new QuoteDocumentGenerator.QuoteDocumentException(
                    'Grouping field path "' + path + '" is not valid: no field "' + segment
                    + '" on ' + current.getDescribe().getName()
                    + '. Fix the Field Path on the Quote Document Grouping record.'
                );
            }

            if (!isLast) {
                List<SObjectType> references = field.getDescribe().getReferenceTo();
                if (references.isEmpty()) {
                    throw new QuoteDocumentGenerator.QuoteDocumentException(
                        'Grouping field path "' + path + '": "' + segment
                        + '" is not a relationship, so nothing can follow it.'
                    );
                }
                current = references[0];
            }
        }
    }
}
