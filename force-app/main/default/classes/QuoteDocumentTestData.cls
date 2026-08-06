/**
 * The quote every QuoteDocument test suite works from, and the helpers that
 * read what CPQ actually computed for it.
 *
 * Extracted so the suites can be split by subject without duplicating fixture
 * code. @TestSetup cannot be inherited or shared, so each suite declares its
 * own one-line @TestSetup that calls setup() here - the data is identical
 * across them, which is what makes an expectation written in one suite mean
 * the same thing in another.
 *
 * Line totals on SBQQ__QuoteLine__c are formula fields, so setup() sets the
 * writable price and quantity inputs and lets CPQ compute the totals. Expected
 * values are then derived from what CPQ actually calculated rather than
 * hardcoded - the point of these assertions is that the generator adds up the
 * same lines CPQ did, not that a particular formula produces a particular
 * number.
 *
 * The CPQ Calculate API is deliberately not invoked: the generator reads stored
 * totals, so priced lines are all it needs, and Calculate would make the tests
 * slow and non-deterministic.
 */
@IsTest
public class QuoteDocumentTestData {

    public static final String CODE_PACKAGE   = 'TEST_PACKAGE';
    public static final String CODE_COMPONENT = 'TEST_COMPONENT';
    public static final String CODE_OPTION    = 'TEST_OPTION';
    public static final String CODE_PLAN      = 'TEST_PLAN';
    public static final String CODE_OPTIONAL  = 'TEST_OPTIONAL';

    public static void setup() {
        Account account = new Account(Name = 'Document Totals Test', Industry = 'Technology');
        insert account;

        Opportunity opportunity = new Opportunity(
            Name = 'Document Totals Test',
            AccountId = account.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30)
        );
        insert opportunity;

        List<Product2> products = new List<Product2>{
            new Product2(Name = 'Test Package',   ProductCode = CODE_PACKAGE,   Family = 'Hardware', IsActive = true),
            new Product2(Name = 'Test Component', ProductCode = CODE_COMPONENT, Family = 'Hardware', IsActive = true),
            new Product2(Name = 'Test Option',    ProductCode = CODE_OPTION,    Family = 'Service',  IsActive = true),
            new Product2(Name = 'Test Plan',      ProductCode = CODE_PLAN,      Family = 'Service',  IsActive = true),
            new Product2(Name = 'Test Optional',  ProductCode = CODE_OPTIONAL,  Family = 'Software', IsActive = true)
        };
        insert products;

        SBQQ__Quote__c quote = new SBQQ__Quote__c(
            SBQQ__Account__c = account.Id,
            SBQQ__Opportunity2__c = opportunity.Id,
            SBQQ__Primary__c = false,
            SBQQ__Type__c = 'Quote'
        );
        insert quote;

        Map<String, Id> productByCode = new Map<String, Id>();
        for (Product2 p : products) {
            productByCode.put(p.ProductCode, p.Id);
        }

        // The package carries the price for itself and its component.
        SBQQ__QuoteLine__c packageLine = line(quote.Id, productByCode.get(CODE_PACKAGE), 1, 10, 100, 90);
        packageLine.SBQQ__Bundle__c = true;
        insert packageLine;

        List<SBQQ__QuoteLine__c> lines = new List<SBQQ__QuoteLine__c>();

        // Bundled component: priced at zero, visible, must never count.
        SBQQ__QuoteLine__c component = line(quote.Id, productByCode.get(CODE_COMPONENT), 2, 10, 0, 0);
        component.SBQQ__Bundled__c = true;
        component.SBQQ__OptionLevel__c = 1;
        component.SBQQ__RequiredBy__c = packageLine.Id;
        lines.add(component);

        // Separately-priced option under the same package: counts.
        SBQQ__QuoteLine__c option = line(quote.Id, productByCode.get(CODE_OPTION), 3, 1, 50, 50);
        option.SBQQ__OptionLevel__c = 1;
        option.SBQQ__RequiredBy__c = packageLine.Id;
        lines.add(option);

        // Standalone recurring charge.
        SBQQ__QuoteLine__c plan = line(quote.Id, productByCode.get(CODE_PLAN), 4, 1, 120, 120);
        plan.SBQQ__ChargeType__c = 'Recurring';
        plan.SBQQ__BillingType__c = 'Advance'; // CPQ rejects a recurring charge without one
        plan.SBQQ__BillingFrequency__c = 'Monthly';
        lines.add(plan);

        // Optional: priced, displayed, excluded from the ordinary totals.
        SBQQ__QuoteLine__c optional = line(quote.Id, productByCode.get(CODE_OPTIONAL), 5, 2, 200, 200);
        optional.SBQQ__Optional__c = true;
        lines.add(optional);

