#requires -Version 5.1
# tests/smoke.ps1 -- plain PowerShell assertions (no Pester). Runs on 5.1 and 7+.
# Run: powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke.ps1
# Works only under .scratch/build/smoke-<guid> inside this repo; cleaned up on pass, kept on fail.
$ErrorActionPreference = "Continue"
$repo = Split-Path -Parent $PSScriptRoot
$src = Join-Path $repo "src"
$init = Join-Path $src "init.ps1"
$smoke = Join-Path $repo (".scratch\build\smoke-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $smoke | Out-Null
$script:failed = @()
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Assert([string]$Check, [string]$Name, [bool]$Ok) {
  if ($Ok) { Write-Host "  ok   [$Check] $Name" }
  else { Write-Host "  FAIL [$Check] $Name"; if ($script:failed -notcontains $Check) { $script:failed += $Check } }
}

function Invoke-Script([string]$Exe, [string]$Script, [string[]]$Arguments) {
  & $Exe -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments | Out-Host
  return $LASTEXITCODE
}

function Write-Text([string]$Path, [string]$Text) {
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [System.IO.File]::WriteAllText($Path, $Text, $utf8)
}

function Get-Snapshot([string]$Dir) {
  # files: path|length|mtime; directories: path only (NTFS directory mtimes drift without content changes)
  Get-ChildItem -LiteralPath $Dir -Recurse -Force | ForEach-Object {
    if ($_.PSIsContainer) { "{0}|d" -f $_.FullName }
    else { "{0}|{1}|{2}" -f $_.FullName, $_.Length, $_.LastWriteTimeUtc.Ticks }
  }
}

function Test-GitIgnored([string]$Dir, [string]$Path) {
  & git -C $Dir check-ignore -q $Path
  return ($LASTEXITCODE -eq 0)
}

function Test-ScaffoldChecks([string]$Exe, [string]$Tag) {
  # check 1: local InPlace scaffold
  $c = "1$Tag"
  Write-Host "CHECK $c local InPlace scaffold ($Exe)"
  $d1 = Join-Path $smoke "$Exe-local\demo-local"
  New-Item -ItemType Directory -Force -Path $d1 | Out-Null
  Push-Location $d1
  $rc = Invoke-Script $Exe $init @("-ProjectName", "demo-local", "-Type", "Skill", "-Execution", "local", "-InPlace")
  Pop-Location
  Assert $c "exit 0 (got $rc)" ($rc -eq 0)
  $expected = @("CLAUDE.md", ".gitignore", ".gitattributes", "SKILL.md", "requirements.txt", "pytest.ini",
    "lib\__init__.py", "lib\clients\__init__.py", "tools\deploy.ps1", "docs\architecture.md", "docs\decisions.md",
    ".claude\settings.json", "handoff_specs", "scripts", "tests\unit", "tests\acceptance",
    ".scratch\probe", ".scratch\build", ".scratch\logs", ".scratch\misc")
  foreach ($e in $expected) { Assert $c "exists $e" (Test-Path -LiteralPath (Join-Path $d1 $e)) }
  $settings = Join-Path $d1 ".claude\settings.json"
  if (Test-Path -LiteralPath $settings) {
    $want = "{`n  `"env`": { `"CLAUDE_CODE_USE_POWERSHELL_TOOL`": `"1`" },`n  `"defaultShell`": `"powershell`"`n}"
    Assert $c "settings.json byte-for-byte v2.0" ([System.IO.File]::ReadAllText($settings) -ceq $want)
  }
  Assert $c "packer copied verbatim" ((Get-FileHash (Join-Path $d1 "tools\deploy.ps1")).Hash -eq (Get-FileHash (Join-Path $src "deploy.ps1")).Hash)
  Assert $c "CLAUDE.md rendered (no {{ tokens)" (-not ([System.IO.File]::ReadAllText((Join-Path $d1 "CLAUDE.md"))).Contains("{{"))
  Assert $c "CLAUDE.md says Execution: local" (([System.IO.File]::ReadAllText((Join-Path $d1 "CLAUDE.md"))).Contains("> Execution: local"))
  Assert $c "no .claspignore without -Clasp" (-not (Test-Path -LiteralPath (Join-Path $d1 ".claspignore")))
  Assert $c "check-ignore .scratch/x" (Test-GitIgnored $d1 ".scratch/x")
  Assert $c "check-ignore handoff_specs/x" (Test-GitIgnored $d1 "handoff_specs/x")
  $st = & git -C $d1 status --porcelain
  Assert $c "status clean" ([string]::IsNullOrEmpty(($st -join "")))
  $n = & git -C $d1 rev-list --count HEAD
  Assert $c "exactly one commit (got $n)" ("$n".Trim() -eq "1")
  $br = & git -C $d1 symbolic-ref --short HEAD
  Assert $c "branch main (got $br)" ("$br".Trim() -eq "main")

  # check 2: cloud InPlace scaffold
  $c = "2$Tag"
  Write-Host "CHECK $c cloud InPlace scaffold ($Exe)"
  $d2 = Join-Path $smoke "$Exe-cloud\demo-cloud"
  New-Item -ItemType Directory -Force -Path $d2 | Out-Null
  Push-Location $d2
  $rc = Invoke-Script $Exe $init @("-ProjectName", "demo-cloud", "-Type", "Skill", "-Execution", "cloud", "-InPlace")
  Pop-Location
  Assert $c "exit 0 (got $rc)" ($rc -eq 0)
  Assert $c ".claude/settings.json absent" (-not (Test-Path -LiteralPath (Join-Path $d2 ".claude\settings.json")))
  Assert $c "handoff_specs/x NOT ignored (tracked)" (-not (Test-GitIgnored $d2 "handoff_specs/x"))
  Assert $c "check-ignore .scratch/x" (Test-GitIgnored $d2 ".scratch/x")
  Assert $c "handoff_specs/.gitkeep exists" (Test-Path -LiteralPath (Join-Path $d2 "handoff_specs\.gitkeep"))
  $tracked = & git -C $d2 ls-files "handoff_specs/.gitkeep"
  Assert $c "handoff_specs/.gitkeep committed" ("$tracked".Trim() -eq "handoff_specs/.gitkeep")
  $st = & git -C $d2 status --porcelain
  Assert $c "status clean" ([string]::IsNullOrEmpty(($st -join "")))

  # check 3: re-run in a non-empty dir is refused and changes nothing
  $c = "3$Tag"
  Write-Host "CHECK $c refuse non-empty dir ($Exe)"
  $before = Get-Snapshot $d1
  Push-Location $d1
  $rc = Invoke-Script $Exe $init @("-ProjectName", "demo-local", "-Type", "Skill", "-Execution", "local", "-InPlace")
  Pop-Location
  $after = Get-Snapshot $d1
  Assert $c "exit 2 (got $rc)" ($rc -eq 2)
  $diff = @(Compare-Object @($before) @($after))
  foreach ($x in $diff) { Write-Host "  changed: $($x.SideIndicator) $($x.InputObject)" }
  Assert $c "file list unchanged" ($diff.Count -eq 0)
  return $d1, $d2
}

$dirs = Test-ScaffoldChecks "powershell" ""

# check 4: packer allowlist on a Skill fixture with decoys
Write-Host "CHECK 4 packer allowlist"
$fx = Join-Path $smoke "pack-fixture"
Write-Text (Join-Path $fx "SKILL.md") "---`nname: pack-fixture`ndescription: smoke fixture`n---`n"
Write-Text (Join-Path $fx "scripts\x.py") "print('x')`n"
Write-Text (Join-Path $fx "lib\y.py") "Y = 1`n"
$decoys = @(".env", ".env.local", "secrets.txt", "docs\d.md", ".scratch\s.txt", "tools\t.txt", "handoff_specs\h.md", "tests\t.py")
foreach ($d in $decoys) { Write-Text (Join-Path $fx $d) "DECOY`n" }
Copy-Item -LiteralPath (Join-Path $src "deploy.ps1") -Destination (Join-Path $fx "tools\deploy.ps1")
$rc = Invoke-Script "powershell" (Join-Path $fx "tools\deploy.ps1") @("-ClaudeAi")
Assert "4" "deploy.ps1 -ClaudeAi exit 0 (got $rc)" ($rc -eq 0)
$zip = Join-Path $fx "dist\pack-fixture.zip"
Assert "4" "zip exists" (Test-Path -LiteralPath $zip)
if (Test-Path -LiteralPath $zip) {
  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $za = [System.IO.Compression.ZipFile]::OpenRead($zip)
  try {
    $names = @($za.Entries | ForEach-Object { $_.FullName })
    Write-Host "  entries: $($names -join ', ')"
    foreach ($w in @("SKILL.md", "scripts/x.py", "lib/y.py")) { Assert "4" "contains $w" ($names -ccontains $w) }
    foreach ($d in $decoys) {
      $dz = $d.Replace('\', '/')
      $hit = @($names | Where-Object { $_ -eq $dz -or ($dz.Contains('/') -and $_.StartsWith($dz.Split('/')[0] + "/")) })
      Assert "4" "excludes $dz" ($hit.Count -eq 0)
    }
    Assert "4" "all entries forward-slash" (-not ($names | Where-Object { $_.Contains('\') }))
    $bomEntries = @()
    foreach ($en in $za.Entries) {
      $s = $en.Open(); $buf = New-Object byte[] 3; $r = $s.Read($buf, 0, 3); $s.Close()
      if ($r -eq 3 -and $buf[0] -eq 0xEF -and $buf[1] -eq 0xBB -and $buf[2] -eq 0xBF) { $bomEntries += $en.FullName }
    }
    Assert "4" "no BOM in zip entries" ($bomEntries.Count -eq 0)
  } finally { $za.Dispose() }
}

# check 5: manifest
Write-Host "CHECK 5 manifest"
$rc = Invoke-Script "powershell" (Join-Path $repo "scripts\release.ps1") @()
Assert "5" "release.ps1 exit 0 (got $rc)" ($rc -eq 0)
$manifest = @{}
foreach ($line in [System.IO.File]::ReadAllText((Join-Path $src "MANIFEST.sha256")).Split("`n")) {
  if ($line -eq "") { continue }
  $parts = $line -split ' ', 2
  $manifest[$parts[1]] = $parts[0]
}
$srcFiles = @(Get-ChildItem -LiteralPath $src -Recurse -File | Where-Object { $_.Name -ne "MANIFEST.sha256" -or $_.DirectoryName -ne $src })
Assert "5" "manifest lists every src file ($($manifest.Count) vs $($srcFiles.Count))" ($manifest.Count -eq $srcFiles.Count)
$mismatch = 0
foreach ($rel in $manifest.Keys) {
  $p = Join-Path $src ($rel.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $p) -or (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $manifest[$rel]) { $mismatch++ }
}
Assert "5" "recomputed hashes match manifest ($mismatch mismatches)" ($mismatch -eq 0)
$tamper = Join-Path $smoke "tamper\init.ps1"
New-Item -ItemType Directory -Force -Path (Split-Path $tamper) | Out-Null
$bytes = [System.IO.File]::ReadAllBytes($init)
$bytes[100] = $bytes[100] -bxor 1
[System.IO.File]::WriteAllBytes($tamper, $bytes)
$th = (Get-FileHash -LiteralPath $tamper -Algorithm SHA256).Hash.ToLowerInvariant()
Assert "5" "manifest has an init.ps1 entry" ($manifest.ContainsKey("init.ps1"))
Assert "5" "untampered init.ps1 matches its entry" ((Get-FileHash -LiteralPath $init -Algorithm SHA256).Hash.ToLowerInvariant() -eq $manifest["init.ps1"])
Assert "5" "tampered copy of init.ps1 fails the comparison" ($manifest.ContainsKey("init.ps1") -and $th -ne $manifest["init.ps1"])

# check 6: no BOM in repo text files or generated scaffold files
Write-Host "CHECK 6 no BOM"
$scan = @(Get-ChildItem -LiteralPath $repo -Recurse -File -Force | Where-Object { $_.FullName -notmatch '\\\.git\\|\\\.scratch\\' })
foreach ($d in $dirs) {
  $scan += @(Get-ChildItem -LiteralPath $d -Recurse -File -Force | Where-Object { $_.FullName -notmatch '\\\.git\\|\\\.venv\\' })
}
$scan += @(Get-ChildItem -LiteralPath $fx -Recurse -File -Force | Where-Object { $_.Extension -ne ".zip" })
$boms = @()
foreach ($f in $scan) {
  $b = [System.IO.File]::ReadAllBytes($f.FullName)
  if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { $boms += $f.FullName }
}
foreach ($x in $boms) { Write-Host "  BOM: $x" }
Assert "6" "no file starts with EF BB BF ($($scan.Count) scanned)" ($boms.Count -eq 0)

# check 7: re-run checks 1-3 under pwsh if present
Write-Host "CHECK 7 pwsh re-run of checks 1-3"
if (Get-Command pwsh -ErrorAction SilentlyContinue) {
  $null = Test-ScaffoldChecks "pwsh" "-pwsh"
} else {
  Write-Host "  pwsh absent, skipped"
}

if ($script:failed.Count -eq 0) {
  Remove-Item -LiteralPath $smoke -Recurse -Force
  Write-Host "SMOKE PASS"
  exit 0
}
Write-Host "Failed checks: $($script:failed -join ', ') (left in $smoke)"
Write-Host "SMOKE FAIL $($script:failed.Count)"
exit 1
