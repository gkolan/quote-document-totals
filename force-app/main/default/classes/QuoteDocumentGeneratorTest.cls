/**
 * Covers the cases that decide whether a signed document carries the right
 * number: a package with bundled components, a separately-priced option, an
 * optional product, a recurring charge, and the change classifications that no
 * quote in this org can currently produce.
 *
 * Line totals on SBQQ__QuoteLine__c are formula fields, so the test sets the
 * writable price and quantity inputs and lets CPQ compute the totals. Expected
 * values are then derived from what CPQ actually calculated rather than
 * hardcoded - the point of these assertions is that the generator adds up the
 * same lines CPQ did, not that a particular formula produces a particular
 * number.
 *
 * The CPQ Calculate API is deliberately not invoked: the generator reads stored
 * totals, so priced lines are all it needs, and Calculate would make the test
 * slow and non-deterministic.
 */
@IsTest
private class QuoteDocumentGeneratorTest {

    private static final String CODE_PACKAGE   = 'TEST_PACKAGE';
    private static final String CODE_COMPONENT = 'TEST_COMPONENT';
    private static final String CODE_OPTION    = 'TEST_OPTION';
    private static final String CODE_PLAN      = 'TEST_PLAN';
    private static final String CODE_OPTIONAL  = 'TEST_OPTIONAL';

    @TestSetup
    static void setup() {
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

    private static SBQQ__QuoteLine__c line(
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

    private static List<SBQQ__QuoteLine__c> computedLines() {
        return [
            SELECT Id, SBQQ__ProductCode__c, SBQQ__ChargeType__c, SBQQ__Optional__c,
                   SBQQ__Bundled__c, SBQQ__NetTotal__c
            FROM SBQQ__QuoteLine__c
            ORDER BY SBQQ__Number__c
        ];
    }

    /** Net total of the lines an ordinary document table should count. */
    private static Decimal expectedCountedNet() {
        Decimal total = 0;
        for (SBQQ__QuoteLine__c l : computedLines()) {
            if (l.SBQQ__Optional__c || l.SBQQ__Bundled__c) { continue; }
            total += l.SBQQ__NetTotal__c == null ? 0 : l.SBQQ__NetTotal__c;
        }
        return total;
    }

    private static Decimal expectedNetForCode(String productCode) {
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
    private static Map<Id, SBQQ__QuoteLine__c> storedLines(List<Id> lineIds) {
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

    private static QuoteDocumentLine documentLine(Id lineId, SBQQ__Quote__c quote) {
        return new QuoteDocumentLine(storedLines(new List<Id>{ lineId }).get(lineId), quote);
    }

    private static Id quoteId() {
        return [SELECT Id FROM SBQQ__Quote__c LIMIT 1].Id;
    }

    private static Quote_Document_Table__c table(String tableCode) {
        return [
            SELECT Id, Table_Code__c, Status__c, Row_Count__c, Measure_Set__c, Line_Filter__c,
                   Amount_List__c, Amount_Discount__c, Amount_Net__c, Quantity__c,
                   Amount_Net_New__c, Amount_Net_Change__c
            FROM Quote_Document_Table__c
            WHERE Table_Code__c = :tableCode
        ];
    }

    private static List<Quote_Document_Row__c> rows(String tableCode) {
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

    private static Quote_Document_Row__c grandTotal(String tableCode) {
        for (Quote_Document_Row__c row : rows(tableCode)) {
            if (row.Row_Type__c == 'Grand Total') {
                return row;
            }
        }
        return null;
    }

    // -----------------------------------------------------------------------

    @IsTest
    static void generatesEveryDefinedTableAsComplete() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        List<Quote_Document_Table__c> tables = [
            SELECT Table_Code__c, Status__c, Row_Count__c FROM Quote_Document_Table__c
        ];

        Assert.areEqual(QuoteDocumentTableDefinition.getAll().size(), tables.size(),
            'Every definition should produce exactly one table');

        for (Quote_Document_Table__c t : tables) {
            Assert.areEqual('Complete', t.Status__c, t.Table_Code__c + ' should be Complete');
            Assert.isTrue(t.Row_Count__c > 0, t.Table_Code__c + ' should have rows');
        }
    }

    @IsTest
    static void bundledComponentIsShownButNotCounted() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Quote_Document_Row__c component;
        for (Quote_Document_Row__c row : rows('BUNDLE_DETAIL')) {
            if (row.Product_Name__c == 'Test Component') {
                component = row;
            }
        }

        Assert.isNotNull(component, 'The bundled component should appear as a detail row');
        Assert.isTrue(component.Is_Displayed__c, 'A bundled component is still printed');
        Assert.isFalse(component.Include_In_Subtotal__c,
            'A bundled component must not count - its price sits in the package');
        Assert.isFalse(component.Include_In_Grand_Total__c,
            'A bundled component must not count toward the grand total either');
        Assert.areEqual(2, component.Group_Level__c,
            'A component indents one level below its package');
    }

    @IsTest
    static void optionalProductIsExcludedFromOrdinaryTotalsAndCountedInItsOwn() {
        Decimal counted = expectedCountedNet();
        Decimal optional = expectedNetForCode(CODE_OPTIONAL);

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Assert.areEqual(counted, grandTotal('PRODUCT_FAMILY_SUMMARY').Amount_Net__c,
            'The ordinary summary must exclude the optional product');

        // A zero total on a table whose entire subject is optional products
        // would be absurd, so the filter has to override the exclusion.
        Assert.areEqual(optional, grandTotal('OPTIONAL_PRODUCTS').Amount_Net__c,
            'The Optional Products table must count its own lines');
        Assert.isTrue(optional > 0, 'The optional line should carry a real price');
    }

    @IsTest
    static void grandTotalReconcilesToTheQuoteNetAmount() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        SBQQ__Quote__c quote = [SELECT SBQQ__NetAmount__c FROM SBQQ__Quote__c LIMIT 1];

        // CPQ's own roll-up excludes optional lines, and so must the document.
        Assert.areEqual(quote.SBQQ__NetAmount__c, grandTotal('PRODUCT_FAMILY_SUMMARY').Amount_Net__c,
            'Product Family Summary must agree with the Quote');
        Assert.areEqual(quote.SBQQ__NetAmount__c, grandTotal('BUNDLE_DETAIL').Amount_Net__c,
            'Bundle Detail must agree with the Quote');
        Assert.areEqual(quote.SBQQ__NetAmount__c, grandTotal('CHARGE_TYPE_SUMMARY').Amount_Net__c,
            'Charge Type Summary must agree with the Quote');
    }

    @IsTest
    static void aggregateRowsNeverCountTowardTotals() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Set<String> aggregates = new Set<String>{
            'Group Header', 'Subtotal', 'Section Total', 'Grand Total'
        };

        for (Quote_Document_Row__c row : [
            SELECT Row_Type__c, Group_Level__c, Quote_Line__c,
                   Include_In_Subtotal__c, Include_In_Grand_Total__c
            FROM Quote_Document_Row__c
        ]) {
            if (!aggregates.contains(row.Row_Type__c)) { continue; }

            Assert.isFalse(row.Include_In_Subtotal__c, row.Row_Type__c + ' must not feed a subtotal');
            Assert.isFalse(row.Include_In_Grand_Total__c, row.Row_Type__c + ' must not feed the grand total');
            Assert.isNull(row.Quote_Line__c, row.Row_Type__c + ' spans lines, so it references none');

            if (row.Row_Type__c == 'Grand Total') {
                Assert.areEqual(0, row.Group_Level__c, 'A grand total belongs to the table, at level 0');
            }
        }
    }

    @IsTest
    static void rowsAreOrderedAndEveryLineAppearsOnce() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Decimal previousOrder = -1;
        Set<Id> seenLines = new Set<Id>();

        for (Quote_Document_Row__c row : rows('BUNDLE_DETAIL')) {
            Assert.isTrue(row.Display_Order__c > previousOrder, 'Display order must strictly increase');
            previousOrder = row.Display_Order__c;

            if (row.Quote_Line__c != null) {
                Assert.isFalse(seenLines.contains(row.Quote_Line__c),
                    'A quote line must appear at most once per table');
                seenLines.add(row.Quote_Line__c);
            }
        }

        // Four of the five lines - the optional one is filtered out entirely.
        Assert.areEqual(4, seenLines.size(), 'Every non-optional line should appear exactly once');
    }

