/**
 * Renders a published document as plain HTML.
 *
 * Deliberately unstyled. This adapter exists to prove STRUCTURE - that a
 * second renderer can be written against the payload alone and produce the
 * same document - not to look like anything. Styling would only make the
 * equivalence test harder to read.
 *
 * The same rule as the JSON adapter: no SOQL, no Custom Metadata, no
 * arithmetic beyond formatting a number for display, no translation. Every
 * string it prints came from the payload. The only judgement it exercises is
 * how to present a typed value, which is exactly what a renderer is for.
 */
public with sharing class QuoteDocumentHtmlAdapter {

    public static String render(Id quoteId, String expectedRequestId, String expectedFingerprint) {
        return render(
            QuoteDocumentRenderService.getPayload(quoteId, expectedRequestId, expectedFingerprint)
        );
    }

    public static String render(QuoteDocumentPayload payload) {
        List<String> out = new List<String>();
        out.add('<article data-quote="' + escape(payload.quoteNumber)
            + '" data-locale="' + escape(payload.locale)
            + '" data-currency="' + escape(payload.currencyIsoCode) + '">');

        for (QuoteDocumentPayload.Section section : payload.sections) {
            if ('Block'.equals(section.sectionType)) {
                out.add(block(section));
            } else {
                out.add(table(section, payload));
            }
        }

        out.add('</article>');
        return String.join(out, '\n');
    }

    /**
     * Block type drives the markup. This is where a renderer gets emphasis
     * from - not from tags smuggled through the body, which step 04 rejects
     * at generation precisely so that this decision stays here.
     */
    private static String block(QuoteDocumentPayload.Section section) {
        List<String> out = new List<String>();
        out.add('<section data-code="' + escape(section.code)
            + '" data-type="' + escape(section.blockType) + '">');

        if (String.isNotBlank(section.heading)) {
            out.add('<h2>' + escape(section.heading) + '</h2>');
        }
        String tag = 'Notice'.equals(section.blockType) ? 'strong' : 'p';
        out.add('<' + tag + '>' + escape(section.body) + '</' + tag + '>');
        out.add('</section>');
        return String.join(out, '\n');
    }

    private static String table(
        QuoteDocumentPayload.Section section, QuoteDocumentPayload payload
    ) {
        List<String> out = new List<String>();
        out.add('<section data-code="' + escape(section.code) + '">');

        if (String.isNotBlank(section.title)) {
            out.add('<h2>' + escape(section.title) + '</h2>');
        }
        if (String.isNotBlank(section.subtitle)) {
            out.add('<h3>' + escape(section.subtitle) + '</h3>');
        }
        if (String.isNotBlank(section.introText)) {
            out.add('<p>' + escape(section.introText) + '</p>');
        }

        out.add('<table><thead><tr>');
        for (QuoteDocumentPayload.Column column : section.columns) {
            out.add('<th data-code="' + escape(column.code) + '">' + escape(column.label) + '</th>');
        }
        out.add('</tr></thead><tbody>');

        for (QuoteDocumentPayload.Row row : section.rows) {
            out.add('<tr data-row-type="' + escape(row.rowType)
                + '" data-key="' + escape(row.key) + '">');
            for (QuoteDocumentPayload.Column column : section.columns) {
                out.add('<td data-code="' + escape(column.code) + '">'
                    + format(row.values.get(column.code), column.dataType, payload)
                    + '</td>');
            }
            out.add('</tr>');
        }

        out.add('</tbody></table>');
        if (String.isNotBlank(section.footerText)) {
            out.add('<p>' + escape(section.footerText) + '</p>');
        }
        out.add('</section>');
        return String.join(out, '\n');
    }

    /**
     * The one place this adapter exercises judgement, and it is presentation
     * judgement only.
     *
     * NULL IS AN EMPTY CELL AND ZERO PRINTS. They are different values and a
     * renderer that collapses them tells the reader a measure was zero when it
     * did not apply at all.
     *
     * The currency code comes from the payload rather than from the running
     * user or the org: the snapshot records which currency it was generated
     * in, and a renderer that looked anywhere else could print a different
     * currency than the one the numbers were calculated in.
     */
    private static String format(Object value, String dataType, QuoteDocumentPayload payload) {
        if (value == null) {
            return '';
        }
        if ('Currency'.equals(dataType)) {
            return escape(payload.currencyIsoCode) + '&nbsp;' + String.valueOf(value);
        }
        if ('Boolean'.equals(dataType)) {
            return value == true ? 'Yes' : 'No';
        }
        return escape(String.valueOf(value));
    }

    private static String escape(String value) {
        return value == null ? '' : value.escapeHtml4();
    }
}
