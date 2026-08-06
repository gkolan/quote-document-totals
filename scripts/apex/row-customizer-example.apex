/**
 * Worked example for docs/quote-document-row-customizer-guide.md.
 *
 * Unlike the other guides' example scripts, this one is NOT hand-built rows -
 * it calls the real QuoteDocumentGenerator.generate(), exactly as the
 * "Generate Document Tables" button does, so it proves the
 * Row_Customizer_Class__c hook actually fires from inside the shipped
 * pipeline rather than only in a unit test. Because generate() replaces every
 * active table for the quote in one transaction (that is how the real API
 * behaves - see QuoteDocumentGenerator.cls), this also regenerates the
 * quote's other tables (Product Family Summary, etc.) alongside the new
 * ROW_CUSTOMIZER_EXAMPLE table. That is expected and harmless: it is the same
 * thing pressing the button would do, and every one of those tables is
 * config-driven and reproducible.
 *
 *   sf apex run --target-org gkCPQDev --file scripts/apex/row-customizer-example.apex
 */

List<SBQQ__Quote__c> seeded = [
    SELECT Id, Name FROM SBQQ__Quote__c
    WHERE SBQQ__Account__r.Name LIKE 'Ridgeline Manufacturing%'
    ORDER BY CreatedDate DESC LIMIT 1
];
SBQQ__Quote__c quote = !seeded.isEmpty() ? seeded[0] : [
    SELECT Id, Name FROM SBQQ__Quote__c WHERE Name = 'Q-00053' LIMIT 1
];

QuoteDocumentGenerator.generate(new Set<Id>{ quote.Id });

Quote_Document_Table__c table = [
    SELECT Id, Status__c, Amount_Net__c, Row_Count__c
    FROM Quote_Document_Table__c
    WHERE Quote__c = :quote.Id AND Table_Code__c = 'ROW_CUSTOMIZER_EXAMPLE'
];

List<Quote_Document_Row__c> rows = [
    SELECT Row_Type__c, Group_Level__c, Display_Order__c, Display_Label__c,
           Amount_Net__c, Include_In_Grand_Total__c, Include_In_Subtotal__c
    FROM Quote_Document_Row__c
    WHERE Quote_Document_Table__c = :table.Id
    ORDER BY Display_Order__c
];

System.debug('=== ' + quote.Name + ' / ROW_CUSTOMIZER_EXAMPLE (status ' + table.Status__c + ') ===');
for (Quote_Document_Row__c row : rows) {
    System.debug(
        row.Row_Type__c.rightPad(14) + ' L' + row.Group_Level__c
        + '  ' + String.valueOf(row.Display_Label__c).rightPad(40)
        + '  Amount_Net__c=' + row.Amount_Net__c
        + '  inGrandTotal=' + row.Include_In_Grand_Total__c
    );
}

Quote_Document_Row__c taxRow = [
    SELECT Amount_Net__c FROM Quote_Document_Row__c
    WHERE Quote_Document_Table__c = :table.Id AND Row_Key__c = 'ESTIMATED_TAX'
];

System.assertEquals('Complete', table.Status__c,
    'The customizer must not break generation for this table');
System.assertEquals((table.Amount_Net__c * 0.08).setScale(2), taxRow.Amount_Net__c,
    'The Informational tax row must be 8% of the table grand total, computed by the customizer at generation time');

System.debug('Grand total Amount_Net__c = ' + table.Amount_Net__c
    + ' | Estimated Tax (informational) = ' + taxRow.Amount_Net__c);