    @IsTest
    static void sectionTotalsSplitRecurringFromOneTime() {
        Decimal recurring = expectedNetForCode(CODE_PLAN);
        Decimal oneTime = expectedCountedNet() - recurring;

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Map<String, Decimal> netBySection = new Map<String, Decimal>();
        for (Quote_Document_Row__c row : rows('PRODUCT_FAMILY_SUMMARY')) {
            if (row.Row_Type__c == 'Section Total') {
                netBySection.put(row.Group_Value__c, row.Amount_Net__c);
            }
        }

        Assert.areEqual(recurring, netBySection.get('Recurring'), 'Only the plan is recurring');
        Assert.areEqual(oneTime, netBySection.get('One-Time'), 'Everything else is a one-off charge');
    }

    @IsTest
    static void nestedGroupingProducesTwoLevelsOfSubtotal() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Set<Decimal> subtotalLevels = new Set<Decimal>();
        for (Quote_Document_Row__c row : rows('GROUP_FAMILY_DETAIL')) {
            if (row.Row_Type__c == 'Subtotal') {
                subtotalLevels.add(row.Group_Level__c);
            }
        }

        Assert.isTrue(subtotalLevels.contains(1), 'Outer grouping should produce a level-1 subtotal');
        Assert.isTrue(subtotalLevels.contains(2), 'Inner grouping should produce a level-2 subtotal');
    }

    /**
     * Drives an injected definition rather than the real TRANSACTION_SUMMARY
     * record, which is inactive until classify() is validated against a genuine
     * amendment (docs/quote-document-totals.md §3). The classification
     * arithmetic still needs covering while the table itself stays off, and a
     * test that depended on the active flag would go quiet exactly when the
     * flag was flipped for safety.
     */
    @IsTest
    static void changeMeasuresClassifyNewBusinessAsNetNew() {
        Decimal counted = expectedCountedNet();

        QuoteDocumentTableDefinition probe = QuoteDocumentTableDefinition.build(
            'TRANSACTION_SUMMARY_PROBE',
            new List<String>{ QuoteDocumentTableDefinition.DIM_TRANSACTION_TYPE },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        probe.measureSet = QuoteDocumentTableDefinition.MEASURES_CHANGE;
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ probe }
        );

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Quote_Document_Row__c total = grandTotal('TRANSACTION_SUMMARY_PROBE');

        Assert.areEqual(counted, total.Amount_Net_New__c, 'A plain quote is all net new business');
        Assert.areEqual(counted, total.Amount_Net_Change__c,
            'Net change equals net new when nothing is removed');
        Assert.areEqual('CHANGE', table('TRANSACTION_SUMMARY_PROBE').Measure_Set__c,
            'The probe declares the change measure set');
    }

    // NOTE: the Termination branch in QuoteDocumentLine.classify() (existing
    // line, negative Net Total) is not covered by any test, and an attempt to
    // cover it here was reverted rather than left broken. SBQQ__NetTotal__c is
    // a managed-package formula field and cannot be assigned even on an
    // unsaved, never-inserted SObject ("Field is not writeable" - confirmed by
    // deploying the attempt), and a real insert cannot produce a negative Net
    // Total from a negative Net Price on a plain quote either (documented in
    // docs/quote-document-totals.md §3). This is not a gap this test suite can
    // close without a real amendment quote in the org - which is exactly the
    // precondition phase-1-classification-validation.md is already blocked on.
    // Confirming that even test data can't reach this branch is itself
    // evidence for that phase's concern, recorded there rather than worked
    // around here.

    @IsTest
    static void cancellationIsValuedFromPriorQuantityAndStoredNegative() {
        SBQQ__Quote__c quote = [SELECT Id, AccountIndustry__c FROM SBQQ__Quote__c LIMIT 1];
        Id productId = [SELECT Id FROM Product2 WHERE ProductCode = :CODE_PLAN].Id;

        // A cancelled amendment line ends at quantity zero, so its own total is
        // zero. The value leaving the deal is the prior quantity at net price.
        SBQQ__QuoteLine__c cancelled = line(quote.Id, productId, 90, 0, 100, 100);
        cancelled.SBQQ__Existing__c = true;
        cancelled.SBQQ__PriorQuantity__c = 5;
        insert cancelled;

        QuoteDocumentLine cancelledLine = documentLine(cancelled.Id, quote);

        Assert.areEqual('Cancellation', cancelledLine.transactionType);
        Assert.areEqual(-500, cancelledLine.amountCancellation,
            'Five units at 100 leaving the deal, stored negative');
        Assert.areEqual(-500, cancelledLine.amountNetChange,
            'Net change is the sum of the classified measures');
    }

    @IsTest
    static void replacementPairIsClassifiedBySign() {
        SBQQ__Quote__c quote = [SELECT Id, AccountIndustry__c FROM SBQQ__Quote__c LIMIT 1];
        Id productId = [SELECT Id FROM Product2 WHERE ProductCode = :CODE_PLAN].Id;

        // The classification only reads whether the field is populated, but the
        // lookup is typed, so a real Subscription is needed.
        SBQQ__Subscription__c subscription = new SBQQ__Subscription__c(
            SBQQ__Account__c = [SELECT Id FROM Account LIMIT 1].Id,
            SBQQ__Product__c = productId,
            SBQQ__Quantity__c = 1,
            SBQQ__SubscriptionStartDate__c = Date.today(),
            SBQQ__SubscriptionEndDate__c = Date.today().addYears(1)
        );
        insert subscription;
        Id subscriptionId = subscription.Id;

        // The replaced side is amended down to nothing, so its value comes from
        // the prior quantity rather than from its own (now zero) total.
        SBQQ__QuoteLine__c removed = line(quote.Id, productId, 91, 0, 200, 200);
        removed.SBQQ__UpgradedSubscription__c = subscriptionId;
        removed.SBQQ__PriorQuantity__c = 1;

        SBQQ__QuoteLine__c added = line(quote.Id, productId, 92, 1, 250, 250);
        added.SBQQ__UpgradedSubscription__c = subscriptionId;

        insert new List<SBQQ__QuoteLine__c>{ removed, added };

        Map<Id, SBQQ__QuoteLine__c> stored = storedLines(new List<Id>{ removed.Id, added.Id });
        QuoteDocumentLine removedLine = new QuoteDocumentLine(stored.get(removed.Id), quote);
        QuoteDocumentLine addedLine = new QuoteDocumentLine(stored.get(added.Id), quote);

        Assert.areEqual('Replacement Removed', removedLine.transactionType);
        Assert.areEqual(-200, removedLine.amountReplacementRemoved,
            'One prior unit at 200 leaving the deal, stored negative');
        Assert.areEqual('Replacement Added', addedLine.transactionType);
        Assert.isTrue(addedLine.amountReplacementAdded > 0, 'An addition is stored positive');
        Assert.areEqual(0, removedLine.amountCancellation,
            'A replacement is not also a cancellation');
    }

    // -----------------------------------------------------------------------
    // The hand-built amendment scenario (phase-1-classification-validation.md)
    // -----------------------------------------------------------------------

    /**
     * Builds one amendment quote carrying every classification the org's own
     * data cannot produce, on a quote of its own so the change measures
     * reconcile against these lines alone.
     *
     * This is the fixture phase-1-classification-validation.md §6.4 calls for.
     * It is NOT the validation that phase is waiting on: these are the branches
     * `classify()` is *written* to produce, so agreement here proves the
     * arithmetic is self-consistent, not that the rules match what CPQ emits on
     * a genuine amendment. Only a real amendment quote can settle that. The
     * value of having it now is that whichever taxonomy §3 settles on, the
     * scenario data is already in place and the remap becomes a one-pass change
     * with the reconciliation already asserted.
     *
     * Termination is deliberately absent - see the note above on why no fixture
     * can reach it.
     */
    private static Id amendmentQuoteId() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Map<String, Id> productByCode = new Map<String, Id>();
        for (Product2 p : [SELECT Id, ProductCode FROM Product2 WHERE IsActive = true]) {
            productByCode.put(p.ProductCode, p.Id);
        }

        SBQQ__Quote__c amendment = new SBQQ__Quote__c(
            SBQQ__Account__c = account.Id,
            SBQQ__Primary__c = false,
            SBQQ__Type__c = 'Amendment'
        );
        insert amendment;

        SBQQ__Subscription__c replaced = new SBQQ__Subscription__c(
            SBQQ__Account__c = account.Id,
            SBQQ__Product__c = productByCode.get(CODE_PLAN),
            SBQQ__Quantity__c = 1,
            SBQQ__SubscriptionStartDate__c = Date.today(),
            SBQQ__SubscriptionEndDate__c = Date.today().addYears(1)
        );
        SBQQ__Subscription__c renewed = new SBQQ__Subscription__c(
            SBQQ__Account__c = account.Id,
            SBQQ__Product__c = productByCode.get(CODE_OPTION),
            SBQQ__Quantity__c = 1,
            SBQQ__SubscriptionStartDate__c = Date.today(),
            SBQQ__SubscriptionEndDate__c = Date.today().addYears(1)
        );
        insert new List<SBQQ__Subscription__c>{ replaced, renewed };

        List<SBQQ__QuoteLine__c> lines = new List<SBQQ__QuoteLine__c>();

        // Net New: ordinary added business on an amendment quote.
        lines.add(line(amendment.Id, productByCode.get(CODE_PACKAGE), 1, 2, 100, 100));

        // Cancellation: amended to zero, so its own total is zero and the value
        // leaving the deal comes from the prior quantity at the current price.
        SBQQ__QuoteLine__c cancelled = line(amendment.Id, productByCode.get(CODE_OPTIONAL), 2, 0, 100, 100);
        cancelled.SBQQ__Existing__c = true;
        cancelled.SBQQ__PriorQuantity__c = 5;
        lines.add(cancelled);

        // Replacement pair: the old value leaves, the new arrives.
        SBQQ__QuoteLine__c removed = line(amendment.Id, productByCode.get(CODE_PLAN), 3, 0, 200, 200);
        removed.SBQQ__UpgradedSubscription__c = replaced.Id;
        removed.SBQQ__PriorQuantity__c = 1;
        lines.add(removed);

        SBQQ__QuoteLine__c added = line(amendment.Id, productByCode.get(CODE_PLAN), 4, 1, 250, 250);
        added.SBQQ__UpgradedSubscription__c = replaced.Id;
        lines.add(added);

        // Renewal at unchanged value. There is no Renewal branch today, so this
        // lands on Replacement Added - recorded here as evidence for the
        // taxonomy decision in phase-1 §3 rather than asserted as desirable.
        SBQQ__QuoteLine__c renewal = line(amendment.Id, productByCode.get(CODE_OPTION), 5, 1, 300, 300);
        renewal.SBQQ__RenewedSubscription__c = renewed.Id;
        lines.add(renewal);

        insert lines;
        return amendment.Id;
    }

    @IsTest
    static void handBuiltAmendmentProducesEveryReachableClassification() {
        Id amendmentId = amendmentQuoteId();

        QuoteDocumentTableDefinition probe = QuoteDocumentTableDefinition.build(
            'AMENDMENT_SCENARIO',
            new List<String>{ QuoteDocumentTableDefinition.DIM_TRANSACTION_TYPE },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        probe.measureSet = QuoteDocumentTableDefinition.MEASURES_CHANGE;
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ probe }
        );

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ amendmentId });
        Test.stopTest();

        Quote_Document_Table__c table = [
            SELECT Id, Status__c, Amount_Net_Change__c
            FROM Quote_Document_Table__c
            WHERE Quote__c = :amendmentId AND Table_Code__c = 'AMENDMENT_SCENARIO'
        ];
        Assert.areEqual('Complete', table.Status__c,
            'The amendment scenario must reconcile - a Failed status here means the change measures do not add up');

        Map<String, Decimal> netChangeByType = new Map<String, Decimal>();
        for (Quote_Document_Row__c row : [
            SELECT Group_Value__c, Amount_Net_Change__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__c = :table.Id
              AND Row_Type__c = 'Subtotal' AND Group_Level__c = 1
        ]) {
            netChangeByType.put(row.Group_Value__c, row.Amount_Net_Change__c);
        }

        Assert.isTrue(netChangeByType.containsKey('Net New'), 'Added business must classify as Net New');
        Assert.isTrue(netChangeByType.containsKey('Cancellation'), 'A line amended to zero must classify as Cancellation');
        Assert.isTrue(netChangeByType.containsKey('Replacement Removed'), 'The leaving side of a pair must classify as Replacement Removed');
        Assert.isTrue(netChangeByType.containsKey('Replacement Added'), 'The arriving side of a pair must classify as Replacement Added');

        Assert.areEqual(-500, netChangeByType.get('Cancellation'),
            'Five prior units at 100 leave the deal, stored negative - not the cancelled line\'s own zero total');
        Assert.areEqual(-200, netChangeByType.get('Replacement Removed'),
            'One prior unit at 200 leaves the deal, stored negative');

        Decimal summed = 0;
        for (Decimal value : netChangeByType.values()) {
            summed += value == null ? 0 : value;
        }
        Assert.areEqual(summed, table.Amount_Net_Change__c,
            'The table net change must equal the sum of its transaction-type subtotals');
    }

    /**
     * A renewal has no branch of its own today - it is only distinguishable by
     * SBQQ__RenewedSubscription__c being populated, and classify() folds that
     * into the replacement pair. Asserted as current behaviour, not as correct:
     * this is the concrete gap phase-1 §3's six-category taxonomy would close,
     * and the assertion should be updated - not deleted - if that decision
     * lands.
     */
    @IsTest
    static void aRenewalCurrentlyHasNoBranchOfItsOwn() {
        Id amendmentId = amendmentQuoteId();

        SBQQ__QuoteLine__c renewalLine = [
            SELECT Id FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Quote__c = :amendmentId AND SBQQ__RenewedSubscription__c != null
        ];
        SBQQ__Quote__c amendment = [
            SELECT Id, AccountIndustry__c FROM SBQQ__Quote__c WHERE Id = :amendmentId
        ];

        QuoteDocumentLine classified = documentLine(renewalLine.Id, amendment);

        Assert.areEqual('Replacement Added', classified.transactionType,
            'A renewal is currently indistinguishable from the arriving side of a replacement');
        Assert.areEqual(0, classified.amountNetNew,
            'A renewal must not be counted as new business');
    }

    @IsTest
    static void unsupportedDimensionAndFilterFailLoudly() {
        SBQQ__Quote__c quote = [SELECT Id, AccountIndustry__c FROM SBQQ__Quote__c LIMIT 1];
        Id anyLineId = [SELECT Id FROM SBQQ__QuoteLine__c LIMIT 1].Id;
        QuoteDocumentLine line = documentLine(anyLineId, quote);

        try {
            line.getGroupingValue('REGION');
            Assert.fail('An unknown dimension should not silently return a value');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('REGION'), 'The message should name the dimension');
        }

        try {
            line.matchesFilter('CHEAP_ONLY');
            Assert.fail('An unknown filter should not silently include everything');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('CHEAP_ONLY'), 'The message should name the filter');
        }
    }

    @IsTest
    static void industryDimensionAndRemainingFiltersAreSupported() {
        SBQQ__Quote__c quote = [SELECT Id, AccountIndustry__c FROM SBQQ__Quote__c LIMIT 1];
        List<SBQQ__QuoteLine__c> allLines = [
            SELECT Id, SBQQ__ChargeType__c, SBQQ__Bundle__c, SBQQ__Bundled__c
            FROM SBQQ__QuoteLine__c ORDER BY SBQQ__Number__c
        ];

        QuoteDocumentLine recurringLine;
        QuoteDocumentLine oneTimeLine;
        QuoteDocumentLine packageLine;
        QuoteDocumentLine bundledLine;
        for (SBQQ__QuoteLine__c raw : allLines) {
            QuoteDocumentLine dl = documentLine(raw.Id, quote);
            if (raw.SBQQ__ChargeType__c == 'Recurring') { recurringLine = dl; }
            if (raw.SBQQ__Bundle__c == true) { packageLine = dl; }
            if (raw.SBQQ__Bundled__c == true) { bundledLine = dl; }
            if (oneTimeLine == null && raw.SBQQ__ChargeType__c != 'Recurring') { oneTimeLine = dl; }
        }

        Assert.areEqual('Technology', recurringLine.getGroupingValue('INDUSTRY'),
            'INDUSTRY reads Account.Industry through the Quote - Technology, set in @TestSetup');

        Assert.isTrue(recurringLine.matchesFilter('RECURRING_ONLY'));
        Assert.isFalse(oneTimeLine.matchesFilter('RECURRING_ONLY'));
        Assert.isTrue(oneTimeLine.matchesFilter('ONE_TIME_ONLY'));
        Assert.isFalse(recurringLine.matchesFilter('ONE_TIME_ONLY'));

        Assert.isTrue(packageLine.matchesFilter('BUNDLE_PARENTS_ONLY'),
            'A package parent counts as a bundle parent');
        Assert.isFalse(bundledLine.matchesFilter('BUNDLE_PARENTS_ONLY'),
            'A bundled component is not a bundle parent');
    }

    /**
     * QuoteDocumentLine.resolvePath is exercised end-to-end by every guide's
     * field-path grouping, but the null-intermediate-relationship fallback
     * specifically needs a line with an unpopulated lookup, which nothing in
     * @TestSetup produces (every seeded line either has no bundle parent at
     * all or a real one). A freshly-constructed SObject with nothing queried
     * is the simplest way to get a genuinely null relationship without an
     * SObjectException, since the "row was retrieved via SOQL without
     * querying this field" exception only applies to records that came from
     * an actual query - not to an in-memory literal.
     */
    @IsTest
    static void resolvePathFallsBackSafelyThroughNullRelationships() {
        QuoteDocumentLine dl = new QuoteDocumentLine(new SBQQ__QuoteLine__c(), new SBQQ__Quote__c());

        Assert.areEqual('Not Specified',
            dl.resolvePath('SBQQ__RequiredBy__r.SBQQ__RequiredBy__r.SBQQ__ProductName__c'),
            'A relationship that goes null partway through a 3-segment path must not throw');
        Assert.areEqual('Not Specified',
            dl.resolvePath('SBQQ__RequiredBy__r.SBQQ__ProductName__c'),
            'A 2-segment path through a single null relationship must also fall back safely');
    }

    @IsTest
    static void generateFailsLoudlyWhenAQuoteIdDoesNotResolve() {
        SBQQ__Quote__c real = [SELECT Id, SBQQ__Account__c, SBQQ__Opportunity2__c FROM SBQQ__Quote__c LIMIT 1];

        SBQQ__Quote__c throwaway = new SBQQ__Quote__c(
            SBQQ__Account__c = real.SBQQ__Account__c,
            SBQQ__Opportunity2__c = real.SBQQ__Opportunity2__c,
            SBQQ__Primary__c = false,
            SBQQ__Type__c = 'Quote'
        );
        insert throwaway;
        Id missingId = throwaway.Id;
        delete throwaway;

        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ real.Id, missingId });
            Assert.fail('A quote id that does not resolve must not be silently skipped');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains(String.valueOf(missingId)),
                'The message should name the missing id: ' + e.getMessage());
        }
    }

    /**
     * Every configured field path in this repo's shipped tables is a custom
     * relationship (SBQQ__Product__r, SBQQ__Group__r, ...), which always ends
     * in __r and resolves via the __r-to__c replace. A standard relationship
     * such as CreatedBy has no __c counterpart - its lookup field is
     * CreatedById - so resolving it needs the "try segment + Id" fallback in
     * validateFieldPath, which nothing else in this suite exercises.
     */
    @IsTest
    static void aFieldPathThroughAStandardRelationshipResolvesViaTheIdFallback() {
        QuoteDocumentTableDefinition byCreator = QuoteDocumentTableDefinition.build(
            'STANDARD_RELATIONSHIP_PROBE',
            new List<String>{ 'CreatedBy.Name' },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ byCreator });

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Assert.areEqual('Complete',
            [SELECT Status__c FROM Quote_Document_Table__c WHERE Table_Code__c = 'STANDARD_RELATIONSHIP_PROBE'].Status__c,
            'A path through a standard relationship (CreatedBy, not CreatedBy__r) must resolve via the Id fallback');
    }

    /**
     * verify() is marked @TestVisible specifically so its reconciliation
     * failures can be proven directly, without needing to corrupt a real
     * generation - QuoteDocumentRowBuilder is internally consistent by
     * construction, so no legitimate configuration ever produces a genuine
     * mismatch for verify() to catch. That makes this test the only way to
     * prove the safety net itself actually fires when the numbers disagree.
     */
    @IsTest
    static void verifyFailsLoudlyWhenMeasuresDoNotReconcile() {
        Quote_Document_Row__c detail = new Quote_Document_Row__c(
            Row_Type__c = 'Detail',
            Group_Level__c = 1,
            Row_Key__c = 'DETAIL:1',
            Include_In_Grand_Total__c = true,
            Amount_Net__c = 100
        );
        Quote_Document_Row__c grandTotal = new Quote_Document_Row__c(
            Row_Type__c = 'Grand Total',
            Group_Level__c = 0,
            Row_Key__c = 'GRAND_TOTAL',
            Amount_Net__c = 999
        );

        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            'VERIFY_MISMATCH_PROBE',
            new List<String>{ 'PRODUCT_FAMILY' },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        Quote_Document_Table__c table = new Quote_Document_Table__c(Table_Code__c = 'VERIFY_MISMATCH_PROBE');

        try {
            QuoteDocumentVerification.verify(
                new SBQQ__Quote__c(), table, definition,
                new List<Quote_Document_Row__c>{ detail, grandTotal }
            );
            Assert.fail('A grand total that does not equal its detail rows must fail verification');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('Amount_Net__c'),
                'The message should name the field that disagreed: ' + e.getMessage());
        }
    }

    @IsTest
    static void verifyThrowsWhenNoGrandTotalRowExists() {
        QuoteDocumentTableDefinition definition = QuoteDocumentTableDefinition.build(
            'NO_GRAND_TOTAL_PROBE',
            new List<String>{ 'PRODUCT_FAMILY' },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        Quote_Document_Table__c table = new Quote_Document_Table__c(Table_Code__c = 'NO_GRAND_TOTAL_PROBE');
        List<Quote_Document_Row__c> rows = new List<Quote_Document_Row__c>{
            new Quote_Document_Row__c(Row_Type__c = 'Detail', Group_Level__c = 1, Row_Key__c = 'DETAIL:1')
        };

        try {
            QuoteDocumentVerification.verify(new SBQQ__Quote__c(), table, definition, rows);
            Assert.fail('A table built without a Grand Total row must fail verification');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('Grand Total'), 'Message: ' + e.getMessage());
        }
    }

    @IsTest
    static void aFieldPathThroughANonRelationshipFieldIsRejected() {
        QuoteDocumentTableDefinition broken = QuoteDocumentTableDefinition.build(
            'NOT_A_RELATIONSHIP_PROBE',
            new List<String>{ 'SBQQ__Quantity__c.Foo' },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ broken });

        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
            Assert.fail('A field path through a non-relationship field must not reach the query');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('is not a relationship'),
                'The message should explain why: ' + e.getMessage());
        }
    }

    /**
     * Proves the fix from
     * specs/quote-docusign-totals/phases/phase-4-test-matrix-reconciliation.md:
     * Row_Key__c has no declarative uniqueness constraint (it can't - the same
     * key text like GRAND_TOTAL is legitimately reused across different
     * Quotes' tables), so nothing but this new assertion in verify() stops two
     * distinct grouping values that sanitize to the same key from silently
     * colliding. "R&D" and "R D" both reduce to "R_D" once buildGroupKey
     * uppercases and strips to [A-Z0-9_].
     */
    @IsTest
    static void duplicateGroupKeysAfterSanitizationFailGenerationLoudly() {
        Id qId = quoteId();
        List<Product2> collidingProducts = new List<Product2>{
            new Product2(Name = 'Collision A', ProductCode = 'COLLIDE_A', Family = 'R&D', IsActive = true),
            new Product2(Name = 'Collision B', ProductCode = 'COLLIDE_B', Family = 'R D', IsActive = true)
        };
        insert collidingProducts;

        insert new List<SBQQ__QuoteLine__c>{
            line(qId, collidingProducts[0].Id, 101, 1, 10, 10),
            line(qId, collidingProducts[1].Id, 102, 1, 10, 10)
        };

        QuoteDocumentTableDefinition collisionProbe = QuoteDocumentTableDefinition.build(
            'COLLISION_PROBE',
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ collisionProbe });

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ qId });
            Assert.fail('Two group values that sanitize to the same key must not both be inserted');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('duplicate Row_Key__c'),
                'The message should name the problem: ' + e.getMessage());
        }
        Test.stopTest();
    }

    /**
     * QuoteDocumentRowBuilder is fed lines in query order everywhere else in
     * this suite (generateOne always queries ORDER BY SBQQ__Number__c), which
     * never exercises the "a later line has a lower sequence than the group's
     * first-seen line" branch in groupLines, or the actual swap inside
     * sortedBySequence's insertion sort. Calling the builder directly - which
     * every guide's own config still goes through in production, this is not
     * a bypass of anything - with lines deliberately out of order proves both
     * without assuming the caller always supplies ascending input.
     */
    @IsTest
    static void groupingTracksTheEarliestLineSequenceEvenWhenFedOutOfOrder() {
        SBQQ__Quote__c quote = [SELECT Id, AccountIndustry__c FROM SBQQ__Quote__c LIMIT 1];
        List<SBQQ__QuoteLine__c> hardwareLines = [
            SELECT Id FROM SBQQ__QuoteLine__c
            WHERE SBQQ__Product__r.ProductCode IN :new List<String>{ CODE_PACKAGE, CODE_COMPONENT }
            ORDER BY SBQQ__Number__c
        ];
        QuoteDocumentLine packageLine = documentLine(hardwareLines[0].Id, quote);
        QuoteDocumentLine componentLine = documentLine(hardwareLines[1].Id, quote);

        QuoteDocumentTableDefinition probe = QuoteDocumentTableDefinition.build(
            'ORDER_PROBE',
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );

        List<Quote_Document_Row__c> rows = new QuoteDocumentRowBuilder(probe)
            .build(new List<QuoteDocumentLine>{ componentLine, packageLine });

        List<Quote_Document_Row__c> details = new List<Quote_Document_Row__c>();
        for (Quote_Document_Row__c row : rows) {
            if (row.Row_Type__c == 'Detail') { details.add(row); }
        }
        Assert.areEqual(2, details.size());
        Assert.areEqual(packageLine.quoteLineId, details[0].Quote_Line__c,
            'Detail rows must sort by sequence, not by input order');
        Assert.areEqual(componentLine.quoteLineId, details[1].Quote_Line__c);
    }

    /**
     * Proves the concern raised in
     * specs/quote-docusign-totals/phases/phase-3-atomicity-test.md: a failed
     * regeneration must leave the previous complete tables exactly as they
     * were, not partially replaced. generateOne takes one savepoint per Quote
     * before its delete-and-reinsert, and every DML for that Quote - including
     * the delete - runs inside the same try/catch that rolls back to that
     * savepoint on any exception. This forces a failure after the delete has
     * already executed (a definition that produces more groups than
     * Max_Groups__c allows, thrown from inside QuoteDocumentRowBuilder.build,
     * partway through generateOne's per-definition loop and therefore after
     * the delete but before any reinsert) and confirms the rollback actually
     * restores the prior records - same Ids, same values - rather than merely
     * leaving the Quote in a state that happens to look untouched.
     */
    @IsTest
    static void aFailedRegenerationLeavesThePreviousCompleteTablesUntouched() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        List<Quote_Document_Table__c> before = [
            SELECT Id, Table_Code__c, Row_Count__c, Amount_Net__c, Generated_On__c
            FROM Quote_Document_Table__c
            WHERE Quote__c = :quoteId()
            ORDER BY Table_Code__c
        ];
        Integer rowCountBefore = [
            SELECT COUNT() FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Quote__c = :quoteId()
        ];
        Assert.isTrue(before.size() > 0, 'The first generation must have produced tables to protect');

        QuoteDocumentTableDefinition broken = QuoteDocumentTableDefinition.build(
            'ATOMICITY_PROBE',
            new List<String>{ 'SBQQ__Product__r.Name' },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        broken.maxGroups = 1;
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ broken });

        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
            Assert.fail('A definition that exceeds Max Groups must fail generation, not silently truncate it');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            // Expected - the failure itself is proven elsewhere
            // (exceedingTheGroupCeilingFailsLoudly). What this test proves is
            // what happens to the *prior* data once this throws.
            Assert.isTrue(e.getMessage().contains('more than 1 groups'),
                'Sanity check that this failed for the expected reason: ' + e.getMessage());
        }

        List<Quote_Document_Table__c> after = [
            SELECT Id, Table_Code__c, Row_Count__c, Amount_Net__c, Generated_On__c
            FROM Quote_Document_Table__c
            WHERE Quote__c = :quoteId()
            ORDER BY Table_Code__c
        ];
        Integer rowCountAfter = [
            SELECT COUNT() FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Quote__c = :quoteId()
        ];

        Assert.areEqual(before.size(), after.size(), 'A failed regeneration must not change the number of tables');
        Assert.areEqual(rowCountBefore, rowCountAfter, 'A failed regeneration must not change the number of rows');
        for (Integer i = 0; i < before.size(); i++) {
            Assert.areEqual(before[i].Id, after[i].Id,
                'The rollback must restore the exact prior records, not merely equivalent new ones');
            Assert.areEqual(before[i].Row_Count__c, after[i].Row_Count__c, 'Row Count must be unchanged');
            Assert.areEqual(before[i].Amount_Net__c, after[i].Amount_Net__c, 'Amount Net must be unchanged');
            Assert.areEqual(before[i].Generated_On__c, after[i].Generated_On__c,
                'Generated On must be unchanged - proving the rollback, not a lucky re-match');
        }
    }

    @IsTest
    static void regeneratingReplacesRatherThanDuplicates() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Integer afterFirst = [SELECT COUNT() FROM Quote_Document_Row__c];
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Integer afterSecond = [SELECT COUNT() FROM Quote_Document_Row__c];
        Test.stopTest();

        Assert.areEqual(afterFirst, afterSecond, 'Regenerating must replace, not accumulate');
        Assert.areEqual(QuoteDocumentTableDefinition.getAll().size(),
            [SELECT COUNT() FROM Quote_Document_Table__c],
            'Regenerating must not leave orphaned tables');
    }

    /**
     * Guards the FOR UPDATE lock added to queryQuotes: a single Apex transaction
     * cannot deadlock or block against its own lock, so this cannot exercise two
     * genuinely concurrent transactions racing for the same Quote - that would
     * need two real transactions, which a unit test cannot create. What this
     * does prove: FOR UPDATE combined with WITH USER_MODE and a child subquery
     * is valid SOQL that still returns the Quote and generates correctly, and
     * that calling generate() twice - which now acquires and releases the lock
     * twice - still completes cleanly (the second call reuses the first's
     * output via the fingerprint check rather than regenerating, since
     * nothing changed - see QuoteDocumentFingerprintTest for that behavior in
     * isolation). A true concurrent-access
     * test belongs in an integration/manual test against a real org (see
     * specs/quote-docusign-totals/phases/phase-2-concurrency-lock.md).
     */
    @IsTest
    static void generateSucceedsWithTheQuoteRowLocked() {
        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
        Test.stopTest();

        Quote_Document_Table__c grandTotalTable = [
            SELECT Status__c FROM Quote_Document_Table__c
            WHERE Quote__c = :quoteId() LIMIT 1
        ];
        Assert.areEqual('Complete', grandTotalTable.Status__c,
            'Generation must still complete normally with FOR UPDATE in the query');
    }

    @IsTest
    static void invocableEntryPointGenerates() {
        QuoteDocumentGenerator.Request request = new QuoteDocumentGenerator.Request();
        request.quoteId = quoteId();

        Test.startTest();
        QuoteDocumentGenerator.generateFromFlow(new List<QuoteDocumentGenerator.Request>{ request });
        Test.stopTest();

        Assert.areEqual(QuoteDocumentTableDefinition.getAll().size(),
            [SELECT COUNT() FROM Quote_Document_Table__c],
            'The Flow entry point should generate the same tables');
    }

    // -----------------------------------------------------------------------
    // Edge cases identified in review, not previously covered by this suite.
    // -----------------------------------------------------------------------

    /**
     * Table_Key__c (Quote Id + Table_Code__c) is the only thing that stops two
     * tables from colliding, and it is enforced by the platform (External Id +
     * Unique on Quote_Document_Table__c) as a last-resort backstop.
     *
     * The primary defense now lives one step earlier: QuoteDocumentTableDefinition
     * .getAll() rejects two active Quote_Document_Table_Def__mdt records that
     * share a Table_Code__c with a named, readable error, the moment real
     * Custom Metadata is loaded - see the "seenTableCodes" check there. This
     * test cannot exercise that check directly: useDefinitions() (below)
     * injects definitions by setting getAll()'s cache straight, bypassing its
     * query loop entirely - the same reason getAll()'s sibling "no grouping
     * dimensions" check also has no direct unit test. Deploying two real
     * conflicting Quote_Document_Table_Def__mdt records just to cover that one
     * guard clause would mean shipping broken config permanently to test a
     * one-line check, which is worse than leaving it covered by inspection.
     *
     * What this test verifies instead - genuinely useful in its own right -
     * is defense in depth: even if two same-coded definitions somehow reached
     * the insert step (bypassing the getAll() guard, as this test does on
     * purpose), the platform's own uniqueness constraint still stops them,
     * rolls back cleanly, and leaves the Quote readably marked Failed rather
     * than silently overwriting one table with another.
     */
    @IsTest
    static void duplicateTableCodeReachingInsertIsStillCaughtByThePlatformAsABackstop() {
        QuoteDocumentTableDefinition first = QuoteDocumentTableDefinition.build(
            'DUPLICATE_CODE_PROBE',
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        QuoteDocumentTableDefinition second = QuoteDocumentTableDefinition.build(
            'DUPLICATE_CODE_PROBE',
            new List<String>{ QuoteDocumentTableDefinition.DIM_CHARGE_TYPE },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ first, second });

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
            Assert.fail('Two active definitions sharing one Table_Code__c must not both be inserted');
        } catch (Exception e) {
            // Deliberately not asserting on e.getMessage() content - today
            // this is the platform's own DmlException text (something like
            // "duplicate value found: Table_Key__c"), not a message this
            // codebase composed, so pinning its exact wording would make the
            // test brittle to a Salesforce platform change rather than to a
            // change in this framework's own behavior.
            Assert.isInstanceOfType(e, QuoteDocumentGenerator.QuoteDocumentException.class,
                'generateOne wraps every DmlException as a QuoteDocumentException via fail(), never lets it escape raw');
        }
        Test.stopTest();

        SBQQ__Quote__c quote = [SELECT Document_Data_Status__c FROM SBQQ__Quote__c WHERE Id = :quoteId()];
        Assert.areEqual('Failed', quote.Document_Data_Status__c,
            'A rolled-back generation must still leave the Quote readably marked Failed, never silently Ready');
    }

    /**
     * Every table in the shared setup data always has at least one counted
     * line, so no existing test proves what happens when a table's own
     * Line_Filter__c legitimately excludes every single line on the quote -
     * plausible in production the moment a rep marks every line on a quote as
     * Optional and a customer views a table that only shows non-optional
     * charges. This is not an error case: a quote can genuinely have nothing
     * to show in one particular table while still being perfectly valid
     * overall, and the framework must produce a clean, zeroed Grand Total
     * rather than failing generation or omitting the table.
     */
    @IsTest
    static void tableWithEveryLineFilteredOutStillProducesACleanZeroGrandTotal() {
        Account account = [SELECT Id FROM Account LIMIT 1];
        Opportunity opportunity = [SELECT Id FROM Opportunity LIMIT 1];

        SBQQ__Quote__c allOptionalQuote = new SBQQ__Quote__c(
            SBQQ__Account__c = account.Id,
            SBQQ__Opportunity2__c = opportunity.Id,
            SBQQ__Primary__c = false,
            SBQQ__Type__c = 'Quote'
        );
        insert allOptionalQuote;

        Product2 onlyProduct = [SELECT Id FROM Product2 WHERE ProductCode = :CODE_OPTIONAL LIMIT 1];
        SBQQ__QuoteLine__c onlyLine = line(allOptionalQuote.Id, onlyProduct.Id, 1, 1, 100, 100);
        onlyLine.SBQQ__Optional__c = true;
        insert onlyLine;

        QuoteDocumentTableDefinition excludeOptionalOnly = QuoteDocumentTableDefinition.build(
            'EMPTY_AFTER_FILTER_PROBE',
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_EXCLUDE_OPTIONAL
        );
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ excludeOptionalOnly });

        Test.startTest();
        QuoteDocumentGenerator.generate(new Set<Id>{ allOptionalQuote.Id });
        Test.stopTest();

        List<Quote_Document_Row__c> rows = [
            SELECT Row_Type__c, Amount_Net__c
            FROM Quote_Document_Row__c
            WHERE Quote_Document_Table__r.Quote__c = :allOptionalQuote.Id
        ];
        Assert.areEqual(1, rows.size(),
            'With every line filtered out, no Group Header/Subtotal/Detail rows should exist - only the Grand Total');
        Assert.areEqual('Grand Total', rows[0].Row_Type__c);
        Assert.areEqual(0, rows[0].Amount_Net__c, 'A Grand Total with nothing to sum must be a clean zero, not null or an error');

        Quote_Document_Table__c generatedTable = [
            SELECT Status__c FROM Quote_Document_Table__c WHERE Quote__c = :allOptionalQuote.Id
        ];
        Assert.areEqual('Complete', generatedTable.Status__c,
            'An empty-after-filtering table is a valid outcome, not a failure');
    }

    /**
     * Row_Customizer_Code__c is free text on the metadata (see
     * docs/quote-document-totals-creation-pipeline/01-custom-metadata-the-blueprint.md
     * §2's precision note) but the registry it feeds is a closed Apex switch
     * statement - see QuoteDocumentRowCustomizerRegistry. A code that doesn't
     * match any registered customizer (a typo, or a customizer that was
     * removed from the registry but not from the metadata) must fail
     * generation loudly and name the bad code, not silently build the table
     * with no customization applied - the latter would mean a table quietly
     * stops carrying whatever the customizer was responsible for (a rounding
     * row, an estimated tax line) with no signal to anyone that it happened.
     */
    @IsTest
    static void unknownRowCustomizerCodeFailsGenerationRatherThanSkippingCustomizationSilently() {
        QuoteDocumentTableDefinition brokenCustomizer = QuoteDocumentTableDefinition.build(
            'BROKEN_CUSTOMIZER_PROBE',
            new List<String>{ QuoteDocumentTableDefinition.DIM_PRODUCT_FAMILY },
            new List<Integer>{ 1 },
            QuoteDocumentTableDefinition.FILTER_ALL
        );
        brokenCustomizer.rowCustomizerCode = 'THIS_CODE_WAS_NEVER_REGISTERED';
        QuoteDocumentTableDefinition.useDefinitions(
            new List<QuoteDocumentTableDefinition>{ brokenCustomizer });

        Test.startTest();
        try {
            QuoteDocumentGenerator.generate(new Set<Id>{ quoteId() });
            Assert.fail('An unregistered Row_Customizer_Code__c must not be silently ignored');
        } catch (QuoteDocumentGenerator.QuoteDocumentException e) {
            Assert.isTrue(e.getMessage().contains('THIS_CODE_WAS_NEVER_REGISTERED'),
                'The error should name the exact bad code so an admin can find it in the metadata: ' + e.getMessage());
        }
        Test.stopTest();
    }
}
