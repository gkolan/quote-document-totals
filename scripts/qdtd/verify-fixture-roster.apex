// Roster verification: one line per quote, counts as the ledger will read them.
Map<String, SBQQ__Quote__c> byKey = new Map<String, SBQQ__Quote__c>();
for (SBQQ__Quote__c q : [SELECT Id, SBQQ__Key__c, SBQQ__Type__c, SBQQ__Account__r.BillingCountry FROM SBQQ__Quote__c WHERE SBQQ__Key__c LIKE 'QDTD-Q%']) {
    byKey.put(q.SBQQ__Key__c, q);
}
Map<Id, Integer> lineCount = new Map<Id, Integer>();
Map<Id, Integer> optionalCount = new Map<Id, Integer>();
Map<Id, Integer> recurringCount = new Map<Id, Integer>();
Map<Id, Integer> bundledCount = new Map<Id, Integer>();
for (AggregateResult ar : [SELECT SBQQ__Quote__c qid, COUNT(Id) c FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__r.SBQQ__Key__c LIKE 'QDTD-Q%' GROUP BY SBQQ__Quote__c]) {
    lineCount.put((Id) ar.get('qid'), (Integer) ar.get('c'));
}
for (AggregateResult ar : [SELECT SBQQ__Quote__c qid, COUNT(Id) c FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__r.SBQQ__Key__c LIKE 'QDTD-Q%' AND SBQQ__Optional__c = true GROUP BY SBQQ__Quote__c]) {
    optionalCount.put((Id) ar.get('qid'), (Integer) ar.get('c'));
}
for (AggregateResult ar : [SELECT SBQQ__Quote__c qid, COUNT(Id) c FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__r.SBQQ__Key__c LIKE 'QDTD-Q%' AND SBQQ__ChargeType__c = 'Recurring' GROUP BY SBQQ__Quote__c]) {
    recurringCount.put((Id) ar.get('qid'), (Integer) ar.get('c'));
}
for (AggregateResult ar : [SELECT SBQQ__Quote__c qid, COUNT(Id) c FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__r.SBQQ__Key__c LIKE 'QDTD-Q%' AND SBQQ__Bundled__c = true GROUP BY SBQQ__Quote__c]) {
    bundledCount.put((Id) ar.get('qid'), (Integer) ar.get('c'));
}
List<String> keys = new List<String>(byKey.keySet());
keys.sort();
System.debug('ROSTER_START');
for (String k : keys) {
    SBQQ__Quote__c q = byKey.get(k);
    System.debug('ROSTER ' + k
        + ' type=' + q.SBQQ__Type__c
        + ' country=' + q.SBQQ__Account__r.BillingCountry
        + ' lines=' + (lineCount.containsKey(q.Id) ? lineCount.get(q.Id) : 0)
        + ' optional=' + (optionalCount.containsKey(q.Id) ? optionalCount.get(q.Id) : 0)
        + ' recurring=' + (recurringCount.containsKey(q.Id) ? recurringCount.get(q.Id) : 0)
        + ' bundled=' + (bundledCount.containsKey(q.Id) ? bundledCount.get(q.Id) : 0));
}
System.debug('ROSTER_COUNT=' + byKey.size());
