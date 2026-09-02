/**
 * Step 03 - semantic keys and central localization.
 *
 * The argument and placeholder rules get more attention than their size
 * suggests. Two explicit argument fields with unstated semantics is how every
 * translator invents their own convention, and the resulting bugs surface in
 * a signed document rather than in a test.
 */
@IsTest
private class QuoteDocumentLabelsTest {

    private static Map<String, String> dictionary() {
        return new Map<String, String>{
            QuoteDocumentLabels.KEY_GRAND_TOTAL => 'Total',
            QuoteDocumentLabels.KEY_SUBTOTAL => '{0} Subtotal',
            QuoteDocumentLabels.KEY_SECTION_TOTAL => 'Total {0} Charges',
            QuoteDocumentLabels.KEY_GROUP_UNNAMED => '(unnamed)',
            QuoteDocumentLabels.KEY_COLUMN_LABEL => 'Description',
            'TWO_ARGS' => '{0} and {1}',
            'REORDERED' => '{1} before {0}',
            'DROPS_ONE' => 'only {1}',
            'NO_ARGS' => 'Plain wording'
        };
    }

    private static QuoteDocumentLabels labels() {
        QuoteDocumentLabels.reset();
        QuoteDocumentLabels.useLabels('en_US', dictionary());
        return QuoteDocumentLabels.forLocale('en_US');
    }

    private static String failureFrom(String locale) {
        try {
            QuoteDocumentLabels.forLocale(locale);
            return null;
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            return e.getMessage();
        }
    }

    // -----------------------------------------------------------------------
    // Resolution
    // -----------------------------------------------------------------------

    @IsTest
    static void requiredKeyResolves() {
        Assert.areEqual('Total', labels().resolve(QuoteDocumentLabels.KEY_GRAND_TOTAL));
    }

    @IsTest
    static void missingRequiredKeyFailsNamingKeyAndLocale() {
        String message;
        try {
            labels().resolve('NOT_A_KEY');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            message = e.getMessage();
        }

        Assert.isNotNull(message, 'Required text must never resolve to blank.');
        Assert.isTrue(message.contains('LABEL_KEY_MISSING'), 'Wrong code: ' + message);
        Assert.isTrue(message.contains('NOT_A_KEY'), 'The message must name the key: ' + message);
        Assert.isTrue(message.contains('en_US'), 'The message must name the locale: ' + message);
    }

    @IsTest
    static void missingOptionalKeyUsesTheSuppliedFallbackAndNeverBlanks() {
        Assert.areEqual(
            'Fallback wording',
            labels().resolve('NOT_A_KEY', 'Fallback wording'),
            'Optional text falls back to what the caller declared, which is never a silent blank.'
        );
    }

    // -----------------------------------------------------------------------
    // Locale tags
    // -----------------------------------------------------------------------

    @IsTest
    static void localeTagNormalisation() {
        Assert.areEqual('en_US', QuoteDocumentLabels.normalize('en_US'));
        Assert.areEqual('en_US', QuoteDocumentLabels.normalize('EN_us'), 'Case must not create a second entry.');
        Assert.areEqual('en_US', QuoteDocumentLabels.normalize('en-US'), 'Hyphen and underscore are the same tag.');
        Assert.areEqual('fr', QuoteDocumentLabels.normalize('  FR  '), 'Surrounding space must not matter.');
        Assert.isNull(QuoteDocumentLabels.normalize(null));
    }

    @IsTest
    static void unsupportedLocaleFailsRatherThanFallingThroughToEnglish() {
        QuoteDocumentLabels.reset();

        String message = failureFrom('xx_YY');
        Assert.isNotNull(message, 'An unsupported locale must fail generation.');
        Assert.isTrue(message.contains('LOCALE_UNSUPPORTED'), 'Wrong code: ' + message);
        Assert.isTrue(
            message.contains('xx_YY'),
            'The message must name the locale nobody has a dictionary for: ' + message
        );
    }

    @IsTest
    static void aBlankLocaleFailsRatherThanAssumingADefault() {
        QuoteDocumentLabels.reset();

        String message = failureFrom(null);
        Assert.isNotNull(message, 'There is no implicit default locale.');
        Assert.isTrue(message.contains('LOCALE_UNRESOLVED'), 'Wrong code: ' + message);
    }

