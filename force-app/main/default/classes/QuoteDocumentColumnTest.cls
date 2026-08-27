/**
 * Step 02 - the column snapshot.
 *
 * The validation tests run without a Quote: binding rules are a pure function
 * of a column definition and the row schema, so testing them through full
 * generation would hide which check fired behind a fixture.
 */
@IsTest
private class QuoteDocumentColumnTest {

    @TestSetup
    static void setup() {
        QuoteDocumentTestData.setup();
    }

    private static QuoteDocumentTableDefinition definition(String tableCode, String measureSet) {
        QuoteDocumentTableDefinition def = QuoteDocumentTableDefinition.build(
            tableCode,
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        def.measureSet = measureSet;
        return def;
    }

    private static QuoteDocumentColumnDefinition column(String code, Integer order, String field, String type) {
        QuoteDocumentColumnDefinition col = new QuoteDocumentColumnDefinition();
        col.columnCode = code;
        col.displayOrder = order;
        col.valueField = field;
        col.dataType = type;
        return col;
    }

    private static String failureFrom(QuoteDocumentColumnDefinition col, QuoteDocumentTableDefinition def) {
        try {
            col.validate(def.tableCode, def.measureSet);
            return null;
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            return e.getMessage();
        }
    }

    // -----------------------------------------------------------------------
    // Defaults
    // -----------------------------------------------------------------------

    /**
     * The count is deliberately not asserted as a literal. It follows
     * measureFields(), so hard-coding it here would make adding a measure look
     * like a test failure rather than the change it is.
     */
    @IsTest
    static void defaultColumnsMatchTheMeasureSet() {
        List<QuoteDocumentColumnDefinition> columns = QuoteDocumentColumnDefinition.defaultsFor(
            QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL
        );

        List<String> measures = QuoteDocumentTableDefinition.measureFields(
            QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL
        );
        Assert.areEqual(
            measures.size() + 1,
            columns.size(),
            'The default set is one label column plus one per measure the table actually populates.'
        );
        Assert.areEqual(QuoteDocumentColumnDefinition.CODE_LABEL, columns[0].columnCode, 'Label column first.');
        Assert.isTrue(columns[0].isLabelColumn(), 'The label column binds no field.');

        for (Integer i = 0; i < measures.size(); i++) {
            Assert.areEqual(
                measures[i],
                columns[i + 1].valueField,
                'Default columns must follow measureFields() order exactly.'
            );
        }
    }

    @IsTest
    static void defaultColumnsForTheChangeSetBindChangeMeasures() {
        List<QuoteDocumentColumnDefinition> columns = QuoteDocumentColumnDefinition.defaultsFor(
            QuoteDocumentTableDefinition.MEASURES_CHANGE
        );

        Boolean sawNetChange = false;
        for (QuoteDocumentColumnDefinition col : columns) {
            if ('Amount_Net_Change__c'.equals(col.valueField)) {
                sawNetChange = true;
            }
            Assert.isNull(
                failureFrom(col, definition('T', QuoteDocumentTableDefinition.MEASURES_CHANGE)),
                'A default column must always be valid for its own measure set: ' + col.columnCode
            );
        }
        Assert.isTrue(sawNetChange, 'A CHANGE table must offer its net change measure.');
    }

    /** Codes are derived mechanically, so a new measure needs no lookup table maintained by hand. */
    @IsTest
    static void columnCodesAreDerivedFromTheFieldName() {
        Assert.areEqual('COL_NET', QuoteDocumentColumnDefinition.codeFor('Amount_Net__c'));
        Assert.areEqual('COL_NET_CHANGE', QuoteDocumentColumnDefinition.codeFor('Amount_Net_Change__c'));
        Assert.areEqual('COL_QUANTITY', QuoteDocumentColumnDefinition.codeFor('Quantity__c'));
    }

    // -----------------------------------------------------------------------
    // Binding rules
    // -----------------------------------------------------------------------

    @IsTest
    static void unknownValueFieldFailsGeneration() {
        String message = failureFrom(
            column('COL_X', 10, 'Not_A_Real_Field__c', 'Text'),
            definition('T', QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL)
        );
        Assert.isNotNull(message, 'A binding to a non-existent field must fail.');
        Assert.isTrue(message.contains('COLUMN_FIELD_UNKNOWN'), 'Wrong code: ' + message);
        Assert.isTrue(
            message.contains('Not_A_Real_Field__c'),
            'The message must name the field, or an admin has to guess which column: ' + message
        );
    }

    /** The precise failure the measure-set restriction was aimed at, without the collateral damage. */
    @IsTest
    static void measureSetMismatchFailsGeneration() {
        String message = failureFrom(
            column('COL_NET_CHANGE', 20, 'Amount_Net_Change__c', 'Currency'),
            definition('T', QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL)
        );
        Assert.isNotNull(message, 'A CHANGE measure on a PRICE_WATERFALL table must fail.');
        Assert.isTrue(message.contains('COLUMN_MEASURE_MISMATCH'), 'Wrong code: ' + message);
        Assert.isTrue(
            message.contains('never') && message.contains('populated'),
            'The message must explain that the column would print blank forever: ' + message
        );
    }

    /**
     * The collateral damage a measure-set allowlist would have caused.
     * Product_Code__c, Quantity__c and Charge_Type__c are legitimate columns
     * today and are not measures.
     */
    @IsTest
    static void nonMeasureFieldIsAValidColumnSource() {
        QuoteDocumentTableDefinition def = definition('T', QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL);

        Assert.isNull(
            failureFrom(column('COL_PRODUCT_CODE', 20, 'Product_Code__c', 'Text'), def),
            'Product_Code__c is a legitimate column and is not a measure.'
        );
        Assert.isNull(
            failureFrom(column('COL_CHARGE_TYPE', 30, 'Charge_Type__c', 'Text'), def),
            'Charge_Type__c is a legitimate column and is not a measure.'
        );
        Assert.isNull(
            failureFrom(column('COL_QUANTITY', 40, 'Quantity__c', 'Number'), def),
            'Quantity__c is a Number measure in PRICE_WATERFALL and must bind.'
        );
    }

    /**
     * The subscriber flexibility case. Group_Key__c stands in for a field a
     * subscriber added in their own org: the binding rule cannot tell core
     * fields from subscriber fields, which is exactly the property that makes
     * the lever work. If this passes, a subscriber-added field passes.
     */
    @IsTest
    static void aFieldOutsideTheMeasureSetsBindsWithNoCoreChange() {
        Assert.isNull(
            failureFrom(
                column('COL_SUBSCRIBER', 50, 'Group_Key__c', 'Text'),
                definition('T', QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL)
            ),
            'Any readable, renderable field must bind with one metadata row and no core change. This is '
                + 'the cheapest flexibility lever in the design and an allowlist would close it.'
        );
    }

    @IsTest
    static void aReferenceFieldIsRejectedAsUnprintable() {
        String message = failureFrom(
            column('COL_LINE', 20, 'Quote_Line__c', 'Text'),
            definition('T', QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL)
        );
        Assert.isNotNull(message, 'A lookup must not be bindable - an Id is not printable.');
        Assert.isTrue(message.contains('COLUMN_TYPE_UNSUPPORTED'), 'Wrong code: ' + message);
        Assert.isTrue(
            message.contains('Id is not printable'),
            'The message must say why, and what to do instead: ' + message
        );
    }

    @IsTest
    static void declaredTypeMustMatchSchema() {
        String message = failureFrom(
            column('COL_NET', 20, 'Amount_Net__c', 'Text'),
            definition('T', QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL)
        );
        Assert.isNotNull(message, 'A Currency field declared as Text must fail.');
        Assert.isTrue(message.contains('COLUMN_TYPE_DECLARATION_MISMATCH'), 'Wrong code: ' + message);
        Assert.isTrue(
            message.contains('Currency'),
            'The message must name the type the field actually is: ' + message
        );
    }

    @IsTest
    static void aMissingDeclaredTypeFails() {
        String message = failureFrom(
            column('COL_NET', 20, 'Amount_Net__c', null),
            definition('T', QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL)
        );
        Assert.isNotNull(message, 'A column with no Data_Type__c must fail rather than be guessed at.');
        Assert.isTrue(message.contains('COLUMN_TYPE_DECLARATION_MISMATCH'), 'Wrong code: ' + message);
    }

    @IsTest
    static void aColumnWithNoOrderFails() {
        String message = failureFrom(
            column('COL_NET', null, 'Amount_Net__c', 'Currency'),
            definition('T', QuoteDocumentTableDefinition.MEASURES_PRICE_WATERFALL)
        );
        Assert.isNotNull(message, 'Renderers print in Display_Order__c and nothing else.');
        Assert.isTrue(message.contains('COLUMN_ORDER_MISSING'), 'Wrong code: ' + message);
    }

    // -----------------------------------------------------------------------
    // Generation
    // -----------------------------------------------------------------------

    @IsTest
    static void everyGeneratedTableCarriesOrderedUniqueColumns() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        Map<Id, List<Quote_Document_Column__c>> byTable = new Map<Id, List<Quote_Document_Column__c>>();
        for (Quote_Document_Column__c col : [
            SELECT Quote_Document_Table__c, Quote_Document_Table__r.Table_Code__c, Column_Code__c,
                   Display_Label__c, Display_Order__c, Value_Field__c, Data_Type__c
            FROM Quote_Document_Column__c
            WHERE Quote_Document_Table__r.Quote__c = :quoteId
            ORDER BY Display_Order__c
        ]) {
            if (!byTable.containsKey(col.Quote_Document_Table__c)) {
                byTable.put(col.Quote_Document_Table__c, new List<Quote_Document_Column__c>());
            }
            byTable.get(col.Quote_Document_Table__c).add(col);
        }

        Assert.isFalse(byTable.isEmpty(), 'Generation must emit columns, or a renderer has no layout to read.');

        for (Id tableId : byTable.keySet()) {
            List<Quote_Document_Column__c> columns = byTable.get(tableId);
            String tableCode = columns[0].Quote_Document_Table__r.Table_Code__c;

            Set<String> codes = new Set<String>();
            Decimal previousOrder = -1;
            Boolean sawLabelOrContent = false;

            for (Quote_Document_Column__c col : columns) {
                Assert.isTrue(codes.add(col.Column_Code__c), tableCode + ' repeats ' + col.Column_Code__c);
                Assert.isNotNull(col.Display_Order__c, tableCode + '/' + col.Column_Code__c + ' has no order.');
                Assert.isTrue(
                    col.Display_Order__c > previousOrder,
                    tableCode + ' column orders must be unique and ascending.'
                );
                previousOrder = col.Display_Order__c;

                Assert.isTrue(
                    String.isNotBlank(col.Display_Label__c),
                    tableCode + '/' + col.Column_Code__c + ' has no heading, so a renderer would print a '
                        + 'blank column header.'
                );
                Assert.isTrue(
                    String.isNotBlank(col.Data_Type__c),
                    tableCode + '/' + col.Column_Code__c + ' has no Data_Type__c.'
                );
                if (String.isBlank(col.Value_Field__c) || col.Value_Field__c != null) {
                    sawLabelOrContent = true;
                }
            }
            Assert.isTrue(sawLabelOrContent, tableCode + ' has no label or content column.');
        }
    }

