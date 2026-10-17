# tools/deploy.ps1 -- run from repo root: .\tools\deploy.ps1 -Both
param([switch]$Both, [switch]$ClaudeCode, [switch]$ClaudeAi)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$name = Split-Path -Leaf $repo
$skillDst = Join-Path $env:USERPROFILE ".claude\skills\$name"
$distZip  = Join-Path $repo "dist\$name.zip"

# ALLOWLIST -- only these ship, in either output, regardless of what else exists in the repo
# (.env, .claude/, tests/, docs/, tools/, handoff_specs/, .scratch/, pytest.ini, .git*, etc. never ship
# because they are never listed here). An earlier blocklist design failed in practice.
# Adding a new shippable file type is a deliberate decision: add it to $ALLOW_FILES or $ALLOW_DIRS.
$ALLOW_FILES = @('SKILL.md')
# directory -> shipped extensions (case-insensitive, recursive)
$ALLOW_DIRS  = [ordered]@{
  'scripts'    = @('.py')
  'lib'        = @('.py')
  'references' = @('.md', '.txt', '.json')
  'data'       = @('.json', '.csv', '.txt')
  'config'     = @('.json')
  'assets'     = @('.css', '.html', '.tmpl', '.svg')
}
# hard deny list: applies to every path segment, even inside allowed directories
$DENY = @('.env*','*.key','*.pem','*secret*','*credential*','*.pyc','__pycache__','.git*','*apikey*','*api_key*','*api-key*','*password*','*passwd*','*private_key*','*privatekey*','*mnemonic*','*keystore*','*access_token*','*auth_token*','*.p12','*.pfx','id_rsa*')

function Test-Denied([string]$rel) {
  foreach ($seg in ($rel -split '[\\/]')) {
    foreach ($pat in $DENY) { if ($seg -like $pat) { return $true } }
  }
  return $false
}

function Get-ShippedRelativePaths {
  if ($null -ne $script:Shipped) { return $script:Shipped }
  $paths = @()
  foreach ($f in $ALLOW_FILES) {
    if (Test-Path (Join-Path $repo $f)) {
      if (Test-Denied $f) { Write-Host "DENIED $f" } else { $paths += $f }
    }
  }
  foreach ($d in $ALLOW_DIRS.Keys) {
    $full = Join-Path $repo $d
    if (Test-Path $full) {
      Get-ChildItem -Path $full -Recurse -File -Force | ForEach-Object {
        $rel = $_.FullName.Substring($repo.Length).TrimStart('\','/')
        if (Test-Denied $rel) { Write-Host "DENIED $($rel.Replace('\','/'))" }
        elseif ($ALLOW_DIRS[$d] -contains $_.Extension.ToLowerInvariant()) { $paths += $rel }
      }
    }
  }
  foreach ($rel in $paths) { Write-Host "SHIP $($rel.Replace('\','/'))" }
  $script:Shipped = $paths
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
  $denyJoined = $DENY -join "','"
  $verify = @"
import zipfile, fnmatch
n = zipfile.ZipFile(r'$pyZip').namelist()
allowed = set(['$pathsJoined'])
deny = ['$denyJoined']
bad = [x for x in n if '\\' in x]
assert not bad, 'BACKSLASH: %s' % bad
assert 'SKILL.md' in n, 'NO SKILL.md'
denied = [x for x in n if any(fnmatch.fnmatchcase(s.lower(), p) for s in x.split('/') for p in deny)]
assert not denied, 'DENIED ENTRY: %s' % denied
outside = [x for x in n if x not in allowed]
assert not outside, 'OUTSIDE ALLOWLIST: %s' % outside
print('OK verified', len(n), 'entries')
"@
  $verify | python -
  if ($LASTEXITCODE -ne 0) { throw "zip verification failed" }
}

if ($Both) { Sync-Skill; Build-Zip }
elseif ($ClaudeCode) { Sync-Skill }
elseif ($ClaudeAi) { Build-Zip }
else { Write-Host "Usage: .\tools\deploy.ps1 -Both | -ClaudeCode | -ClaudeAi" }