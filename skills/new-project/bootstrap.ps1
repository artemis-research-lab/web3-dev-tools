#requires -Version 5.1
<#
.SYNOPSIS
  Bootstrap a new project in the current empty directory from a pinned web3-dev-tools release.

.DESCRIPTION
  Downloads src/MANIFEST.sha256 of a pinned tag (vX.Y.Z only), checks it against a pinned hash,
  downloads every file it lists into tools/, verifies each SHA-256, writes tools/SOURCE and runs
  tools/init.ps1 -InPlace with a repo-local git identity. Then verifies the committed bytes.

  Claude Code local skill (Windows PowerShell 5.1 and PowerShell 7+). Not a packaged skill.
  Never pushes, never calls gh, never talks to a git remote. The only network host is
  raw.githubusercontent.com. Nothing is written outside the current directory.

  Exit codes: 0 ok, 2 precondition refused, 3 template missing (init.ps1),
  4 git identity missing, 5 integrity or verification failure, 6 ref refused.
  A non-zero exit code of init.ps1 is propagated.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\bootstrap.ps1 -ProjectName my-skill -Type Skill -Execution local
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)] [string]$ProjectName,
  [ValidateSet("Skill","MCP")] [string]$Type = "Skill",
  [ValidateSet("local","cloud")] [string]$Execution = "local",
  [string]$Repo = "artemis-research-lab/web3-dev-tools",
  [string]$Ref,                 # default: $DefaultRef
  [string]$ManifestSha256,      # default: $DefaultManifestSha256 when -Ref is not given
  [string]$GitUser, [string]$GitEmail,
  [string]$LocalBundle          # test hook: path to a src/ directory used instead of the network
)
$DefaultRef = 'v0.3.0'
$DefaultManifestSha256 = '0c9afc088ebaec4ce103f8701b383d6957a859c9df09d8cd7e95d9721817ea5a'

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$utf8 = New-Object System.Text.UTF8Encoding($false)
$proj = (Get-Location).ProviderPath
$tools = Join-Path $proj "tools"
$download = Join-Path $tools ".download"

function Stop-Bootstrap([int]$Code, [string]$Message) {
  Write-Host "REFUSED (exit $Code): $Message" -ForegroundColor Red
  exit $Code
}

function Invoke-Native {
  # On 5.1, native stderr can surface as an error record; keep it non-terminating and check exit codes.
  param([string]$Exe, [string[]]$Arguments)
  $ErrorActionPreference = "Continue"
  & $Exe @Arguments
}

function Get-FileSha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-GitBlobSha256([string]$Spec) {
  # raw bytes of a committed blob (no console decoding), hashed
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "git"
  $psi.Arguments = "show $Spec"
  $psi.WorkingDirectory = $proj
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $errTask = $p.StandardError.ReadToEndAsync()
  $ms = New-Object System.IO.MemoryStream
  $p.StandardOutput.BaseStream.CopyTo($ms)
  $p.WaitForExit()
  $null = $errTask.Result
  if ($p.ExitCode -ne 0) { return $null }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $h = $sha.ComputeHash($ms.ToArray()) } finally { $sha.Dispose() }
  return ([System.BitConverter]::ToString($h)).Replace("-", "").ToLowerInvariant()
}

function Remove-Tools {
  if (Test-Path -LiteralPath $tools) { Remove-Item -LiteralPath $tools -Recurse -Force }
}

function Stop-Integrity([string]$Message) {
  Remove-Tools
  Stop-Bootstrap 5 $Message
}

# ---------------------------------------------------------------------------
# 1. Directory check (nothing is written before checks 1-4 pass)
# ---------------------------------------------------------------------------
foreach ($item in @(Get-ChildItem -LiteralPath $proj -Force)) {
  if ($item.PSIsContainer -and $item.Name -eq ".git") {
    Invoke-Native git @("-C", $proj, "rev-parse", "-q", "--verify", "HEAD") | Out-Null
    if ($LASTEXITCODE -eq 0) { Stop-Bootstrap 2 "current directory .git already has commits: $proj" }
  } elseif ($item.PSIsContainer -and $item.Name -eq "tools" -and @(Get-ChildItem -LiteralPath $item.FullName -Force).Count -eq 0) {
    continue
  } else {
    Stop-Bootstrap 2 "current directory is not empty (found '$($item.Name)'): $proj"
  }
}

