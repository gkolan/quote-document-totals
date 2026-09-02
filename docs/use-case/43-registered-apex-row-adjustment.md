# Add a registered Apex-based row adjustment

## Status and scope

**Repository status:** Ready for an Apex extension. The inactive `DISCOUNT_EXAMPLE` table definition, required Apex class shape, approved-code list, generation connection, seven registered examples, and automated tests are included.

**Org verification status:** Not verified in your Salesforce org. A developer must deploy and test the code, and an administrator must complete the output checks in this guide before the table is activated for users.

This task includes Apex. Do not create or edit the Apex class without a reviewed change and passing tests. Before activation, confirm the deployment contents, connect an approved code to a table definition, generate a test Quote, and check the result.

## Use case scenario

Generated rows need controlled logic that table settings and an autolaunched Flow cannot safely provide. Examples include a calculated discount row, estimated tax, a rounding adjustment, or rebuilding group totals after moving rows.

## What this produces

A reviewed Apex class receives the complete generated row list, makes a specific adjustment, and returns the complete list. The table definition refers to a short registered code instead of a class name.

The shipped `DISCOUNT_EXAMPLE` demonstrates the pattern. It applies a 5% loyalty discount to the Detail row with the largest Net Amount, adds a negative Discount row, and updates the matching subtotal and Grand Total.

## Before you start

Confirm all of the following:

- A Salesforce developer owns the Apex change and its tests.
- The Quote Document Totals metadata and Apex in this repository have been deployed.
- The administrator can open **Setup** and **Custom Metadata Types**.
- A non-production org and a Quote with at least one positive-price Quote Line are available.
- The Salesforce developer has supplied the exact approved code, expected rows and amounts, test results, and rollback instructions.

**Stop here if** you have only a class name or an untested code value. The Apex class must follow the package requirements, be added to the approved-code list, and pass automated tests before it is connected to a table.

## Terms in plain language

| Term               | Meaning in this guide                                                                                                        |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| Apex               | Salesforce code. A developer must create, review, test, and deploy it.                                                       |
| Row customizer     | A class that receives all rows for one generated table and returns the complete adjusted list.                               |
| Approved-code list | The controlled list that connects a short code, such as `DISCOUNT_EXAMPLE`, to one approved Apex class.                      |
| Row key            | The unique text that identifies a generated row within the table.                                                            |
| Reconciliation     | The check that detail contributions, section subtotals, and the Grand Total still agree.                                     |
| Customizer version | A text value that identifies the behavior of the registered code. Change it whenever that behavior changes.                  |
| Cache policy       | The rule that decides whether a previous generated result can be reused. `STANDARD` is used by the shipped discount example. |

## Configure in Salesforce

### 1. Developer implementation and registration

The developer must complete these steps in source control:

1. Create a `with sharing` class that implements `QuoteDocumentRowCustomizer`.
2. Implement `customize(QuoteDocumentRowCustomizerContext context)` and return the complete row collection.
3. Use `context.newRow(...)` to create a row with the package's normal starting values.
4. Give every new row a unique Row Key and Display Order.
5. Set **Include in Subtotal** and **Include in Grand Total** deliberately. A note normally has both clear. A counted adjustment must also update affected subtotal and Grand Total rows.
6. Add one exact mapping in `QuoteDocumentRowCustomizerRegistry.resolve`.
7. Add customer-facing translations through the shipped label metadata instead of placing English text directly in new code.
8. Add and pass tests for the class, approved-code connection, generated rows, totals, invalid output, and changed behavior version.

Example approved-code entry:

```apex
when 'MY_ORG_TAX' {
    return new MyOrgTaxRowCustomizer();
}
```

The value `MY_ORG_TAX` is only an example. The administrator must use the exact code that the developer actually registered.

The repository currently registers these exact codes:

| Registered code        | Shipped class                            |
| ---------------------- | ---------------------------------------- |
| `DISCOUNT_EXAMPLE`     | `QuoteDocumentDiscountRowCustomizer`     |
| `INDUSTRY_ALLEGIANCE`  | `QuoteDocumentIndustryRowCustomizer`     |
| `ROUNDING_EXAMPLE`     | `QuoteDocumentRoundingRowCustomizer`     |
| `ESTIMATED_TAX`        | `QuoteDocumentEstimatedTaxRowCustomizer` |
| `MONTHLY_SUBSCRIPTION` | `QuoteDocumentMonthlyRowCustomizer`      |
| `PACKAGE_COMPOSITION`  | `QuoteDocumentCompositionCustomizer`     |
| `FLOW`                 | `QuoteDocumentFlowRowCustomizer`         |

An unknown code stops generation. This prevents metadata from running an arbitrary class or silently skipping a required rule.

### 2. Administrator configuration

Test the shipped discount example before connecting new code:

