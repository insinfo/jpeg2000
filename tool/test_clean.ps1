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

  The script runs the tests and then deletes entries that match a known
  leftover pattern AND have not been touched for -StaleMinutes. Anything the
  user put in TEMP is left alone, and so is anything a concurrent run is using:
  a live kernel directory is young, so age is what separates a leftover from
  work in progress.

  It deliberately does NOT delete "whatever appeared during this run". A run
  that finishes normally leaves nothing behind, so there is nothing to collect;
  what appears during a run may well belong to a *concurrent* run, and deleting
  it breaks that one with `Failed to load ... dart_test.kernel.<hash>`. That
  happened, which is why the rule is age and only age.

  The exit code is the test runner's, so this is a drop-in replacement for
  `dart test` in scripts and in CI.

.PARAMETER TestArgs
  Arguments forwarded to `dart test`. Defaults to none, i.e. the whole suite.

.PARAMETER StaleMinutes
  Only remove leftovers untouched for this many minutes. Default 30. A live
  run keeps writing to its own directories, so this is what keeps a concurrent
  run safe. Setting it to 0 disables cleaning entirely.

.PARAMETER CleanOnly
  Clean and exit without running tests.

.EXAMPLE
  pwsh tool/test_clean.ps1
  pwsh tool/test_clean.ps1 -TestArgs '-j1','test/render'
  pwsh tool/test_clean.ps1 -CleanOnly
  pwsh tool/test_clean.ps1 -CleanOnly -StaleMinutes 5   # more aggressive
#>
[CmdletBinding()]
param(
  [string[]] $TestArgs = @(),
  [int] $StaleMinutes = 30,
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

$exitCode = 0
if (-not $CleanOnly) {
  Write-Host "dart test $($TestArgs -join ' ')" -ForegroundColor Cyan
  & dart test @TestArgs
  $exitCode = $LASTEXITCODE
}

# `dart_test.kernel.<hash>` is content-addressed, so a run REUSES a directory
# created long ago and only reads from it: old creation time, old write time,
# and in use right now. Age cannot tell that apart. So while any `dart test` is
# running -- here or in another checkout -- nothing is removed at all. Deleting
# a live kernel directory breaks that run with
# `Failed to load ... dart_test.kernel.<hash>`, which is how this was found.
$live = @(Get-CimInstance Win32_Process -Filter "Name='dart.exe'" -ErrorAction SilentlyContinue |
          Where-Object { $_.CommandLine -match 'test' })
if ($live.Count -gt 0) {
  Write-Host "TEMP: $($live.Count) test run(s) still active, skipping cleanup." -ForegroundColor DarkYellow
  $StaleMinutes = 0
}

$toRemove = @()
if ($StaleMinutes -gt 0) {
  $cutoff = (Get-Date).AddMinutes(-$StaleMinutes)
  foreach ($i in (Get-Leftovers)) {
    # Both timestamps: a directory whose contents are still being written has a
    # recent LastWriteTime even when it was created long ago.
    $lastTouch = $i.LastWriteTime
    if ($i.CreationTime -gt $lastTouch) { $lastTouch = $i.CreationTime }
    if ($lastTouch -lt $cutoff) { $toRemove += $i }
  }
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
