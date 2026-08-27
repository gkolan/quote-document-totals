/**
 * ONE definition of "the semantic document", used by two things that must
 * never disagree: the integrity check that refuses to render a tampered
 * snapshot, and the adapter-equivalence test that proves two renderers were
 * given the same content.
 *
 * Two canonicalizers would drift, and the drift would be invisible - the
 * integrity check would pass on a document the equivalence test called
 * different, or the reverse, and neither would report anything.
 *
 * WHY A SECOND HASH EXISTS AT ALL
 * -------------------------------
 * Document_Data_Fingerprint__c hashes the INPUTS: the quote, its lines, the
 * configuration. It answers "should this be rebuilt". It cannot see tampering,
 * because none of these change any input:
 *
 *   - editing Display_Label__c or a block body
 *   - editing an amount on a saved row
 *   - changing Display_Order__c or Is_Displayed__c
 *   - changing a column binding
 *   - deleting one Detail row and inserting a replacement
 *
 * Row_Count__c catches a couple of those. Most render modified, with every
 * expectation matching. This hash covers the OUTPUT, so it catches all of them.
 *
 * SEMANTIC, NOT PHYSICAL
 * ----------------------
 * Record Ids, timestamps and the request Id are excluded deliberately: they
 * vary between two generations that produced the same document, and a hash
 * that changed on every regeneration would be useless for detecting the one
 * case that matters.
 */
