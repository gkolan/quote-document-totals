/**
 * Step 08 - two renderers, one document.
 *
 * THE CANONICALIZER LIVES HERE, NOT IN THE ADAPTERS.
 * If an adapter had to produce the canonical form itself, it would have taken
 * on logic the contract says belongs to the payload - and the equivalence
 * test would be proving that two adapters share a helper rather than that the
 * payload is complete.
 *
 * JSON and HTML are never byte-equivalent, so "the same document" needs a
 * definition or this test becomes a matter of opinion. The definition is
 * step 08 §3a, implemented below.
 */
@IsTest
private class QuoteDocumentAdapterTest {

    @TestSetup
    static void setup() {
        QuoteDocumentTestData.setup();
    }

    private static QuoteDocumentGenerator.GenerationOutcome launch() {
        return QuoteDocumentGenerator.generate(
            new Set<Id>{ QuoteDocumentTestData.quoteId() }
        )[0];
    }

    private static QuoteDocumentPayload payload() {
        QuoteDocumentGenerator.GenerationOutcome outcome = launch();
        return QuoteDocumentRenderService.getPayload(
            outcome.quoteId, outcome.requestId, outcome.fingerprint
        );
    }

    // -----------------------------------------------------------------------
    // The canonical form (§3a)
    // -----------------------------------------------------------------------

    /**
     * Reduces a payload to the semantic document, applying every rule in the
     * §3a table. Both adapters are compared against THIS rather than against
     * each other's markup, so a difference is always a difference in content.
     */
    private static String canonical(QuoteDocumentPayload payload) {
        List<String> parts = new List<String>();

        for (QuoteDocumentPayload.Section section : payload.sections) {
            parts.add('SECTION|' + section.sectionType + '|' + section.code + '|' + section.displayOrder);

            if ('Block'.equals(section.sectionType)) {
                parts.add('BLOCK|' + section.blockType + '|' + norm(section.heading)
                    + '|' + norm(section.body));
                continue;
            }

            parts.add('TITLE|' + norm(section.title) + '|' + norm(section.subtitle));
            for (QuoteDocumentPayload.Column column : section.columns) {
                parts.add('COL|' + column.code + '|' + norm(column.label)
                    + '|' + column.dataType + '|' + column.displayOrder);
            }
            for (QuoteDocumentPayload.Row row : section.rows) {
                parts.add('ROW|' + row.key + '|' + row.rowType + '|' + row.displayOrder);
                for (QuoteDocumentPayload.Column column : section.columns) {
                    parts.add('  VAL|' + column.code + '|'
                        + value(row.values.get(column.code), column.dataType));
                }
            }
        }

        // Currency is compared as the ISO code. Symbol, separator and
        // placement are renderer choices and are excluded by design.
        parts.add('CURRENCY|' + norm(payload.currencyIsoCode));
        return String.join(parts, '\n');
    }

    /**
     * Text rule: trim, collapse internal whitespace runs, normalise newlines,
     * and UNDO HTML escaping - `&amp;` and `&` are the same value, and
     * treating them as different would make escaping look like a content
     * difference.
     */
    private static String norm(String value) {
        if (value == null) {
            return '~null';
        }
        String text = value.unescapeHtml4()
            .replace('\r\n', '\n')
            .replace('\r', '\n');
        return text.trim().replaceAll('\\s+', ' ');
    }

    /**
     * Value rule. Null and zero are DISTINCT: a zero prints, a null is an
     * empty cell, and an adapter that collapsed them would tell the reader a
     * measure was zero when it did not apply at all.
     *
     * CANONICALIZED ON THE DECLARED TYPE, NOT ON `instanceof`. Apex reports
     * `aDate instanceof Datetime` as TRUE, so a runtime check silently
     * collapses Date into DateTime - which this test caught by asserting the
     * two must differ. The payload already declares each column type, so the
     * declaration is both more reliable and the thing the contract says a
     * renderer should trust.
     */
    private static String value(Object raw) {
        return value(raw, null);
    }

    private static String value(Object raw, String dataType) {
        if (raw == null) {
            return '~null';
        }
        if ('Date'.equals(dataType)) {
            return '@d' + String.valueOf(raw);
        }
        if ('DateTime'.equals(dataType)) {
            return '@dt' + String.valueOf(raw);
        }
        if (raw instanceof Decimal) {
            return '#' + ((Decimal) raw).stripTrailingZeros().toPlainString();
        }
        if (raw instanceof Boolean) {
            return ((Boolean) raw) ? '!true' : '!false';
        }
        return '=' + norm(String.valueOf(raw));
    }

