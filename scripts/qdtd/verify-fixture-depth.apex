// Bundle depth: walk every RequiredBy chain on quote 2 and report its length
// together with the OptionLevel at each node, which is what the depth cases and
// DIM_BUNDLE both depend on being consistent.
Map<Id, SBQQ__QuoteLine__c> lines = new Map<Id, SBQQ__QuoteLine__c>(
    [SELECT Id, SBQQ__Number__c, SBQQ__RequiredBy__c, SBQQ__OptionLevel__c, SBQQ__Bundle__c,
            SBQQ__Bundled__c, SBQQ__Product__r.ProductCode
     FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__r.SBQQ__Key__c = 'QDTD-Q2']);

Integer deepest = 0;
for (SBQQ__QuoteLine__c l : lines.values()) {
    // Only report leaves - a leaf is a line nothing else requires.
    Boolean isParent = false;
    for (SBQQ__QuoteLine__c other : lines.values()) {
        if (other.SBQQ__RequiredBy__c == l.Id) { isParent = true; break; }
    }
    if (isParent) { continue; }

    List<String> chain = new List<String>();
    SBQQ__QuoteLine__c cursor = l;
    Integer guard = 0;
    while (cursor != null && guard++ < 20) {
        chain.add(cursor.SBQQ__Product__r.ProductCode + '(lvl=' + cursor.SBQQ__OptionLevel__c
                  + ',bundled=' + cursor.SBQQ__Bundled__c + ')');
        cursor = cursor.SBQQ__RequiredBy__c == null ? null : lines.get(cursor.SBQQ__RequiredBy__c);
    }
    if (chain.size() > deepest) { deepest = chain.size(); }
    if (chain.size() >= 4) {
        List<String> reversed = new List<String>();
        for (Integer i = chain.size() - 1; i >= 0; i--) { reversed.add(chain[i]); }
        System.debug('CHAIN depth=' + chain.size() + ' :: ' + String.join(reversed, ' -> '));
    }
}
System.debug('DEEPEST_CHAIN=' + deepest);

// Replacement branches: these only fire when the subscription lookups are non-null.
for (SBQQ__QuoteLine__c l : [SELECT SBQQ__Quote__r.SBQQ__Key__c, SBQQ__Product__r.ProductCode,
        SBQQ__Quantity__c, SBQQ__PriorQuantity__c, SBQQ__Existing__c,
        SBQQ__RenewedSubscription__c, SBQQ__UpgradedSubscription__c
     FROM SBQQ__QuoteLine__c
     WHERE SBQQ__RenewedSubscription__c != null OR SBQQ__UpgradedSubscription__c != null
     ORDER BY SBQQ__Quote__r.SBQQ__Key__c, SBQQ__Number__c]) {
    System.debug('REPLACEMENT ' + l.SBQQ__Quote__r.SBQQ__Key__c + ' ' + l.SBQQ__Product__r.ProductCode
        + ' qty=' + l.SBQQ__Quantity__c + ' prior=' + l.SBQQ__PriorQuantity__c
        + ' renewed=' + (l.SBQQ__RenewedSubscription__c != null)
        + ' upgraded=' + (l.SBQQ__UpgradedSubscription__c != null));
}
System.debug('SUBSCRIPTIONS=' + [SELECT COUNT() FROM SBQQ__Subscription__c WHERE SBQQ__Product__r.ProductCode LIKE 'QDTD-%']);
