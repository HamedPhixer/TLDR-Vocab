<#
  build.ps1 - make the two downloads into dist\

    TLDR-Vocab-<version>.zip            the app, for people with AutoHotkey v2
    TLDR-Vocab-<version>-portable.zip   the same plus AutoHotkey64.exe, its
                                        licence and "Start TLDR Vocab.bat"
    manifest.json                       every file of the app with its size and
                                        SHA-256 - for an update check later
    notes.md                            this version's section of CHANGELOG.md,
                                        the release notes

  The version comes from VocabVersion in lib\Config.ahk. On GitHub the tag
  that started the build must match it (v1.2.0 for "1.2.0"), or nothing is
  built - a release can never carry the wrong number.

  .\build.ps1 -AhkDir <folder with AutoHotkey64.exe and its license.txt>
#>
param([Parameter(Mandatory = $true)][string]$AhkDir)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$dist = Join-Path $root "dist"

$m = Select-String -Path (Join-Path $root "lib\Config.ahk") -Pattern 'VocabVersion := "([^"]+)"'
if (-not $m) { throw "VocabVersion not found in lib\Config.ahk" }
$version = $m.Matches[0].Groups[1].Value
if ($env:GITHUB_REF_NAME -and $env:GITHUB_REF_NAME -like "v*" -and $env:GITHUB_REF_NAME -ne "v$version") {
    throw "Tag $($env:GITHUB_REF_NAME) does not match VocabVersion $version in lib\Config.ahk"
}

# the release notes: this version's section of CHANGELOG.md, from its "## "
# heading to the next one. A version without notes is not built.
$log = Get-Content (Join-Path $root "CHANGELOG.md") -Encoding UTF8
$start = -1
for ($i = 0; $i -lt $log.Count; $i++) { if ($log[$i] -match "^## \[?$([regex]::Escape($version))\]?(\s|$)") { $start = $i; break } }
if ($start -lt 0) { throw "CHANGELOG.md has no section for $version" }
$end = $log.Count
for ($i = $start + 1; $i -lt $log.Count; $i++) { if ($log[$i] -match "^## ") { $end = $i; break } }
$notes = ($log[($start + 1)..($end - 1)] -join "`n").Trim()

$exe = Join-Path $AhkDir "AutoHotkey64.exe"
$lic = @("license.txt", "AutoHotkey license.txt") | % { Join-Path $AhkDir $_ } | ? { Test-Path $_ } | Select-Object -First 1
if (-not (Test-Path $exe)) { throw "No AutoHotkey64.exe in $AhkDir" }
if (-not $lic) { throw "No AutoHotkey licence (license.txt) in $AhkDir" }

if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory $dist | Out-Null
[IO.File]::WriteAllText((Join-Path $dist "notes.md"), $notes + "`n", (New-Object Text.UTF8Encoding $false))
$stage = Join-Path $dist "stage\TLDR Vocab"
New-Item -ItemType Directory -Force (Join-Path $stage "lib") | Out-Null

# the app: what a user needs, nothing of tests\, tools\ or docs\
Copy-Item (Join-Path $root "Vocab.ahk"), (Join-Path $root "dictionary.png"), (Join-Path $root "README.md"), (Join-Path $root "LICENSE") $stage
Copy-Item (Join-Path $root "lib\*.ahk") (Join-Path $stage "lib")

# manifest, before the portable extras are added
$files = Get-ChildItem $stage -Recurse -File | Sort-Object FullName | ForEach-Object {
    [ordered]@{
        path   = $_.FullName.Substring($stage.Length + 1).Replace("\", "/")
        size   = $_.Length
        sha256 = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
    }
}
[ordered]@{ name = "TLDR Vocab"; version = $version; files = @($files) } |
    ConvertTo-Json -Depth 4 | Set-Content (Join-Path $dist "manifest.json") -Encoding UTF8

$plain = Join-Path $dist "TLDR-Vocab-$version.zip"
Compress-Archive -Path $stage -DestinationPath $plain

Copy-Item $exe $stage
Copy-Item $lic (Join-Path $stage "AutoHotkey license.txt")
Copy-Item (Join-Path $root "portable\Start TLDR Vocab.bat") $stage
$portable = Join-Path $dist "TLDR-Vocab-$version-portable.zip"
Compress-Archive -Path $stage -DestinationPath $portable

Remove-Item (Join-Path $dist "stage") -Recurse -Force
Get-ChildItem $dist | ForEach-Object { "{0,-40} {1,10:N0} bytes" -f $_.Name, $_.Length }