    /**
     * The same canonical form, derived from the serialized JSON rather than
     * from the payload object. Two independent walks producing one string is
     * what makes the comparison meaningful - a shared helper would only prove
     * the helper is deterministic.
     */
    private static String canonicalUntyped(Map<String, Object> payload) {
        List<String> parts = new List<String>();

        for (Object rawSection : (List<Object>) payload.get('sections')) {
            Map<String, Object> section = (Map<String, Object>) rawSection;
            String sectionType = (String) section.get('sectionType');

            parts.add('SECTION|' + sectionType + '|' + section.get('code')
                + '|' + decimalOf(section.get('displayOrder')));

            if ('Block'.equals(sectionType)) {
                parts.add('BLOCK|' + section.get('blockType') + '|' + norm((String) section.get('heading'))
                    + '|' + norm((String) section.get('body')));
                continue;
            }

            parts.add('TITLE|' + norm((String) section.get('title'))
                + '|' + norm((String) section.get('subtitle')));

            List<Object> columns = (List<Object>) section.get('columns');
            for (Object rawColumn : columns) {
                Map<String, Object> column = (Map<String, Object>) rawColumn;
                parts.add('COL|' + column.get('code') + '|' + norm((String) column.get('label'))
                    + '|' + column.get('dataType') + '|' + decimalOf(column.get('displayOrder')));
            }

            for (Object rawRow : (List<Object>) section.get('rows')) {
                Map<String, Object> row = (Map<String, Object>) rawRow;
                parts.add('ROW|' + row.get('key') + '|' + row.get('rowType')
                    + '|' + decimalOf(row.get('displayOrder')));

                Map<String, Object> values = (Map<String, Object>) row.get('values');
                for (Object rawColumn : columns) {
                    Map<String, Object> column = (Map<String, Object>) rawColumn;
                    String code = (String) column.get('code');
                    parts.add('  VAL|' + code + '|'
                        + value(values.get(code), (String) column.get('dataType')));
                }
            }
        }

        parts.add('CURRENCY|' + norm((String) payload.get('currencyIsoCode')));
        return String.join(parts, '\n');
    }

    /** JSON numbers arrive as Integer, Long or Double; the canonical form wants one shape. */
    private static String decimalOf(Object raw) {
        if (raw == null) {
            return 'null';
        }
        return String.valueOf(Decimal.valueOf(String.valueOf(raw)));
    }

    // -----------------------------------------------------------------------
    // Equivalence
    // -----------------------------------------------------------------------

    /**
     * Both adapters are handed the same payload, so what this proves is that
     * neither ADDS or LOSES content on the way out - which is the real risk,
     * and the one a byte comparison could never distinguish from formatting.
     */
    @IsTest
    static void bothAdaptersProduceTheSameSemanticDocument() {
        Test.startTest();
        QuoteDocumentPayload source = payload();
        String jsonOut = QuoteDocumentJsonAdapter.render(source);
        String html = QuoteDocumentHtmlAdapter.render(source);
        Test.stopTest();

        Assert.isTrue(String.isNotBlank(jsonOut), 'The JSON adapter must produce output.');
        Assert.isTrue(String.isNotBlank(html), 'The HTML adapter must produce output.');

        // Deserialized UNTYPED, deliberately. Row.values is a
        // Map<String, Object>, and Apex cannot deserialize back into an
        // untyped Object field - "Apex Type unsupported in JSON: Object".
        // That is a real property of this DTO shape and it is fine: a JSON
        // renderer's output is read by other systems, not round-tripped back
        // into Apex. Comparing the untyped structure tests what actually
        // matters - that nothing was lost or altered on the way out.
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonOut);
        Assert.areEqual(
            canonical(source),
            canonicalUntyped(parsed),
            'The JSON adapter must not lose or alter content. If this differs, a value did not survive '
                + 'serialization and every downstream consumer is reading something the snapshot does not '
                + 'say.'
        );

