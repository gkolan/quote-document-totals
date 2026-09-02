# Deactivates every TDX_* table definition, unconditionally, and VERIFIES it.
#
#     pwsh -File scripts/qdtd/deactivate-all.ps1
#
# Safe at any time. Run it if a matrix run was interrupted, or if anything looks
# wrong: an active-but-broken definition breaks generation for every quote in the
# org, because QuoteDocumentTableDefinition.getAll() validates every active
# record in one pass.
#
# The verification query at the end is the point. A `finally` cannot survive a
# killed process, and repository state cannot prove org state - only a live query
# can say whether anything is still active.

param([string]$TargetOrg = 'quotedoctotals')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

python (Join-Path $PSScriptRoot 'gen-defs.py') | Out-Null
sf project deploy start --target-org $TargetOrg --source-dir (Join-Path $root 'force-app/main/default/customMetadata') --wait 30 2>&1 | Out-Null

$active = (sf data query --target-org $TargetOrg -q "SELECT Id FROM Quote_Document_Table_Def__mdt WHERE Table_Code__c LIKE 'TDX%' AND Is_Active__c = true" --json | ConvertFrom-Json).result.totalSize
Write-Output "active TDX definitions remaining: $active"

if ($active -ne 0) {
    Write-Output "STILL ACTIVE - this is an incident, not something to retry silently."
    exit 1
}
Write-Output "verified: nothing from the permutation set is active in $TargetOrg"