1. In **Setup**, open **Custom Metadata Types**.
2. Find **Quote Document Table Definition** and select **Manage Records**.
3. Open **Discount Example**. Its table code is `DISCOUNT_EXAMPLE`.
4. Confirm these values:

   | Field                  | Required value     |
   | ---------------------- | ------------------ |
   | Amount Basis           | `Final Value`      |
   | Line Filter            | `ALL`              |
   | Measure Set            | `PRICE_WATERFALL`  |
   | Show Details           | Selected           |
   | Show Section Totals    | Not selected       |
   | Row Customizer Code    | `DISCOUNT_EXAMPLE` |
   | Row Customizer Version | `1`                |
   | Cache Policy           | `STANDARD`         |
   | Active                 | Not selected       |

5. Select **Edit**, select **Active**, and save. Leave every other value unchanged for the first test.

For a new registered adjustment, edit the intended table and enter the developer-supplied code in **Row Customizer Code**. Set **Row Customizer Version** to `1` for its first release. Change no other table behavior until this connection has been tested.

## Worked example

Assume a grouped Quote has these positive Net Amounts:

| Detail row | Net Amount |
| ---------- | ---------: |
| Support    |    $200.00 |
| Software   |  $1,000.00 |

`DISCOUNT_EXAMPLE` selects Software because it has the largest Net Amount. It calculates 5% of $1,000.00 and creates a `Discount` row for **-$50.00**. The label starts with **Loyalty Discount -** and includes the selected row's label. The matching section subtotal and the Grand Total are each reduced by $50.00.

The customizer adds no discount when no Detail row has a positive amount. Do not use this example with a production pricing policy unless the 5% rule and its selection method are actually approved.

## Generate and verify

### Developer checks before handoff

The developer must provide evidence that:

- the new class and its test class pass;
- generation was tested through `QuoteDocumentGenerator.generate`, not only by calling the class directly;
- new Row Keys and Display Orders are unique;
- subtotal and Grand Total reconciliation passes;
- empty, duplicate, malformed, and non-reconciling output relevant to the rule is rejected or handled;
- an unknown approved code fails with a clear error; and
- the class, tests, approved-code change, labels, and table-version change are included in one deployment.

### Administrator output checks

1. Open a test Quote with at least one positive-price Quote Line.
2. Record the Quote's expected total before activating the example.
3. Select **Generate Document Tables**.
4. Wait until **Document Data Status** is `Ready`.
5. Open the related **Quote Document Tables** list and select **Discount Example**.
6. Open its related **Quote Document Rows**.
7. Find the largest positive Detail Net Amount and calculate 5% of it.
8. Confirm there is one Discount row with the same amount shown as a negative value.
9. Confirm the affected subtotal and Grand Total were reduced by that amount.
10. Generate the Quote again and confirm the current result contains only one Discount row for the selected Quote Line.

Do not activate newly registered code for production until both sets of checks pass.

## Troubleshooting

| Problem                                        | What it means                                                                                         | What to do                                                                                                                              |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Generation says the customizer code is unknown | The code is misspelled, the approved-code change was not deployed, or deployment pieces do not match. | Clear the code to restore standard behavior. Ask the Salesforce developer to confirm the exact approved-code entry and deployment.      |
| Generation fails after the customizer runs     | The class threw an error or returned invalid rows or totals.                                          | Open the generation error, clear the code, and give the error and Quote example to the developer. Do not repair generated rows by hand. |
| No adjustment row appears                      | The test data did not meet the rule, or the wrong table definition was generated.                     | Compare the Quote with the developer's stated conditions. For `DISCOUNT_EXAMPLE`, include a positive Net Amount Detail row.             |
| The adjustment appears twice                   | The class returned duplicate output or two adjustments are connected.                                 | Clear the code and ask the developer to test repeated generation and unique Row Keys.                                                   |
| Old output remains after a code change         | The customizer version still identifies the earlier behavior.                                         | Increase **Row Customizer Version**, run the invalidation batch below, and generate again.                                              |
| Grand Total does not agree with the adjustment | A counted row was added without updating every affected total.                                        | Clear the code immediately and return the failure to the developer. Do not activate the table.                                          |

## Deactivate or roll back

To stop using the shipped example, clear **Active** on `DISCOUNT_EXAMPLE`.

To remove a registered adjustment from another table:

1. Edit the table definition in **Custom Metadata Types**.
2. Clear **Row Customizer Code**.
3. Increase **Row Customizer Version** from its current whole number, such as `1`, to the next whole number, such as `2`.
4. Save.
5. Ask a Salesforce developer or administrator with Execute Anonymous access to run:

   ```apex
   Database.executeBatch(new QuoteDocumentInvalidationJob(), 200);
   ```

6. Generate an affected test Quote again and confirm the standard rows and totals return.

If the deployment itself must be rolled back, the Salesforce developer must deploy the previous class, approved-code list, labels, and table version together. Do not delete generated Table, Row, saved document, or Error records by hand.

## Production checklist

- [ ] A developer owns the Apex implementation and review.
- [ ] The exact approved code is documented and deployed.
- [ ] The class, test, approved-code list, labels, and version were deployed together.
- [ ] All Apex tests passed.
- [ ] Generation-path and invalid-output tests passed.
- [ ] The administrator used the exact registered code.
- [ ] New Row Keys and Display Orders are unique.
- [ ] Subtotals and Grand Total reconcile.
- [ ] The same test Quote generated successfully twice.
- [ ] The rollback steps were tested outside production.
