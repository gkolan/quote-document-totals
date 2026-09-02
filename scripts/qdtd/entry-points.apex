// Step 06: the generation ENTRY POINTS, as opposed to the table configuration.
//
// The matrix run drives QuoteDocumentGenerator.generate() only. These are the
// other four ways generation is reached, each of which can fail on its own:
// the invocable a Flow calls, the async path, the queueable job, and a bulk
// call covering every fixture quote in one transaction.
//
// Run with exactly one TDX definition active, so the assertions below are about
// the entry point rather than about which tables happen to be configured.

List<SBQQ__Quote__c> quotes = [
    SELECT Id, SBQQ__Key__c FROM SBQQ__Quote__c
    WHERE SBQQ__Key__c IN ('QDTD-Q1', 'QDTD-Q2', 'QDTD-Q11') ORDER BY SBQQ__Key__c
];
Map<Id, String> keyById = new Map<Id, String>();
for (SBQQ__Quote__c q : quotes) { keyById.put(q.Id, q.SBQQ__Key__c); }

// ---------------------------------------------------------------------------
// 1. The invocable a Flow calls. Returns a Result so a screen flow can show a
//    real confirmation - and so the request id and fingerprint are readable
//    back off the action, which the launch contract requires.
// ---------------------------------------------------------------------------
List<QuoteDocumentGenerator.Request> requests = new List<QuoteDocumentGenerator.Request>();
for (SBQQ__Quote__c q : quotes) {
    QuoteDocumentGenerator.Request request = new QuoteDocumentGenerator.Request();
    request.quoteId = q.Id;
    requests.add(request);
}
for (QuoteDocumentGenerator.Result result : QuoteDocumentGenerator.generateFromFlow(requests)) {
    System.debug('ENTRY|generateFromFlow|success=' + result.success
        + '|tables=' + result.tableCount + '|rows=' + result.rowCount
        + '|requestId=' + (String.isNotBlank(result.requestId) ? 'present' : 'MISSING')
        + '|fingerprint=' + (String.isNotBlank(result.fingerprint) ? 'present' : 'MISSING')
        + '|message=' + (result.message == null ? '' : result.message.left(120)));
}

// ---------------------------------------------------------------------------
// 2. Bulk. FINDING: all 19 fixture quotes in one synchronous call exceeds the
//    100-SOQL governor limit ("Too many SOQL queries: 101"), and a governor
//    LimitException cannot be caught - the transaction dies rather than
//    reporting. That matches generate()'s own header ("Correct for a single
//    quote from a button or flow; use generateAsync for anything larger"), so
//    it is a documented boundary rather than a defect - but it does mean a
//    backfill must chunk. Eight quotes is under the limit and proves the bulk
//    path itself works.
// ---------------------------------------------------------------------------
// Built with a loop rather than new Map<Id, SObject>([SOQL]).keySet(): the
// inline-query form does not parse in anonymous Apex.
Set<Id> allFixtureIds = new Set<Id>();
for (SBQQ__Quote__c q : [SELECT Id FROM SBQQ__Quote__c WHERE SBQQ__Key__c LIKE 'QDTD-Q%' LIMIT 8]) {
    allFixtureIds.add(q.Id);
}
// The outcome list is used inline rather than assigned. Anonymous Apex rejects a
// top-level generic declaration over an inner class (`List<X.Y> v = ...`) with
// "Unexpected token '<'" - it only parses inside a block, which is why the slice
// harness can declare one and this script cannot.
try {
    System.debug('ENTRY|bulk|quotes=' + allFixtureIds.size()
        + '|outcomes=' + QuoteDocumentGenerator.generate(allFixtureIds).size()
        + '|queries=' + Limits.getQueries() + '/' + Limits.getLimitQueries()
        + '|dmlRows=' + Limits.getDmlRows() + '/' + Limits.getLimitDmlRows());
} catch (Exception e) {
    System.debug('ENTRY|bulk|FAILED|' + e.getMessage().left(200));
}

// ---------------------------------------------------------------------------
// 3. Async, and 4. the queueable job. Both are fire-and-forget here; the
//    caller checks the resulting statuses in a later transaction, because
//    that is the only honest way to observe an async result.
// ---------------------------------------------------------------------------
try {
    QuoteDocumentGenerator.generateAsync(new Set<Id>{ quotes[0].Id });
    System.debug('ENTRY|generateAsync|enqueued for ' + keyById.get(quotes[0].Id));
} catch (Exception e) {
    System.debug('ENTRY|generateAsync|FAILED|' + e.getMessage().left(200));
}

try {
    System.enqueueJob(new QuoteDocumentGenerateJob(quotes[1].Id));
    System.debug('ENTRY|QuoteDocumentGenerateJob|enqueued for ' + keyById.get(quotes[1].Id));
} catch (Exception e) {
    System.debug('ENTRY|QuoteDocumentGenerateJob|FAILED|' + e.getMessage().left(200));
}

System.debug('ENTRY_POINTS_DONE');