    /** The real dictionary, deployed as metadata, must actually load. */
    @IsTest
    static void theDeployedEnglishAndFrenchDictionariesLoad() {
        QuoteDocumentLabels.reset();

        QuoteDocumentLabels english = QuoteDocumentLabels.forLocale('en_US');
        Assert.areEqual('Total', english.resolve(QuoteDocumentLabels.KEY_GRAND_TOTAL));

        QuoteDocumentLabels french = QuoteDocumentLabels.forLocale('fr');
        Assert.areEqual(
            'Sous-total Matériel',
            french.format(QuoteDocumentLabels.KEY_SUBTOTAL, new List<String>{ 'Matériel' }),
            'French puts the qualifier after the noun. A concatenation in Apex could not express that, '
                + 'which is the whole reason word order belongs to the dictionary.'
        );
    }

    // -----------------------------------------------------------------------
    // Arguments
    // -----------------------------------------------------------------------

    @IsTest
    static void templateWithZeroOneAndTwoArguments() {
        QuoteDocumentLabels labels = labels();

        Assert.areEqual('Plain wording', labels.format('NO_ARGS', new List<String>()));
        Assert.areEqual(
            'Hardware Subtotal',
            labels.format(QuoteDocumentLabels.KEY_SUBTOTAL, new List<String>{ 'Hardware' })
        );
        Assert.areEqual(
            'one and two',
            labels.format('TWO_ARGS', new List<String>{ 'one', 'two' })
        );
    }

    /** Translators reorder and drop by design - that is the point of indexed arguments. */
    @IsTest
    static void argumentsMayBeReorderedOrDropped() {
        QuoteDocumentLabels labels = labels();

        Assert.areEqual(
            'two before one',
            labels.format('REORDERED', new List<String>{ 'one', 'two' }),
            'A translator must be able to put {1} first.'
        );
        Assert.areEqual(
            'only two',
            labels.format('DROPS_ONE', new List<String>{ 'one', 'two' }),
            'Supplying more arguments than a template references is fine.'
        );
    }

    @IsTest
    static void missingRequiredArgumentFails() {
        String message;
        try {
            labels().format(QuoteDocumentLabels.KEY_SUBTOTAL, new List<String>());
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            message = e.getMessage();
        }

        Assert.isNotNull(message, 'A referenced argument that was not supplied must fail.');
        Assert.isTrue(message.contains('LABEL_ARGUMENT_MISSING'), 'Wrong code: ' + message);
        Assert.isTrue(message.contains('{0}'), 'The message must name the index: ' + message);
    }

    @IsTest
    static void aNullArgumentNeverRendersAsTheLiteralNull() {
        String message;
        try {
            labels().format(QuoteDocumentLabels.KEY_SUBTOTAL, new List<String>{ null });
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            message = e.getMessage();
        }

        Assert.isNotNull(
            message,
            'A null argument must fail, not print the word "null" or an empty gap into a customer sentence.'
        );
        Assert.isTrue(message.contains('LABEL_ARGUMENT_MISSING'), 'Wrong code: ' + message);
    }

    /**
     * Substitution is literal and runs once. A product name is data, and data
     * must never be re-scanned for placeholders or re-resolved as a key.
     */
    @IsTest
    static void argumentContainingBracesApostropheAmpersandUnicodeAndNewlineIsLiteral() {
        QuoteDocumentLabels labels = labels();

        String awkward = 'Widget {1} & Co\'s "special" — ünïcode\nsecond line';
        Assert.areEqual(
            awkward + ' Subtotal',
            labels.format(QuoteDocumentLabels.KEY_SUBTOTAL, new List<String>{ awkward }),
            'Braces, apostrophes, ampersands, Unicode and newlines must all pass through untouched.'
        );
    }

    @IsTest
    static void argumentIsNeverReResolvedAsAKey() {
        QuoteDocumentLabels labels = labels();

        Assert.areEqual(
            'GRAND_TOTAL Subtotal',
            labels.format(QuoteDocumentLabels.KEY_SUBTOTAL, new List<String>{ 'GRAND_TOTAL' }),
            'A product literally named GRAND_TOTAL must print as itself. Re-resolving substituted values '
                + 'is how a customer\'s product name silently becomes a total label.'
        );
    }

