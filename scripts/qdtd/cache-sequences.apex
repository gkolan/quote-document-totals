// Cache policy behaviour, which only means anything across REPEATED runs.
//
// One definition is active when this runs (the caller activates it). Each
// sequence generates, changes something or nothing, generates again, and
// reports whether the second run reused the first snapshot or rebuilt it.
//
// "Reused" is read from the generation outcome itself, and corroborated by the
// payload hash: a reuse must leave the hash identical, a rebuild must not.

SBQQ__Quote__c quote = [SELECT Id, SBQQ__Key__c, SBQQ__ExpirationDate__c
                        FROM SBQQ__Quote__c WHERE SBQQ__Key__c = 'QDTD-Q1' LIMIT 1];

String policy = [SELECT Cache_Policy__c FROM Quote_Document_Table_Def__mdt
                 WHERE Table_Code__c LIKE 'TDX%' AND Is_Active__c = true LIMIT 1].Cache_Policy__c;

QuoteDocumentGenerator.GenerationOutcome first = QuoteDocumentGenerator.generate(new Set<Id>{ quote.Id })[0];
System.debug('CACHE|' + policy + '|run1|reused=' + first.reused + '|hash=' + first.payloadHash);

// 1. No change at all.
QuoteDocumentGenerator.GenerationOutcome second = QuoteDocumentGenerator.generate(new Set<Id>{ quote.Id })[0];
System.debug('CACHE|' + policy + '|run2-no-change|reused=' + second.reused + '|hash=' + second.payloadHash
    + '|hashSame=' + (first.payloadHash == second.payloadHash));

// 2. Change a field NOTHING reads: not in the fingerprint (which hashes
//    SBQQ__NetAmount__c, AccountIndustry__c and the currency), not in
//    QuoteDocumentStaleness.WATCHED_QUOTE_FIELDS, and not in any declared
//    dependency set. SBQQ__ExpirationDate__c satisfies all three - it appears
//    in none of the framework's classes. If a policy rebuilds after this, it is
//    reacting to something it never declared.
quote.SBQQ__ExpirationDate__c = Date.today().addDays(Math.mod(Crypto.getRandomInteger(), 90) + 1);
update quote;
QuoteDocumentGenerator.GenerationOutcome third = QuoteDocumentGenerator.generate(new Set<Id>{ quote.Id })[0];
System.debug('CACHE|' + policy + '|run3-inert-field|reused=' + third.reused + '|hash=' + third.payloadHash
    + '|hashSame=' + (second.payloadHash == third.payloadHash));

// 3. Change a field the fingerprint DOES hash, via the declared dependency
//    path SBQQ__Account__r.Industry - which also drives AccountIndustry__c.
Account account = [SELECT Id, Industry FROM Account WHERE Id IN
                   (SELECT SBQQ__Account__c FROM SBQQ__Quote__c WHERE Id = :quote.Id) LIMIT 1];
String priorIndustry = account.Industry;
account.Industry = (account.Industry == 'Energy') ? 'Retail' : 'Energy';
update account;
QuoteDocumentGenerator.GenerationOutcome fourth = QuoteDocumentGenerator.generate(new Set<Id>{ quote.Id })[0];
System.debug('CACHE|' + policy + '|run4-declared-dependency|reused=' + fourth.reused + '|hash=' + fourth.payloadHash
    + '|hashSame=' + (third.payloadHash == fourth.payloadHash));

// Restore, so the sequence leaves the fixture as it found it.
account.Industry = priorIndustry;
update account;
System.debug('CACHE_SEQUENCE_DONE');
