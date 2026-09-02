# Generate or refresh document data from a Quote

## Status and scope

**Repository status:** The **Generate Document Tables** Quote quick action, **Generate Quote Document Tables** screen Flow, permission-set access, immediate Apex option, and background Apex options are included.

**Org verification status:** Repository tests cover generation, safe reuse, failure rollback, and request ownership. A Salesforce administrator must still add the action to the Quote page and verify it with the target users in a sandbox.

Use this guide to give users one safe action that builds the saved document data or reuses it when nothing relevant changed.

## Use case scenario

A sales user has finished calculating a Quote and needs current, checked information for a proposal. The user should not need to know whether Salesforce must rebuild the saved tables or can reuse the existing result.

## What this produces

The action produces one complete saved result for the Quote:

- **Quote Document Table** records for each active table definition;
- ordered **Quote Document Row** and **Quote Document Column** records;
- ordered **Quote Document Block** records for document text;
- **Document Data Status = Ready** on success; and
- a request Id and change check that a document launch can use to select the exact result.

The action does not send, sign, or create a document. It prepares the Salesforce data that a document tool uses.

## Before you start

You need:

- Salesforce CPQ and this package deployed to a sandbox;
- the `CPQ_Document_Totals` permission set assigned to the test user;
- an active Quote page layout or Lightning record page used by that user;
- at least one active Quote Document Table Definition; and
- a calculated test Quote with Quote Lines.

**Stop here if** the Quote is still calculating, the user cannot run actions on the Quote, or **Document Data Status** is already **Generating** from a live request. Correct the prerequisite or allow the live request to finish before starting another attempt.

## Terms in plain language

| Salesforce term       | What it means in this guide                                                                          |
| --------------------- | ---------------------------------------------------------------------------------------------------- |
| Quick action          | The **Generate Document Tables** button shown on a Quote.                                            |
| Screen Flow           | The short Salesforce screen that runs generation and displays the result.                            |
| Saved result          | The Tables, Columns, Rows, and Blocks produced together for one Quote.                               |
| Ready                 | Salesforce finished all checks and the saved result may be used.                                     |
| Reused                | The saved result was already current, so Salesforce checked it and kept it.                          |
| Request Id            | The identifier for one generation attempt. Support staff can use it to match an error to an attempt. |
| Change check          | The stored value Salesforce compares with current Quote data and settings.                           |
| Background generation | Apex starts work separately so a larger set of Quotes does not share one transaction limit.          |

## Configure in Salesforce

### Add the action to a Quote page layout

1. Open **Setup**.
2. Select **Object Manager**.
3. Select **Quote**. In a Salesforce CPQ org, this is the managed Quote object.
4. Select **Page Layouts**.
5. Open the layout assigned to the test user.
6. In the palette, select **Mobile & Lightning Actions**.
7. Drag **Generate Document Tables** into **Salesforce Mobile and Lightning Experience Actions**.
8. Save the layout.

### Check a Lightning page that uses Dynamic Actions

1. Open a test Quote and select **Setup → Edit Page**.
2. Select the Highlights Panel.
3. If **Enable Dynamic Actions** is selected, add **Generate Document Tables** to the action list.
4. Set visibility rules only when the business has a documented reason. Do not hide the action merely because the Quote is **Ready**; the action also performs the fresh change check.
5. Save and activate the page for the intended app, record type, and user assignment.

### Confirm access

1. Open **Setup → Permission Sets → CPQ Document Totals → Manage Assignments**.
2. Confirm the test user is assigned.
3. Log in as that user or use **Login As** in the sandbox.
4. Open a Quote and confirm the action is visible.

## Worked example

Use a calculated Quote with two payable Quote Lines and at least one active shipped table definition.

1. Run **Generate Document Tables** for the first time. The message must say that records were generated and include table and row counts.
2. Run it again without changing the Quote. The message must say the existing saved result was reused.
3. Change the quantity of one Quote Line and calculate the Quote.
4. Run the action again. Salesforce must rebuild the result instead of reusing the earlier one.

The exact totals depend on the active table definitions. The behavior under test is first build, safe reuse, and rebuild after a relevant change.

## Generate and verify

1. Open the calculated sandbox Quote.
2. Select **Generate Document Tables**.
3. Wait for the confirmation screen. Record the table count, row count, and whether the result was reused.
4. Close the Flow and refresh the Quote.
5. Confirm **Document Data Status** is **Ready**.
6. Confirm **Document Data Error** is blank.
7. Confirm **Document Data Generated On** contains the successful completion time.
8. Open the **Quote Document Tables** related list and confirm the expected tables exist.
9. Open one generated table and confirm its status is **Complete**. Quote status **Ready** and Table status **Complete** are different fields and both are expected.
10. Run the action again without changing anything and confirm the message says the existing result was reused.
11. Preview the document only after the Quote is **Ready**.

For a custom document launch, a developer must run the shipped generate-or-reuse operation first and pass its returned Request Id and change check to the document service. The launch must not select whichever generated rows happen to exist.

## Troubleshooting

| Problem                            | What it means                                                                                                    | What to do                                                                                                                            |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Action is missing                  | It is not on the assigned page layout or Dynamic Actions list, or the user lacks access.                         | Check page assignment, Dynamic Actions, and the `CPQ_Document_Totals` permission-set assignment.                                      |
| Flow says no Quote Id was supplied | The action was launched without Quote record context.                                                            | Confirm the quick action uses `Generate_Quote_Document_Tables` and is placed on the Quote object.                                     |
| Status remains Generating          | A request is still running or stopped before completing.                                                         | Wait for a live request. If it exceeds the configured abandonment window, run the action again and retain the request Id for support. |
| Status becomes Failed              | Salesforce rejected data, configuration, permissions, or an extension result.                                    | Read **Document Data Error**, correct the named cause, and run the action again. Do not create a document from the failed attempt.    |
| Second run rebuilds unexpectedly   | A relevant Quote value, Quote Line value, configuration record, language, or extension version changed.          | Review the recent change. Rebuilding is correct when output could differ.                                                             |
| Changed Quote is reused            | The changed field may not be declared as output-relevant, or an extension version or dependency was not updated. | Stop document creation and review the freshness configuration using use case 41.                                                      |
| User sees an access error          | Object, field, Flow, or Apex access is missing.                                                                  | Reassign the shipped permission set and verify that local permission-set groups do not mute required access.                          |

## Deactivate or roll back

1. Remove **Generate Document Tables** from the affected Quote page layout or Dynamic Actions list.
2. Save and activate the Lightning page assignment when Dynamic Actions are used.
3. Do not delete the shipped Flow or quick action to hide it from one group of users.
4. To restore access, add the action back and test as the target user.
5. Removing the action does not delete saved document data. Current generated records remain governed by Quote status and the normal retention process.

## Production checklist

- [ ] The action is on every intended Quote page layout or Dynamic Actions assignment.
- [ ] The intended users have the `CPQ_Document_Totals` permission set.
- [ ] A first sandbox run generates Tables, Columns, Rows, and Blocks successfully.
- [ ] An unchanged second run reports reuse.
- [ ] A relevant Quote Line change causes a rebuild.
- [ ] A forced configuration error records **Failed** and a useful error message.
- [ ] Users know that only **Ready** document data may be used.
- [ ] Any custom document launch uses the returned Request Id and change check.
