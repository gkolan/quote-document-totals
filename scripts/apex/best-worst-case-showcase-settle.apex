/**
 * Run this once, a few seconds after scripts/apex/best-worst-case-showcase.apex
 * completes - never merge the two into one script.
 *
 * CPQ recalculates several of the Quote's own rollup fields (SBQQ__NetAmount__c,
 * SBQQ__ListAmount__c, and others QuoteDocumentStaleness.WATCHED_QUOTE_FIELDS
 * watches) asynchronously after a batch of Quote Line inserts, finishing a few
 * seconds after the synchronous insert itself returns - this is the exact race
 * QuoteDocumentStaleness.cls's own header comment describes. The build script
 * calls QuoteDocumentGenerator.generate() before that async recalculation has
 * necessarily finished, so its Ready status can be correctly flipped back to
 * Stale moments later by the framework's own safety net - working exactly as
 * designed, not a bug in either script.
 *
 * A single Apex script (one execute-anonymous call) is one transaction, and
 * the async recalculation only completes after that transaction commits, so
 * this cannot be folded into the build script itself - it has to be a second,
 * separate run with a real commit boundary between them.
 *
 *   sf apex run --target-org <alias> --file scripts/apex/best-worst-case-showcase.apex
 *   sf apex run --target-org <alias> --file scripts/apex/best-worst-case-showcase-settle.apex
 *
 * Safe to run more than once - QuoteDocumentGenerator.generate() reuses the
 * prior output via its fingerprint check when nothing has actually changed
 * (see QuoteDocumentFingerprintTest), so a third or fourth run costs one
 * cheap query pass per quote rather than a full rebuild.
 */
List<Id> quoteIds = new List<Id>();
for (SBQQ__Quote__c quote : [
    SELECT Id FROM SBQQ__Quote__c
    WHERE SBQQ__Account__r.Name LIKE '%[BEST-CASE]' OR SBQQ__Account__r.Name LIKE '%[WORST-CASE]'
]) {
    quoteIds.add(quote.Id);
}

if (quoteIds.isEmpty()) {
    System.debug('No showcase quotes found - run best-worst-case-showcase.apex first.');
} else {
    QuoteDocumentGenerator.generate(new Set<Id>(quoteIds));

    for (SBQQ__Quote__c quote : [
        SELECT Name, Document_Data_Status__c, Document_Data_Generated_On__c
        FROM SBQQ__Quote__c WHERE Id IN :quoteIds ORDER BY Name
    ]) {
        System.debug(quote.Name + ' => ' + quote.Document_Data_Status__c
            + ' (generated ' + quote.Document_Data_Generated_On__c + ')');
        System.assertEquals('Ready', quote.Document_Data_Status__c,
            'Both showcase quotes must settle to Ready once CPQ\'s async recalculation has finished');
    }
}
