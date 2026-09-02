# Exports the persisted fixture values, but only once CPQ has stopped changing them.
#
#     pwsh scripts/qdtd/export-fixture-totals.ps1
#
# CPQ recalculates quote lines asynchronously after the insert transaction
# commits. Reading straight after the fixtures load captures values mid-flight:
# two reads of the same rows, with no writes in between, differed on 206 of 331
# lines. So this polls until two consecutive reads agree, and only then writes
# specs/quote-document-test-data/results/fixture-totals.csv.
#
# It never writes to the org.

param(
    [string]$TargetOrg = 'quotedoctotals',
    [int]$MaxAttempts = 12,
    [int]$SettleSeconds = 15
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$exportApex = Join-Path $PSScriptRoot 'export-fixture-totals.apex'
$results = Join-Path $root 'specs/quote-document-test-data/results'
$target = Join-Path $results 'fixture-totals.csv'

function Read-Fixtures {
    $log = sf apex run --target-org $TargetOrg --file $exportApex 2>&1 | Out-String
    $rows = $log -split "`n" |
        Where-Object { $_ -match 'USER_DEBUG' } |
        ForEach-Object { ($_ -replace '.*DEBUG\|CSV&#124;', '').TrimEnd("`r") }
    # A zero-row read means the query never ran - a bad Apex file, or an `sf`
    # that this shell cannot resolve. Treating that as "nothing changed" would
    # silently report a settled snapshot of nothing, so fail loudly instead.
    if ($null -eq $rows -or $rows.Count -eq 0) {
        throw "Export returned no rows. Check that 'sf' is on PATH in THIS shell and that the org alias is correct."
    }
    return $rows
}

$previous = $null
for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    $current = Read-Fixtures
    if ($null -ne $previous) {
        $changed = 0
        for ($i = 0; $i -lt [Math]::Min($previous.Count, $current.Count); $i++) {
            if ($previous[$i] -ne $current[$i]) { $changed++ }
        }
        Write-Output "attempt ${attempt} - $($current.Count) rows, $changed changed since last read"
        if ($changed -eq 0 -and $current.Count -gt 1) {
            $current | Set-Content -Path $target -Encoding utf8
            Write-Output "settled after $attempt reads; wrote $target"
            exit 0
        }
    } else {
        Write-Output "attempt ${attempt} - $($current.Count) rows (baseline)"
    }
    $previous = $current
    Start-Sleep -Seconds $SettleSeconds
}

Write-Output "NOT SETTLED after $MaxAttempts reads - CPQ is still changing these rows."
Write-Output "Not writing ${target} - a moving snapshot would make every derived expectation wrong."
exit 1
