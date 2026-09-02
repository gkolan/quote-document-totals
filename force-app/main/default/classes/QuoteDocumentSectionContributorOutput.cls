/** Unsaved, vendor-neutral records returned by a whole-document composer. */
public with sharing class QuoteDocumentSectionContributorOutput {
  public List<Quote_Document_Table__c> tables = new List<Quote_Document_Table__c>();
  public List<Quote_Document_Column__c> columns = new List<Quote_Document_Column__c>();
  public List<Quote_Document_Row__c> rows = new List<Quote_Document_Row__c>();
  public List<Quote_Document_Block__c> blocks = new List<Quote_Document_Block__c>();
  public List<Quote_Document_Fact__c> facts = new List<Quote_Document_Fact__c>();

  /** Adds another contributor's output without sharing mutable lists. */
  public void addAll(QuoteDocumentSectionContributorOutput other) {
    if (other == null) {
      return;
    }
    tables.addAll(
      other.tables == null ? new List<Quote_Document_Table__c>() : other.tables
    );
    columns.addAll(
      other.columns == null
        ? new List<Quote_Document_Column__c>()
        : other.columns
    );
    rows.addAll(
      other.rows == null ? new List<Quote_Document_Row__c>() : other.rows
    );
    blocks.addAll(
      other.blocks == null ? new List<Quote_Document_Block__c>() : other.blocks
    );
    facts.addAll(
      other.facts == null ? new List<Quote_Document_Fact__c>() : other.facts
    );
  }

  /** True when the contributor deliberately returned no document content. */
  public Boolean isEmpty() {
    return tables.isEmpty() &&
      columns.isEmpty() &&
      rows.isEmpty() &&
      blocks.isEmpty() &&
      facts.isEmpty();
  }
}
