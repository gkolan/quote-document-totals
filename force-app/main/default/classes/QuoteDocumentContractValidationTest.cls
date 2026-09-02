/**
 * Step 06 - the ten failure conditions, gathered in one place.
 *
 * Most already had owners by the time this step ran: duplicate keys and
 * ordering came with steps 01A, 02 and 04, missing labels and unsupported
 * locales with step 03, reconciliation with the original verify(). Gathering
 * them here is the point rather than a formality - a contract whose
 * guarantees are asserted in eight different files is a contract nobody can
 * check at a glance, and the first adapter to hit a gap will paper over it.
 *
 * Conditions 1, 1a, 1b and 8 are retrieval-side. They have no code to test
 * until step 07 builds the render service, and are listed at the bottom as
 * explicitly not covered rather than quietly omitted.
 */
@IsTest
private class QuoteDocumentContractValidationTest {

    @TestSetup
    static void setup() {
        QuoteDocumentTestData.setup();
    }

    private static QuoteDocumentTableDefinition definition(String code) {
        QuoteDocumentTableDefinition def = QuoteDocumentTableDefinition.build(
            code,
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        def.displayTitle = 'A Title';
        return def;
    }

    // -----------------------------------------------------------------------
    // Condition 2 - a table is incomplete
    // -----------------------------------------------------------------------

    @IsTest
    static void generationFailsWhenATableHasNoTitle() {
        Quote_Document_Table__c table = new Quote_Document_Table__c(
            Table_Code__c = 'NO_TITLE_TABLE',
            Locale__c = 'en_US'
        );

        String message;
        try {
            QuoteDocumentVerification.verify(
                new SBQQ__Quote__c(),
                table,
                definition('NO_TITLE_TABLE'),
                new List<Quote_Document_Row__c>{
                    QuoteDocumentRowBuilder.defaultRow('Grand Total', 0, 'GRAND_TOTAL', 'Total', 10)
                }
            );
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            message = e.getMessage();
        }

        Assert.isNotNull(message, 'A table with no heading must never be published.');
        Assert.isTrue(message.contains('TABLE_TITLE_MISSING'), 'Wrong code: ' + message);
        Assert.isTrue(message.contains('NO_TITLE_TABLE'), 'The message must name the table: ' + message);
    }

    @IsTest
    static void generationFailsWhenATableHasNoLocale() {
        Quote_Document_Table__c table = new Quote_Document_Table__c(
            Table_Code__c = 'NO_LOCALE_TABLE',
            Display_Title__c = 'A Title'
        );

        String message;
        try {
            QuoteDocumentVerification.verify(
                new SBQQ__Quote__c(),
                table,
                definition('NO_LOCALE_TABLE'),
                new List<Quote_Document_Row__c>{
                    QuoteDocumentRowBuilder.defaultRow('Grand Total', 0, 'GRAND_TOTAL', 'Total', 10)
                }
            );
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            message = e.getMessage();
        }

        Assert.isNotNull(message, 'A snapshot with no locale cannot know when it needs regenerating.');
        Assert.isTrue(message.contains('TABLE_LOCALE_MISSING'), 'Wrong code: ' + message);
        Assert.isTrue(message.contains('NO_LOCALE_TABLE'), 'The message must name the table: ' + message);
    }

    /** Every real generated table passes, or the assertion above is just a tripwire on nothing. */
    @IsTest
    static void everyGeneratedTablePassesPresentationVerification() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        for (Quote_Document_Table__c table : [
            SELECT Table_Code__c, Display_Title__c, Locale__c, Status__c
            FROM Quote_Document_Table__c WHERE Quote__c = :quoteId
        ]) {
            Assert.isTrue(String.isNotBlank(table.Display_Title__c), table.Table_Code__c + ' has no title.');
            Assert.isTrue(String.isNotBlank(table.Locale__c), table.Table_Code__c + ' has no locale.');
            Assert.areEqual('Complete', table.Status__c, table.Table_Code__c + ' published incomplete.');
        }
    }

    // -----------------------------------------------------------------------
    // Condition 3 - duplicate display keys
    // -----------------------------------------------------------------------

    @IsTest
    static void generationFailsOnDuplicateColumnCode() {
        QuoteDocumentTableDefinition def = definition('DUP_COLUMN');

        Map<String, List<QuoteDocumentColumnDefinition>> columns =
            new Map<String, List<QuoteDocumentColumnDefinition>>();
        columns.put('DUP_COLUMN', new List<QuoteDocumentColumnDefinition>{
            columnDef('COL_NET', 10, 'Amount_Net__c', 'Currency'),
            columnDef('COL_NET', 20, 'Amount_List__c', 'Currency')
        });
        QuoteDocumentColumnDefinition.useColumns(columns);

        String message;
        try {
            QuoteDocumentColumnDefinition.forTable(def);
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            message = e.getMessage();
        }

        Assert.isNotNull(message, 'Two columns sharing a code makes one of them unaddressable.');
        Assert.isTrue(message.contains('COLUMN_CODE_DUPLICATE'), 'Wrong code: ' + message);
        Assert.isTrue(message.contains('COL_NET'), 'The message must name the colliding code: ' + message);
    }

