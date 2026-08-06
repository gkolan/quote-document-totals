/**
 * Transaction classification - which change measure a line feeds, and with
 * what sign.
 *
 * Split out of QuoteDocumentGeneratorTest because this is the one area of the
 * framework whose correctness is still open: classify() is PROVISIONAL until
 * validated against a real CPQ amendment (docs/quote-document-totals.md §3,
 * specs/quote-docusign-totals/phases/phase-1-classification-validation.md).
 * Keeping it in its own suite means the work that closes that phase - or the
 * six-category taxonomy remap, if finance confirms it - lands in one file
 * rather than threaded through the generation tests.
 *
 * Fixture data comes from QuoteDocumentTestData, identical to every other
 * QuoteDocument suite.
 */
@IsTest
private class QuoteDocumentClassificationTest {

    @TestSetup
    static void setup() {
        QuoteDocumentTestData.setup();
    }

    private static final String CODE_PACKAGE  = QuoteDocumentTestData.CODE_PACKAGE;
    private static final String CODE_OPTION   = QuoteDocumentTestData.CODE_OPTION;
    private static final String CODE_PLAN     = QuoteDocumentTestData.CODE_PLAN;
    private static final String CODE_OPTIONAL = QuoteDocumentTestData.CODE_OPTIONAL;

    private static Id quoteId() {
        return QuoteDocumentTestData.quoteId();
    }

    private static Decimal expectedCountedNet() {
        return QuoteDocumentTestData.expectedCountedNet();
    }

    private static SBQQ__QuoteLine__c line(
        Id quoteId, Id productId, Integer lineNumber,
        Decimal quantity, Decimal listPrice, Decimal netPrice
    ) {
        return QuoteDocumentTestData.line(quoteId, productId, lineNumber, quantity, listPrice, netPrice);
    }

    private static Map<Id, SBQQ__QuoteLine__c> storedLines(List<Id> lineIds) {
        return QuoteDocumentTestData.storedLines(lineIds);
    }

    private static QuoteDocumentLine documentLine(Id lineId, SBQQ__Quote__c quote) {
        return QuoteDocumentTestData.documentLine(lineId, quote);
    }

    private static Quote_Document_Table__c table(String tableCode) {
        return QuoteDocumentTestData.table(tableCode);
    }

    private static Quote_Document_Row__c grandTotal(String tableCode) {
        return QuoteDocumentTestData.grandTotal(tableCode);
    }

    // -----------------------------------------------------------------------
    // Branches reachable from the ordinary test quote
    // -----------------------------------------------------------------------

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
}
