# tools/deploy.ps1 -- run from repo root: .\tools\deploy.ps1 -Both
param([switch]$Both, [switch]$ClaudeCode, [switch]$ClaudeAi)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$name = Split-Path -Leaf $repo
$skillDst = Join-Path $env:USERPROFILE ".claude\skills\$name"
$distZip  = Join-Path $repo "dist\$name.zip"

# ALLOWLIST -- only these ship, in either output, regardless of what else exists
# in the repo (.env, .claude/, tests/, handoff_specs/, pytest.ini, .git*, etc.
# never ship because they are never listed here -- not because something else
# blocks them). Fixed 2026-09 after amm-pool-monitor's .env leak (the old
# $EXCLUDE blocklist required remembering to add every new sensitive file
# type, and that failed in practice -- a live .env with API keys shipped in
# both the synced skill folder and the distributable zip). Adding a new
# shippable file type is now a deliberate decision: add it to $ALLOW_FILES
# or $ALLOW_DIRS explicitly, don't rely on nothing else catching it.
$ALLOW_FILES = @('SKILL.md', 'CLAUDE.md', 'requirements.txt')
$ALLOW_DIRS  = @('scripts', 'lib')   # every *.py file within these, recursively

function Get-ShippedRelativePaths {
  $paths = @()
  foreach ($f in $ALLOW_FILES) {
    if (Test-Path (Join-Path $repo $f)) { $paths += $f }
  }
  foreach ($d in $ALLOW_DIRS) {
    $full = Join-Path $repo $d
    if (Test-Path $full) {
      Get-ChildItem -Path $full -Recurse -File -Filter "*.py" | ForEach-Object {
        $paths += $_.FullName.Substring($repo.Length).TrimStart('\','/')
      }
    }
  }
  return $paths
}

function Sync-Skill {
  if (Test-Path $skillDst) { Remove-Item $skillDst -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $skillDst | Out-Null
  foreach ($rel in (Get-ShippedRelativePaths)) {
    $src = Join-Path $repo $rel
    $dst = Join-Path $skillDst $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    Copy-Item $src $dst -Force
  }
  Write-Host "OK synced -> $skillDst"
}

function Build-Zip {
  $paths = Get-ShippedRelativePaths
  $pyRepo = $repo.Replace('\','/'); $pyZip = $distZip.Replace('\','/')
  $pathsJoined = ($paths | ForEach-Object { $_.Replace('\','/') }) -join "','"
  $py = @"
import zipfile
from pathlib import Path
repo = Path(r'$pyRepo'); out = Path(r'$pyZip')
out.parent.mkdir(parents=True, exist_ok=True)
if out.exists(): out.unlink()
allowed = ['$pathsJoined']
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zf:
    for rel in allowed:
        p = repo / rel
        if p.is_file():
            zf.write(p, rel)
print('OK packed', out)
"@
  $py | python -
  if ($LASTEXITCODE -ne 0) { throw "python zip pack failed" }
  python -c "import zipfile; n=zipfile.ZipFile(r'$distZip').namelist(); assert all('\\' not in x for x in n), 'BACKSLASH'; assert any(x.endswith('SKILL.md') for x in n), 'NO SKILL.md'; print('OK verified', len(n), 'entries')"
}

if ($Both) { Sync-Skill; Build-Zip }
elseif ($ClaudeCode) { Sync-Skill }
elseif ($ClaudeAi) { Build-Zip }
else { Write-Host "Usage: .\tools\deploy.ps1 -Both | -ClaudeCode | -ClaudeAi" }