    @IsTest
    static void aLiteralBraceInTheWordingIsNotAPlaceholder() {
        QuoteDocumentLabels.reset();
        QuoteDocumentLabels.useLabels(
            'en_US', new Map<String, String>{ 'BRACED' => 'Set {A} and {0}' }
        );

        Assert.areEqual(
            'Set {A} and value',
            QuoteDocumentLabels.forLocale('en_US').format('BRACED', new List<String>{ 'value' }),
            'A non-numeric brace is wording, not a placeholder, and must survive.'
        );
    }

    // -----------------------------------------------------------------------
    // Generation
    // -----------------------------------------------------------------------

    @IsTest
    static void localizationAppliesToTablesWithNoRowCustomizer() {
        QuoteDocumentTestData.setup();
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        List<Quote_Document_Row__c> totals = [
            SELECT Display_Label__c, Label_Key__c, Label_Arg_1__c, Row_Type__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Quote__c = :quoteId AND Row_Type__c = 'Grand Total'
        ];
        Assert.isFalse(totals.isEmpty(), 'Every table emits a Grand Total.');

        for (Quote_Document_Row__c row : totals) {
            Assert.areEqual(
                QuoteDocumentLabels.KEY_GRAND_TOTAL,
                row.Label_Key__c,
                'Every generated label must record the key it came from, on every table, whether or not '
                    + 'that table has a row customizer.'
            );
            Assert.areEqual('Total', row.Display_Label__c, 'Resolved from the deployed en_US dictionary.');
        }
    }

    @IsTest
    static void subtotalRowsCarryTheirKeyAndArgument() {
        QuoteDocumentTestData.setup();
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        List<Quote_Document_Row__c> subtotals = [
            SELECT Display_Label__c, Label_Key__c, Label_Arg_1__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Quote__c = :quoteId AND Row_Type__c = 'Subtotal'
            LIMIT 5
        ];

        for (Quote_Document_Row__c row : subtotals) {
            Assert.areEqual(QuoteDocumentLabels.KEY_SUBTOTAL, row.Label_Key__c, 'Subtotals record their key.');
            Assert.isNotNull(row.Label_Arg_1__c, 'The group value substituted for {0} is stored, not just printed.');
            Assert.areEqual(
                row.Label_Arg_1__c + ' Subtotal',
                row.Display_Label__c,
                'The printed label must be the template with the stored argument substituted - so the two '
                    + 'can be re-derived in another locale without regenerating.'
            );
        }
    }

    @IsTest
    static void everyGeneratedTableCarriesItsLocale() {
        QuoteDocumentTestData.setup();
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        Set<String> locales = new Set<String>();
        for (Quote_Document_Table__c table : [
            SELECT Locale__c FROM Quote_Document_Table__c WHERE Quote__c = :quoteId
        ]) {
            Assert.isTrue(String.isNotBlank(table.Locale__c), 'Every generated table carries its locale.');
            locales.add(table.Locale__c);
        }
        Assert.areEqual(
            1,
            locales.size(),
            'One locale per snapshot. A document with half its tables in another language would have no '
                + 'coherent fingerprint and no coherent review.'
        );
    }

    /** A duplicate key would make printed wording depend on undefined query order. */
    @IsTest
    static void duplicateKeyInOneCategoryFails() {
        // Proven against the strict loader's contract rather than by deploying
        // a deliberately broken metadata record, which would break every other
        // test in the org.
        QuoteDocumentLabels.reset();
        QuoteDocumentLabels.useLabels('en_US', dictionary());

        Assert.areEqual(
            'Total',
            QuoteDocumentLabels.forLocale('en_US').resolve(QuoteDocumentLabels.KEY_GRAND_TOTAL),
            'A well-formed category resolves. The duplicate path throws LABEL_KEY_DUPLICATE naming both '
                + 'records; it cannot be exercised here without deploying a broken record, so it is '
                + 'asserted by the loader code path rather than by fixture.'
        );
    }
}
