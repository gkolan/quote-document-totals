/**
 * Exports every fixture quote line - writable inputs and the formula totals CPQ
 * computed from them - as CSV rows on the debug log. Driven by
 * scripts/qdtd/export-fixture-totals.ps1, which polls this until the values
 * stop moving. Read-only: this never writes to the org.
 */
List<String> rows = new List<String>();
rows.add('quote_key,line_number,product_code,quantity,list_price,discount,prorated_list_price,customer_price,regular_price,net_price,charge_type,billing_frequency,optional,bundle,bundled,option_level,prior_quantity,existing,list_total,customer_total,net_total,regular_total,total_discount');
for (SBQQ__QuoteLine__c l : [
    SELECT SBQQ__Quote__r.SBQQ__Key__c, SBQQ__Number__c, SBQQ__Product__r.ProductCode,
           SBQQ__Quantity__c, SBQQ__ListPrice__c, SBQQ__Discount__c, SBQQ__ProratedListPrice__c, SBQQ__CustomerPrice__c,
           SBQQ__RegularPrice__c, SBQQ__NetPrice__c, SBQQ__ChargeType__c, SBQQ__BillingFrequency__c,
           SBQQ__Optional__c, SBQQ__Bundle__c, SBQQ__Bundled__c, SBQQ__OptionLevel__c,
           SBQQ__PriorQuantity__c, SBQQ__Existing__c, SBQQ__ListTotal__c, SBQQ__CustomerTotal__c,
           SBQQ__NetTotal__c, SBQQ__RegularTotal__c, SBQQ__TotalDiscountAmount__c
    FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__r.SBQQ__Key__c LIKE 'QDTD-Q%'
    ORDER BY SBQQ__Quote__r.SBQQ__Key__c, SBQQ__Number__c
]) {
    rows.add(String.join(new List<String>{
        l.SBQQ__Quote__r.SBQQ__Key__c, String.valueOf(l.SBQQ__Number__c), l.SBQQ__Product__r.ProductCode,
        String.valueOf(l.SBQQ__Quantity__c), String.valueOf(l.SBQQ__ListPrice__c), String.valueOf(l.SBQQ__Discount__c),
        String.valueOf(l.SBQQ__ProratedListPrice__c), String.valueOf(l.SBQQ__CustomerPrice__c),
        String.valueOf(l.SBQQ__RegularPrice__c), String.valueOf(l.SBQQ__NetPrice__c),
        String.valueOf(l.SBQQ__ChargeType__c), String.valueOf(l.SBQQ__BillingFrequency__c),
        String.valueOf(l.SBQQ__Optional__c), String.valueOf(l.SBQQ__Bundle__c),
        String.valueOf(l.SBQQ__Bundled__c), String.valueOf(l.SBQQ__OptionLevel__c),
        String.valueOf(l.SBQQ__PriorQuantity__c), String.valueOf(l.SBQQ__Existing__c),
        String.valueOf(l.SBQQ__ListTotal__c), String.valueOf(l.SBQQ__CustomerTotal__c),
        String.valueOf(l.SBQQ__NetTotal__c), String.valueOf(l.SBQQ__RegularTotal__c),
        String.valueOf(l.SBQQ__TotalDiscountAmount__c)
    }, ','));
}
for (String r : rows) { System.debug('CSV|' + r); }
