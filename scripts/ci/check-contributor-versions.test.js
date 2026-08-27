'use strict';

/**
 * Step 01A section 10: "the CI version gate has its own executable suite - a
 * gate with no tests is a gate nobody can trust."
 *
 * Every case below must FAIL the build rather than warn. Node's built-in test
 * runner, so the suite needs no dependency the repo does not already have:
 *
 *     node --test scripts/ci/
 */

const test = require('node:test');
const assert = require('node:assert');
const path = require('node:path');

const {
    parseRegistry,
    parseDefinitions,
    findViolations,
    GateError
} = require('./check-contributor-versions.js');

/** Token values as they were at the merge base, for tests that need a "before". */
function tokensBefore(overrides) {
    return Object.assign(
        {
            'Quote_Document_Table_Def.DISCOUNT_EXAMPLE.md-meta.xml': {
                customizerVersion: '1',
                flowVersion: null
            }
        },
        overrides || {}
    );
}

const GOOD_REGISTRY = `
public with sharing class QuoteDocumentRowCustomizerRegistry {
    public static QuoteDocumentRowCustomizer resolve(String customizerCode) {
        switch on customizerCode {
            when 'DISCOUNT_EXAMPLE'      { return new QuoteDocumentDiscountRowCustomizer(); }
            when 'ESTIMATED_TAX'         { return new QuoteDocumentEstimatedTaxRowCustomizer(); }
            when else { throw new QuoteDocumentGenerator.QuoteDocumentException('x'); }
        }
    }
}`;

const CLASS = (n) => 'force-app/main/default/classes/' + n + '.cls';
const FLOW = (n) => 'force-app/main/default/flows/' + n + '.flow-meta.xml';
const CMDT = (n) => 'force-app/main/default/customMetadata/' + n;

function definition(overrides) {
    return Object.assign(
        {
            file: 'Quote_Document_Table_Def.DISCOUNT_EXAMPLE.md-meta.xml',
            tableCode: 'DISCOUNT_EXAMPLE',
            customizerCode: 'DISCOUNT_EXAMPLE',
            customizerVersion: '1',
            flowName: null,
            flowVersion: null
        },
        overrides
    );
}

// ---------------------------------------------------------------------------
// Registry parsing - the cases that must not be silently skipped
// ---------------------------------------------------------------------------

test('parses a well-formed registry', () => {
    const mapping = parseRegistry(GOOD_REGISTRY);
    assert.strictEqual(mapping.size, 2);
    assert.strictEqual(mapping.get('DISCOUNT_EXAMPLE'), 'QuoteDocumentDiscountRowCustomizer');
});

test('a registry with no switch fails the gate rather than reporting success', () => {
    assert.throws(() => parseRegistry('public class Nothing {}'), GateError);
});

test('parsing zero codes fails - a gate that checks nothing must not pass', () => {
    const empty = 'class R { void m() { switch on code { when else { return null; } } } }';
    assert.throws(() => parseRegistry(empty), GateError);
});

test('a multiline when branch fails loudly instead of being skipped', () => {
    const multiline = `
    switch on customizerCode {
        when 'DISCOUNT_EXAMPLE' {
            return new QuoteDocumentDiscountRowCustomizer();
        }
        when 'ESTIMATED_TAX' { return new QuoteDocumentEstimatedTaxRowCustomizer(); }
    }`;
    assert.throws(
        () => parseRegistry(multiline),
        (e) => e instanceof GateError && /could not be parsed/.test(e.message),
        'A branch the gate cannot read must fail the build. Skipping it silently drops a contributor ' +
            'out of the gate, which is the exact failure this gate exists to prevent.'
    );
});

test('a commented-out branch is not read as a live mapping', () => {
    const commented = `
    switch on customizerCode {
        // when 'REMOVED_EXAMPLE' { return new QuoteDocumentRemovedRowCustomizer(); }
        when 'DISCOUNT_EXAMPLE' { return new QuoteDocumentDiscountRowCustomizer(); }
    }`;
    const mapping = parseRegistry(commented);
    assert.strictEqual(mapping.size, 1);
    assert.ok(!mapping.has('REMOVED_EXAMPLE'));
});

