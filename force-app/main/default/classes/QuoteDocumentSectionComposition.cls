/** Loads and runs whole-document composers, then validates their unsaved output. */
public with sharing class QuoteDocumentSectionComposition {
  @TestVisible
  private static List<Quote_Document_Composer__mdt> injectedConfigs;

  /** Test-only configuration injection; production always reads Custom Metadata. */
  @TestVisible
  private static void useConfigs(List<Quote_Document_Composer__mdt> configs) {
    injectedConfigs = configs;
  }

  /** Runs active Apex and Flow composers in configured order. */
  public static QuoteDocumentSectionContributorOutput compose(
    SBQQ__Quote__c quote,
    List<QuoteDocumentLine> lines,
    List<Quote_Document_Fact__c> documentFacts,
    String locale,
    String currencyIsoCode
  ) {
    QuoteDocumentSectionContributorOutput combined = new QuoteDocumentSectionContributorOutput();
    for (Quote_Document_Composer__mdt config : configs()) {
      validateConfig(config);
      QuoteDocumentSectionContributorContext context = new QuoteDocumentSectionContributorContext(
        quote,
        lines,
        documentFacts,
        locale,
        currencyIsoCode,
        config.Composer_Code__c,
        config.Version__c
      );

      QuoteDocumentSectionContributorOutput output;
      if (String.isNotBlank(config.Composer_Code__c)) {
        output = QuoteDocumentSectionContributorRegistry.resolve(
            config.Composer_Code__c
          )
          .compose(context);
      } else {
        output = QuoteDocumentFlowSectionContributor.compose(
          config.Flow_API_Name__c,
          context
        );
      }
      if (output == null) {
        throw QuoteDocumentContributorError.build(
          QuoteDocumentContributorError.NO_OUTPUT,
          'Document composer "' + config.DeveloperName + '" returned null.'
        );
      }
      String sourceIdentity = String.isNotBlank(config.Composer_Code__c)
        ? 'APEX_COMPOSER:' + config.Composer_Code__c
        : 'FLOW_COMPOSER:' + config.Flow_API_Name__c;
      for (Quote_Document_Table__c table : output.tables) {
        if (String.isBlank(table.Source_Identity__c)) {
          table.Source_Identity__c = sourceIdentity;
        }
        if (String.isBlank(table.Source_Version__c)) {
          table.Source_Version__c = config.Version__c;
        }
        if (String.isBlank(table.Locale__c)) {
          table.Locale__c = context.locale;
        }
        if (String.isBlank(table.Status__c)) {
          table.Status__c = 'Generating';
        }
        if (String.isBlank(table.Amount_Basis__c)) {
          table.Amount_Basis__c = 'Final Value';
        }
      }
      for (Quote_Document_Block__c block : output.blocks) {
        if (String.isBlank(block.Source_Identity__c)) {
          block.Source_Identity__c = sourceIdentity;
        }
        if (String.isBlank(block.Locale__c)) {
          block.Locale__c = context.locale;
        }
        if (String.isBlank(block.Source_Version__c)) {
          block.Source_Version__c = config.Version__c;
        }
      }
      for (Quote_Document_Fact__c fact : output.facts) {
        if (String.isBlank(fact.Source_Identity__c)) {
          fact.Source_Identity__c = sourceIdentity + ':' + config.Version__c;
        }
      }
      combined.addAll(output);
    }
    return combined;
  }

  /** Stable composer identity included in the snapshot fingerprint. */
  public static List<String> fingerprintParts() {
    List<String> parts = new List<String>();
    for (Quote_Document_Composer__mdt config : configs()) {
      validateConfig(config);
      parts.add(String.valueOf(config.Display_Order__c));
      parts.add(config.Composer_Code__c);
      parts.add(config.Flow_API_Name__c);
      parts.add(config.Version__c);
      parts.addAll(parsePaths(config.Quote_Dependency_Paths__c));
      parts.addAll(parsePaths(config.Line_Dependency_Paths__c));
    }
    return parts;
  }

  /** Quote fields a composer declares beyond the standard context. */
  public static List<String> quoteDependencyPaths() {
    return dependencyPaths(true);
  }

  /** Quote Line fields a composer declares beyond the standard context. */
  public static List<String> lineDependencyPaths() {
    return dependencyPaths(false);
  }

  /** Whole-document composers are rerun because their complete dependencies are not enumerable. */
  public static Boolean hasActiveComposers() {
    return !configs().isEmpty();
  }

  /** Validates keys and relationships against both standard and contributed Tables. */
  public static void validate(
    QuoteDocumentSectionContributorOutput output,
    Id quoteId,
    Set<String> existingTableKeys,
    Set<String> existingRowKeys
  ) {
    Set<String> tableKeys = existingTableKeys == null
      ? new Set<String>()
      : existingTableKeys.clone();
    Set<String> contributedTableKeys = new Set<String>();
    Set<String> rowKeys = existingRowKeys == null
      ? new Set<String>()
      : existingRowKeys.clone();
    Set<String> factCodes = new Set<String>();
    Map<String, Integer> displayedColumnsByTable = new Map<String, Integer>();
    Map<String, Integer> displayedRowsByTable = new Map<String, Integer>();
    Map<String, Set<String>> columnCodesByTable = new Map<String, Set<String>>();
    Map<String, Set<Decimal>> columnOrdersByTable = new Map<String, Set<Decimal>>();
    Map<String, Set<Decimal>> rowOrdersByTable = new Map<String, Set<Decimal>>();
    Map<String, Quote_Document_Table__c> contributedTablesByKey = new Map<String, Quote_Document_Table__c>();
    Map<String, Decimal> grandTotalInputsByTable = new Map<String, Decimal>();
    Map<String, Decimal> payableAmountsByTable = new Map<String, Decimal>();

    for (Quote_Document_Table__c table : output.tables) {
      rejectId(table.Id, 'Table');
      require(
        table.Table_Key__c,
        'DOCUMENT_TABLE_KEY_MISSING',
        'A contributed Table has no Table_Key__c.'
      );
      if (!tableKeys.add(table.Table_Key__c)) {
        fail(
          'DOCUMENT_TABLE_KEY_DUPLICATE',
          'Table key "' + table.Table_Key__c + '" is used more than once.'
        );
      }
      contributedTableKeys.add(table.Table_Key__c);
      contributedTablesByKey.put(table.Table_Key__c, table);
      require(
        table.Name,
        'DOCUMENT_TABLE_NAME_MISSING',
        'Contributed Table "' +
          table.Table_Key__c +
          '" has no Salesforce Table Name.'
      );
      require(
        table.Table_Code__c,
        'DOCUMENT_TABLE_CODE_MISSING',
        'Contributed Table "' + table.Table_Key__c + '" has no Table Code.'
      );
      require(
        table.Display_Title__c,
        'DOCUMENT_TABLE_TITLE_MISSING',
        'Contributed Table "' +
          table.Table_Key__c +
          '" has no customer-facing title.'
      );
      require(
        table.Source_Identity__c,
        'DOCUMENT_TABLE_SOURCE_MISSING',
        'Contributed Table "' + table.Table_Key__c + '" has no source identity.'
      );
      require(
        table.Source_Version__c,
        'DOCUMENT_TABLE_VERSION_MISSING',
        'Contributed Table "' + table.Table_Key__c + '" has no source version.'
      );
      if (table.Display_Order__c == null) {
        fail(
          'DOCUMENT_TABLE_ORDER_MISSING',
          'Contributed Table "' + table.Table_Key__c + '" has no Display Order.'
        );
      }
      table.Quote__c = quoteId;
      table.Is_Displayed__c = table.Is_Displayed__c != false;
    }
    for (Quote_Document_Column__c column : output.columns) {
      rejectId(column.Id, 'Column');
      require(
        column.Table_Key__c,
        'DOCUMENT_COLUMN_TABLE_KEY_MISSING',
        'A contributed Column has no Table_Key__c.'
      );
      if (!contributedTableKeys.contains(column.Table_Key__c)) {
        fail(
          'DOCUMENT_COLUMN_TABLE_UNKNOWN',
          'Column "' +
            column.Column_Code__c +
            '" names unknown Table key "' +
            column.Table_Key__c +
            '".'
        );
      }
      require(
        column.Column_Code__c,
        'DOCUMENT_COLUMN_CODE_MISSING',
        'A contributed Column has no Column Code.'
      );
      require(
        column.Display_Label__c,
        'DOCUMENT_COLUMN_LABEL_MISSING',
        'Column "' + column.Column_Code__c + '" has no customer-facing label.'
      );
      require(
        column.Data_Type__c,
        'DOCUMENT_COLUMN_TYPE_MISSING',
        'Column "' + column.Column_Code__c + '" has no Data Type.'
      );
      column.Is_Displayed__c = column.Is_Displayed__c != false;
      if (column.Display_Order__c == null) {
        fail(
          'DOCUMENT_COLUMN_ORDER_MISSING',
          'Column "' + column.Column_Code__c + '" has no Display Order.'
        );
      }
      addUnique(
        columnCodesByTable,
        column.Table_Key__c,
        column.Column_Code__c,
        'DOCUMENT_COLUMN_CODE_DUPLICATE'
      );
      addUniqueOrder(
        columnOrdersByTable,
        column.Table_Key__c,
        column.Display_Order__c,
        'DOCUMENT_COLUMN_ORDER_DUPLICATE'
      );
      QuoteDocumentColumnDefinition definition = new QuoteDocumentColumnDefinition();
      definition.columnCode = column.Column_Code__c;
      definition.displayOrder = column.Display_Order__c.intValue();
      definition.valueField = column.Value_Field__c;
      definition.dataType = column.Data_Type__c;
      definition.formatRole = column.Format_Role__c;
      definition.totalRule = column.Total_Rule__c;
      definition.validate(
        contributedTablesByKey.get(column.Table_Key__c).Table_Code__c,
        contributedTablesByKey.get(column.Table_Key__c).Measure_Set__c
      );
      if (column.Is_Displayed__c != false) {
        increment(displayedColumnsByTable, column.Table_Key__c);
      }
    }
    for (Quote_Document_Row__c row : output.rows) {
      rejectId(row.Id, 'Row');
      require(
        row.Table_Key__c,
        'DOCUMENT_ROW_TABLE_KEY_MISSING',
        'A contributed Row has no Table_Key__c.'
      );
      require(
        row.Row_Key__c,
        'DOCUMENT_ROW_KEY_MISSING',
        'A contributed Row has no Row_Key__c.'
      );
      require(
        row.Row_Type__c,
        'DOCUMENT_ROW_TYPE_MISSING',
        'Row "' + row.Row_Key__c + '" has no Row Type.'
      );
      require(
        row.Display_Label__c,
        'DOCUMENT_ROW_LABEL_MISSING',
        'Row "' + row.Row_Key__c + '" has no customer-facing label.'
      );
      if (row.Group_Level__c == null) {
        fail(
          'DOCUMENT_ROW_LEVEL_MISSING',
          'Row "' + row.Row_Key__c + '" has no Group Level.'
        );
      }
      row.Is_Displayed__c = row.Is_Displayed__c != false;
      if (!contributedTableKeys.contains(row.Table_Key__c)) {
        fail(
          'DOCUMENT_ROW_TABLE_UNKNOWN',
          'Row "' +
            row.Row_Key__c +
            '" names unknown Table key "' +
            row.Table_Key__c +
            '".'
        );
      }
      String rowIdentity = row.Table_Key__c + '::' + row.Row_Key__c;
      if (!rowKeys.add(rowIdentity)) {
        fail(
          'DOCUMENT_ROW_KEY_DUPLICATE',
          'Row key "' + row.Row_Key__c + '" is used more than once.'
        );
      }
      if (row.Display_Order__c == null) {
        fail(
          'DOCUMENT_ROW_ORDER_MISSING',
          'Row "' + row.Row_Key__c + '" has no Display Order.'
        );
      }
      addUniqueOrder(
        rowOrdersByTable,
        row.Table_Key__c,
        row.Display_Order__c,
        'DOCUMENT_ROW_ORDER_DUPLICATE'
      );
      if (row.Is_Displayed__c != false) {
        increment(displayedRowsByTable, row.Table_Key__c);
        if (row.Include_In_Grand_Total__c == true) {
          Decimal inputAmount = row.Amount_Net__c == null
            ? 0
            : row.Amount_Net__c;
          grandTotalInputsByTable.put(
            row.Table_Key__c,
            (grandTotalInputsByTable.containsKey(row.Table_Key__c)
              ? grandTotalInputsByTable.get(row.Table_Key__c)
              : 0) + inputAmount
          );
        }
        if ('Payable'.equals(row.Total_Role__c)) {
          if (payableAmountsByTable.containsKey(row.Table_Key__c)) {
            fail(
              'DOCUMENT_TABLE_PAYABLE_DUPLICATE',
              'Table "' + row.Table_Key__c + '" has more than one Payable Row.'
            );
          }
          payableAmountsByTable.put(
            row.Table_Key__c,
            row.Amount_Net__c == null ? 0 : row.Amount_Net__c
          );
        }
      }
    }
    List<Quote_Document_Block__c> keptBlocks = new List<Quote_Document_Block__c>();
    for (Quote_Document_Block__c block : output.blocks) {
      rejectId(block.Id, 'Block');
      block.Quote__c = quoteId;
      if (
        String.isNotBlank(block.Related_Table_Key__c) &&
        !tableKeys.contains(block.Related_Table_Key__c)
      ) {
        continue;
      }
      if (
        String.isNotBlank(block.Related_Row_Key__c) &&
        !rowKeys.contains(
          block.Related_Table_Key__c + '::' + block.Related_Row_Key__c
        )
      ) {
        continue;
      }
      QuoteDocumentBlockBuilder.validate(block);
      keptBlocks.add(block);
    }
    output.blocks = keptBlocks;
    for (Quote_Document_Fact__c fact : output.facts) {
      rejectId(fact.Id, 'Fact');
      fact.Quote__c = quoteId;
      if (!factCodes.add(fact.Fact_Code__c)) {
        fail(
          'DOCUMENT_FACT_CODE_DUPLICATE',
          'Fact code "' +
            fact.Fact_Code__c +
            '" is used more than once by document composers.'
        );
      }
    }
    QuoteDocumentFactBuilder.validate(output.facts);
    for (Quote_Document_Table__c table : output.tables) {
      if (!displayedColumnsByTable.containsKey(table.Table_Key__c)) {
        fail(
          'DOCUMENT_TABLE_COLUMNS_MISSING',
          'Table "' + table.Table_Key__c + '" has no displayed Columns.'
        );
      }
      if (!displayedRowsByTable.containsKey(table.Table_Key__c)) {
        fail(
          'DOCUMENT_TABLE_ROWS_MISSING',
          'Table "' +
            table.Table_Key__c +
            '" has no displayed Rows. Return no Table when there is no applicable content.'
        );
      }
      if (
        payableAmountsByTable.containsKey(table.Table_Key__c) &&
        payableAmountsByTable.get(table.Table_Key__c) !=
        (grandTotalInputsByTable.containsKey(table.Table_Key__c)
          ? grandTotalInputsByTable.get(table.Table_Key__c)
          : 0)
      ) {
        fail(
          'DOCUMENT_TABLE_PAYABLE_UNRECONCILED',
          'Table "' +
            table.Table_Key__c +
            '" Payable does not equal the displayed Rows marked Include in Grand Total.'
        );
      }
    }
  }

  private static void increment(Map<String, Integer> counts, String key) {
    counts.put(key, counts.containsKey(key) ? counts.get(key) + 1 : 1);
  }

  private static void addUnique(
    Map<String, Set<String>> valuesByTable,
    String tableKey,
    String value,
    String code
  ) {
    if (!valuesByTable.containsKey(tableKey)) {
      valuesByTable.put(tableKey, new Set<String>());
    }
    if (!valuesByTable.get(tableKey).add(value)) {
      fail(
        code,
        'Table "' + tableKey + '" uses "' + value + '" more than once.'
      );
    }
  }

  private static void addUniqueOrder(
    Map<String, Set<Decimal>> valuesByTable,
    String tableKey,
    Decimal value,
    String code
  ) {
    if (!valuesByTable.containsKey(tableKey)) {
      valuesByTable.put(tableKey, new Set<Decimal>());
    }
    if (!valuesByTable.get(tableKey).add(value)) {
      fail(
        code,
        'Table "' +
          tableKey +
          '" uses Display Order ' +
          value +
          ' more than once.'
      );
    }
  }

  private static List<Quote_Document_Composer__mdt> configs() {
    List<Quote_Document_Composer__mdt> records = injectedConfigs == null
      ? [
          SELECT
            DeveloperName,
            Is_Active__c,
            Composer_Code__c,
            Flow_API_Name__c,
            Version__c,
            Display_Order__c,
            Quote_Dependency_Paths__c,
            Line_Dependency_Paths__c
          FROM Quote_Document_Composer__mdt
          WHERE Is_Active__c = TRUE
          WITH USER_MODE
        ]
      : injectedConfigs;
    List<ConfigOrder> ordered = new List<ConfigOrder>();
    Set<Decimal> composerOrders = new Set<Decimal>();
    for (Quote_Document_Composer__mdt record : records) {
      if (record.Is_Active__c == true) {
        validateConfig(record);
        if (!composerOrders.add(record.Display_Order__c)) {
          fail(
            'DOCUMENT_COMPOSER_ORDER_DUPLICATE',
            'More than one active document composer uses Display Order ' +
              record.Display_Order__c +
              '.'
          );
        }
        ordered.add(new ConfigOrder(record));
      }
    }
    ordered.sort();
    List<Quote_Document_Composer__mdt> active = new List<Quote_Document_Composer__mdt>();
    for (ConfigOrder item : ordered) {
      active.add(item.record);
    }
    return active;
  }

  private static List<String> dependencyPaths(Boolean quotePaths) {
    Set<String> uniquePaths = new Set<String>();
    for (Quote_Document_Composer__mdt config : configs()) {
      uniquePaths.addAll(
        parsePaths(
          quotePaths
            ? config.Quote_Dependency_Paths__c
            : config.Line_Dependency_Paths__c
        )
      );
    }
    List<String> ordered = new List<String>(uniquePaths);
    ordered.sort();
    return ordered;
  }

  private static List<String> parsePaths(String configuredPaths) {
    List<String> paths = new List<String>();
    if (String.isBlank(configuredPaths)) {
      return paths;
    }
    for (String candidate : configuredPaths.split('[,;\\n\\r]+')) {
      String path = candidate.trim();
      if (String.isNotBlank(path)) {
        paths.add(path);
      }
    }
    paths.sort();
    return paths;
  }

  private class ConfigOrder implements Comparable {
    private Quote_Document_Composer__mdt record;
    private ConfigOrder(Quote_Document_Composer__mdt record) {
      this.record = record;
    }
    public Integer compareTo(Object otherValue) {
      ConfigOrder other = (ConfigOrder) otherValue;
      Decimal mine = record.Display_Order__c == null
        ? 0
        : record.Display_Order__c;
      Decimal theirs = other.record.Display_Order__c == null
        ? 0
        : other.record.Display_Order__c;
      if (mine < theirs) {
        return -1;
      }
      if (mine > theirs) {
        return 1;
      }
      return String.valueOf(record.DeveloperName)
        .compareTo(String.valueOf(other.record.DeveloperName));
    }
  }

  private static void validateConfig(Quote_Document_Composer__mdt config) {
    Boolean hasApex = String.isNotBlank(config.Composer_Code__c);
    Boolean hasFlow = String.isNotBlank(config.Flow_API_Name__c);
    if (hasApex == hasFlow) {
      fail(
        'DOCUMENT_COMPOSER_TYPE_INVALID',
        'Composer "' +
          config.DeveloperName +
          '" must name exactly one Apex code or Flow API name.'
      );
    }
    require(
      config.Version__c,
      QuoteDocumentContributorError.VERSION_UNDECLARED,
      'Composer "' + config.DeveloperName + '" has no Version__c.'
    );
    if (config.Display_Order__c == null) {
      fail(
        'DOCUMENT_COMPOSER_ORDER_MISSING',
        'Composer "' + config.DeveloperName + '" has no Display Order.'
      );
    }
    if (!Pattern.matches('^[1-9][0-9]*$', config.Version__c)) {
      fail(
        QuoteDocumentContributorError.VERSION_UNDECLARED,
        'Composer "' +
          config.DeveloperName +
          '" Version__c must be a positive whole number.'
      );
    }
  }

  private static void rejectId(Id idValue, String kind) {
    if (idValue != null) {
      fail(
        'DOCUMENT_COMPOSER_RETURNED_PERSISTED_RECORD',
        kind + ' output already has Salesforce Id ' + idValue + '.'
      );
    }
  }
  private static void require(String value, String code, String detail) {
    if (String.isBlank(value)) {
      fail(code, detail);
    }
  }
  private static void fail(String code, String detail) {
    throw QuoteDocumentContributorError.build(code, detail);
  }
}