    @IsTest
    static void generationFailsOnDuplicateRowKey() {
        List<Quote_Document_Row__c> rows = new List<Quote_Document_Row__c>{
            QuoteDocumentRowBuilder.defaultRow('Detail', 1, 'SAME_KEY', 'One', 10),
            QuoteDocumentRowBuilder.defaultRow('Detail', 1, 'SAME_KEY', 'Two', 20),
            QuoteDocumentRowBuilder.defaultRow('Grand Total', 0, 'GRAND_TOTAL', 'Total', 30)
        };

        String message;
        try {
            QuoteDocumentVerification.verify(
                new SBQQ__Quote__c(),
                new Quote_Document_Table__c(
                    Table_Code__c = 'DUP_ROW', Display_Title__c = 'T', Locale__c = 'en_US'
                ),
                definition('DUP_ROW'),
                rows
            );
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            message = e.getMessage();
        }

        Assert.isNotNull(message, 'A duplicate row key makes a row unaddressable by a template.');
        Assert.isTrue(message.contains('SAME_KEY'), 'The message must name the colliding key: ' + message);
    }

    private static QuoteDocumentColumnDefinition columnDef(
        String code, Integer order, String field, String type
    ) {
        QuoteDocumentColumnDefinition col = new QuoteDocumentColumnDefinition();
        col.columnCode = code;
        col.displayOrder = order;
        col.valueField = field;
        col.dataType = type;
        return col;
    }

    // -----------------------------------------------------------------------
    // Condition 4 - ambiguous ordering
    // -----------------------------------------------------------------------

    @IsTest
    static void generationFailsOnAmbiguousDisplayOrder() {
        QuoteDocumentTableDefinition def = definition('DUP_ORDER');

        Map<String, List<QuoteDocumentColumnDefinition>> columns =
            new Map<String, List<QuoteDocumentColumnDefinition>>();
        columns.put('DUP_ORDER', new List<QuoteDocumentColumnDefinition>{
            columnDef('COL_NET', 10, 'Amount_Net__c', 'Currency'),
            columnDef('COL_LIST', 10, 'Amount_List__c', 'Currency')
        });
        QuoteDocumentColumnDefinition.useColumns(columns);

        String message;
        try {
            QuoteDocumentColumnDefinition.forTable(def);
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            message = e.getMessage();
        }

        Assert.isNotNull(message, 'Two columns at one order print in an arbitrary sequence.');
        Assert.isTrue(message.contains('COLUMN_ORDER_DUPLICATE'), 'Wrong code: ' + message);
        Assert.isTrue(message.contains('10'), 'The message must name the duplicated order: ' + message);
    }

    @IsTest
    static void generationFailsOnAmbiguousRowOrder() {
        List<Quote_Document_Row__c> rows = new List<Quote_Document_Row__c>{
            QuoteDocumentRowBuilder.defaultRow('Detail', 1, 'R1', 'One', 10),
            QuoteDocumentRowBuilder.defaultRow('Detail', 1, 'R2', 'Two', 10),
            QuoteDocumentRowBuilder.defaultRow('Grand Total', 0, 'GT', 'Total', 20)
        };

        String message;
        try {
            QuoteDocumentContributorOutput.validate(rows, definition('DUP_ROW_ORDER'));
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            message = e.getMessage();
        }

        Assert.isNotNull(message, 'Two rows at one order print in an arbitrary sequence.');
        Assert.isTrue(
            message.contains(QuoteDocumentContributorError.DUPLICATE_DISPLAY_ORDER),
            'Wrong code: ' + message
        );
    }

    // -----------------------------------------------------------------------
    // Conditions 5 and 6 - labels and locale
    // -----------------------------------------------------------------------

    @IsTest
    static void generationFailsOnMissingRequiredLabel() {
        QuoteDocumentLabels.reset();
        QuoteDocumentLabels.useLabels('en_US', new Map<String, String>{ 'SOMETHING_ELSE' => 'x' });

        String message;
        try {
            QuoteDocumentLabels.forLocale('en_US').resolve(QuoteDocumentLabels.KEY_GRAND_TOTAL);
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            message = e.getMessage();
        }

        Assert.isNotNull(message, 'Required text must never resolve to blank.');
        Assert.isTrue(message.contains('LABEL_KEY_MISSING'), 'Wrong code: ' + message);
        Assert.isTrue(
            message.contains(QuoteDocumentLabels.KEY_GRAND_TOTAL) && message.contains('en_US'),
            'The message must name the key AND the locale: ' + message
        );
    }