public with sharing class QuoteDocumentPayloadHash {

    private static final String SEPARATOR = '';

    /**
     * Reads the persisted snapshot back and canonicalizes it.
     *
     * Reads from the DATABASE rather than from the in-memory lists the
     * generator still holds. That is the whole point: the hash must describe
     * what was actually saved, including anything a trigger, a validation
     * rule or a field default changed on the way in. Hashing the in-memory
     * intent would certify a document that was never stored.
     */
    public static String compute(Id quoteId) {
        return digest(canonicalize(quoteId));
    }

    @TestVisible
    private static String canonicalize(Id quoteId) {
        List<String> parts = new List<String>();

        // Tables, in the order a renderer walks them.
        for (Quote_Document_Table__c table : [
            SELECT Id, Table_Code__c, Display_Title__c, Display_Subtitle__c, Intro_Text__c,
                   Footer_Text__c, Is_Displayed__c, Locale__c, Display_Order__c, Status__c, Row_Count__c
            FROM Quote_Document_Table__c
            WHERE Quote__c = :quoteId
            ORDER BY Display_Order__c, Table_Code__c
        ]) {
            parts.add('T');
            parts.add(text(table.Table_Code__c));
            parts.add(text(table.Display_Title__c));
            parts.add(text(table.Display_Subtitle__c));
            parts.add(text(table.Intro_Text__c));
            parts.add(text(table.Footer_Text__c));
            parts.add(flag(table.Is_Displayed__c));
            parts.add(text(table.Locale__c));
            parts.add(number(table.Display_Order__c));
            parts.add(text(table.Status__c));

            for (Quote_Document_Column__c column : [
                SELECT Column_Code__c, Display_Label__c, Display_Order__c, Value_Field__c,
                       Data_Type__c, Is_Displayed__c
                FROM Quote_Document_Column__c
                WHERE Quote_Document_Table__c = :table.Id
                ORDER BY Display_Order__c, Column_Code__c
            ]) {
                parts.add('C');
                parts.add(text(column.Column_Code__c));
                parts.add(text(column.Display_Label__c));
                parts.add(number(column.Display_Order__c));
                parts.add(text(column.Value_Field__c));
                parts.add(text(column.Data_Type__c));
                parts.add(flag(column.Is_Displayed__c));
            }

            for (Quote_Document_Row__c row : [
                SELECT Row_Key__c, Row_Type__c, Display_Label__c, Label_Key__c, Label_Arg_1__c,
                       Label_Arg_2__c, Display_Order__c, Group_Level__c, Group_Value__c,
                       Is_Displayed__c, Include_In_Subtotal__c, Include_In_Grand_Total__c,
                       Amount_List__c, Amount_Regular__c, Amount_Discount__c, Amount_Net__c,
                       Amount_Customer__c, Quantity__c, Amount_Net_New__c, Amount_Cancellation__c,
                       Amount_Replacement_Removed__c, Amount_Replacement_Added__c,
                       Amount_Termination__c, Amount_Net_Change__c, Amount_Final__c,
                       Product_Code__c, Product_Name__c, Charge_Type__c, Transaction_Type__c
                FROM Quote_Document_Row__c
                WHERE Quote_Document_Table__c = :table.Id
                ORDER BY Display_Order__c, Row_Key__c
            ]) {
                parts.add('R');
                parts.add(text(row.Row_Key__c));
                parts.add(text(row.Row_Type__c));
                parts.add(text(row.Display_Label__c));
                parts.add(text(row.Label_Key__c));
                parts.add(text(row.Label_Arg_1__c));
                parts.add(text(row.Label_Arg_2__c));
                parts.add(number(row.Display_Order__c));
                parts.add(number(row.Group_Level__c));
                parts.add(text(row.Group_Value__c));
                parts.add(flag(row.Is_Displayed__c));
                parts.add(flag(row.Include_In_Subtotal__c));
                parts.add(flag(row.Include_In_Grand_Total__c));

                // Every measure, both sets. A table only populates one set, but
                // hashing both means adding a measure cannot silently fall
                // outside the integrity check.
                for (String field : allMeasureFields()) {
                    parts.add(number((Decimal) row.get(field)));
                }
                parts.add(text(row.Product_Code__c));
                parts.add(text(row.Product_Name__c));
                parts.add(text(row.Charge_Type__c));
                parts.add(text(row.Transaction_Type__c));
            }
        }

        for (Quote_Document_Block__c block : [
            SELECT Block_Code__c, Block_Type__c, Display_Order__c, Is_Displayed__c,
                   Locale__c, Heading__c, Body__c, Source_Version__c
            FROM Quote_Document_Block__c
            WHERE Quote__c = :quoteId
            ORDER BY Display_Order__c, Block_Code__c
        ]) {
            parts.add('B');
            parts.add(text(block.Block_Code__c));
            parts.add(text(block.Block_Type__c));
            parts.add(number(block.Display_Order__c));
            parts.add(flag(block.Is_Displayed__c));
            parts.add(text(block.Locale__c));
            parts.add(text(block.Heading__c));
            parts.add(text(block.Body__c));
            parts.add(text(block.Source_Version__c));
        }

        return String.join(parts, SEPARATOR);
    }

    private static List<String> allMeasureFields() {
        List<String> fields = new List<String>(
            QuoteDocumentTableDefinition.measureFields(
                QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL
            )
        );
        fields.addAll(
            QuoteDocumentTableDefinition.measureFields(QuoteDocumentTableDefinition.MEASURES_CHANGE)
        );
        fields.sort();
        return fields;
    }

    /** Null and empty encode differently - "no value" and "blank text" are different documents. */
    private static String text(String value) {
        return value == null ? '~null' : '=' + value;
    }

    /** Scale-normalised, so 10 and 10.00 hash alike; null stays distinct from zero. */
    private static String number(Decimal value) {
        return value == null ? '~null' : '#' + value.stripTrailingZeros().toPlainString();
    }

    private static String flag(Boolean value) {
        return value == null ? '~null' : (value ? '!true' : '!false');
    }

    private static String digest(String canonical) {
        return EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(canonical))
        );
    }

    /**
     * Refuses to hand out a snapshot that no longer matches what was
     * published.
     *
     * Never repairs. Nothing here knows which version was correct - the
     * persisted records or the hash - so the only safe action is to fail and
     * regenerate from the authoritative inputs. A "repair" would be a guess
     * written into a document someone signs.
     */
    public static void assertIntact(Id quoteId, String expectedHash) {
        if (String.isBlank(expectedHash)) {
            throw QuoteDocumentContributorError.build(
                'PAYLOAD_HASH_MISSING',
                'Quote ' + quoteId + ' has no Document_Payload_Hash__c, so its snapshot cannot be proven '
                    + 'untampered. Regenerate it - a snapshot published before integrity hashing existed '
                    + 'is not repairable, only replaceable.'
            );
        }

        String actual = compute(quoteId);
        if (!expectedHash.equals(actual)) {
            throw QuoteDocumentContributorError.build(
                'PAYLOAD_INTEGRITY_MISMATCH',
                'Quote ' + quoteId + ' was edited after publication. Expected payload hash ' + expectedHash
                    + ', found ' + actual + '. The source fingerprint still matches, so this is tampering '
                    + 'rather than a stale snapshot. Regenerate from the quote - the records must not be '
                    + '"repaired", because nothing knows which version was correct.'
            );
        }
    }
}
