/**
 * Step 01 - table presentation fields.
 *
 * Audit rows 1 and 5: a printable heading that is not the record's Name, and
 * a visibility decision the data carries rather than each renderer
 * re-deriving with a count() conditional.
 */
@IsTest
private class QuoteDocumentPresentationTest {

    @TestSetup
    static void setup() {
        QuoteDocumentTestData.setup();
    }

    private static List<Quote_Document_Table__c> generatedTables(Id quoteId) {
        return [
            SELECT Table_Code__c, Name, Display_Title__c, Display_Subtitle__c,
                   Intro_Text__c, Footer_Text__c, Is_Displayed__c, Row_Count__c
            FROM Quote_Document_Table__c
            WHERE Quote__c = :quoteId
            ORDER BY Display_Order__c
        ];
    }

    /**
     * The heading must be printable, and must not be Name. Name deliberately
     * carries the quote number so a record is findable in a list view, which
     * would put "Q-00063 - " in the middle of a customer's document.
     */
    @IsTest
    static void everyGeneratedTableHasAPrintableTitle() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        List<Quote_Document_Table__c> tables = generatedTables(quoteId);
        Assert.isFalse(tables.isEmpty(), 'The fixture must generate at least one table.');

        SBQQ__Quote__c quote = [SELECT Name FROM SBQQ__Quote__c WHERE Id = :quoteId];

        for (Quote_Document_Table__c table : tables) {
            Assert.isNotNull(
                table.Display_Title__c,
                table.Table_Code__c + ' generated with no Display_Title__c. Config load should have made '
                    + 'this impossible, so reaching here means the snapshot step was skipped.'
            );
            Assert.isTrue(
                String.isNotBlank(table.Display_Title__c),
                table.Table_Code__c + ' has a blank Display_Title__c.'
            );
            Assert.isFalse(
                table.Display_Title__c.contains(quote.Name),
                table.Table_Code__c + ' prints the quote number in its heading: "' + table.Display_Title__c
                    + '". That is what Name is for; a title is what the customer reads.'
            );
            Assert.areNotEqual(
                table.Name,
                table.Display_Title__c,
                table.Table_Code__c + ': the title must be the configured heading, not a copy of Name.'
            );
        }
    }

    /**
     * The replacement for the count(...) > 0 XPath.
     *
     * The fixture ships WITH an optional line, so the empty case has to be
     * created rather than assumed - an earlier draft of this test assumed it
     * and passed for the wrong reason until the assertion was tightened.
     *
     * Asserted on lines rather than rows, and explicitly NOT on Row_Count__c:
     * the builder always emits a Grand Total, so an empty table still has a
     * row and an assertion on Row_Count__c = 0 could never fire.
     */
    @IsTest
    static void aTableWithNoQualifyingLinesIsNotDisplayed() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        // Remove every optional line, so OPTIONAL_PRODUCTS has nothing to show.
        delete [SELECT Id FROM SBQQ__QuoteLine__c WHERE SBQQ__Quote__c = :quoteId AND SBQQ__Optional__c = true];

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        Quote_Document_Table__c optional;
        for (Quote_Document_Table__c table : generatedTables(quoteId)) {
            if ('OPTIONAL_PRODUCTS'.equals(table.Table_Code__c)) {
                optional = table;
            }
        }

        Assert.isNotNull(
            optional,
            'OPTIONAL_PRODUCTS must still be generated when it has no lines - a hidden table and a table '
                + 'that was never generated are different states, and only one of them is evidence that '
                + 'generation ran.'
        );
        Assert.isFalse(
            optional.Is_Displayed__c,
            'A quote with no optional lines must produce OPTIONAL_PRODUCTS with Is_Displayed__c = false, '
                + 'so no renderer has to evaluate count(...) > 0 to reach the same conclusion.'
        );

        List<Quote_Document_Row__c> grandTotals = [
            SELECT Id FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__c = :optional.Id AND Row_Type__c = 'Grand Total'
        ];
        Assert.areEqual(
            1,
            grandTotals.size(),
            'A hidden table is still a complete, verified table. Hiding is not deleting.'
        );
    }

    /** Tables that do have qualifying lines must print. */
    @IsTest
    static void aTableWithQualifyingLinesIsDisplayed() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        Boolean sawDisplayed = false;
        for (Quote_Document_Table__c table : generatedTables(quoteId)) {
            if (table.Is_Displayed__c) {
                sawDisplayed = true;
            }
        }
        Assert.isTrue(
            sawDisplayed,
            'The fixture has priced lines, so at least one table must be displayed. If nothing is, the '
                + 'visibility rule is inverted and every document would print empty.'
        );
    }

    /**
     * The disclaimer existed only as typed text inside a Word file, where no
     * review, translation or test could reach it. It is data now.
     */
    @IsTest
    static void theOptionalProductsDisclaimerIsCarriedInTheData() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        for (Quote_Document_Table__c table : generatedTables(quoteId)) {
            if ('OPTIONAL_PRODUCTS'.equals(table.Table_Code__c)) {
                Assert.isTrue(
                    String.isNotBlank(table.Intro_Text__c),
                    'OPTIONAL_PRODUCTS must carry its disclaimer in Intro_Text__c, not in a Word template.'
                );
                Assert.isTrue(
                    table.Intro_Text__c.toLowerCase().contains('not included in the quote'),
                    'The disclaimer must still say the prices are excluded from the committed total, which '
                        + 'is the whole reason it exists: ' + table.Intro_Text__c
                );
            }
        }
    }

    /**
     * The real validator, not a proxy for it.
     *
     * An earlier version of this test asserted that the in-memory fixture
     * builder left the title blank. That was weak - it tested a test helper -
     * and it broke as soon as the helper started producing valid definitions,
     * which it must, since verification now refuses to publish a table with no
     * title. This calls the config-load validation directly instead.
     */
    @IsTest
    static void anActiveDefinitionWithNoTitleFailsConfigLoad() {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            'NO_TITLE',
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        definition.displayTitle = null;

        String message;
        try {
            definition.validatePresentationConfig();
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            message = e.getMessage();
        }

        Assert.isNotNull(message, 'An active definition with no Display_Title__c must fail config load.');
        Assert.isTrue(message.contains('NO_TITLE'), 'The message must name the definition: ' + message);
        Assert.isTrue(
            message.contains('Table_Name__c'),
            'And must say why there is no fallback to it, or someone will add one: ' + message
        );
    }

    /** Title and name stay separate values - conflating them is what prints an internal label. */
    @IsTest
    static void titleAndNameAreSeparateConcepts() {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            'SEPARATE',
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        definition.displayTitle = 'What the customer reads';

        Assert.areNotEqual(
            definition.tableName,
            definition.displayTitle,
            'The admin-facing name and the printed heading are different things.'
        );
        definition.validatePresentationConfig();
    }
}
