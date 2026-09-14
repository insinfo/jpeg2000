<#
.SYNOPSIS
  Runs `dart test` and removes the temporary files the run leaves behind.

.DESCRIPTION
  Every `dart test` invocation writes a `dart_test.kernel.<hash>` directory
  holding the compiled kernel for the package, plus `dart_test.vm.<hash>` for
  the VM service. They are never cleaned up. On a package the size of this one
  each is hundreds of megabytes, and a day of iterating fills the disk: this
  script exists because the system drive hit zero bytes free with more than
  20 GB of leftovers in TEMP.

  Browser automation adds its own: each launched Chromium, Firefox or WebKit
  gets a profile directory under TEMP, and a crashed or killed browser never
  removes it. Those are small individually and arrive by the hundred.

  The script snapshots TEMP before the run, runs the tests, and then deletes
  only entries that (a) match a known leftover pattern, and (b) did not exist
  before the run, or are older than -StaleMinutes. Anything the user put in
  TEMP, and anything a concurrent run is still using, is left alone.

  The exit code is the test runner's, so this is a drop-in replacement for
  `dart test` in scripts and in CI.

.PARAMETER TestArgs
  Arguments forwarded to `dart test`. Defaults to none, i.e. the whole suite.

.PARAMETER StaleMinutes
  Also remove matching leftovers older than this, from runs that died without
  cleaning up. Default 120. Use 0 to only remove what this run created.

.PARAMETER CleanOnly
  Clean and exit without running tests.

.EXAMPLE
  pwsh tool/test_clean.ps1
  pwsh tool/test_clean.ps1 -TestArgs '-j1','test/render'
  pwsh tool/test_clean.ps1 -CleanOnly
#>
[CmdletBinding()]
param(
  [string[]] $TestArgs = @(),
  [int] $StaleMinutes = 120,
  [switch] $CleanOnly
)

$ErrorActionPreference = 'Stop'

# Only these are ever deleted. Being conservative here is the whole point: a
# pattern that is too broad turns a disk-space script into a data-loss script.
$patterns = @(
  'dart_test.kernel.*',
  'dart_test.vm.*',
  'playwright_*',
  'playwright-*'
)

$temp = [System.IO.Path]::GetTempPath()

function Get-Leftovers {
  $found = @()
  foreach ($p in $patterns) {
    $found += Get-ChildItem -LiteralPath $temp -Filter $p -Force -ErrorAction SilentlyContinue
  }
  return $found
}

function Measure-SizeGB($items) {
  $bytes = 0
  foreach ($i in $items) {
    try {
      if ($i.PSIsContainer) {
        $bytes += (Get-ChildItem -LiteralPath $i.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                   Measure-Object -Property Length -Sum).Sum
      } else {
        $bytes += $i.Length
      }
    } catch { }
  }
  return [math]::Round(($bytes / 1GB), 2)
}

$before = @{}
foreach ($i in (Get-Leftovers)) { $before[$i.FullName] = $true }

$exitCode = 0
if (-not $CleanOnly) {
  Write-Host "dart test $($TestArgs -join ' ')" -ForegroundColor Cyan
  & dart test @TestArgs
  $exitCode = $LASTEXITCODE
}

$cutoff = (Get-Date).AddMinutes(-$StaleMinutes)
$toRemove = @()
foreach ($i in (Get-Leftovers)) {
  $isNew = -not $before.ContainsKey($i.FullName)
  $isStale = ($StaleMinutes -gt 0) -and ($i.CreationTime -lt $cutoff)
  if ($isNew -or $isStale) { $toRemove += $i }
}

if ($toRemove.Count -eq 0) {
  Write-Host "TEMP: nothing to clean." -ForegroundColor DarkGray
} else {
  $sizeGB = Measure-SizeGB $toRemove
  $removed = 0
  foreach ($i in $toRemove) {
    try {
      Remove-Item -LiteralPath $i.FullName -Recurse -Force -ErrorAction Stop
      $removed++
    } catch {
      # A directory a concurrent run still holds open stays. That is correct:
      # the next invocation will pick it up once it is released.
    }
  }
  $held = $toRemove.Count - $removed
  $msg = "TEMP: removed $removed of $($toRemove.Count) leftovers (~$sizeGB GB)"
  if ($held -gt 0) { $msg += "; $held still in use, left alone" }
  Write-Host $msg -ForegroundColor Green
}

$free = [math]::Round((Get-PSDrive ($temp.Substring(0,1))).Free / 1GB, 2)
Write-Host "Free on $($temp.Substring(0,2)) $free GB" -ForegroundColor DarkGray

exit $exitCode
