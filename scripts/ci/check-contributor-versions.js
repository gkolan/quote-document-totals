#!/usr/bin/env node
/**
 * Step 01A section 10 - the contributor version gate.
 *
 * Nothing in the platform can see an Apex body or a Flow definition change.
 * The fingerprint hashes Row_Customizer_Version__c and
 * Row_Customizer_Flow_Version__c instead, so a contributor whose LOGIC
 * changed under an unchanged version token leaves the fingerprint identical,
 * quotes stay Ready, and generation reuses a snapshot the new logic would
 * never have produced. That is a wrong document, not a hygiene problem.
 *
 * Bumping the token is therefore an operational discipline, and this gate is
 * the only thing that enforces it. It compares changed files against the
 * merge base and fails the build when a customizer class or contributor Flow
 * moved without its token moving with it.
 *
 * EVERYTHING HERE FAILS THE BUILD. Nothing warns. A gate that warns is a gate
 * that gets scrolled past, and the failure it is guarding against is silent
 * by construction - there is no second chance to notice it.
 *
 * Exit codes: 0 clean, 1 violations found, 2 the gate itself could not run
 * (which is also a build failure - a gate that cannot run has not passed).
 */

'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const CMDT_DIR = path.join(REPO_ROOT, 'force-app', 'main', 'default', 'customMetadata');
const CLASS_DIR = path.join(REPO_ROOT, 'force-app', 'main', 'default', 'classes');
const FLOW_DIR = path.join(REPO_ROOT, 'force-app', 'main', 'default', 'flows');
const REGISTRY = path.join(CLASS_DIR, 'QuoteDocumentRowCustomizerRegistry.cls');

class GateError extends Error {}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

/** Reads one <values><field>X</field><value ...>Y</value></values> pair. */
function cmdtValue(xml, field) {
    const pattern = new RegExp(
        '<field>' + field + '</field>\\s*<value[^>]*>([\\s\\S]*?)</value>'
    );
    const match = xml.match(pattern);
    return match ? match[1].trim() : null;
}

/**
 * code -> Apex class name, from the registry's switch.
 *
 * Deliberately strict about the shape it accepts. A `when` branch this regex
 * cannot read is not skipped - skipping is how a gate silently stops covering
 * the one contributor someone reformatted. It is reported, and the build
 * fails. The cases that must not slip through, per section 10: multiline
 * branches, commented-out branches, and a reformatted registry.
 */
function parseRegistry(source) {
    if (!source || !source.includes('switch on')) {
        throw new GateError(
            'QuoteDocumentRowCustomizerRegistry.cls has no switch statement. Either the registry moved or ' +
                'this gate is parsing the wrong file - both mean the gate is no longer checking anything.'
        );
    }

    const mapping = new Map();
    const unreadable = [];

    // Strip block comments first so a commented-out branch cannot be read as
    // live. Line comments are handled per line below, where the distinction
    // between "commented out" and "unreadable" still matters.
    const withoutBlockComments = source.replace(/\/\*[\s\S]*?\*\//g, '');
    const lines = withoutBlockComments.split(/\r?\n/);

    for (const raw of lines) {
        const line = raw.trim();
        if (line.startsWith('//')) {
            continue;
        }
        if (!/^when\b/.test(line)) {
            continue;
        }
        if (/^when\s+else\b/.test(line)) {
            continue;
        }

        const match = line.match(/^when\s+'([^']+)'\s*\{\s*return\s+new\s+([A-Za-z0-9_]+)\s*\(\s*\)\s*;\s*\}/);
        if (!match) {
            // A branch that opens here and closes on a later line, or one
            // written in a shape this gate does not know. Never skipped.
            unreadable.push(line);
            continue;
        }
        mapping.set(match[1], match[2]);
    }

    if (unreadable.length > 0) {
        throw new GateError(
            'These registry branches could not be parsed, so the gate cannot tell which class they map to:\n' +
                unreadable.map((l) => '    ' + l).join('\n') +
                '\nKeep each branch on one line as `when \'CODE\' { return new ClassName(); }`, or update ' +
                'this gate to understand the new shape. Skipping them would leave a contributor unguarded.'
        );
    }

    if (mapping.size === 0) {
        throw new GateError(
            'Parsed zero customizer codes from the registry. That is almost certainly a parsing failure ' +
                'rather than a registry with no entries, and a gate that checks nothing must not report success.'
        );
    }

    return mapping;
}

/** Every table definition that names a contributor, with its declared version tokens. */
function parseDefinitions(dir, readFile, listFiles) {
    const files = listFiles(dir).filter(
        (f) => f.startsWith('Quote_Document_Table_Def.') && f.endsWith('.md-meta.xml')
    );

    if (files.length === 0) {
        throw new GateError(
            'Found no Quote_Document_Table_Def__mdt records under ' + dir + '. The gate cannot map a ' +
                'changed contributor back to the token that must be bumped.'
        );
    }

    const definitions = [];
    for (const file of files) {
        const xml = readFile(path.join(dir, file));
        const code = cmdtValue(xml, 'Row_Customizer_Code__c');
        const flow = cmdtValue(xml, 'Row_Customizer_Flow__c');
        if (!code && !flow) {
            continue;
        }
        definitions.push({
            file,
            tableCode: cmdtValue(xml, 'Table_Code__c'),
            customizerCode: code,
            customizerVersion: cmdtValue(xml, 'Row_Customizer_Version__c'),
            flowName: flow,
            flowVersion: cmdtValue(xml, 'Row_Customizer_Flow_Version__c')
        });
    }
    return definitions;
}