# ---------------------------------------------------------------------------
# 2. Arguments
# ---------------------------------------------------------------------------
if ($Repo -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') { Stop-Bootstrap 2 "invalid -Repo '$Repo' (expected owner/repo)" }
if ($ProjectName -cnotmatch '^[a-z0-9][a-z0-9-]*$') { Stop-Bootstrap 2 "invalid -ProjectName '$ProjectName' (lowercase letters, digits, '-')" }
if ($LocalBundle) {
  if (-not (Test-Path -LiteralPath (Join-Path $LocalBundle "MANIFEST.sha256"))) { Stop-Bootstrap 2 "-LocalBundle has no MANIFEST.sha256: $LocalBundle" }
  $LocalBundle = (Resolve-Path -LiteralPath $LocalBundle).ProviderPath
}

# ---------------------------------------------------------------------------
# 3. Ref and manifest pin
# ---------------------------------------------------------------------------
if ($PSBoundParameters.ContainsKey("Ref")) {
  $effRef = $Ref
  $pin = $ManifestSha256
} else {
  $effRef = $DefaultRef
  $pin = $DefaultManifestSha256
  if ($ManifestSha256) { $pin = $ManifestSha256 }
}
if ($effRef -cnotmatch '^v\d+\.\d+\.\d+$') { Stop-Bootstrap 6 "ref '$effRef' refused: only release tags vX.Y.Z are allowed" }
if ($pin) {
  $pin = $pin.ToLowerInvariant()
  if ($pin -cnotmatch '^[0-9a-f]{64}$') { Stop-Bootstrap 2 "manifest pin is not a SHA-256 hex string" }
} else {
  Write-Host "WARNING UNPINNED manifest (ref $effRef given without -ManifestSha256)" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# 4. Git identity (repo-local, passed to init.ps1)
# ---------------------------------------------------------------------------
$explicitEmail = $PSBoundParameters.ContainsKey("GitEmail")
if ($GitUser -or $GitEmail) {
  if (-not ($GitUser -and $GitEmail)) { Stop-Bootstrap 4 "-GitUser and -GitEmail must be given together" }
  $idUser = $GitUser; $idEmail = $GitEmail
} else {
  $idFile = Join-Path $PSScriptRoot "identity.json"
  if (-not (Test-Path -LiteralPath $idFile)) { Stop-Bootstrap 4 "no git identity: pass -GitUser/-GitEmail or create $idFile" }
  try { $id = [System.IO.File]::ReadAllText($idFile) | ConvertFrom-Json } catch { Stop-Bootstrap 4 "identity.json is not valid JSON" }
  $idUser = "$($id.git_user)".Trim(); $idEmail = "$($id.git_email)".Trim()
  if (-not ($idUser -and $idEmail)) { Stop-Bootstrap 4 "identity.json needs both git_user and git_email" }
}
if (-not $explicitEmail -and -not $idEmail.EndsWith("@users.noreply.github.com")) {
  Stop-Bootstrap 4 "git_email in identity.json must be a GitHub noreply address"
}
Write-Host "identity: ok"

# ---------------------------------------------------------------------------
# 5. Fetch manifest and check the pin
# ---------------------------------------------------------------------------
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12
$base = "https://raw.githubusercontent.com/$Repo/$effRef/src"
$tmpManifest = Join-Path $download "MANIFEST.sha256"
try {
  New-Item -ItemType Directory -Force -Path $download | Out-Null
  if ($LocalBundle) { Copy-Item -LiteralPath (Join-Path $LocalBundle "MANIFEST.sha256") -Destination $tmpManifest }
  else { Invoke-WebRequest -UseBasicParsing -Uri "$base/MANIFEST.sha256" -OutFile $tmpManifest }
} catch { Stop-Integrity "manifest download failed: $($_.Exception.Message)" }
$manifestHash = Get-FileSha256 $tmpManifest
Write-Host "manifest sha256: $manifestHash"
if ($pin -and $manifestHash -ne $pin) { Stop-Integrity "MANIFEST PIN MISMATCH (expected $pin)" }

# ---------------------------------------------------------------------------
# 6. Parse manifest
# ---------------------------------------------------------------------------
$entries = @()
$seen = @{}
$lines = [System.IO.File]::ReadAllText($tmpManifest).Split("`n")
for ($i = 0; $i -lt $lines.Count; $i++) {
  $line = $lines[$i]
  if ($line -eq "" -and $i -eq $lines.Count - 1) { continue }
  if ($line -cnotmatch '^([0-9a-f]{64}) ([^ ]+)$') { Stop-Integrity "bad manifest line $($i + 1)" }
  $h = $Matches[1]; $rel = $Matches[2]
  if ($rel -cnotmatch '^[A-Za-z0-9._/-]+$' -or $rel.StartsWith("/") -or $rel.Contains("..") -or $rel.Contains("//") -or $rel.EndsWith("/")) {
    Stop-Integrity "unsafe manifest path on line $($i + 1)"
  }
  foreach ($seg in $rel.Split("/")) { if ($seg -eq ".") { Stop-Integrity "unsafe manifest path on line $($i + 1)" } }
  if ($rel -eq "SOURCE" -or $rel -eq "MANIFEST.sha256" -or $rel.StartsWith(".download")) { Stop-Integrity "reserved manifest path on line $($i + 1)" }
  $key = $rel.ToLowerInvariant()
  if ($seen.ContainsKey($key)) { Stop-Integrity "duplicate manifest path on line $($i + 1)" }
  $seen[$key] = $true
  $entries += New-Object PSObject -Property @{ Rel = $rel; Hash = $h }
}
if ($entries.Count -eq 0 -or -not $seen.ContainsKey("init.ps1")) { Stop-Integrity "manifest does not list init.ps1" }

# ---------------------------------------------------------------------------
# 7. Download and verify every file
# ---------------------------------------------------------------------------
foreach ($e in $entries) {
  $dst = Join-Path $tools ($e.Rel.Replace("/", "\"))
  try {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
    if ($LocalBundle) { Copy-Item -LiteralPath (Join-Path $LocalBundle ($e.Rel.Replace("/", "\"))) -Destination $dst }
    else { Invoke-WebRequest -UseBasicParsing -Uri "$base/$($e.Rel)" -OutFile $dst }
  } catch { Stop-Integrity "download failed: $($e.Rel)" }
  if ((Get-FileSha256 $dst) -ne $e.Hash) { Stop-Integrity "HASH MISMATCH $($e.Rel)" }
  Write-Host "MATCH $($e.Rel)"
}

# ---------------------------------------------------------------------------
# 8. tools/SOURCE and tools/MANIFEST.sha256
# ---------------------------------------------------------------------------
$today = (Get-Date).ToString("yyyy-MM-dd")
$source = "repo=$Repo`nref=$effRef`nmanifest_sha256=$manifestHash`ndate=$today`n"
[System.IO.File]::WriteAllText((Join-Path $tools "SOURCE"), $source, $utf8)
Move-Item -LiteralPath $tmpManifest -Destination (Join-Path $tools "MANIFEST.sha256")
Remove-Item -LiteralPath $download -Recurse -Force

# ---------------------------------------------------------------------------
# 9. Run init.ps1 in place
# ---------------------------------------------------------------------------
$initArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $tools "init.ps1"),
  "-ProjectName", $ProjectName, "-Type", $Type, "-Execution", $Execution, "-InPlace",
  "-GitUser", $idUser, "-GitEmail", $idEmail)
Invoke-Native powershell $initArgs
$initRc = $LASTEXITCODE
if ($initRc -ne 0) {
  Write-Host "init.ps1 failed (exit $initRc)" -ForegroundColor Red
  exit $initRc
}

# ---------------------------------------------------------------------------
# 10. Post-verify the committed state
# ---------------------------------------------------------------------------
$bad = @()
foreach ($e in $entries) {
  if ((Get-GitBlobSha256 "HEAD:tools/$($e.Rel)") -ne $e.Hash) { $bad += "committed bytes differ: tools/$($e.Rel)" }
}
if ((Get-GitBlobSha256 "HEAD:tools/MANIFEST.sha256") -ne $manifestHash) { $bad += "committed bytes differ: tools/MANIFEST.sha256" }
$tracked = @(Invoke-Native git @("-C", $proj, "ls-files", "--", "tools/SOURCE", "tools/MANIFEST.sha256"))
foreach ($t in @("tools/SOURCE", "tools/MANIFEST.sha256")) { if ($tracked -notcontains $t) { $bad += "not committed: $t" } }
$count = Invoke-Native git @("-C", $proj, "rev-list", "--count", "HEAD")
if ("$count".Trim() -ne "1") { $bad += "expected exactly one commit, got '$count'" }
$st = Invoke-Native git @("-C", $proj, "status", "--porcelain")
if (-not [string]::IsNullOrEmpty((@($st) -join ""))) { $bad += "working tree not clean" }
foreach ($ig in @(".env", ".scratch/x")) {
  Invoke-Native git @("-C", $proj, "check-ignore", "-q", $ig) | Out-Null
  if ($LASTEXITCODE -ne 0) { $bad += "not ignored: $ig" }
}
if ($bad.Count -gt 0) {
  foreach ($b in $bad) { Write-Host "  $b" -ForegroundColor Red }
  Stop-Bootstrap 5 "post-verify failed"
}
Write-Host "post-verify: ok"

# ---------------------------------------------------------------------------
# 11. Done (no push, no gh, no remote)
# ---------------------------------------------------------------------------
$fileCount = @(Get-ChildItem -LiteralPath $tools -Recurse -File -Force).Count
Write-Host "OK bootstrap $ProjectName $Type $Execution ref=$effRef"
Write-Host "tools/ files: $fileCount"
exit 0
