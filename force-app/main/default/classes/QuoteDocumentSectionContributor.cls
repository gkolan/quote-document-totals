/** Builds complete vendor-neutral document sections before any output records are saved. */
public interface QuoteDocumentSectionContributor {
  /** Returns unsaved Tables, Columns, Rows, Blocks, and Facts for one Quote. */
  QuoteDocumentSectionContributorOutput compose(
    QuoteDocumentSectionContributorContext context
  );
}