        insert lines;
    }

    public static SBQQ__QuoteLine__c line(
        Id quoteId, Id productId, Integer lineNumber,
        Decimal quantity, Decimal listPrice, Decimal netPrice
    ) {
        return new SBQQ__QuoteLine__c(
            SBQQ__Quote__c = quoteId,
            SBQQ__Product__c = productId,
            SBQQ__Number__c = lineNumber,
            SBQQ__Quantity__c = quantity,
            SBQQ__ListPrice__c = listPrice,
            SBQQ__RegularPrice__c = listPrice,
            SBQQ__NetPrice__c = netPrice,
            SBQQ__CustomerPrice__c = netPrice
        );
    }

    // -----------------------------------------------------------------------
    // What CPQ actually computed, so expectations are derived not guessed.
    // -----------------------------------------------------------------------

    public static List<SBQQ__QuoteLine__c> computedLines() {
        return [
            SELECT Id, SBQQ__ProductCode__c, SBQQ__ChargeType__c, SBQQ__Optional__c,
                   SBQQ__Bundled__c, SBQQ__NetTotal__c
            FROM SBQQ__QuoteLine__c
            ORDER BY SBQQ__Number__c
        ];
    }

    /** Net total of the lines an ordinary document table should count. */
    public static Decimal expectedCountedNet() {
        Decimal total = 0;
        for (SBQQ__QuoteLine__c l : computedLines()) {
            if (l.SBQQ__Optional__c || l.SBQQ__Bundled__c) { continue; }
            total += l.SBQQ__NetTotal__c == null ? 0 : l.SBQQ__NetTotal__c;
        }
        return total;
    }

    public static Decimal expectedNetForCode(String productCode) {
        for (SBQQ__QuoteLine__c l : computedLines()) {
            if (l.SBQQ__ProductCode__c == productCode) {
                return l.SBQQ__NetTotal__c == null ? 0 : l.SBQQ__NetTotal__c;
            }
        }
        return 0;
    }

    /**
     * Quote lines with everything QuoteDocumentLine reads. Kept in one place so
     * a field added to the generator's query fails here loudly rather than at
     * runtime with an unqueried-field error.
     */
    public static Map<Id, SBQQ__QuoteLine__c> storedLines(List<Id> lineIds) {
        return new Map<Id, SBQQ__QuoteLine__c>([
            SELECT Id, SBQQ__Number__c, SBQQ__Product__c, SBQQ__ProductName__c, SBQQ__ProductCode__c,
                   SBQQ__Product__r.Family, SBQQ__ChargeType__c, SBQQ__Bundle__c, SBQQ__Bundled__c,
                   SBQQ__Optional__c, SBQQ__OptionLevel__c, SBQQ__RequiredBy__c,
                   SBQQ__RequiredBy__r.SBQQ__ProductName__c, SBQQ__Group__c, SBQQ__Group__r.Name,
                   SBQQ__Quantity__c, SBQQ__ListTotal__c, SBQQ__RegularTotal__c,
                   SBQQ__TotalDiscountAmount__c, SBQQ__NetTotal__c, SBQQ__CustomerTotal__c,
                   SBQQ__NetPrice__c, SBQQ__Existing__c, SBQQ__PriorQuantity__c,
                   SBQQ__UpgradedSubscription__c, SBQQ__RenewedSubscription__c
            FROM SBQQ__QuoteLine__c WHERE Id IN :lineIds
        ]);
    }

    public static QuoteDocumentLine documentLine(Id lineId, SBQQ__Quote__c quote) {
        return new QuoteDocumentLine(storedLines(new List<Id>{ lineId }).get(lineId), quote);
    }

    public static Id quoteId() {
        return [SELECT Id FROM SBQQ__Quote__c LIMIT 1].Id;
    }

    public static Quote_Document_Table__c table(String tableCode) {
        return [
            SELECT Id, Table_Code__c, Status__c, Row_Count__c, Measure_Set__c, Line_Filter__c,
                   Amount_List__c, Amount_Discount__c, Amount_Net__c, Quantity__c,
                   Amount_Net_New__c, Amount_Net_Change__c
            FROM Quote_Document_Table__c
            WHERE Table_Code__c = :tableCode
        ];
    }

    public static List<Quote_Document_Row__c> rows(String tableCode) {
        return [
            SELECT Row_Type__c, Group_Level__c, Display_Order__c, Display_Label__c, Group_Value__c,
                   Quote_Line__c, Is_Displayed__c, Include_In_Subtotal__c, Include_In_Grand_Total__c,
                   Product_Name__c, Product_Family__c, Transaction_Type__c,
                   Amount_List__c, Amount_Net__c, Amount_Net_New__c, Amount_Net_Change__c, Quantity__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Table_Code__c = :tableCode
            ORDER BY Display_Order__c
        ];
    }

    public static Quote_Document_Row__c grandTotal(String tableCode) {
        for (Quote_Document_Row__c row : rows(tableCode)) {
            if (row.Row_Type__c == 'Grand Total') {
                return row;
            }
        }
        return null;
    }
}
