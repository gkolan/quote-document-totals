/**
 * Loads and evaluates vendor-neutral Table composition conditions.
 * Conditions in one numbered set are AND; the numbered sets are OR.
 */
public with sharing class QuoteDocumentCondition {
  public Integer conditionSet;
  public Integer sequence;
  public String fieldPath;
  public String operator;
  public String compareValue;
  public String dataType;

  private static final Set<String> OPERATORS = new Set<String>{
    'Equals',
    'Not Equals',
    'Is Blank',
    'Is Not Blank',
    'In',
    'Greater Than',
    'Greater Or Equal',
    'Less Than',
    'Less Or Equal'
  };
  private static Map<String, List<QuoteDocumentCondition>> cachedByTableCode;

  /**
   * @param tableCode Stable Table definition code.
   * @param lines Lines already accepted by the compatibility line filter.
   * @return Lines matching at least one complete condition set.
   */
  public static List<QuoteDocumentLine> apply(
    String tableCode,
    List<QuoteDocumentLine> lines
  ) {
    List<QuoteDocumentCondition> conditions = forTable(tableCode);
    if (conditions.isEmpty()) {
      return lines == null ? new List<QuoteDocumentLine>() : lines;
    }
    List<QuoteDocumentLine> kept = new List<QuoteDocumentLine>();
    for (
      QuoteDocumentLine line : (lines == null
        ? new List<QuoteDocumentLine>()
        : lines)
    ) {
      if (matchesAnySet(line, conditions)) {
        kept.add(line);
      }
    }
    return kept;
  }

  /**
   * @param tableCode Stable Table definition code.
   * @return Conditions in stable set and sequence order.
   */
  public static List<QuoteDocumentCondition> forTable(String tableCode) {
    load();
    return cachedByTableCode.containsKey(tableCode)
      ? cachedByTableCode.get(tableCode)
      : new List<QuoteDocumentCondition>();
  }

  /** @return Every Quote Line field path required by active conditions. */
  public static Set<String> allFieldPaths() {
    load();
    Set<String> paths = new Set<String>();
    for (List<QuoteDocumentCondition> conditions : cachedByTableCode.values()) {
      for (QuoteDocumentCondition condition : conditions) {
        paths.add(condition.fieldPath);
      }
    }
    return paths;
  }

  private static void load() {
    if (cachedByTableCode != null) {
      return;
    }
    cachedByTableCode = new Map<String, List<QuoteDocumentCondition>>();
    Map<Id, String> codeByDefinitionId = new Map<Id, String>();
    for (
      Quote_Document_Table_Def__mdt definition : Quote_Document_Table_Def__mdt.getAll()
        .values()
    ) {
      codeByDefinitionId.put(definition.Id, definition.Table_Code__c);
    }
    for (
      Quote_Document_Condition__mdt record : Quote_Document_Condition__mdt.getAll()
        .values()
    ) {
      if (record.Is_Active__c != true) {
        continue;
      }
      String tableCode = codeByDefinitionId.get(record.Table_Definition__c);
      if (String.isBlank(tableCode)) {
        throw QuoteDocumentContributorError.build(
          'CONDITION_TABLE_UNKNOWN',
          'Condition ' +
            record.DeveloperName +
            ' does not resolve to a Table Definition.'
        );
      }
      QuoteDocumentCondition condition = new QuoteDocumentCondition();
      condition.conditionSet = integerOf(record.Condition_Set__c);
      condition.sequence = integerOf(record.Sequence__c);
      condition.fieldPath = record.Field_Path__c;
      condition.operator = record.Operator__c;
      condition.compareValue = record.Compare_Value__c;
      condition.dataType = record.Data_Type__c;
      condition.validate(tableCode);
      if (!cachedByTableCode.containsKey(tableCode)) {
        cachedByTableCode.put(tableCode, new List<QuoteDocumentCondition>());
      }
      insertOrdered(cachedByTableCode.get(tableCode), condition);
    }
  }

  private void validate(String tableCode) {
    if (
      conditionSet == null ||
      conditionSet < 1 ||
      sequence == null ||
      sequence < 1
    ) {
      fail(
        tableCode,
        'CONDITION_ORDER_INVALID',
        'Condition Set and Sequence must be positive whole numbers.'
      );
    }
    if (String.isBlank(fieldPath)) {
      fail(tableCode, 'CONDITION_FIELD_MISSING', 'Field Path is required.');
    }
    if (!OPERATORS.contains(operator)) {
      fail(
        tableCode,
        'CONDITION_OPERATOR_UNSUPPORTED',
        'Operator is not supported: ' + operator + '.'
      );
    }
    if (
      !new Set<String>{ 'Text', 'Number', 'Date', 'Boolean' }.contains(dataType)
    ) {
      fail(
        tableCode,
        'CONDITION_TYPE_UNSUPPORTED',
        'Data Type is not supported: ' + dataType + '.'
      );
    }
    QuoteDocumentQuery.validateLineFieldPath(fieldPath);
    if (
      !new Set<String>{ 'Is Blank', 'Is Not Blank' }.contains(operator) &&
      String.isBlank(compareValue)
    ) {
      fail(
        tableCode,
        'CONDITION_VALUE_MISSING',
        'Compare Value is required for ' + operator + '.'
      );
    }
    if (
      new Set<String>{
          'Greater Than',
          'Greater Or Equal',
          'Less Than',
          'Less Or Equal'
        }
        .contains(operator) &&
      !new Set<String>{ 'Number', 'Date' }.contains(dataType)
    ) {
      fail(
        tableCode,
        'CONDITION_COMPARISON_INVALID',
        operator + ' requires Number or Date.'
      );
    }
    if (
      !new Set<String>{ 'Is Blank', 'Is Not Blank', 'In' }.contains(operator)
    ) {
      parse(compareValue);
    }
    if ('In'.equals(operator)) {
      for (String candidate : splitValues(compareValue)) {
        parse(candidate);
      }
    }
  }

  private static Boolean matchesAnySet(
    QuoteDocumentLine line,
    List<QuoteDocumentCondition> conditions
  ) {
    Map<Integer, Boolean> matchedBySet = new Map<Integer, Boolean>();
    for (QuoteDocumentCondition condition : conditions) {
      Boolean prior =
        !matchedBySet.containsKey(condition.conditionSet) ||
        matchedBySet.get(condition.conditionSet);
      matchedBySet.put(
        condition.conditionSet,
        prior && condition.matches(line.fieldPathRawValue(condition.fieldPath))
      );
    }
    for (Boolean matched : matchedBySet.values()) {
      if (matched) {
        return true;
      }
    }
    return false;
  }

  private Boolean matches(Object actual) {
    Boolean blank =
      actual == null ||
      (actual instanceof String && String.isBlank((String) actual));
    if ('Is Blank'.equals(operator)) {
      return blank;
    }
    if ('Is Not Blank'.equals(operator)) {
      return !blank;
    }
    if (blank) {
      return 'Not Equals'.equals(operator);
    }
    Object typedActual = parse(String.valueOf(actual));
    if ('In'.equals(operator)) {
      for (String candidate : splitValues(compareValue)) {
        if (compare(typedActual, parse(candidate)) == 0) {
          return true;
        }
      }
      return false;
    }
    Integer result = compare(typedActual, parse(compareValue));
    switch on operator {
      when 'Equals' {
        return result == 0;
      }
      when 'Not Equals' {
        return result != 0;
      }
      when 'Greater Than' {
        return result > 0;
      }
      when 'Greater Or Equal' {
        return result >= 0;
      }
      when 'Less Than' {
        return result < 0;
      }
      when 'Less Or Equal' {
        return result <= 0;
      }
      when else {
        return false;
      }
    }
  }

  private Object parse(String value) {
    try {
      switch on dataType {
        when 'Number' {
          return Decimal.valueOf(value);
        }
        when 'Date' {
          return Date.valueOf(value);
        }
        when 'Boolean' {
          if (
            !new Set<String>{ 'true', 'false' }.contains(value.toLowerCase())
          ) {
            throw new QuoteDocumentGenerator.QuoteDocumentException(
              'Expected true or false.'
            );
          }
          return Boolean.valueOf(value);
        }
        when else {
          return value.trim();
        }
      }
    } catch (Exception e) {
      throw QuoteDocumentContributorError.build(
        'CONDITION_VALUE_INVALID',
        'Value "' +
          value +
          '" is not a valid ' +
          dataType +
          ' for field ' +
          fieldPath +
          '.'
      );
    }
  }

  private Integer compare(Object left, Object right) {
    if (left instanceof Decimal) {
      Decimal a = (Decimal) left;
      Decimal b = (Decimal) right;
      return a == b ? 0 : (a < b ? -1 : 1);
    }
    if (left instanceof Date) {
      Date a = (Date) left;
      Date b = (Date) right;
      return a == b ? 0 : (a < b ? -1 : 1);
    }
    if (left instanceof Boolean) {
      return left == right ? 0 : ((Boolean) left ? 1 : -1);
    }
    return String.valueOf(left).compareTo(String.valueOf(right));
  }

  private static List<String> splitValues(String raw) {
    List<String> values = new List<String>();
    for (String candidate : raw.split(';')) {
      if (String.isNotBlank(candidate)) {
        values.add(candidate.trim());
      }
    }
    return values;
  }

  private static void insertOrdered(
    List<QuoteDocumentCondition> conditions,
    QuoteDocumentCondition candidate
  ) {
    Integer position = 0;
    while (
      position < conditions.size() &&
      (conditions[position].conditionSet < candidate.conditionSet ||
      (conditions[position].conditionSet == candidate.conditionSet &&
      conditions[position].sequence <= candidate.sequence))
    ) {
      position++;
    }
    if (position == conditions.size()) {
      conditions.add(candidate);
    } else {
      conditions.add(position, candidate);
    }
  }

  private static Integer integerOf(Decimal value) {
    return value == null ? null : Integer.valueOf(String.valueOf(value));
  }

  private void fail(String tableCode, String code, String detail) {
    throw QuoteDocumentContributorError.build(
      code,
      'Table ' +
        tableCode +
        ', condition set ' +
        conditionSet +
        ', sequence ' +
        sequence +
        ': ' +
        detail
    );
  }

  @TestVisible
  private static QuoteDocumentCondition forTest(
    Integer conditionSet,
    Integer sequence,
    String fieldPath,
    String operator,
    String compareValue,
    String dataType
  ) {
    QuoteDocumentCondition condition = new QuoteDocumentCondition();
    condition.conditionSet = conditionSet;
    condition.sequence = sequence;
    condition.fieldPath = fieldPath;
    condition.operator = operator;
    condition.compareValue = compareValue;
    condition.dataType = dataType;
    condition.validate('TEST');
    return condition;
  }

  @TestVisible
  private static void useConditions(
    Map<String, List<QuoteDocumentCondition>> conditions
  ) {
    cachedByTableCode = conditions;
  }
}
