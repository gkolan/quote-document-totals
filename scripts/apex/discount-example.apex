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
    SELECT Id, Status__c, Amount_Net__c, Row_Count__c
    FROM Quote_Document_Table__c
    WHERE Quote__c = :quote.Id AND Table_Code__c = 'DISCOUNT_EXAMPLE'
];

List<Quote_Document_Row__c> rows = [
    SELECT Row_Type__c, Group_Level__c, Display_Order__c, Display_Label__c,
           Amount_Net__c, Include_In_Grand_Total__c, Include_In_Subtotal__c, Quote_Line__c
    FROM Quote_Document_Row__c
    WHERE Quote_Document_Table__c = :table.Id
    ORDER BY Display_Order__c
];

System.debug('=== ' + quote.Name + ' / DISCOUNT_EXAMPLE (status ' + table.Status__c + ') ===');
for (Quote_Document_Row__c row : rows) {
    System.debug(row.Row_Type__c + ' L' + row.Group_Level__c + '  ' + row.Display_Label__c
        + '  Amount_Net__c=' + row.Amount_Net__c + '  inGrandTotal=' + row.Include_In_Grand_Total__c);
}

List<Quote_Document_Row__c> discountRows = [
    SELECT Display_Label__c, Amount_Net__c FROM Quote_Document_Row__c
    WHERE Quote_Document_Table__c = :table.Id AND Row_Type__c = 'Discount'
];
System.debug('Table grand total Amount_Net__c = ' + table.Amount_Net__c);
for (Quote_Document_Row__c d : discountRows) {
    System.debug('Discount row: ' + d.Display_Label__c + ' = ' + d.Amount_Net__c);
}

System.assertEquals('Complete', table.Status__c, 'The customizer must not break generation for this table');
System.assertEquals(1, discountRows.size(), 'Exactly one line - the largest - should be discounted');
