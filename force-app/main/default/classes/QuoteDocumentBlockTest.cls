/**
 * Step 04 - narrative blocks.
 *
 * The markup tests carry most of the weight. "No markup" is easy to state
 * and easy to implement wrongly: a blanket ban on '<' would be simpler and
 * would reject "terminates in < 30 days", which is ordinary contractual
 * prose. Both directions are asserted here so neither half can quietly
 * regress into the other.
 */
@IsTest
private class QuoteDocumentBlockTest {

    @TestSetup
    static void setup() {
        QuoteDocumentTestData.setup();
    }

    private static Quote_Document_Block__c block(String body) {
        return new Quote_Document_Block__c(
            Block_Code__c = 'TEST_BLOCK',
            Block_Type__c = 'Paragraph',
            Display_Order__c = 5000,
            Locale__c = 'en_US',
            Body__c = body,
            Source_Version__c = '1',
            Is_Displayed__c = true
        );
    }

    private static String failureFrom(Quote_Document_Block__c b) {
        try {
            QuoteDocumentBlockBuilder.validate(b);
            return null;
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            return e.getMessage();
        }
    }

    // -----------------------------------------------------------------------
    // The markup rule, both directions
    // -----------------------------------------------------------------------

    @IsTest
    static void markupInBodyIsRejected() {
        for (String markup : new List<String>{
            'Before <div class="x">after',
            'Ends here</p>',
            'A tag <# <Value Select="X"/> #> smuggled in',
            'A merge field «CustomerName» smuggled in',
            'Closing guillemet only »'
        }) {
            String message = failureFrom(block(markup));
            Assert.isNotNull(message, 'Markup must be rejected: ' + markup);
            Assert.isTrue(
                message.contains('BLOCK_BODY_MARKUP'),
                'Wrong code for "' + markup + '": ' + message
            );
        }
    }

    /**
     * The case a blanket character ban would break. A less-than sign followed
     * by a space or a digit is prose, not a tag, and contract text is full of
     * it.
     */
    @IsTest
    static void lessThanInProseIsAccepted() {
        for (String prose : new List<String>{
            'Terminates in < 30 days.',
            'Quantities < 100 are billed at list.',
            'Use the > and < operators as needed.',
            'A > B and 5 < 6.'
        }) {
            Assert.isNull(
                failureFrom(block(prose)),
                'Ordinary prose using comparison signs must be storable: ' + prose
            );
        }
    }

    @IsTest
    static void emptyBodyIsRejected() {
        String message = failureFrom(block('   '));
        Assert.isNotNull(message, 'A blank body is a blank space in a customer document.');
        Assert.isTrue(message.contains('BLOCK_BODY_EMPTY'), 'Wrong code: ' + message);
    }

    @IsTest
    static void aMissingSourceVersionIsRejected() {
        Quote_Document_Block__c b = block('Ordinary text.');
        b.Source_Version__c = null;

        String message = failureFrom(b);
        Assert.isNotNull(message, 'A block with no source version cannot prove which wording was agreed.');
        Assert.isTrue(message.contains('BLOCK_VERSION_MISSING'), 'Wrong code: ' + message);
    }

    @IsTest
    static void unicodeAndNewlinesArePreserved() {
        String text = 'Ligne un\nLigne deux\n\nAccentué — ünïcode ✓ 日本語';

        Assert.isNull(failureFrom(block(text)), 'Unicode and newlines are ordinary text.');

        Quote_Document_Block__c persisted = block(text);
        persisted.Quote__c = QuoteDocumentTestData.quoteId();
        insert persisted;

        Quote_Document_Block__c reread = [
            SELECT Body__c FROM Quote_Document_Block__c WHERE Id = :persisted.Id
        ];
        Assert.areEqual(
            text,
            reread.Body__c,
            'Body must round-trip byte-for-byte. A renderer prints what was stored, so any normalisation '
                + 'here would change the document without anyone deciding to.'
        );
    }

    @IsTest
    static void maximumLengthBodyRoundTrips() {
        String chunk = 'The parties agree to the terms set out in this schedule. ';
        String body = '';
        while (body.length() + chunk.length() < 32000) {
            body += chunk;
        }
        // Trailing whitespace is stripped on save - see the test below. Ending
        // the fixture on a real character keeps this test about LENGTH, which
        // is what it is here to check.
        body = body.trim();

        Quote_Document_Block__c persisted = block(body);
        persisted.Quote__c = QuoteDocumentTestData.quoteId();
        insert persisted;

        Quote_Document_Block__c reread = [
            SELECT Body__c FROM Quote_Document_Block__c WHERE Id = :persisted.Id
        ];
        Assert.areEqual(body.length(), reread.Body__c.length(), 'A long clause must not be truncated.');
        Assert.areEqual(body, reread.Body__c, 'A long clause must round-trip exactly.');
    }

    /**
     * A platform behaviour worth pinning rather than discovering later: a Long
     * Text Area strips LEADING and TRAILING whitespace on save. Interior
     * newlines and spaces survive untouched.
     *
     * It matters because "preserved byte-for-byte" is a contract claim. A
     * clause authored with a trailing space or a trailing blank line does not
     * come back the way it went in, and no amount of care in this framework
     * changes that - so it is stated here instead of being assumed away.
     */
    @IsTest
    static void trailingWhitespaceIsStrippedOnSaveAndInteriorWhitespaceIsNot() {
        String authored = '  Leading and trailing spaces.  \n\n';

        Quote_Document_Block__c persisted = block(authored);
        persisted.Quote__c = QuoteDocumentTestData.quoteId();
        insert persisted;

        Quote_Document_Block__c reread = [
            SELECT Body__c FROM Quote_Document_Block__c WHERE Id = :persisted.Id
        ];
        Assert.areEqual(
            authored.trim(),
            reread.Body__c,
            'The platform trims a Long Text Area on save. Anything relying on trailing whitespace surviving '
                + 'is relying on something that does not happen.'
        );

        String interiorText = 'One\n\n   indented   \n\nTwo';
        Quote_Document_Block__c interior = block(interiorText);
        interior.Quote__c = QuoteDocumentTestData.quoteId();
        interior.Block_Code__c = 'TEST_BLOCK_INTERIOR';
        interior.Display_Order__c = 5001;
        insert interior;

        Quote_Document_Block__c interiorReread = [
            SELECT Body__c FROM Quote_Document_Block__c WHERE Id = :interior.Id
        ];
        Assert.areEqual(
            interiorText,
            interiorReread.Body__c,
            'Interior spacing is part of the wording and must survive exactly.'
        );
    }

