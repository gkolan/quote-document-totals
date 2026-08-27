/**
 * Which columns a table prints, in what order, bound to what, formatted how.
 *
 * Before this existed the column layout lived only in a Word template's
 * `<Value Select="..."/>` tags. That is the single largest reason a second
 * renderer was expensive: the layout had to be rebuilt by hand and could
 * diverge from the first with nothing to catch it.
 *
 * DEFAULTS, SO NOTHING HAD TO BE AUTHORED TWICE
 * ---------------------------------------------
 * A table definition with no column records emits a label column plus one per
 * field in its measure set. Every definition that existed before this step
 * keeps working with zero new configuration. Records are needed only when a
 * table wants a SUBSET, a different order, or a non-measure field - which is
 * exactly what the guides show most tables doing.
 *
 * WHY ANY READABLE FIELD IS BINDABLE
 * ----------------------------------
 * Restricting bindings to the table's measure set would have been the safe
 * looking choice and would have closed the cheapest flexibility lever in the
 * design: a subscriber adding a custom field to Quote_Document_Row__c in
 * their own org can print it with one metadata row and no core change. It
 * would also have banned Product_Code__c, Quantity__c and Charge_Type__c,
 * which are legitimate columns today.
 *
 * The failure that restriction was aimed at - a CHANGE table printing
 * Amount_List__c, which that measure set never populates - is caught exactly,
 * by COLUMN_MEASURE_MISMATCH, without the collateral damage.
 */
