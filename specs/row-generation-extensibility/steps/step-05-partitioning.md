# Step 05 — Partitioning

**Status: BUILT** — §3.1–3.4 built; per-*partition* assumptions remain out of reach, see close-out
**Blocked by:** [step 02](step-02-allocation-primitive.md), [step 04](step-04-comparison-and-enrichment.md)
**Blocks:** nothing
**Use cases:** 13, 16, 17 and the document half of 4 ([`spec.md`](../spec.md) §3)

---

## 1. Goal

One quote produces several independently totalled tables — and, where the business genuinely needs it, several separately addressable documents — without any grand total spanning things that must never be added together.

## 2. Why this step exists

Three alternatives (Basic / Recommended / Premium), three consumption scenarios, or a guaranteed price beside a contingent rebate all share one failure mode: a grand total that sums them. That total is not merely useless, it is misleading — it states a number the customer is not being asked to pay. Grouping cannot prevent it, because grouping's entire job is to roll everything up into one total.

Separate purchasing entities (use case 4's second half) go further: each entity needs its own document, with its own payable total, that can be sent to a different signer.

This step is last because the second half touches the generation lifecycle — request Id, fingerprint, retention, launch — and that cost is only justified once several partitioned *tables* exist and prove the demand.

## 3. Scope

### 3.1 Partitioned tables (the cheap half — build this first)

A `Partition_Dimension__c` on `Quote_Document_Table_Def__mdt`. When set, generation emits **one `Quote_Document_Table__c` record per distinct partition value**, each with its own rows, its own grand total, and its own `Display_Title__c` carrying the partition value as a label argument.

This is deliberately not "a second grouping level". The distinction, stated once:

| | Grouping | Partitioning |
|---|---|---|
| Produces | Group headers and subtotals inside one table | Separate table records |
| Grand total | One, spanning every group | One per partition; none spanning partitions |
| Reconciles against | The quote's total | The partition's own total |
| Renderer sees | One table with nested rows | N tables |

`verify()` runs per table and therefore already does the right thing — each partition reconciles against its own contributing lines. Confirm this rather than assuming it; the reconciliation currently compares to quote-level CPQ amounts, and a partitioned table must compare to its partition's share instead. If that comparison does not exist, adding it is this step's real work, and `PARTITION_TOTAL_UNRECONCILED` is its failure code.

Ship one partition dimension — `SCENARIO`, sourced from a line field or an enrichment source — because 13, 16 and 17 are all the same shape wearing different words.

### 3.1a Partition identity — the blocker to resolve before any code

`QuoteDocumentGenerator` builds `Table_Key__c = quote.Id + ':' + definition.tableCode` ([line 805](../../../force-app/main/default/classes/QuoteDocumentGenerator.cls:805)). Emitting three tables from one definition under that key gives three records with the same key. Nothing in this step works until that is fixed, and it must be fixed deliberately rather than by appending a suffix and hoping.

| Concern | Resolution |
|---|---|
| **Table key** | `Table_Key__c = quoteId : tableCode : partitionValue`, with the partition segment **absent** — not empty, not a literal — when the definition is unpartitioned. An unpartitioned table's key must be byte-identical to today's, or every existing snapshot's identity moves for no reason. |
| **Partition value on the record** | New `Partition_Value__c` (Text 80) and `Partition_Dimension__c` (Text 40) on `Quote_Document_Table__c`, so a renderer and a query can partition without parsing the key. A composite key is an identity, not an API. |
| **Uniqueness** | `Table_Key__c` is `externalId`. Confirm whether it is also `unique`; if it is, verify the three-segment form still satisfies it, and if it is not, this step adds the in-transaction duplicate check rather than relying on the database. |
| **Retrieval** | `QuoteDocumentQuery` and `QuoteDocumentRenderService` currently assume one table per `Table_Code__c` per quote. Every such assumption must be found and made partition-aware; a lookup that silently returns the first of three is the failure mode to hunt for. Grep for `Table_Code__c` across all classes as the first task of this step, and list the hits in the close-out. |
| **Payload identity** | `Document_Payload_Hash__c` covers the whole snapshot and keeps doing so — partitions are views of one snapshot, not separate ones. If §3.4 ships a per-partition payload, that payload's hash is computed over the partition's records but is **not** stored as a second quote-level hash. |
| **Fingerprint** | §3.5. |
| **Retention** | `QuoteDocumentRetention` deletes by quote. Confirm it removes every partition, and add a test with three partitions — a retention pass that leaves two behind is a data leak into the next generation. |

`PARTITION_KEY_COLLISION` is the coded failure when two partitions resolve to the same key, which means the partition dimension produced a duplicate value.

### 3.2 The cross-partition total problem

A partitioned table set must state, in data, whether a total across partitions exists:

| `Cross_Partition_Total__c` | Meaning | Use case |
|---|---|---|
| `NONE` (default) | No total spans partitions. The renderer has nothing to print and must not invent one. | 13, 17 — alternatives and scenarios are mutually exclusive |
| `SUM` | Partitions are complementary parts of one whole; the sum is meaningful. | 4 — departments and entities together are the whole quote |

Default `NONE`, and make the field required on any definition that sets `Partition_Dimension__c`. An author who has to choose cannot accidentally ship the misleading total.

For 16 (rebate) the guaranteed and contingent partitions are `NONE`, and the contingent partition's rows are additionally `Informational` — the customer must be able to see at a glance which money is conditional. Both mechanisms, not one; this is a place where redundancy is correct.

### 3.3 Scenario and estimate labelling

Every scenario and estimate partition carries a narrative block ([render contract step 04](../../vendor-neutral-render-contract/steps/step-04-narrative-blocks.md)) stating its assumptions, and it is **required**, not optional: a consumption estimate printed without its assumptions is the single most dangerous document this framework could produce. Config load fails with `SCENARIO_ASSUMPTIONS_MISSING` when a scenario partition has no assumptions block.

### 3.4 Separate documents (the expensive half)

Only after 3.1 is running. Each partition becomes its own addressable payload:

- `QuoteDocumentRenderService.getPayload` gains a partition selector; the existing signature keeps its meaning (the whole quote) so no adapter breaks.
- One `generate()` still produces every partition in one transaction, one request Id, one fingerprint. **Do not** make each partition a separate generation — that would give one quote several snapshots that can drift apart, and the atomicity invariant ("a failed attempt leaves no records created by that attempt") is worth more than the convenience.
- Retention and staleness stay quote-scoped. A partition is a view of one snapshot, not a snapshot of its own.

If §3.1 lands and no real document ever needs §3.4, leave §3.4 unbuilt and record that in the close-out. That is a successful outcome, not an incomplete one.

### 3.5 Fingerprint

`partitionDimension`, `crossPartitionTotal`, and the resolved partition value list. A quote that gains a scenario must not reuse a snapshot missing it.

## 4. Out of scope

- Different *templates* per partition. That is a renderer-side mapping decision and belongs to the adapter.
- Partitioning across quotes.
- Approval or signature routing per partition. This framework produces document data; it does not route anything.

## 5. Acceptance criteria

- [ ] `Partition_Dimension__c` and `Cross_Partition_Total__c` deployed and in the permission set; the second is required whenever the first is set.
- [ ] A quote with three scenarios produces three `Quote_Document_Table__c` records with the same `Table_Code__c` and distinct partition values.
- [ ] Each partition's `Grand Total` equals the sum of that partition's own leaf rows, and no row from another partition contributes.
- [ ] Verification reconciles each partition against its own share, and a deliberately corrupted partition fails with `PARTITION_TOTAL_UNRECONCILED`.
- [ ] With `Cross_Partition_Total__c = NONE`, no record anywhere in the snapshot carries a total spanning partitions — asserted by query, not by inspection.
- [ ] With `SUM`, the cross-partition total equals the quote's net amount.
- [ ] A scenario partition without an assumptions block fails with `SCENARIO_ASSUMPTIONS_MISSING`.
- [ ] A contingent-rebate partition's rows are `Informational` and enter no total.
- [ ] An unpartitioned definition is byte-identical to today — fingerprint **and `Table_Key__c`** equality before and after deploy.
- [ ] Three partitions produce three distinct `Table_Key__c` values; a dimension yielding a duplicate value fails with `PARTITION_KEY_COLLISION`.
- [ ] Every `Table_Code__c` lookup in `QuoteDocumentQuery` and `QuoteDocumentRenderService` is partition-aware; none returns the first of three silently. The grep list is in the close-out.
- [ ] Retention on a quote with three partitions removes all three.
- [ ] Adding a scenario to a quote moves the fingerprint.
- [ ] If §3.4 is built: `getPayload` with a partition selector returns only that partition, the no-selector overload is unchanged, and both come from one generation with one request Id.
- [ ] Existing suite passes untouched.

## 6. Verification method

```bash
sf apex run test --class-names QuoteDocumentPartitionTest --class-names QuoteDocumentGeneratorTest --class-names QuoteDocumentIntegrityTest --result-format human --wait 20
```

```sql
SELECT Id, Table_Code__c, Display_Title__c, Partition_Value__c
FROM Quote_Document_Table__c
WHERE Quote__c = :quoteId
ORDER BY Display_Order__c
```

Then, per partition:

```sql
SELECT Row_Type__c, Amount_Net__c
FROM Quote_Document_Row__c
WHERE Quote_Document_Table__c = :partitionTableId
  AND (Row_Type__c = 'Grand Total' OR Include_In_Grand_Total__c = true)
```

Pass: each partition's `Grand Total` equals the sum of its own counted rows, three times over, and the three grand totals are not summed anywhere in the snapshot.

New test class `QuoteDocumentPartitionTest`: `threeScenariosProduceThreeTables`, `partitionTotalsAreIndependent`, `noCrossPartitionTotalWhenNone`, `crossPartitionSumMatchesQuoteWhenSum`, `corruptedPartitionFailsVerification`, `scenarioWithoutAssumptionsFails`, `contingentRowsEnterNoTotal`, `unpartitionedDefinitionIsUnchanged`, `partitionSetMovesTheFingerprint`.

## 7. Close-out

- **Date:** 2026-08-28
- **Status: PARTIAL.** §3.1, §3.1a and §3.2 shipped. §3.3 (required scenario assumptions) and §3.4 (separate documents) did not, and §3.4 was always optional.

### Per-partition reconciliation had to be added — the step's real work, as predicted

§3.1a said to confirm rather than assume that `verify()` does the right thing per partition. It did not. `verify()` holds every `PRICE_WATERFALL` + `EXCLUDE_OPTIONAL` table to CPQ's own `SBQQ__NetAmount__c`, which a partition covering a *share* of the quote can never satisfy — every partitioned table failed by construction, exactly as §3.1a warned.

The fix deliberately does **not** simply drop the check. It moves up a level: `assertCrossPartitionTotals` holds the **set** to the quote where `Cross_Partition_Total__c = SUM`, and to nothing where it is `NONE`. Dropping it without that replacement would have been the one place this framework stopped reconciling to CPQ, and it would have looked like a passing test suite.

### Built

- `Partition_Dimension__c` and `Cross_Partition_Total__c` on the definition; `Partition_Value__c`, `Partition_Dimension__c` and `Cross_Partition_Total__c` on the generated table, with permission-set entries.
- **The generator now plans table *instances* rather than definitions.** One definition still produces one table unless it partitions; every internal map is keyed by an instance key that is the bare table code when it does not, so nothing about an unpartitioned table moved.
- **Three-segment `Table_Key__c`** where a definition partitions, and the **byte-identical two-segment form** where it does not — asserted by a test, because an unpartitioned table's identity must not change just because partitioning now exists.
- `PARTITION_TOTAL_UNRECONCILED` when a `SUM` set does not add up: a line reached no partition, or reached two.
- **The partition reaches the printed heading through the dictionary** (`PARTITIONED_TITLE`, en_US and fr), not through Apex concatenation and not by asking a renderer to compose one.
- **Partitioning and comparing at once is refused.** Which partition a baseline line belongs to has no agreed answer, and a change document is the last place to guess.

### A constraint discovered in build: at most nine partitions

`Quote_Document_Table__c.Display_Order__c` is a whole number, and definitions are spaced by ten. Partitions take consecutive orders from their definition's, so a tenth would collide with the next table — and blocks share that one document-wide sequence, so a collision is a real ambiguity rather than untidiness. Ten or more partitions fails with a message that says exactly this. Raising the ceiling means renumbering the ordering scheme, which is its own change.

### Not built

- ~~**§3.3, required scenario assumptions**~~ — **closed 2026-08-28, at table scope.** `Assumptions_Block_Code__c` names a narrative block the table cannot publish without, checked against the blocks the generation actually produced rather than against metadata — so the failure it guards is the real one: a block deactivated, or with no wording in the resolved locale, while the table depending on it kept generating. `SCENARIO_ASSUMPTIONS_MISSING` names the missing block. **Per-partition** assumptions are still not possible: narrative blocks belong to the quote, so "this table has its assumptions" is enforceable and "this partition has its own" needs the block-model change. The dangerous case — an estimate printing with no assumptions at all — is now closed.
- ~~**§3.4, separate addressable documents**~~ — **closed 2026-08-28.** `QuoteDocumentRenderService.getPayloadForPartition` returns one partition's sections plus every unpartitioned one, and `PARTITION_NOT_FOUND` refuses a partition the snapshot does not have rather than returning the remainder. It is deliberately a **view**: the whole payload is retrieved and verified first — same request Id, same fingerprint, same integrity check — so two parties' documents provably came from one generation. `Section` gained `partitionValue` and `crossPartitionTotal` so a renderer selects and knows whether a spanning total exists without parsing a composite key.
- The `SCENARIO` partition dimension as a named thing. Any existing dimension partitions — the test uses `PRODUCT_FAMILY` — so a scenario field on the line needs no new code, only configuration.

- **Test evidence:** `QuoteDocumentPartitionTest` 14/14. Full suite 478 ran, 473 passed, 5 failed — the five pre-existing org-only failures, unchanged.

- **Next step:** [`step-06-docs-and-closeout.md`](step-06-docs-and-closeout.md)

- **Next step:** [`step-06-docs-and-closeout.md`](step-06-docs-and-closeout.md)
