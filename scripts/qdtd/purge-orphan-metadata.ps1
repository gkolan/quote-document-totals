# Deletes TDX_* custom metadata records that exist in the org but not in source.
#
#     pwsh -File scripts/qdtd/purge-orphan-metadata.ps1
#
# A source deploy CREATES and UPDATES metadata records; it never deletes the ones
# the source no longer contains. When a definition's grouping set shrinks - say
# from five nesting levels to one - the four extra Quote_Document_Grouping__mdt
# records stay behind and keep applying. The table then nests five deep in the
# org while source says one, and nothing reports a problem.
#
# That is not hypothetical: it produced a table with 63 groups and depth 5 from a
# single-level definition, and the only reason it surfaced was the ledger's depth
# check comparing reported depth against configured depth.
#
# Run this after any regeneration that removes groupings, before the matrix run.

param([string]$TargetOrg = 'quotedoctotals')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$metadataDir = Join-Path $root 'force-app/main/default/customMetadata'
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("qdtd-purge-" + [guid]::NewGuid().ToString('N').Substring(0, 8))

$inSource = @{}
Get-ChildItem $metadataDir -Filter 'Quote_Document_*.TDX_*.md-meta.xml' | ForEach-Object {
    $inSource[($_.Name -replace '\.md-meta\.xml$', '')] = $true
}

$orphans = @()
foreach ($type in @('Quote_Document_Grouping', 'Quote_Document_Table_Def')) {
    $object = if ($type -eq 'Quote_Document_Grouping') { 'Quote_Document_Grouping__mdt' } else { 'Quote_Document_Table_Def__mdt' }
    $names = (sf data query --target-org $TargetOrg -q "SELECT DeveloperName FROM $object WHERE DeveloperName LIKE 'TDX%'" --json | ConvertFrom-Json).result.records.DeveloperName
    foreach ($name in $names) {
        $full = "$type.$name"
        if (-not $inSource.ContainsKey($full)) { $orphans += $full }
    }
}

if ($orphans.Count -eq 0) {
    Write-Output "no orphaned TDX metadata records - org matches source"
    exit 0
}

Write-Output "orphaned records to delete ($($orphans.Count)):"
$orphans | ForEach-Object { Write-Output "   $_" }

New-Item -ItemType Directory -Path $work -Force | Out-Null
@'
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <version>62.0</version>
</Package>
'@ | Set-Content (Join-Path $work 'package.xml') -Encoding utf8

$members = ($orphans | ForEach-Object { "        <members>$_</members>" }) -join "`n"
@"
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
$members
        <name>CustomMetadata</name>
    </types>
    <version>62.0</version>
</Package>
"@ | Set-Content (Join-Path $work 'destructiveChangesPost.xml') -Encoding utf8

sf project deploy start --target-org $TargetOrg --metadata-dir $work --wait 30
if ($LASTEXITCODE -ne 0) { throw "destructive deploy failed" }

$remaining = (sf data query --target-org $TargetOrg -q "SELECT Id FROM Quote_Document_Grouping__mdt WHERE DeveloperName LIKE 'TDX%'" --json | ConvertFrom-Json).result.totalSize
$expected = (Get-ChildItem $metadataDir -Filter 'Quote_Document_Grouping.TDX_*').Count
Write-Output "groupings now in org: $remaining   in source: $expected"
if ($remaining -ne $expected) { Write-Output "STILL MISMATCHED"; exit 1 }
Write-Output "org matches source"