public with sharing class QuoteDocumentColumnDefinition {

    public String columnCode;
    public Integer displayOrder;
    public String valueField;
    public String dataType;

    /** The label column: no bound field, prints the row's own Display_Label__c. */
    public static final String CODE_LABEL = 'COL_LABEL';

    public Boolean isLabelColumn() {
        return String.isBlank(valueField);
    }

    // -----------------------------------------------------------------------
    // Type rules
    // -----------------------------------------------------------------------

    /**
     * Readable is not the same as render-safe. Every rejection here is a value
     * a renderer could not print without inventing a presentation decision of
     * its own, which is precisely what this contract forbids.
     */
    private static final Map<DisplayType, String> RENDERABLE = new Map<DisplayType, String>{
        DisplayType.STRING    => 'Text',
        DisplayType.TEXTAREA  => 'Text',
        DisplayType.PICKLIST  => 'Text',
        DisplayType.EMAIL     => 'Text',
        DisplayType.PHONE     => 'Text',
        DisplayType.URL       => 'Text',
        DisplayType.BOOLEAN   => 'Boolean',
        DisplayType.DATE      => 'Date',
        DisplayType.DATETIME  => 'DateTime',
        DisplayType.INTEGER   => 'Number',
        DisplayType.DOUBLE    => 'Number',
        DisplayType.CURRENCY  => 'Currency',
        DisplayType.PERCENT   => 'Percent'
    };

    /** Named so the error can say WHY, not merely that the type is unsupported. */
    private static final Map<DisplayType, String> REJECTED = new Map<DisplayType, String>{
        DisplayType.MULTIPICKLIST => 'a multi-select picklist - the separator between values is a '
            + 'presentation decision, so resolve it into a text field in Apex first',
        DisplayType.BASE64 => 'binary content, which is not printable',
        DisplayType.ENCRYPTEDSTRING => 'an encrypted field, which must never enter a snapshot',
        DisplayType.REFERENCE => 'a lookup - an Id is not printable. Bind the resolved text field instead',
        DisplayType.ADDRESS => 'a compound address, which has no single scalar value',
        DisplayType.LOCATION => 'a compound location, which has no single scalar value',
        DisplayType.ANYTYPE => 'polymorphic, so no renderer can know how to format it',
        DisplayType.DATACATEGORYGROUPREFERENCE => 'a data category reference, which is not printable'
    };

    /**
     * Validates the binding against the real schema, and returns the column.
     *
     * Two separate checks, because they fail for different reasons and a
     * single message would explain neither well: the field must be RENDERABLE,
     * and the declared Data_Type__c must AGREE with what the field actually
     * is. The second is not redundant with the schema - Data_Type__c is what
     * the renderer reads so it never has to describe the schema itself, which
     * means a wrong declaration is how two adapters start formatting the same
     * value differently.
     */
    public void validate(String tableCode, String measureSet) {
        if (String.isBlank(columnCode)) {
            throw QuoteDocumentContributorError.build(
                'COLUMN_CODE_MISSING',
                'Table ' + tableCode + ' has a column definition with no Column_Code__c. A renderer keys '
                    + 'layout off the code, so an unnamed column cannot be bound to anything.'
            );
        }
        if (displayOrder == null) {
            throw QuoteDocumentContributorError.build(
                'COLUMN_ORDER_MISSING',
                'Table ' + tableCode + ', column ' + columnCode + ' has no Display_Order__c. Renderers print '
                    + 'in Display_Order__c and nothing else, so its position would be arbitrary.'
            );
        }

        if (isLabelColumn()) {
            // Nothing to schema-check; the label column prints the row's own
            // Display_Label__c, which every row is guaranteed to carry.
            requireDeclaredType(tableCode, 'Text');
            return;
        }

        SObjectField field = Quote_Document_Row__c.SObjectType.getDescribe()
            .fields.getMap().get(valueField.toLowerCase());

        if (field == null) {
            throw QuoteDocumentContributorError.build(
                'COLUMN_FIELD_UNKNOWN',
                'Table ' + tableCode + ', column ' + columnCode + ' binds Value_Field__c "' + valueField
                    + '", which does not exist on Quote_Document_Row__c. A renamed or deleted field must '
                    + 'fail here rather than arriving as a permanently blank column.'
            );
        }

        DescribeFieldResult describe = field.getDescribe();
        DisplayType type = describe.getType();

        if (REJECTED.containsKey(type)) {
            throw QuoteDocumentContributorError.build(
                'COLUMN_TYPE_UNSUPPORTED',
                'Table ' + tableCode + ', column ' + columnCode + ' binds ' + valueField + ', which is '
                    + REJECTED.get(type) + '.'
            );
        }
        if (!RENDERABLE.containsKey(type)) {
            throw QuoteDocumentContributorError.build(
                'COLUMN_TYPE_UNSUPPORTED',
                'Table ' + tableCode + ', column ' + columnCode + ' binds ' + valueField + ', of type '
                    + type + ', which no renderer in this contract knows how to format.'
            );
        }

        // Rich text is TEXTAREA with isHtmlFormatted, so it cannot be caught
        // by DisplayType alone. It carries markup, and no vendor-neutral
        // payload may contain markup - that is the whole point of the contract.
        if (type == DisplayType.TEXTAREA && describe.isHtmlFormatted()) {
            throw QuoteDocumentContributorError.build(
                'COLUMN_TYPE_UNSUPPORTED',
                'Table ' + tableCode + ', column ' + columnCode + ' binds ' + valueField + ', a Rich Text '
                    + 'field. Rich text carries HTML, and a vendor-neutral payload may not contain markup.'
            );
        }

        requireDeclaredType(tableCode, RENDERABLE.get(type));
        requireMeasureBelongsToThisTable(tableCode, measureSet);
    }

    private void requireDeclaredType(String tableCode, String expected) {
        if (String.isBlank(dataType)) {
            throw QuoteDocumentContributorError.build(
                'COLUMN_TYPE_DECLARATION_MISMATCH',
                'Table ' + tableCode + ', column ' + columnCode + ' has no Data_Type__c. It should be "'
                    + expected + '". A renderer reads this instead of describing the schema itself, so it '
                    + 'cannot be left for the renderer to guess.'
            );
        }
        if (!expected.equalsIgnoreCase(dataType)) {
            throw QuoteDocumentContributorError.build(
                'COLUMN_TYPE_DECLARATION_MISMATCH',
                'Table ' + tableCode + ', column ' + columnCode + ' declares Data_Type__c "' + dataType
                    + '" but ' + (isLabelColumn() ? 'a label column' : valueField) + ' is "' + expected
                    + '". A Currency field declared as Text is exactly how two adapters start formatting '
                    + 'the same value differently.'
            );
        }
    }

    /**
     * A measure from the OTHER measure set is never populated for this table,
     * so the column would print blank forever. Non-measure fields are always
     * allowed - see the class comment.
     */
    private void requireMeasureBelongsToThisTable(String tableCode, String measureSet) {
        Set<String> allowed = new Set<String>(QuoteDocumentTableDefinition.measureFields(measureSet));
        if (allowed.contains(valueField)) {
            return;
        }

        Set<String> everyMeasure = new Set<String>(
            QuoteDocumentTableDefinition.measureFields(QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL)
        );
        everyMeasure.addAll(
            QuoteDocumentTableDefinition.measureFields(QuoteDocumentTableDefinition.MEASURES_CHANGE)
        );

        if (everyMeasure.contains(valueField)) {
            throw QuoteDocumentContributorError.build(
                'COLUMN_MEASURE_MISMATCH',
                'Table ' + tableCode + ' uses measure set ' + measureSet + ', but column ' + columnCode
                    + ' binds ' + valueField + ', which belongs to the other measure set and is never '
                    + 'populated for this table. The column would print blank on every row.'
            );
        }
        // Not a measure at all - Product_Code__c, Quantity__c, a subscriber's
        // own field. Always allowed, deliberately.
    }

    // -----------------------------------------------------------------------
    // Loading
    // -----------------------------------------------------------------------

    /**
     * The default set, used when a definition declares no columns: the row
     * label, then every measure the table actually populates.
     *
     * The count is deliberately not fixed anywhere - it follows measureFields()
     * so adding a measure does not silently leave a table printing a stale
     * column list.
     */
    public static List<QuoteDocumentColumnDefinition> defaultsFor(String measureSet) {
        List<QuoteDocumentColumnDefinition> columns = new List<QuoteDocumentColumnDefinition>();

        QuoteDocumentColumnDefinition label = new QuoteDocumentColumnDefinition();
        label.columnCode = CODE_LABEL;
        label.displayOrder = 10;
        label.dataType = 'Text';
        columns.add(label);

        Integer order = 20;
        for (String measure : QuoteDocumentTableDefinition.measureFields(measureSet)) {
            QuoteDocumentColumnDefinition column = new QuoteDocumentColumnDefinition();
            column.columnCode = codeFor(measure);
            column.displayOrder = order;
            column.valueField = measure;
            column.dataType = declaredTypeOf(measure);
            columns.add(column);
            order += 10;
        }
        return columns;
    }

    /** Amount_Net__c -> COL_NET, Quantity__c -> COL_QUANTITY. Mechanical, so a new measure needs no table here. */
    @TestVisible
    private static String codeFor(String fieldName) {
        String bare = fieldName.endsWith('__c') ? fieldName.removeEnd('__c') : fieldName;
        if (bare.startsWith('Amount_')) {
            bare = bare.removeStart('Amount_');
        }
        return 'COL_' + bare.toUpperCase();
    }

    /** Reads the declared type off the schema, so the defaults can never disagree with validate(). */
    private static String declaredTypeOf(String fieldName) {
        SObjectField field = Quote_Document_Row__c.SObjectType.getDescribe()
            .fields.getMap().get(fieldName.toLowerCase());
        if (field == null) {
            return 'Text';
        }
        String declared = RENDERABLE.get(field.getDescribe().getType());
        return declared == null ? 'Text' : declared;
    }

    private static Map<String, List<QuoteDocumentColumnDefinition>> cached;

    /** code -> ordered columns, for every table definition that declares any. */
    public static Map<String, List<QuoteDocumentColumnDefinition>> byTableCode() {
        if (cached != null) {
            return cached;
        }

        Map<Id, String> codeByDefinitionId = new Map<Id, String>();
        for (Quote_Document_Table_Def__mdt record : [
            SELECT Id, Table_Code__c FROM Quote_Document_Table_Def__mdt
        ]) {
            codeByDefinitionId.put(record.Id, record.Table_Code__c);
        }

        Map<String, List<QuoteDocumentColumnDefinition>> byCode =
            new Map<String, List<QuoteDocumentColumnDefinition>>();

        for (Quote_Document_Column_Def__mdt record : [
            SELECT Table_Definition__c, Column_Code__c, Display_Order__c, Value_Field__c, Data_Type__c
            FROM Quote_Document_Column_Def__mdt
            WHERE Is_Active__c = true
            ORDER BY Display_Order__c
        ]) {
            String tableCode = codeByDefinitionId.get(record.Table_Definition__c);
            if (tableCode == null) {
                continue;
            }

            QuoteDocumentColumnDefinition column = new QuoteDocumentColumnDefinition();
            column.columnCode = record.Column_Code__c;
            column.displayOrder = record.Display_Order__c == null
                ? null : Integer.valueOf(record.Display_Order__c);
            column.valueField = record.Value_Field__c;
            column.dataType = record.Data_Type__c;

            if (!byCode.containsKey(tableCode)) {
                byCode.put(tableCode, new List<QuoteDocumentColumnDefinition>());
            }
            byCode.get(tableCode).add(column);
        }

        cached = byCode;
        return cached;
    }

    /**
     * The columns one table will actually generate: its explicit records if it
     * has any, otherwise the defaults. Validated here so a broken column
     * definition fails config load, on the first generation of any quote,
     * rather than on whichever quote happens to exercise that table.
     */
    public static List<QuoteDocumentColumnDefinition> forTable(QuoteDocumentTableDefinition definition) {
        List<QuoteDocumentColumnDefinition> columns = byTableCode().get(definition.tableCode);
        if (columns == null || columns.isEmpty()) {
            columns = defaultsFor(definition.measureSet);
        }

        Set<String> seenCodes = new Set<String>();
        Set<Integer> seenOrders = new Set<Integer>();

        for (QuoteDocumentColumnDefinition column : columns) {
            column.validate(definition.tableCode, definition.measureSet);

            if (!seenCodes.add(column.columnCode)) {
                throw QuoteDocumentContributorError.build(
                    'COLUMN_CODE_DUPLICATE',
                    'Table ' + definition.tableCode + ' declares Column_Code__c "' + column.columnCode
                        + '" twice. A renderer keys off the code, so a duplicate makes one of the two '
                        + 'unaddressable.'
                );
            }
            if (!seenOrders.add(column.displayOrder)) {
                throw QuoteDocumentContributorError.build(
                    'COLUMN_ORDER_DUPLICATE',
                    'Table ' + definition.tableCode + ' has two columns at Display_Order__c '
                        + column.displayOrder + '. Their printed order would depend on query order, so two '
                        + 'renderers could legitimately print the same snapshot differently.'
                );
            }
        }
        return columns;
    }

    @TestVisible
    private static void useColumns(Map<String, List<QuoteDocumentColumnDefinition>> columns) {
        cached = columns;
    }
}