test('a block-commented branch is not read as a live mapping', () => {
    const commented = `
    switch on customizerCode {
        /* when 'REMOVED_EXAMPLE' { return new QuoteDocumentRemovedRowCustomizer(); } */
        when 'DISCOUNT_EXAMPLE' { return new QuoteDocumentDiscountRowCustomizer(); }
    }`;
    const mapping = parseRegistry(commented);
    assert.ok(!mapping.has('REMOVED_EXAMPLE'));
});

// ---------------------------------------------------------------------------
// Definition parsing
// ---------------------------------------------------------------------------

test('a missing metadata directory fails the gate', () => {
    assert.throws(
        () => parseDefinitions('/nowhere', () => '', () => []),
        GateError
    );
});

test('reads the version tokens off a definition', () => {
    const xml = `<CustomMetadata>
        <values><field>Table_Code__c</field><value xsi:type="xsd:string">T1</value></values>
        <values><field>Row_Customizer_Code__c</field><value xsi:type="xsd:string">C1</value></values>
        <values><field>Row_Customizer_Version__c</field><value xsi:type="xsd:string">7</value></values>
    </CustomMetadata>`;
    const defs = parseDefinitions(
        '/x',
        () => xml,
        () => ['Quote_Document_Table_Def.T1.md-meta.xml']
    );
    assert.strictEqual(defs.length, 1);
    assert.strictEqual(defs[0].customizerVersion, '7');
});

test('definitions with no contributor are ignored', () => {
    const xml = `<CustomMetadata>
        <values><field>Table_Code__c</field><value xsi:type="xsd:string">T1</value></values>
    </CustomMetadata>`;
    const defs = parseDefinitions(
        '/x',
        () => xml,
        () => ['Quote_Document_Table_Def.T1.md-meta.xml']
    );
    assert.strictEqual(defs.length, 0);
});

// ---------------------------------------------------------------------------
// The rule itself
// ---------------------------------------------------------------------------

const registry = parseRegistry(GOOD_REGISTRY);

test('changing a customizer class without bumping its version is a violation', () => {
    const violations = findViolations({
        changedFiles: [CLASS('QuoteDocumentDiscountRowCustomizer')],
        registry,
        definitions: [definition()],
        previousTokens: tokensBefore()
    });
    assert.strictEqual(violations.length, 1);
    assert.match(violations[0], /Row_Customizer_Version__c/);
});

test('changing a customizer class AND its version is clean', () => {
    const violations = findViolations({
        changedFiles: [
            CLASS('QuoteDocumentDiscountRowCustomizer'),
            CMDT('Quote_Document_Table_Def.DISCOUNT_EXAMPLE.md-meta.xml')
        ],
        registry,
        definitions: [definition({ customizerVersion: '2' })],
        previousTokens: tokensBefore()
    });
    assert.deepStrictEqual(violations, []);
});

test('changing an unrelated class is clean', () => {
    const violations = findViolations({
        changedFiles: [CLASS('QuoteDocumentRowBuilder')],
        registry,
        definitions: [definition()],
        previousTokens: tokensBefore()
    });
    assert.deepStrictEqual(violations, []);
});

test('editing a contributor Flow without bumping its version is a violation', () => {
    const violations = findViolations({
        changedFiles: [FLOW('QuoteDocumentSampleFlowContributor')],
        registry,
        previousTokens: tokensBefore({
            'Quote_Document_Table_Def.FLOW_CONTRIBUTOR_EXAMPLE.md-meta.xml': {
                customizerVersion: null,
                flowVersion: '1'
            }
        }),
        definitions: [
            definition({
                file: 'Quote_Document_Table_Def.FLOW_CONTRIBUTOR_EXAMPLE.md-meta.xml',
                tableCode: 'FLOW_CONTRIBUTOR_EXAMPLE',
                customizerCode: null,
                customizerVersion: null,
                flowName: 'QuoteDocumentSampleFlowContributor',
                flowVersion: '1'
            })
        ]
    });
    assert.strictEqual(violations.length, 1);
    assert.match(violations[0], /Row_Customizer_Flow_Version__c/);
});

