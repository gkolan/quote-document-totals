/**
 * Reads one Category__c out of Quote_Document_Key_Value__mdt as a plain
 * Key__c -> Value__c map. Exists so a small lookup table - a product-to-label
 * override, a rate table, a name alias - never needs its own Custom Metadata
 * Type: it needs a Category and some rows here instead.
 *
 * Deliberately Apex, not a raw SOQL literal at each call site, so "what
 * happens on a duplicate key in the same category" is decided once (first
 * row wins, in query order) rather than differently by whoever writes the
 * next SOQL.
 */
public with sharing class QuoteDocumentKeyValueMap {

    /**
     * Test-only configuration, because Custom Metadata cannot be inserted in a
     * test. Without it a config-driven test can only assert what the org
     * happens to be configured for, which in an unconfigured org is nothing -
     * so the test passes while proving nothing.
     */
    @TestVisible
    private static Map<String, Map<String, String>> overrides =
        new Map<String, Map<String, String>>();

    /** Every Key__c -> Value__c pair whose Category__c matches, case-sensitive. */
    public static Map<String, String> get(String category) {
        if (Test.isRunningTest() && overrides.containsKey(category)) {
            return overrides.get(category);
        }
        Map<String, String> result = new Map<String, String>();
        for (Quote_Document_Key_Value__mdt row : [
            SELECT Key__c, Value__c
            FROM Quote_Document_Key_Value__mdt
            WHERE Category__c = :category
        ]) {
            if (!result.containsKey(row.Key__c)) {
                result.put(row.Key__c, row.Value__c);
            }
        }
        return result;
    }
}