// ---------------------------------------------------------------------------
// The rule
// ---------------------------------------------------------------------------

/**
 * Pure, so the suite can drive it without a git repository.
 *
 * changedFiles: repo-relative paths changed since the merge base.
 */
function findViolations({ changedFiles, registry, definitions }) {
    const violations = [];
    const changed = new Set(changedFiles);

    const classChanged = (className) =>
        changed.has('force-app/main/default/classes/' + className + '.cls');
    const flowChanged = (flowName) =>
        changed.has('force-app/main/default/flows/' + flowName + '.flow-meta.xml');
    const definitionChanged = (file) =>
        changed.has('force-app/main/default/customMetadata/' + file);

    for (const definition of definitions) {
        if (definition.customizerCode) {
            const className = registry.get(definition.customizerCode);
            if (!className) {
                violations.push(
                    definition.tableCode +
                        ' names Row_Customizer_Code__c "' + definition.customizerCode +
                        '", which the registry does not resolve. Either the code was renamed and the ' +
                        'metadata was not updated, or the registry branch was removed. Generation would ' +
                        'fail at runtime, and until then this contributor is outside the version gate.'
                );
            } else if (classChanged(className) && !definitionChanged(definition.file)) {
                violations.push(
                    className + '.cls changed but ' + definition.file + ' did not, so ' +
                        'Row_Customizer_Version__c for table ' + definition.tableCode + ' is still "' +
                        definition.customizerVersion + '". The fingerprint cannot see an Apex body change, ' +
                        'so quotes using this table stay Ready and reuse a snapshot the new logic would ' +
                        'not have produced. Bump the version and run the step 05 invalidation job.'
                );
            }
        }

        if (definition.flowName) {
            if (flowChanged(definition.flowName) && !definitionChanged(definition.file)) {
                violations.push(
                    definition.flowName + '.flow-meta.xml changed but ' + definition.file + ' did not, so ' +
                        'Row_Customizer_Flow_Version__c for table ' + definition.tableCode + ' is still "' +
                        definition.flowVersion + '". Editing a Flow does not change its API name, so the ' +
                        'fingerprint cannot see the change. Bump the version and run the step 05 ' +
                        'invalidation job.'
                );
            }
        }
    }

    return violations;
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function changedFilesSince(base) {
    let mergeBase;
    try {
        mergeBase = execFileSync('git', ['merge-base', base, 'HEAD'], {
            cwd: REPO_ROOT,
            encoding: 'utf8'
        }).trim();
    } catch (e) {
        throw new GateError(
            'Could not resolve a merge base against "' + base + '". Without it the gate has no idea what ' +
                'changed, and a gate that cannot run has not passed. In CI, fetch the base branch first ' +
                '(actions/checkout defaults to a shallow clone). Underlying error: ' + e.message
        );
    }

    const output = execFileSync('git', ['diff', '--name-only', mergeBase, 'HEAD'], {
        cwd: REPO_ROOT,
        encoding: 'utf8'
    });
    return output.split(/\r?\n/).filter(Boolean);
}

function main(argv) {
    const baseArg = argv.indexOf('--base');
    const base = baseArg === -1 ? 'origin/master' : argv[baseArg + 1];

    if (!fs.existsSync(REGISTRY)) {
        throw new GateError(
            'QuoteDocumentRowCustomizerRegistry.cls not found at ' + REGISTRY + '. The gate cannot map ' +
                'customizer codes to classes.'
        );
    }

    const registry = parseRegistry(fs.readFileSync(REGISTRY, 'utf8'));
    const definitions = parseDefinitions(
        CMDT_DIR,
        (p) => fs.readFileSync(p, 'utf8'),
        (d) => fs.readdirSync(d)
    );
    const changedFiles = changedFilesSince(base);
    const violations = findViolations({ changedFiles, registry, definitions });

    if (violations.length > 0) {
        console.error('Contributor version gate FAILED:\n');
        violations.forEach((v, i) => console.error('  ' + (i + 1) + '. ' + v + '\n'));
        console.error(
            'If this is an emergency deployment, the only supported way past this gate is to record a ' +
                'manual invalidation run - not to skip the gate and fix it later. The document is already ' +
                'wrong by the time anyone notices.'
        );
        return 1;
    }

    console.log(
        'Contributor version gate passed: ' + registry.size + ' registry codes, ' +
            definitions.length + ' contributor table definitions, ' + changedFiles.length +
            ' changed files since ' + base + '.'
    );
    return 0;
}

if (require.main === module) {
    try {
        process.exit(main(process.argv.slice(2)));
    } catch (e) {
        if (e instanceof GateError) {
            console.error('Contributor version gate COULD NOT RUN:\n\n  ' + e.message);
            process.exit(2);
        }
        throw e;
    }
}

module.exports = { parseRegistry, parseDefinitions, findViolations, cmdtValue, GateError, FLOW_DIR };
