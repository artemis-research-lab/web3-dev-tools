#requires -Version 5.1
# scripts/release.ps1 -- regenerate src/MANIFEST.sha256 and check VERSION.
# Prints the tag command; never tags, never pushes.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\release.ps1
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$src = Join-Path $repo "src"
$manifest = Join-Path $src "MANIFEST.sha256"

$version = ([System.IO.File]::ReadAllText((Join-Path $src "VERSION"))).Trim()
$rootVersion = ([System.IO.File]::ReadAllText((Join-Path $repo "VERSION"))).Trim()
if ($version -ne $rootVersion) {
  Write-Host "ERROR: VERSION ($rootVersion) does not match src/VERSION ($version)" -ForegroundColor Red
  exit 1
}

$entries = @()
foreach ($f in Get-ChildItem -LiteralPath $src -Recurse -File) {
  $rel = $f.FullName.Substring($src.Length).TrimStart('\', '/').Replace('\', '/')
  if ($rel -eq "MANIFEST.sha256") { continue }
  $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  $entries += New-Object PSObject -Property @{ Rel = $rel; Hash = $hash }
}
$rels = [string[]]($entries | ForEach-Object { $_.Rel })
[System.Array]::Sort($rels, [System.StringComparer]::Ordinal)
$lines = foreach ($r in $rels) { $e = $entries | Where-Object { $_.Rel -eq $r }; "$($e.Hash) $r" }
$text = ($lines -join "`n") + "`n"
[System.IO.File]::WriteAllText($manifest, $text, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "OK wrote src/MANIFEST.sha256 ($($rels.Count) files) for version $version"
Write-Host $text.TrimEnd()
Write-Host ""
Write-Host "Tag command (not run):"
Write-Host "  git tag -a v$version -m `"web3-dev-tools v$version`""
exit 0