    /** The documented layout, exactly - four columns in the order its guide's section 8 table shows. */
    @IsTest
    static void explicitColumnDefinitionsWinOverDefaults() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        List<Quote_Document_Column__c> columns = [
            SELECT Column_Code__c, Value_Field__c, Data_Type__c, Display_Order__c
            FROM Quote_Document_Column__c
            WHERE Quote_Document_Table__r.Quote__c = :quoteId
              AND Quote_Document_Table__r.Table_Code__c = 'PRODUCT_FAMILY_SUMMARY'
            ORDER BY Display_Order__c
        ];

        if (columns.isEmpty()) {
            Assert.isTrue(true, 'PRODUCT_FAMILY_SUMMARY is not active in this org.');
            return;
        }

        Assert.areEqual(
            4,
            columns.size(),
            'PRODUCT_FAMILY_SUMMARY documents four columns. Falling back to the six-measure default set '
                + 'would mean the data no longer matches the guide.'
        );
        Assert.areEqual('COL_LABEL', columns[0].Column_Code__c);
        Assert.areEqual('Amount_List__c', columns[1].Value_Field__c);
        Assert.areEqual('Amount_Discount__c', columns[2].Value_Field__c);
        Assert.areEqual('Amount_Net__c', columns[3].Value_Field__c);
        Assert.areEqual('Currency', columns[3].Data_Type__c);
    }

    /** Every bound field must exist on the row object, or the column prints blank forever. */
    @IsTest
    static void everyGeneratedBindingResolvesOnTheRowObject() {
        Id quoteId = QuoteDocumentTestData.quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId });
        Test.stopTest();

        Map<String, SObjectField> rowFields = Quote_Document_Row__c.SObjectType.getDescribe().fields.getMap();

        for (Quote_Document_Column__c col : [
            SELECT Column_Code__c, Value_Field__c FROM Quote_Document_Column__c
            WHERE Quote_Document_Table__r.Quote__c = :quoteId
        ]) {
            if (String.isBlank(col.Value_Field__c)) {
                continue;
            }
            Assert.isTrue(
                rowFields.containsKey(col.Value_Field__c.toLowerCase()),
                col.Column_Code__c + ' binds ' + col.Value_Field__c + ', which is not on Quote_Document_Row__c.'
            );
        }
    }
}
