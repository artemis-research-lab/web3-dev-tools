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
    "lib\__init__.py", "lib\clients\__init__.py", "tools\deploy.ps1", "references\runtime.md", "docs\architecture.md", "docs\decisions.md",
    ".claude\settings.json", "handoff_specs", "scripts", "tests\unit", "tests\acceptance",
    ".scratch\probe", ".scratch\build", ".scratch\logs", ".scratch\misc")
  foreach ($e in $expected) { Assert $c "exists $e" (Test-Path -LiteralPath (Join-Path $d1 $e)) }
  $settings = Join-Path $d1 ".claude\settings.json"
  if (Test-Path -LiteralPath $settings) {
    $want = "{`n  `"env`": { `"CLAUDE_CODE_USE_POWERSHELL_TOOL`": `"1`" },`n  `"defaultShell`": `"powershell`"`n}"
    Assert $c "settings.json byte-for-byte v2.0" ([System.IO.File]::ReadAllText($settings) -ceq $want)
  }
  Assert $c "packer copied verbatim" ((Get-FileHash (Join-Path $d1 "tools\deploy.ps1")).Hash -eq (Get-FileHash (Join-Path $src "deploy.ps1")).Hash)
  $cm = [System.IO.File]::ReadAllText((Join-Path $d1 "CLAUDE.md"))
  Assert $c "CLAUDE.md says Execution: local" ($cm.Contains("> Execution: local"))
  Assert "S1$Tag" "local CLAUDE.md contains 'PowerShell ONLY'" ($cm.Contains("PowerShell ONLY"))
  Assert "S1$Tag" "local CLAUDE.md contains 'Get-ChildItem'" ($cm.Contains("Get-ChildItem"))
  Assert "S1$Tag" "local CLAUDE.md has no {{ tokens" (-not $cm.Contains("{{"))
  $attr = & git -C $d1 check-attr text -- tools/deploy.ps1
  Assert "S3$Tag" "local: check-attr text tools/deploy.ps1 is unset (got '$attr')" ("$attr".Trim() -eq "tools/deploy.ps1: text: unset")
  $sk = [System.IO.File]::ReadAllText((Join-Path $d1 "SKILL.md"))
  Assert "S7$Tag" "SKILL.md does not mention CLAUDE.md" (-not $sk.Contains("CLAUDE.md"))
  Assert "S7$Tag" "SKILL.md points to references/runtime.md" ($sk.Contains("references/runtime.md"))
  Assert "S7$Tag" "references/runtime.md exists" (Test-Path -LiteralPath (Join-Path $d1 "references\runtime.md"))
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
  $cm = [System.IO.File]::ReadAllText((Join-Path $d2 "CLAUDE.md"))
  Assert "S2$Tag" "cloud CLAUDE.md contains 'Bash on Linux'" ($cm.Contains("Bash on Linux"))
  foreach ($bad in @("PowerShell ONLY", "Get-ChildItem", "Write-Host", "{{")) {
    Assert "S2$Tag" "cloud CLAUDE.md does not contain '$bad'" (-not $cm.Contains($bad))
  }
  $attr = & git -C $d2 check-attr text -- tools/deploy.ps1
  Assert "S3$Tag" "cloud: check-attr text tools/deploy.ps1 is unset (got '$attr')" ("$attr".Trim() -eq "tools/deploy.ps1: text: unset")

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

  # S5: tools/ bytes survive a clone (D12)
  Write-Host "CHECK S5$Tag clone keeps tools bytes ($Exe)"
  $cl = Join-Path $smoke "$Exe-clone\demo-local"
  & git clone -q $d1 $cl
  Assert "S5$Tag" "git clone exit 0" ($LASTEXITCODE -eq 0)
  $ch = Join-Path $cl "tools\deploy.ps1"
  Assert "S5$Tag" "cloned tools\deploy.ps1 hash equals src\deploy.ps1" ((Test-Path -LiteralPath $ch) -and (Get-FileHash -LiteralPath $ch).Hash -eq (Get-FileHash -LiteralPath (Join-Path $src "deploy.ps1")).Hash)
  return $d1, $d2
}

$dirs = Test-ScaffoldChecks "powershell" ""

# check 4 / S6: packer ships only run-time components (allowlist + hard deny list)
function Get-ZipNames([string]$Zip) {
  Add-Type -AssemblyName System.IO.Compression
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $za = [System.IO.Compression.ZipFile]::OpenRead($Zip)
  try {
    $boms = @()
    foreach ($en in $za.Entries) {
      $s = $en.Open(); $buf = New-Object byte[] 3; $r = $s.Read($buf, 0, 3); $s.Close()
      if ($r -eq 3 -and $buf[0] -eq 0xEF -and $buf[1] -eq 0xBB -and $buf[2] -eq 0xBF) { $boms += $en.FullName }
    }
    return New-Object PSObject -Property @{ Names = @($za.Entries | ForEach-Object { $_.FullName }); Boms = $boms }
  } finally { $za.Dispose() }
}

function Invoke-Packer([string]$Project) {
  $lines = @(& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Project "tools\deploy.ps1") -ClaudeAi 2>&1 | ForEach-Object { "$_" })
  $script:packerRc = $LASTEXITCODE
  foreach ($l in $lines) { Write-Host "  | $l" }
  return $lines
}

function Test-ZipExact([string]$Check, [string]$Zip, [string[]]$Want) {
  Assert $Check "zip exists" (Test-Path -LiteralPath $Zip)
  if (-not (Test-Path -LiteralPath $Zip)) { return @() }
  $z = Get-ZipNames $Zip
  $names = @($z.Names)
  Write-Host "  entries: $($names -join ', ')"
  $diff = @(Compare-Object ($Want | Sort-Object) ($names | Sort-Object) -CaseSensitive)
  foreach ($x in $diff) { Write-Host "  entry diff: $($x.SideIndicator) $($x.InputObject)" }
  Assert $Check "zip entry set equals exactly: $($Want -join ', ')" ($diff.Count -eq 0)
  Assert $Check "all entries forward-slash" (-not ($names | Where-Object { $_.Contains('\') }))
  Assert $Check "no BOM in zip entries" (@($z.Boms).Count -eq 0)
  return $names
}

Write-Host "CHECK 4/S6 packer: decoy fixture"
$fx = Join-Path $smoke "pack-fixture"
$ship = @("SKILL.md", "scripts\x.py", "lib\y.py", "references\r.md", "data\d.json", "config\c.json")
Write-Text (Join-Path $fx "SKILL.md") "---`nname: pack-fixture`ndescription: smoke fixture`n---`n"
Write-Text (Join-Path $fx "scripts\x.py") "print('x')`n"
Write-Text (Join-Path $fx "lib\y.py") "Y = 1`n"
Write-Text (Join-Path $fx "references\r.md") "# r`n"
Write-Text (Join-Path $fx "data\d.json") "{}`n"
Write-Text (Join-Path $fx "config\c.json") "{}`n"
$decoys = @("CLAUDE.md", "requirements.txt", "pytest.ini", ".env", ".env.local", "data\.env", "config\secrets.json",
  "config\my_credentials.json", "lib\__pycache__\y.cpython-311.pyc", "docs\d.md", ".scratch\s.txt", "tools\t.txt",
  "handoff_specs\h.md", "tests\t.py", ".claude\settings.json")
foreach ($d in $decoys) { Write-Text (Join-Path $fx $d) "DECOY`n" }
Copy-Item -LiteralPath (Join-Path $src "deploy.ps1") -Destination (Join-Path $fx "tools\deploy.ps1")
$out = Invoke-Packer $fx
Assert "S6" "deploy.ps1 -ClaudeAi exit 0 (got $script:packerRc)" ($script:packerRc -eq 0)
$names = Test-ZipExact "S6" (Join-Path $fx "dist\pack-fixture.zip") ($ship | ForEach-Object { $_.Replace('\', '/') })
foreach ($d in $decoys) {
  $dz = $d.Replace('\', '/')
  Assert "S6" "excludes decoy $dz" (-not ($names -contains $dz))
}
foreach ($d in @("data/.env", "config/secrets.json", "config/my_credentials.json", "lib/__pycache__/y.cpython-311.pyc")) {
  Assert "S6" "output lists DENIED $d" (@($out | Where-Object { $_.Trim() -eq "DENIED $d" }).Count -eq 1)
}
foreach ($s in $ship) {
  $sz = $s.Replace('\', '/')
  Assert "S6" "output lists SHIP $sz" (@($out | Where-Object { $_.Trim() -eq "SHIP $sz" }).Count -ge 1)
}

Write-Host "CHECK 4/S6 packer: init.ps1 Skill scaffold"
$d1 = $dirs[0]
$out = Invoke-Packer $d1
Assert "S6" "scaffold deploy.ps1 -ClaudeAi exit 0 (got $script:packerRc)" ($script:packerRc -eq 0)
$null = Test-ZipExact "S6" (Join-Path $d1 "dist\demo-local.zip") @("SKILL.md", "lib/__init__.py", "lib/clients/__init__.py", "references/runtime.md")
$st = & git -C $d1 status --porcelain
Assert "S6" "scaffold status still clean after packing" ([string]::IsNullOrEmpty(($st -join "")))
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

# S4: no internal project names or key narrative in tracked (or to-be-tracked) repo files
Write-Host "CHECK S4 repo text hygiene"
$needles = @(("am" + "m-"), ("api" + " keys"))
$repoFiles = @(& git -C $repo ls-files) + @(& git -C $repo ls-files --others --exclude-standard)
$hits = @()
foreach ($rf in $repoFiles) {
  $fp = Join-Path $repo ($rf.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $fp)) { continue }
  $txt = [System.IO.File]::ReadAllText($fp)
  foreach ($nd in $needles) { if ($txt.IndexOf($nd, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $hits += "$rf : $nd" } }
}
foreach ($h in $hits) { Write-Host "  hit: $h" }
Assert "S4" "no tracked file contains the internal-name or key-narrative strings ($($repoFiles.Count) files)" ($hits.Count -eq 0)
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
