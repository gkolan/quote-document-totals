/**
 * Builds the standalone narrative blocks for one quote's snapshot.
 *
 * Introductions, notices, terms, clauses, signature instructions and the
 * headings between tables are all standalone: none belongs to a single table,
 * and Intro_Text__c / Footer_Text__c cannot model any of them without
 * inventing an empty table to hang them from.
 *
 * Which blocks are included is decided HERE, during generation, never by the
 * renderer. A renderer walks one ordered sequence of tables and blocks and
 * prints what it is given.
 */
public with sharing class QuoteDocumentBlockBuilder {

    /**
     * Rejects markup by PATTERN, not by character.
     *
     * A blanket ban on `<` would be simpler and wrong: "terminates in < 30
     * days" is ordinary contractual prose and must be storable. What is
     * actually forbidden is a tag - `<` immediately followed by a letter or a
     * slash - plus the two template syntaxes this framework has already been
     * bitten by, DocuSign CLM's `<#` and merge-field guillemets.
     *
     * The point is not tidiness. A vendor-neutral payload containing vendor
     * markup is not vendor-neutral, and markup smuggled through a body is how
     * one renderer's output silently stops matching another's.
     */
    private static final Pattern MARKUP = Pattern.compile('(?s).*(<[A-Za-z/]|<#|«|»).*');

    @TestVisible
    private static Boolean containsMarkup(String body) {
        return body != null && MARKUP.matcher(body).matches();
    }

    /**
     * Validates one block's content before it can be persisted.
     *
     * Body is checked here rather than declaratively because the platform
     * cannot mark a Long Text Area required - so "empty body" would otherwise
     * be a silent success producing a blank paragraph in a customer document.
     */
    public static void validate(Quote_Document_Block__c block) {
        if (String.isBlank(block.Body__c)) {
            throw QuoteDocumentContributorError.build(
                'BLOCK_BODY_EMPTY',
                'Block ' + block.Block_Code__c + ' has no Body__c. A block with no text is a blank space in '
                    + 'a customer document; the platform cannot mark a Long Text Area required, so this is '
                    + 'checked here instead of being left to fail silently.'
            );
        }
        if (containsMarkup(block.Body__c)) {
            throw QuoteDocumentContributorError.build(
                'BLOCK_BODY_MARKUP',
                'Block ' + block.Block_Code__c + ' contains markup - an HTML tag, a "<#" template tag, or a '
                    + 'merge-field guillemet. A vendor-neutral payload carrying vendor markup is not '
                    + 'vendor-neutral. A renderer that needs bold gets it from Block_Type__c. Note that '
                    + 'ordinary prose using a less-than sign, such as "terminates in < 30 days", is fine.'
            );
        }
        if (String.isBlank(block.Source_Version__c)) {
            throw QuoteDocumentContributorError.build(
                'BLOCK_VERSION_MISSING',
                'Block ' + block.Block_Code__c + ' has no Source_Version__c. A signed document must be able '
                    + 'to prove which wording the customer agreed to after the source text has moved on.'
            );
        }
    }

    /**
     * Every active content record for this locale, ordered.
     *
     * Locale matching follows the same rule as the label dictionary: an exact
     * match wins, a region-qualified locale falls back to its base language,
     * and a base language never expands to a region.
     */
    public static List<Quote_Document_Block__c> build(SBQQ__Quote__c quote, String locale) {
        List<Quote_Document_Content__mdt> content = contentFor(locale);

        List<Quote_Document_Block__c> blocks = new List<Quote_Document_Block__c>();
        Set<String> seenCodes = new Set<String>();

        for (Quote_Document_Content__mdt record : content) {
            if (!seenCodes.add(record.Block_Code__c)) {
                throw QuoteDocumentContributorError.build(
                    'BLOCK_CODE_DUPLICATE',
                    'Two active Quote_Document_Content__mdt records supply Block_Code__c "'
                        + record.Block_Code__c + '" for locale ' + locale + '. Which wording printed would '
                        + 'depend on query order.'
                );
            }

            Quote_Document_Block__c block = new Quote_Document_Block__c(
                Quote__c = quote.Id,
                Block_Code__c = record.Block_Code__c,
                Block_Type__c = record.Block_Type__c,
                Display_Order__c = record.Display_Order__c,
                Locale__c = locale,
                Heading__c = record.Heading__c,
                Body__c = record.Body__c,
                Source_Version__c = record.Version__c,
                Is_Displayed__c = true
            );
            validate(block);
            blocks.add(block);
        }
        return blocks;
    }

    private static List<Quote_Document_Content__mdt> contentFor(String locale) {
        List<Quote_Document_Content__mdt> exact = [
            SELECT Block_Code__c, Block_Type__c, Display_Order__c, Heading__c, Body__c, Version__c, Locale__c
            FROM Quote_Document_Content__mdt
            WHERE Is_Active__c = true AND Locale__c = :locale
            ORDER BY Display_Order__c
        ];
        if (!exact.isEmpty() || !locale.contains('_')) {
            return exact;
        }

        String base = locale.split('_')[0];
        return [
            SELECT Block_Code__c, Block_Type__c, Display_Order__c, Heading__c, Body__c, Version__c, Locale__c
            FROM Quote_Document_Content__mdt
            WHERE Is_Active__c = true AND Locale__c = :base
            ORDER BY Display_Order__c
        ];
    }

    /**
     * Blocks and tables share ONE document-wide ordering sequence, so a
     * collision between them is a real ambiguity rather than a tidiness
     * problem: the renderer would have to choose, and two renderers could
     * legitimately choose differently.
     */
    public static void assertOrderingIsUnambiguous(
        List<Quote_Document_Block__c> blocks, List<Quote_Document_Table__c> tables
    ) {
        Map<Decimal, String> ownerByOrder = new Map<Decimal, String>();

        for (Quote_Document_Table__c table : tables) {
            if (table.Display_Order__c != null) {
                ownerByOrder.put(table.Display_Order__c, 'table ' + table.Table_Code__c);
            }
        }
        for (Quote_Document_Block__c block : blocks) {
            if (block.Display_Order__c == null) {
                continue;
            }
            if (ownerByOrder.containsKey(block.Display_Order__c)) {
                throw QuoteDocumentContributorError.build(
                    'DOCUMENT_ORDER_DUPLICATE',
                    'Block ' + block.Block_Code__c + ' and ' + ownerByOrder.get(block.Display_Order__c)
                        + ' both sit at Display_Order__c ' + block.Display_Order__c
                        + '. Blocks and tables share one document-wide sequence, so their printed order '
                        + 'would depend on query order and two renderers could legitimately disagree.'
                );
            }
            ownerByOrder.put(block.Display_Order__c, 'block ' + block.Block_Code__c);
        }
    }
}