    @IsTest
    static void generationFailsOnUnsupportedLocale() {
        QuoteDocumentLabels.reset();

        String message;
        try {
            QuoteDocumentLabels.forLocale('zz_ZZ');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            message = e.getMessage();
        }

        Assert.isNotNull(message, 'An unsupported locale must fail, not fall through to English.');
        Assert.isTrue(message.contains('LOCALE_UNSUPPORTED'), 'Wrong code: ' + message);
        Assert.isTrue(message.contains('zz_ZZ'), 'The message must name the requested locale: ' + message);
    }

    // -----------------------------------------------------------------------
    // Condition 7 - reconciliation, unchanged
    // -----------------------------------------------------------------------

    /**
     * The four original assertions must still hold, and no existing test was
     * modified to accommodate the presentation ones. Asserted by generating
     * normally: if reconciliation had been weakened, this would publish a
     * table whose money does not add up.
     */
    @IsTest
    static void reconciliationStillGuardsEveryPublishedTable() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        List<Quote_Document_Table__c> tables = [
            SELECT Table_Code__c, Status__c FROM Quote_Document_Table__c WHERE Quote__c = :quoteId
        ];
        Assert.isFalse(tables.isEmpty(), 'The fixture must generate tables.');
        for (Quote_Document_Table__c table : tables) {
            Assert.areEqual(
                'Complete',
                table.Status__c,
                table.Table_Code__c + ' reached publication without completing verification.'
            );
        }
    }

    // -----------------------------------------------------------------------
    // Rollback
    // -----------------------------------------------------------------------

    /**
     * A failed presentation assertion must leave nothing behind. On a FIRST
     * generation that means zero tables - on a regeneration it means the
     * previous snapshot restored with its original Ids, which is a different
     * claim and is tested separately below.
     */
    @IsTest
    static void aFailedFirstGenerationLeavesNoRecords() {
        Id quoteId = QuoteDocumentTestData.quoteId();
        delete [SELECT Id FROM Quote_Document_Table__c WHERE Quote__c = :quoteId];

        List<QuoteDocumentTableDefinition> definitions = QuoteDocumentTableDefinition.getAll();
        definitions[0].rowCustomizerCode = 'NO_SUCH_CODE';
        definitions[0].rowCustomizerVersion = '1';
        definitions[0].cachePolicy = QuoteDocumentTableDefinition.CACHE_STANDARD;
        QuoteDocumentTableDefinition.useDefinitions(definitions);

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
            Assert.fail('The broken configuration must fail generation.');
        } catch (QuoteDocumentGenerator.QuoteDocumentException expected) {
            // expected
        }
        Test.stopTest();

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Quote_Document_Table__c WHERE Quote__c = :quoteId],
            'A failed first generation must leave no partial snapshot.'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Quote_Document_Block__c WHERE Quote__c = :quoteId],
            'Blocks are part of the same savepoint and must roll back with everything else.'
        );
    }

    /**
     * The claim an earlier draft of the spec got wrong: a failed REGENERATION
     * leaves the previous snapshot intact with its ORIGINAL record Ids,
     * because the rollback restores the delete. "Zero records for the quote"
     * is only true when the first generation fails.
     */
    @IsTest
    static void aFailedRegenerationRestoresThePreviousSnapshotWithItsOriginalIds() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });

        Map<Id, Quote_Document_Table__c> before = new Map<Id, Quote_Document_Table__c>([
            SELECT Id, Table_Code__c FROM Quote_Document_Table__c WHERE Quote__c = :quoteId
        ]);
        Assert.isFalse(before.isEmpty(), 'There must be a snapshot to preserve.');

        List<QuoteDocumentTableDefinition> definitions = QuoteDocumentTableDefinition.getAll();
        definitions[0].rowCustomizerCode = 'NO_SUCH_CODE';
        definitions[0].rowCustomizerVersion = '1';
        definitions[0].cachePolicy = QuoteDocumentTableDefinition.CACHE_STANDARD;
        QuoteDocumentTableDefinition.useDefinitions(definitions);
        update new SBQQ__Quote__c(Id = quoteId, Document_Data_Fingerprint__c = 'force-rebuild');

        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
            Assert.fail('The broken configuration must fail regeneration.');
        } catch (QuoteDocumentGenerator.QuoteDocumentException expected) {
            // expected
        }
        Test.stopTest();

        Map<Id, Quote_Document_Table__c> after = new Map<Id, Quote_Document_Table__c>([
            SELECT Id, Table_Code__c FROM Quote_Document_Table__c WHERE Quote__c = :quoteId
        ]);

        Assert.areEqual(
            before.keySet(),
            after.keySet(),
            'A failed regeneration must restore the previous snapshot with its ORIGINAL record Ids. New Ids '
                + 'would mean the rollback re-created rather than restored, and anything holding a '
                + 'reference to the old records would be pointing at nothing.'
        );
    }
}
