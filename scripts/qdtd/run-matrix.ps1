# Runs the permutation matrix, one activation slice at a time.
#
#     pwsh -File scripts/qdtd/run-matrix.ps1        (from a shell where `sf` resolves)
#
# Why slices, and why some definitions run alone:
#
#   * QuoteDocumentTableDefinition.getAll() loads EVERY active definition in one
#     pass, so activation is a global mutation. Only the slice under test is ever
#     active; everything else is deactivated in the same deploy.
#   * A generation throw rolls back the whole quote's output. Any definition
#     whose expectations.csv predicts a runtime failure on any quote therefore
#     runs ALONE, so its throw cannot destroy another definition's results.
#
# Teardown is not left to a `finally`: a killed process would leave TDX
# definitions active. The run ends by regenerating every file inactive and
# deploying that, and the caller must then verify with a live query - see
# step 05. `scripts/qdtd/deactivate-all.ps1` does the same thing on demand.

param(
    # Re-run a subset: -Codes for specific definitions, -Quotes for specific
    # quote numbers. Used to fill in rows lost to a transient org error without
    # repeating the whole 33-slice run, and to attribute a batched failure.
    [string[]]$Codes,
    [int[]]$Quotes,
    [switch]$MergeLedger,
    [string]$TargetOrg = 'quotedoctotals',
    [int]$BatchSize = 11,
    [int]$QuoteChunk = 5,
    [switch]$SkipDeactivateAtEnd
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$results = Join-Path $root 'specs/quote-document-test-data/results'
$metadataDir = Join-Path $root 'force-app/main/default/customMetadata'
$template = Get-Content (Join-Path $PSScriptRoot 'run-slice.apex.template') -Raw
$sliceApex = Join-Path $PSScriptRoot 'run-slice.generated.apex'
$ledgerPath = Join-Path $results 'ledger.csv'

$matrix = Import-Csv (Join-Path $results 'matrix.csv')
$expectations = Import-Csv (Join-Path $results 'expectations.csv')

# Definitions predicted to fail at runtime on at least one quote run alone -
# and so does every definition carrying a contributor.
#
# The first full run showed why the second half matters: TDX_051's discount
# customizer threw a verification error nobody predicted, and because it shared a
# slice, TDX_045-TDX_055 were all recorded as ERROR with TDX_051's message. A
# throw rolls back the whole quote, so an UNPREDICTED failure poisons its
# slice-mates just as thoroughly as a predicted one. Contributors are where
# unpredicted throws come from, so they are isolated by construction.
$soloCodes = @()
$soloCodes += $expectations | Where-Object { $_.expect -like 'ERROR*' } | Select-Object -ExpandProperty table_code
$soloCodes += $matrix | Where-Object { $_.row_customizer_code -or $_.row_customizer_flow } | Select-Object -ExpandProperty table_code
$soloCodes = $soloCodes | Select-Object -Unique

if ($Codes) {
    $matrix = $matrix | Where-Object { $Codes -contains $_.table_code }
    $soloCodes = $matrix.table_code    # a targeted re-run always runs solo
}
$batchCodes = $matrix.table_code | Where-Object { $soloCodes -notcontains $_ }

$slices = @()
foreach ($code in $soloCodes) { $slices += , @($code) }
for ($i = 0; $i -lt $batchCodes.Count; $i += $BatchSize) {
    $slices += , @($batchCodes[$i..([Math]::Min($i + $BatchSize - 1, $batchCodes.Count - 1))])
}

Write-Output "$($matrix.Count) definitions: $($soloCodes.Count) solo (predicted runtime failure), $($batchCodes.Count) batched into $($slices.Count - $soloCodes.Count) slices"
Write-Output "$($slices.Count) activation cycles total"

function Set-ActiveDefinitions([string[]]$active) {
    # Regenerate every TDX file inactive, then flip just this slice on. Writing
    # the whole set each time is what guarantees the previous slice is off.
    python (Join-Path $PSScriptRoot 'gen-defs.py') | Out-Null
    foreach ($code in $active) {
        $file = Join-Path $metadataDir "Quote_Document_Table_Def.$code.md-meta.xml"
        $xml = Get-Content $file -Raw
        $xml = $xml -replace '(?s)(<field>Is_Active__c</field>\s*<value xsi:type="xsd:boolean">)false(</value>)', '${1}true${2}'
        Set-Content -Path $file -Value $xml -Encoding utf8
    }
    sf project deploy start --target-org $TargetOrg --source-dir $metadataDir --wait 30 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Deploy failed while activating: $($active -join ', ')" }
}

$ledger = @('table_code,quote_key,outcome,group_count,row_count,depth,detail')
$existing = @{}
if ($MergeLedger -and (Test-Path $ledgerPath)) {
    # Keep every row this targeted run is NOT about, so a re-run fills gaps
    # instead of replacing the ledger with a fragment.
    Import-Csv $ledgerPath | ForEach-Object {
        $existing["$($_.table_code)|$($_.quote_key)"] = "$($_.table_code),$($_.quote_key),$($_.outcome),$($_.group_count),$($_.row_count),$($_.depth),$($_.detail)"
    }
}

for ($s = 0; $s -lt $slices.Count; $s++) {
    $slice = $slices[$s]
    $label = if ($slice.Count -eq 1) { "$($slice[0]) (solo)" } else { "$($slice.Count) definitions" }
    Write-Output "slice $($s + 1)/$($slices.Count): $label"

    Set-ActiveDefinitions $slice

    $codeLiterals = ($slice | ForEach-Object { "'$_'" }) -join ', '
    $sliceRows = 0

    # Chunked for the same governor-limit reason the template explains.
    $quoteNumbers = if ($Quotes) { $Quotes } else { 1..19 }
    for ($i = 0; $i -lt $quoteNumbers.Count; $i += $QuoteChunk) {
        $chunk = @()
        foreach ($n in $quoteNumbers[$i..([Math]::Min($i + $QuoteChunk - 1, $quoteNumbers.Count - 1))]) {
            $chunk += "'QDTD-Q$n'"
        }

        $apex = $template -replace '__SLICE_CODES__', $codeLiterals
        $apex = $apex -replace '__QUOTE_KEYS__', ($chunk -join ', ')
        $apex | Set-Content -Path $sliceApex -Encoding utf8

        # Retried once. Salesforce returned a transient UNKNOWN_EXCEPTION on three
        # separate runs, each time losing a whole chunk - and a lost chunk is
        # silent here, showing up only as "expectations with no ledger row" in
        # the checker afterwards. One retry turns the common case into a hiccup
        # instead of a re-run of the entire matrix.
        $lines = @()
        foreach ($attempt in 1..2) {
            $log = sf apex run --target-org $TargetOrg --file $sliceApex 2>&1 | Out-String
            $lines = $log -split "`n" |
                Where-Object { $_ -match 'DEBUG\|LEDGER&#124;' } |
                ForEach-Object { ($_ -replace '.*DEBUG\|LEDGER&#124;', '').TrimEnd("`r") -replace '&#124;', ',' }
            if ($lines.Count -gt 0) { break }
            if ($attempt -eq 1) {
                Write-Output "  chunk $q returned nothing, retrying once"
                Start-Sleep -Seconds 5
            }
        }

        if ($lines.Count -eq 0) {
            Write-Output "  WARNING: chunk $q returned no ledger rows after a retry:"
            ($log -split "`n" | Where-Object { $_ -match 'System\.|Error \(' } | Select-Object -First 1)
        } else {
            $ledger += $lines
            $sliceRows += $lines.Count
        }
    }
    Write-Output "  $sliceRows ledger rows"

    if ($MergeLedger) {
        foreach ($line in $ledger | Select-Object -Skip 1) {
            $parts = $line -split ',', 3
            $existing["$($parts[0])|$($parts[1])"] = $line
        }
        $merged = @('table_code,quote_key,outcome,group_count,row_count,depth,detail')
        $merged += ($existing.Values | Sort-Object)
        $merged | Set-Content -Path $ledgerPath -Encoding utf8
    } else {
        $ledger | Set-Content -Path $ledgerPath -Encoding utf8
    }
}

if (-not $SkipDeactivateAtEnd) {
    Write-Output "deactivating every TDX definition"
    python (Join-Path $PSScriptRoot 'gen-defs.py') | Out-Null
    sf project deploy start --target-org $TargetOrg --source-dir $metadataDir --wait 30 2>&1 | Out-Null
    $active = (sf data query --target-org $TargetOrg -q "SELECT Id FROM Quote_Document_Table_Def__mdt WHERE Table_Code__c LIKE 'TDX%' AND Is_Active__c = true" --json | ConvertFrom-Json).result.totalSize
    Write-Output "VERIFIED active TDX definitions remaining: $active (must be 0)"
}

Write-Output "wrote $ledgerPath ($($ledger.Count - 1) rows)"
