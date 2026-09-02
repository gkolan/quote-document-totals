/**
 * Worked example for docs/quote-document-extension-recipes.md.
 *
 * Like row-customizer-example.apex, this calls the real
 * QuoteDocumentGenerator.generate() rather than hand-building rows, so it
 * proves the Industry Map lookup and the re-bucketing rule both fire from
 * inside the shipped pipeline against real quote lines. It also regenerates
 * every other active table for the same quote, for the same reason
 * documented in row-customizer-example.apex.
 *
 * This demo quote's real lines only exercise two of the three reassignment
 * paths (the default-fallback and the over-$1,000 overflow) - none of its
 * non-zero lines happen to fall between $0 and the threshold, and its only
 * $0 lines are bundled components, which never count toward any table's
 * totals regardless of industry mapping. The "stays in its own mapped
 * industry" and "zero-total reassignment" paths are proven with controlled
 * synthetic data instead, by QuoteDocumentIndustryAllegianceRowCustomizerTest.
 *
 *   sf apex run --target-org your-org-alias --file scripts/apex/industry-allegiance-example.apex
 */

List<SBQQ__Quote__c> seeded = [
    SELECT Id, Name FROM SBQQ__Quote__c
    WHERE SBQQ__Account__r.Name LIKE 'Ridgeline Manufacturing%'
    ORDER BY CreatedDate DESC LIMIT 1
];
SBQQ__Quote__c quote = !seeded.isEmpty() ? seeded[0] : [
    SELECT Id, Name FROM SBQQ__Quote__c ORDER BY CreatedDate DESC LIMIT 1
];

QuoteDocumentGenerator.generate(new Set<Id>{ quote.Id });

Quote_Document_Table__c table = [
    SELECT Id, Status__c, Amount_Net__c
    FROM Quote_Document_Table__c
    WHERE Quote__c = :quote.Id AND Table_Code__c = 'INDUSTRY_ALLEGIANCE'
];

List<Quote_Document_Row__c> rows = [
    SELECT Row_Type__c, Group_Level__c, Display_Order__c, Display_Label__c, Group_Value__c, Amount_Net__c
    FROM Quote_Document_Row__c
    WHERE Quote_Document_Table__c = :table.Id
    ORDER BY Display_Order__c
];

System.debug('=== ' + quote.Name + ' / INDUSTRY_ALLEGIANCE (status ' + table.Status__c + ') ===');
for (Quote_Document_Row__c row : rows) {
    System.debug(row.Row_Type__c + ' L' + row.Group_Level__c + '  ' + row.Display_Label__c
        + '  Amount_Net__c=' + row.Amount_Net__c);
}

System.assertEquals('Complete', table.Status__c, 'Re-bucketing by industry allegiance must still reconcile');
System.debug('Grand total Amount_Net__c = ' + table.Amount_Net__c);