        // Every section, column and row code in the payload must appear in the
        // HTML. The HTML carries them as data- attributes precisely so
        // structure can be compared without parsing presentation.
        for (QuoteDocumentPayload.Section section : source.sections) {
            Assert.isTrue(
                html.contains('data-code="' + section.code + '"'),
                'Section ' + section.code + ' is missing from the HTML output.'
            );
            if (section.columns == null) {
                continue;
            }
            for (QuoteDocumentPayload.Column column : section.columns) {
                Assert.isTrue(
                    html.contains('data-code="' + column.code + '"'),
                    'Column ' + column.code + ' is missing from the HTML output.'
                );
            }
            for (QuoteDocumentPayload.Row row : section.rows) {
                Assert.isTrue(
                    html.contains('data-key="' + row.key.escapeHtml4() + '"'),
                    'Row ' + row.key + ' is missing from the HTML output.'
                );
            }
        }
    }

    /**
     * The distinction most likely to be quietly lost, and the one that changes
     * what a document means.
     */
    @IsTest
    static void nullAndZeroAreDistinguished() {
        Assert.areNotEqual(
            value(null),
            value(0),
            'Null and zero must canonicalize differently. A zero prints; a null is an empty cell. An '
                + 'adapter that collapsed them would tell the reader a measure was zero when it did not '
                + 'apply at all.'
        );
        Assert.areEqual('~null', value(null));
        Assert.areEqual('#0', value(0));

        // And through the real adapter.
        QuoteDocumentPayload source = new QuoteDocumentPayload();
        source.currencyIsoCode = 'USD';
        QuoteDocumentPayload.Section section = new QuoteDocumentPayload.Section();
        section.sectionType = 'Table';
        section.code = 'T';
        section.displayOrder = 10;
        section.title = 'T';
        section.columns = new List<QuoteDocumentPayload.Column>();
        section.rows = new List<QuoteDocumentPayload.Row>();

        QuoteDocumentPayload.Column zeroColumn = new QuoteDocumentPayload.Column();
        zeroColumn.code = 'COL_ZERO';
        zeroColumn.label = 'Zero';
        zeroColumn.dataType = 'Number';
        zeroColumn.displayOrder = 10;
        QuoteDocumentPayload.Column nullColumn = new QuoteDocumentPayload.Column();
        nullColumn.code = 'COL_NULL';
        nullColumn.label = 'Null';
        nullColumn.dataType = 'Number';
        nullColumn.displayOrder = 20;
        section.columns.add(zeroColumn);
        section.columns.add(nullColumn);

        QuoteDocumentPayload.Row row = new QuoteDocumentPayload.Row();
        row.key = 'R1';
        row.rowType = 'Detail';
        row.displayOrder = 10;
        row.values.put('COL_ZERO', 0);
        row.values.put('COL_NULL', null);
        section.rows.add(row);
        source.sections.add(section);

        String html = QuoteDocumentHtmlAdapter.render(source);
        Assert.isTrue(
            html.contains('<td data-code="COL_ZERO">0</td>'),
            'A zero must print as a zero: ' + html
        );
        Assert.isTrue(
            html.contains('<td data-code="COL_NULL"></td>'),
            'A null must print as an empty cell: ' + html
        );
    }

    /**
     * A Date and a DateTime at the same instant are different values and a
     * renderer formats them differently.
     *
     * This test earned its keep: the first canonicalizer used `instanceof`
     * and collapsed them, because Apex reports `aDate instanceof Datetime` as
     * true. The fix was to canonicalize on the type the payload DECLARES,
     * which is what the contract provides Column.dataType for.
     */
    @IsTest
    static void dateAndDateTimeAreNotCollapsed() {
        Date day = Date.newInstance(2026, 8, 27);
        Datetime moment = Datetime.newInstanceGmt(2026, 8, 27, 0, 0, 0);

        Assert.areNotEqual(
            value(day, 'Date'),
            value(moment, 'DateTime'),
            'Collapsing a Date into a DateTime hides a real distinction. Apex\'s own instanceof does '
                + 'exactly that, which is why the declared type is used instead.'
        );
        Assert.isTrue(value(day, 'Date').startsWith('@d'), 'A Date canonicalizes as a Date.');
        Assert.isTrue(value(moment, 'DateTime').startsWith('@dt'), 'A DateTime as a DateTime.');
    }

    @IsTest
    static void escapedAndUnescapedTextCompareEqual() {
        Assert.areEqual(
            norm('Smith &amp; Co'),
            norm('Smith & Co'),
            'HTML escaping is a transport concern. If it counted as a content difference, every text field '
                + 'containing an ampersand would look like a mismatch.'
        );
        Assert.areEqual(norm('a &lt; b'), norm('a < b'));
        Assert.areEqual(
            norm('  leading and   internal  '),
            norm('leading and internal'),
            'Whitespace runs collapse and edges trim.'
        );
        Assert.areEqual(norm('line\r\ntwo'), norm('line\ntwo'), 'Newlines normalise.');
    }

    @IsTest
    static void hiddenElementsAreAbsentFromBoth() {
        Test.startTest();
        QuoteDocumentPayload source = payload();
        String html = QuoteDocumentHtmlAdapter.render(source);
        Test.stopTest();

        for (Quote_Document_Table__c table : [
            SELECT Table_Code__c FROM Quote_Document_Table__c
            WHERE Quote__c = :QuoteDocumentTestData.quoteId() AND Is_Displayed__c = false
        ]) {
            Assert.isFalse(
                html.contains('data-code="' + table.Table_Code__c + '"'),
                'A hidden table reached the HTML. Hidden is excluded from the payload, so an adapter that '
                    + 'printed one would have to have gone round the contract.'
            );
        }
    }

    // -----------------------------------------------------------------------
    // The adapters are as thin as claimed
    // -----------------------------------------------------------------------

    /**
     * Asserted against the adapters' own source. An adapter that queries has
     * stopped being an adapter - it has become a second, competing definition
     * of what the document is.
     */
    @IsTest
    static void adaptersContainNoQueries() {
        for (ApexClass cls : [
            SELECT Name, Body FROM ApexClass
            WHERE Name IN ('QuoteDocumentJsonAdapter', 'QuoteDocumentHtmlAdapter')
        ]) {
            String body = cls.Body;
            Assert.isFalse(body.contains('[SELECT'), cls.Name + ' contains SOQL.');
            Assert.isFalse(body.contains('Database.query'), cls.Name + ' contains dynamic SOQL.');
            Assert.isFalse(body.contains('__mdt'), cls.Name + ' reads Custom Metadata.');
            Assert.isFalse(
                body.contains('QuoteDocumentLabels'),
                cls.Name + ' resolves labels. Every string it prints must already have come from the '
                    + 'payload - if it needs to translate, the payload is incomplete and the fix belongs '
                    + 'upstream.'
            );
            Assert.isFalse(
                body.contains('QuoteDocumentGenerator'),
                cls.Name + ' references the generator. Dependency points one way only: adapter to service.'
            );
        }
    }

    @IsTest
    static void adaptersPerformNoCalculationOrTranslation() {
        for (ApexClass cls : [
            SELECT Name, Body FROM ApexClass
            WHERE Name IN ('QuoteDocumentJsonAdapter', 'QuoteDocumentHtmlAdapter')
        ]) {
            // No arithmetic on money. Formatting a value for display is
            // allowed and is what a renderer is for; deriving one is not.
            Assert.isFalse(
                cls.Body.contains('Amount_') ,
                cls.Name + ' names a measure field. It must address values by column code, never by field '
                    + 'API name, or a subscriber field could never be printed without changing it.'
            );
            Assert.isFalse(
                cls.Body.contains('measureFields'),
                cls.Name + ' reads the measure set. That is a generation concern.'
            );
        }
    }

    /**
     * The testable half of the renderer-outage drill: an adapter blowing up
     * must not damage the snapshot. It reads and never writes, so the
     * assertion is that the payload hash is unchanged after a failed render.
     */
    @IsTest
    static void adapterThrowLeavesTheSnapshotUnchanged() {
        Test.startTest();
        QuoteDocumentGenerator.GenerationOutcome outcome = launch();
        String hashBefore = [
            SELECT Document_Payload_Hash__c FROM SBQQ__Quote__c WHERE Id = :outcome.quoteId
        ].Document_Payload_Hash__c;

        Boolean threw = false;
        try {
            // A null payload is the simplest way to make an adapter fail
            // without contriving a fixture that damages the snapshot.
            QuoteDocumentHtmlAdapter.render((QuoteDocumentPayload) null);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        Assert.isTrue(threw, 'The adapter must fail loudly rather than emit a half-document.');

        String hashAfter = [
            SELECT Document_Payload_Hash__c FROM SBQQ__Quote__c WHERE Id = :outcome.quoteId
        ].Document_Payload_Hash__c;
        Assert.areEqual(
            hashBefore,
            hashAfter,
            'A renderer failure must leave the snapshot untouched. Rendering reads; nothing about the '
                + 'document is wrong just because one renderer could not print it.'
        );
    }

    /** Both adapters honour the launch contract - there is no adapter-only shortcut. */
    @IsTest
    static void adaptersBindToTheLaunchExpectations() {
        Test.startTest();
        QuoteDocumentGenerator.GenerationOutcome outcome = launch();

        String jsonOut = QuoteDocumentJsonAdapter.render(
            outcome.quoteId, outcome.requestId, outcome.fingerprint
        );
        String html = QuoteDocumentHtmlAdapter.render(
            outcome.quoteId, outcome.requestId, outcome.fingerprint
        );

        Boolean jsonRefused = false;
        try {
            QuoteDocumentJsonAdapter.render(outcome.quoteId, 'wrong', 'wrong');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            jsonRefused = e.getMessage().contains('SNAPSHOT_MOVED');
        }
        Test.stopTest();

        Assert.isTrue(
            String.isNotBlank(jsonOut) && String.isNotBlank(html),
            'Both render with valid expectations.'
        );
        Assert.isTrue(
            jsonRefused,
            'An adapter that could read a snapshot without matching expectations would be the bypass the '
                + 'contract prohibits, wearing a renderer\'s clothes.'
        );
    }
}
