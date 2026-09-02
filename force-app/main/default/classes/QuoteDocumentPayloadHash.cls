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
        return computeAll(new Set<Id>{ quoteId }).get(quoteId);
    }

    /**
     * Hashes many quotes with the SAME fixed number of queries as one.
     *
     * The single-quote form used to be the only one, and the render service
     * called it per request - so integrity verification cost four queries per
     * quote in a batch. The flat-query-count test that should have caught it
     * requested the same quote three times, and the per-quote cache made it
     * pass. Two mistakes compounding: a per-quote cost, and a test that
     * measured the cache instead of the work.
     *
     * Everything here is keyed by quote up front, so nothing scales with batch
     * size.
     */
    public static Map<Id, String> computeAll(Set<Id> quoteIds) {
        Map<Id, String> digests = new Map<Id, String>();
        if (quoteIds == null || quoteIds.isEmpty()) {
            return digests;
        }

        Map<Id, List<Quote_Document_Table__c>> tablesByQuote =
            new Map<Id, List<Quote_Document_Table__c>>();
        Map<Id, Id> quoteByTable = new Map<Id, Id>();

        for (Quote_Document_Table__c table : [
            SELECT Id, Quote__c, Table_Code__c, Display_Title__c, Display_Subtitle__c, Intro_Text__c,
                   Footer_Text__c, Is_Displayed__c, Locale__c, Display_Order__c, Status__c
            FROM Quote_Document_Table__c
            WHERE Quote__c IN :quoteIds
            ORDER BY Display_Order__c, Table_Code__c
        ]) {
            if (!tablesByQuote.containsKey(table.Quote__c)) {
                tablesByQuote.put(table.Quote__c, new List<Quote_Document_Table__c>());
            }
            tablesByQuote.get(table.Quote__c).add(table);
            quoteByTable.put(table.Id, table.Quote__c);
        }

        Set<Id> tableIds = quoteByTable.keySet();

        Map<Id, List<Quote_Document_Column__c>> columnsByTable =
            new Map<Id, List<Quote_Document_Column__c>>();
        for (Quote_Document_Column__c column : [
            SELECT Quote_Document_Table__c, Column_Code__c, Display_Label__c, Display_Order__c,
                   Value_Field__c, Data_Type__c, Is_Displayed__c
            FROM Quote_Document_Column__c
            WHERE Quote_Document_Table__c IN :tableIds
            ORDER BY Display_Order__c, Column_Code__c
        ]) {
            if (!columnsByTable.containsKey(column.Quote_Document_Table__c)) {
                columnsByTable.put(column.Quote_Document_Table__c, new List<Quote_Document_Column__c>());
            }
            columnsByTable.get(column.Quote_Document_Table__c).add(column);
        }

        List<String> boundFields = new List<String>(configuredBindings(columnsByTable));
        List<String> rowFields = rowFieldList(boundFields);
        List<String> hashFields = rowHashFields(boundFields);

        Map<Id, List<SObject>> rowsByTable = new Map<Id, List<SObject>>();
        String rowSoql =
            'SELECT ' + String.join(rowFields, ', ')
            + ' FROM Quote_Document_Row__c WHERE Quote_Document_Table__c IN :tableIds'
            + ' ORDER BY Display_Order__c, Row_Key__c';
        for (SObject row : Database.query(rowSoql)) {
            Id parent = (Id) row.get('Quote_Document_Table__c');
            if (!rowsByTable.containsKey(parent)) {
                rowsByTable.put(parent, new List<SObject>());
            }
            rowsByTable.get(parent).add(row);
        }

        Map<Id, List<Quote_Document_Block__c>> blocksByQuote =
            new Map<Id, List<Quote_Document_Block__c>>();
        for (Quote_Document_Block__c block : [
            SELECT Quote__c, Block_Code__c, Block_Type__c, Display_Order__c, Is_Displayed__c,
                   Locale__c, Heading__c, Body__c, Source_Version__c
            FROM Quote_Document_Block__c
            WHERE Quote__c IN :quoteIds
            ORDER BY Display_Order__c, Block_Code__c
        ]) {
            if (!blocksByQuote.containsKey(block.Quote__c)) {
                blocksByQuote.put(block.Quote__c, new List<Quote_Document_Block__c>());
            }
            blocksByQuote.get(block.Quote__c).add(block);
        }

        for (Id quoteId : quoteIds) {
            digests.put(quoteId, digest(canonicalize(
                tablesByQuote.containsKey(quoteId)
                    ? tablesByQuote.get(quoteId) : new List<Quote_Document_Table__c>(),
                columnsByTable,
                rowsByTable,
                blocksByQuote.containsKey(quoteId)
                    ? blocksByQuote.get(quoteId) : new List<Quote_Document_Block__c>(),
                hashFields
            )));
        }
        return digests;
    }

    /**
     * The canonical form, from collections the caller already loaded.
     *
     * Takes data rather than an Id so it can be called once per quote inside a
     * bulk load without issuing a single further query.
     */
    private static String canonicalize(
        List<Quote_Document_Table__c> tables,
        Map<Id, List<Quote_Document_Column__c>> columnsByTable,
        Map<Id, List<SObject>> rowsByTable,
        List<Quote_Document_Block__c> blocks,
        List<String> hashFields
    ) {
        List<String> parts = new List<String>();

        for (Quote_Document_Table__c table : tables) {
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

            for (Quote_Document_Column__c column : columnsFor(columnsByTable, table.Id)) {
                parts.add('C');
                parts.add(text(column.Column_Code__c));
                parts.add(text(column.Display_Label__c));
                parts.add(number(column.Display_Order__c));
                parts.add(text(column.Value_Field__c));
                parts.add(text(column.Data_Type__c));
                parts.add(flag(column.Is_Displayed__c));
            }

            for (SObject row : rowsFor(rowsByTable, table.Id)) {
                parts.add('R');
                // Every selected field, in one sorted order, so the canonical
                // form does not depend on how the SELECT list was assembled -
                // and so a newly bound field is covered without anyone
                // remembering to add it here.
                for (String field : hashFields) {
                    parts.add(field);
                    parts.add(scalar(row.get(field)));
                }
            }
        }

        for (Quote_Document_Block__c block : blocks) {
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

    private static List<Quote_Document_Column__c> columnsFor(
        Map<Id, List<Quote_Document_Column__c>> byTable, Id tableId
    ) {
        return byTable.containsKey(tableId) ? byTable.get(tableId) : new List<Quote_Document_Column__c>();
    }

    private static List<SObject> rowsFor(Map<Id, List<SObject>> byTable, Id tableId) {
        return byTable.containsKey(tableId) ? byTable.get(tableId) : new List<SObject>();
    }

    /** Every field any configured column binds, whether or not core knows about it. */
    private static Set<String> configuredBindings(
        Map<Id, List<Quote_Document_Column__c>> columnsByTable
    ) {
        Map<String, SObjectField> rowFields =
            Quote_Document_Row__c.SObjectType.getDescribe().fields.getMap();

        Set<String> bound = new Set<String>();
        for (List<Quote_Document_Column__c> columns : columnsByTable.values()) {
            for (Quote_Document_Column__c column : columns) {
                if (String.isNotBlank(column.Value_Field__c)
                    && rowFields.containsKey(column.Value_Field__c.toLowerCase())) {
                    bound.add(column.Value_Field__c);
                }
            }
        }
        return bound;
    }

    /**
     * The hashed field list: the semantic base, every measure, and every
     * configured binding. Sorted, because the canonical form has to be
     * deterministic and a Set has no order.
     *
     * Interpolated into SOQL, so every name is either a literal here or one
     * the row describe has already proved exists.
     */
    private static List<String> rowFieldList(List<String> boundFields) {
        List<String> selected = new List<String>(rowHashFields(boundFields));
        // The parent Id is needed to GROUP the rows but must never be HASHED -
        // tables are deleted and recreated on every regeneration, so hashing
        // it would change the digest on every rebuild and make the integrity
        // check useless for the one case it exists for. The existing
        // regeneration test caught exactly this.
        selected.add('Quote_Document_Table__c');
        selected.sort();
        return selected;
    }

    /** The semantic fields: everything that PRINTS, and nothing that merely identifies a record. */
    private static List<String> rowHashFields(List<String> boundFields) {
        Set<String> fields = new Set<String>{
            'Row_Key__c', 'Row_Type__c', 'Display_Label__c',
            'Label_Key__c', 'Label_Arg_1__c', 'Label_Arg_2__c', 'Display_Order__c',
            'Group_Level__c', 'Group_Value__c', 'Is_Displayed__c',
            'Include_In_Subtotal__c', 'Include_In_Grand_Total__c',
            'Product_Code__c', 'Product_Name__c', 'Charge_Type__c', 'Transaction_Type__c'
        };
        fields.addAll(allMeasureFields());
        if (boundFields != null) {
            fields.addAll(boundFields);
        }

        List<String> sorted = new List<String>(fields);
        sorted.sort();
        return sorted;
    }

    /** One encoding for any scalar, so a newly bound field needs no per-type branch here. */
    private static String scalar(Object value) {
        if (value == null) {
            return '~null';
        }
        if (value instanceof Decimal) {
            return number((Decimal) value);
        }
        if (value instanceof Boolean) {
            return flag((Boolean) value);
        }
        return text(String.valueOf(value));
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
        assertIntact(quoteId, expectedHash, null);
    }

    /**
     * `actualHash` may be supplied by a caller that already hashed the batch,
     * so a bulk retrieval does not re-query per quote. Null means compute it.
     */
    public static void assertIntact(Id quoteId, String expectedHash, String actualHash) {
        if (String.isBlank(expectedHash)) {
            throw QuoteDocumentContributorError.build(
                'PAYLOAD_HASH_MISSING',
                'Quote ' + quoteId + ' has no Document_Payload_Hash__c, so its snapshot cannot be proven '
                    + 'untampered. Regenerate it - a snapshot published before integrity hashing existed '
                    + 'is not repairable, only replaceable.'
            );
        }

        String actual = actualHash == null ? compute(quoteId) : actualHash;
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
