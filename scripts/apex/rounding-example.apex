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
    WHERE Quote__c = :quote.Id AND Table_Code__c = 'ROUNDING_EXAMPLE'
];

List<Quote_Document_Row__c> rows = [
    SELECT Row_Type__c, Group_Level__c, Display_Order__c, Display_Label__c,
           Amount_Net__c, Include_In_Grand_Total__c, Include_In_Subtotal__c
    FROM Quote_Document_Row__c
    WHERE Quote_Document_Table__c = :table.Id
    ORDER BY Display_Order__c
];

System.debug('=== ' + quote.Name + ' / ROUNDING_EXAMPLE (status ' + table.Status__c + ') ===');
for (Quote_Document_Row__c row : rows) {
    System.debug(row.Row_Type__c + ' L' + row.Group_Level__c + '  ' + row.Display_Label__c
        + '  Amount_Net__c=' + row.Amount_Net__c + '  inGrandTotal=' + row.Include_In_Grand_Total__c);
}

Quote_Document_Row__c roundingRow = [
    SELECT Amount_Net__c FROM Quote_Document_Row__c
    WHERE Quote_Document_Table__c = :table.Id AND Row_Key__c = 'ROUNDING_ADJUSTMENT'
];
System.debug('Table grand total Amount_Net__c = ' + table.Amount_Net__c
    + ' | Rounding adjustment = ' + roundingRow.Amount_Net__c);

System.assertEquals('Complete', table.Status__c, 'The customizer must not break generation for this table');
System.assertEquals(0, Math.mod(table.Amount_Net__c.intValue(), 100),
    'The stamped grand total must be a multiple of $100 after rounding');
