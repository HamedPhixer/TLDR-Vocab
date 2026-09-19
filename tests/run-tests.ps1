<#
  run-tests.ps1 - check Vocab before a release

  1. AutoHotkey's syntax check of Vocab.ahk and everything in lib\ and tools\
  2. tests\Logic.test.ahk   - the rules; no screen, no network
  3. tests\Screen.test.ahk  - real text read back by the real code (needs a
                              desktop; a window of test text shows for a few
                              seconds - do not cover it)

  .\run-tests.ps1                  everything
  .\run-tests.ps1 -NoScreen        only 1 and 2 (what GitHub runs)
  .\run-tests.ps1 -Ahk <path>      a particular AutoHotkey64.exe

  Exit code 0 when everything passed.
#>
param([string]$Ahk = "", [switch]$NoScreen)

$here = $PSScriptRoot
$root = Split-Path $here -Parent

if (-not $Ahk) {
    $candidates = @($env:AHK_EXE,
        "$root\AutoHotkey64.exe",
        "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe",
        "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe")
    $Ahk = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $Ahk -or -not (Test-Path $Ahk)) { Write-Host "AutoHotkey v2 not found - pass -Ahk <path to AutoHotkey64.exe>"; exit 2 }
Write-Host "AutoHotkey: $Ahk"

$failed = 0

# 1. syntax
foreach ($f in @("$root\Vocab.ahk") + (Get-ChildItem "$root\tools\*.ahk" | % FullName)) {
    $p = Start-Process $Ahk -ArgumentList "/Validate /ErrorStdOut `"$f`"" -PassThru -NoNewWindow -Wait -RedirectStandardError "$here\validate.err"
    $err = Get-Content "$here\validate.err" -Raw -ErrorAction SilentlyContinue
    if ($p.ExitCode -eq 0) { Write-Host "PASS syntax: $(Split-Path $f -Leaf)" }
    else { Write-Host "FAIL syntax: $(Split-Path $f -Leaf)`n$err"; $failed++ }
}
Remove-Item "$here\validate.err" -ErrorAction SilentlyContinue

# 2 and 3. the tests
$tests = @("Logic.test.ahk")
if (-not $NoScreen) { $tests += "Screen.test.ahk" }
foreach ($t in $tests) {
    $out = "$here\results-" + ($t -replace "\.ahk$", "") + ".txt"
    Remove-Item $out -ErrorAction SilentlyContinue
    $p = Start-Process $Ahk -ArgumentList "/ErrorStdOut `"$here\$t`"" -PassThru
    if (-not $p.WaitForExit(120000)) { $p.Kill(); Write-Host "FAIL $t : did not finish in 2 minutes"; $failed++; continue }
    if (-not (Test-Path $out)) { Write-Host "FAIL $t : wrote no results"; $failed++; continue }
    $lines = Get-Content $out -Encoding UTF8
    Write-Host "--- $t"
    $lines | Where-Object { $_ -ne "DONE" } | ForEach-Object { Write-Host $_ }
    $failed += ($lines | Where-Object { $_ -like "FAIL*" }).Count
    if ($lines -notcontains "DONE") { Write-Host "FAIL $t : stopped before the end"; $failed++ }
}

Write-Host ""
if ($failed) { Write-Host "$failed FAILED"; exit 1 }
Write-Host "ALL PASSED"; exit 0
