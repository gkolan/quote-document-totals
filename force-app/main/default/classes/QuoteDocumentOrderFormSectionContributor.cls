/** Example composer that creates Hardware, Software, and Services tables from Product Family. */
public with sharing class QuoteDocumentOrderFormSectionContributor implements QuoteDocumentSectionContributor {
  public QuoteDocumentSectionContributorOutput compose(
    QuoteDocumentSectionContributorContext context
  ) {
    QuoteDocumentSectionContributorOutput output = new QuoteDocumentSectionContributorOutput();
    Map<String, List<QuoteDocumentLine>> linesByFamily = new Map<String, List<QuoteDocumentLine>>();
    for (QuoteDocumentLine line : context.lines) {
      if (
        line.isBundledComponent == true ||
        line.isDisplayed == false ||
        line.isOptional == true
      ) {
        continue;
      }
      String family = String.isBlank(line.productFamily)
        ? 'Other'
        : line.productFamily;
      if (!linesByFamily.containsKey(family)) {
        linesByFamily.put(family, new List<QuoteDocumentLine>());
      }
      linesByFamily.get(family).add(line);
    }

    List<String> families = new List<String>(linesByFamily.keySet());
    families.sort();
    Decimal tableOrder = 100;
    for (String family : families) {
      String sectionName = sectionName(family);
      String key =
        'ORDER_FORM:' + sectionName.toUpperCase().replaceAll('[^A-Z0-9]+', '_');
      output.tables.add(
        new Quote_Document_Table__c(
          Name = (context.quote.Name + ' - ' + sectionName).abbreviate(80),
          Quote__c = context.quote.Id,
          Table_Key__c = key,
          Table_Code__c = key,
          Display_Title__c = sectionName,
          Display_Order__c = tableOrder,
          Is_Displayed__c = true,
          Locale__c = context.locale,
          Status__c = 'Generating',
          Amount_Basis__c = 'Final Value',
          Measure_Set__c = 'PRICE_WATERFALL',
          Group_Dimensions__c = 'NONE'
        )
      );
      addColumns(output, key, family);
      addRows(output, key, linesByFamily.get(family));
      tableOrder += 10;
    }
    return output;
  }

  private static void addColumns(
    QuoteDocumentSectionContributorOutput output,
    String key,
    String family
  ) {
    output.columns.add(
      column(key, 'PRODUCT_CODE', 'Product Code', 'Text', 'Product_Code__c', 10)
    );
    output.columns.add(
      column(key, 'PRODUCT_NAME', 'Product Name', 'Text', 'Product_Name__c', 20)
    );
    output.columns.add(
      column(
        key,
        'DESCRIPTION',
        'Description',
        'Text',
        'Product_Description__c',
        30
      )
    );
    Decimal order = 40;
    if (isServices(family)) {
      output.columns.add(
        column(key, 'START_DATE', 'Start Date', 'Date', 'Start_Date__c', order)
      );
      order += 10;
      output.columns.add(
        column(key, 'END_DATE', 'End Date', 'Date', 'End_Date__c', order)
      );
      order += 10;
    }
    output.columns.add(
      column(key, 'QUANTITY', 'Quantity', 'Number', 'Quantity__c', order)
    );
    order += 10;
    output.columns.add(
      column(
        key,
        'LIST_PRICE',
        'List Price',
        'Currency',
        'Amount_List__c',
        order
      )
    );
    order += 10;
    output.columns.add(
      column(
        key,
        'DISCOUNT',
        'Discount',
        'Currency',
        'Amount_Discount__c',
        order
      )
    );
    order += 10;
    output.columns.add(
      column(
        key,
        'CUSTOMER_PRICE',
        'Customer Price',
        'Currency',
        'Amount_Net__c',
        order
      )
    );
  }

  private static Quote_Document_Column__c column(
    String tableKey,
    String code,
    String label,
    String dataType,
    String valueField,
    Decimal order
  ) {
    return new Quote_Document_Column__c(
      Table_Key__c = tableKey,
      Column_Code__c = code,
      Display_Label__c = label,
      Data_Type__c = dataType,
      Value_Field__c = valueField,
      Format_Role__c = code,
      Total_Rule__c = 'CUSTOMER_PRICE'.equals(code) ? 'Payable' : 'None',
      Display_Order__c = order,
      Is_Displayed__c = true
    );
  }

  private static void addRows(
    QuoteDocumentSectionContributorOutput output,
    String tableKey,
    List<QuoteDocumentLine> lines
  ) {
    Decimal order = 10;
    Decimal total = 0;
    Decimal listTotal = 0;
    Decimal discountTotal = 0;
    for (QuoteDocumentLine line : lines) {
      Decimal quantity = line.quantity == null ? 0 : line.quantity;
      Decimal amount = line.amountNet == null ? 0 : line.amountNet;
      output.rows.add(
        new Quote_Document_Row__c(
          Table_Key__c = tableKey,
          Row_Key__c = tableKey + ':LINE:' + String.valueOf(line.quoteLineId),
          Row_Type__c = 'Detail',
          Display_Label__c = line.productName,
          Display_Order__c = order,
          Group_Level__c = 0,
          Is_Displayed__c = true,
          Quote_Line__c = line.quoteLineId,
          Product_Code__c = line.productCode,
          Product_Name__c = line.productName,
          Product_Description__c = line.productDescription,
          Start_Date__c = line.subscriptionStartDate,
          End_Date__c = line.subscriptionEndDate,
          Quantity__c = quantity,
          Unit_Price__c = quantity == 0 ? null : amount / quantity,
          Amount_List__c = line.amountList,
          Amount_Discount__c = line.amountDiscount,
          Amount_Net__c = amount,
          Include_In_Subtotal__c = true,
          Include_In_Grand_Total__c = true,
          Total_Role__c = 'Line Extension'
        )
      );
      total += amount;
      listTotal += line.amountList == null ? 0 : line.amountList;
      discountTotal += line.amountDiscount == null ? 0 : line.amountDiscount;
      order += 10;
    }
    output.rows.add(
      new Quote_Document_Row__c(
        Table_Key__c = tableKey,
        Row_Key__c = tableKey + ':TOTAL',
        Row_Type__c = 'Grand Total',
        Display_Label__c = 'Total',
        Display_Order__c = order,
        Group_Level__c = 0,
        Is_Displayed__c = true,
        Amount_List__c = listTotal,
        Amount_Discount__c = discountTotal,
        Amount_Net__c = total,
        Include_In_Subtotal__c = false,
        Include_In_Grand_Total__c = false,
        Total_Role__c = 'Payable'
      )
    );
  }

  private static Boolean isServices(String family) {
    return 'Service'.equalsIgnoreCase(family) ||
      'Services'.equalsIgnoreCase(family);
  }

  private static String sectionName(String family) {
    if ('Software'.equalsIgnoreCase(family)) {
      return 'Software Subscriptions';
    }
    if (isServices(family)) {
      return 'Services Schedule';
    }
    return family;
  }
}