    // -----------------------------------------------------------------------
    // Ordering
    // -----------------------------------------------------------------------

    @IsTest
    static void blocksAndTablesShareOneDisplayOrderSequence() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        List<Decimal> orders = new List<Decimal>();
        for (Quote_Document_Table__c table : [
            SELECT Display_Order__c FROM Quote_Document_Table__c WHERE Quote__c = :quoteId
        ]) {
            orders.add(table.Display_Order__c);
        }

        List<Quote_Document_Block__c> blocks = [
            SELECT Block_Code__c, Display_Order__c, Locale__c, Source_Version__c, Body__c, Is_Displayed__c
            FROM Quote_Document_Block__c WHERE Quote__c = :quoteId ORDER BY Display_Order__c
        ];
        Assert.isFalse(blocks.isEmpty(), 'The shipped content records must produce blocks.');

        Set<Decimal> seen = new Set<Decimal>(orders);
        for (Quote_Document_Block__c b : blocks) {
            Assert.isTrue(
                seen.add(b.Display_Order__c),
                'Block ' + b.Block_Code__c + ' collides with a table at Display_Order__c '
                    + b.Display_Order__c + '. One document-wide sequence means no ties.'
            );
        }
    }

    /** A collision is a real ambiguity, so it must fail rather than be resolved arbitrarily. */
    @IsTest
    static void duplicateDisplayOrderAcrossBlocksAndTablesIsRejected() {
        List<Quote_Document_Table__c> tables = new List<Quote_Document_Table__c>{
            new Quote_Document_Table__c(Table_Code__c = 'T1', Display_Order__c = 100)
        };
        List<Quote_Document_Block__c> blocks = new List<Quote_Document_Block__c>{ block('Text.') };
        blocks[0].Display_Order__c = 100;

        String message;
        try {
            QuoteDocumentBlockBuilder.assertOrderingIsUnambiguous(blocks, tables);
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            message = e.getMessage();
        }

        Assert.isNotNull(message, 'A block and a table at the same order must fail.');
        Assert.isTrue(message.contains('DOCUMENT_ORDER_DUPLICATE'), 'Wrong code: ' + message);
        Assert.isTrue(message.contains('T1'), 'The message must name both colliding items: ' + message);
    }

    // -----------------------------------------------------------------------
    // Generation
    // -----------------------------------------------------------------------

    @IsTest
    static void everyBlockCarriesLocaleAndVersion() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        Set<String> tableLocales = new Set<String>();
        for (Quote_Document_Table__c t : [
            SELECT Locale__c FROM Quote_Document_Table__c WHERE Quote__c = :quoteId
        ]) {
            tableLocales.add(t.Locale__c);
        }

        for (Quote_Document_Block__c b : [
            SELECT Block_Code__c, Locale__c, Source_Version__c, Body__c
            FROM Quote_Document_Block__c WHERE Quote__c = :quoteId
        ]) {
            Assert.isTrue(String.isNotBlank(b.Body__c), b.Block_Code__c + ' has no body.');
            Assert.isTrue(String.isNotBlank(b.Source_Version__c), b.Block_Code__c + ' has no source version.');
            Assert.isTrue(
                tableLocales.contains(b.Locale__c),
                b.Block_Code__c + ' is in locale ' + b.Locale__c + ' but its tables are in ' + tableLocales
                    + '. One locale per snapshot, or the document is half translated.'
            );
        }
    }

    /** Regeneration must replace blocks, not accumulate them. */
    @IsTest
    static void regeneratingDoesNotAccumulateBlocks() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Integer afterFirst = [SELECT COUNT() FROM Quote_Document_Block__c WHERE Quote__c = :quoteId];

        // Force a rebuild rather than a reuse.
        update new SBQQ__Quote__c(Id = quoteId, Document_Data_Fingerprint__c = 'forced-mismatch');
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Integer afterSecond = [SELECT COUNT() FROM Quote_Document_Block__c WHERE Quote__c = :quoteId];
        Test.stopTest();

        Assert.areEqual(
            afterFirst,
            afterSecond,
            'Regeneration replaces the snapshot. Accumulating blocks would print every clause twice.'
        );
    }

    @IsTest
    static void markupDetectionIsPatternBasedNotCharacterBased() {
        Assert.isTrue(QuoteDocumentBlockBuilder.containsMarkup('<b>bold</b>'), 'A tag is markup.');
        Assert.isTrue(QuoteDocumentBlockBuilder.containsMarkup('</p>'), 'A closing tag is markup.');
        Assert.isFalse(QuoteDocumentBlockBuilder.containsMarkup('< 30 days'), 'A comparison is not markup.');
        Assert.isFalse(QuoteDocumentBlockBuilder.containsMarkup('a < 5 and b > 2'), 'Neither is this.');
        Assert.isFalse(QuoteDocumentBlockBuilder.containsMarkup(null), 'Null is not markup.');
    }
}