test('a customizer code the registry cannot resolve is a violation, not a skip', () => {
    const violations = findViolations({
        changedFiles: [],
        registry,
        definitions: [definition({ customizerCode: 'RENAMED_AWAY' })],
        previousTokens: tokensBefore()
    });
    assert.strictEqual(violations.length, 1);
    assert.match(violations[0], /does not resolve/);
});

test('a table with both contributors reports each independently', () => {
    const violations = findViolations({
        changedFiles: [
            CLASS('QuoteDocumentDiscountRowCustomizer'),
            FLOW('QuoteDocumentSampleFlowContributor')
        ],
        registry,
        previousTokens: tokensBefore({
            'Quote_Document_Table_Def.DISCOUNT_EXAMPLE.md-meta.xml': {
                customizerVersion: '1',
                flowVersion: '1'
            }
        }),
        definitions: [
            definition({
                flowName: 'QuoteDocumentSampleFlowContributor',
                flowVersion: '1'
            })
        ]
    });
    assert.strictEqual(
        violations.length,
        2,
        'Apex and Flow tokens are separate identities and a build must be told about both.'
    );
});

// ---------------------------------------------------------------------------
// The reviewer's reproduction: changed customizer, changed metadata FILE,
// unchanged token. The gate used to pass this.
// ---------------------------------------------------------------------------

test('a changed metadata file with an UNCHANGED token is still a violation', () => {
    const violations = findViolations({
        // Both files changed, which is what the old file-level check asked for.
        changedFiles: [
            CLASS('QuoteDocumentDiscountRowCustomizer'),
            CMDT('Quote_Document_Table_Def.DISCOUNT_EXAMPLE.md-meta.xml')
        ],
        registry,
        // ...but the token is exactly what it was.
        definitions: [definition({ customizerVersion: '1' })],
        previousTokens: tokensBefore()
    });

    assert.strictEqual(
        violations.length,
        1,
        'Editing the metadata record is not enough. The token is what the fingerprint hashes, so a ' +
            'changed file with a standing token still ships a stale snapshot - and the file-level check ' +
            'called that green.'
    );
    assert.match(violations[0], /still "1"/);
});

test('a genuinely bumped token passes', () => {
    const violations = findViolations({
        changedFiles: [
            CLASS('QuoteDocumentDiscountRowCustomizer'),
            CMDT('Quote_Document_Table_Def.DISCOUNT_EXAMPLE.md-meta.xml')
        ],
        registry,
        definitions: [definition({ customizerVersion: '2' })],
        previousTokens: tokensBefore()
    });
    assert.deepStrictEqual(violations, []);
});

test('an unchanged FLOW token is a violation even when its record was edited', () => {
    const violations = findViolations({
        changedFiles: [
            FLOW('QuoteDocumentSampleFlowContributor'),
            CMDT('Quote_Document_Table_Def.FLOW_CONTRIBUTOR_EXAMPLE.md-meta.xml')
        ],
        registry,
        definitions: [
            definition({
                file: 'Quote_Document_Table_Def.FLOW_CONTRIBUTOR_EXAMPLE.md-meta.xml',
                tableCode: 'FLOW_CONTRIBUTOR_EXAMPLE',
                customizerCode: null,
                customizerVersion: null,
                flowName: 'QuoteDocumentSampleFlowContributor',
                flowVersion: '1'
            })
        ],
        previousTokens: {
            'Quote_Document_Table_Def.FLOW_CONTRIBUTOR_EXAMPLE.md-meta.xml': {
                customizerVersion: null,
                flowVersion: '1'
            }
        }
    });
    assert.strictEqual(violations.length, 1);
    assert.match(violations[0], /Row_Customizer_Flow_Version__c/);
});

test('a record that did not exist at the base is new, not stale', () => {
    const violations = findViolations({
        changedFiles: [CLASS('QuoteDocumentDiscountRowCustomizer')],
        registry,
        definitions: [definition()],
        previousTokens: {}
    });
    assert.deepStrictEqual(
        violations,
        [],
        'A newly added contributor has no previous token to compare against, and treating that as stale ' +
            'would block every first commit of a customizer.'
    );
});
