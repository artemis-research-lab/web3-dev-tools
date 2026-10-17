#requires -Version 5.1
<#
.SYNOPSIS
  Scaffold a new Web3 dev project (Skill or MCP) per Claude-Dual-Dev-Workflow-for-Web3-Projects.md v2.0.
  Distributed as part of the web3-dev-tools bundle (src/ of a pinned release tag).

.DESCRIPTION
  Creates the directory tree + generic config/dotfiles + tools/deploy.ps1 (copied from this bundle)
  + CLAUDE.md, .gitignore, .gitattributes, docs/*.md rendered from templates\*.tpl + a SKILL.md
  front-matter stub. Does NOT write any client/lib .py source --
  those are produced by the project/module handoff specs (gen project spec / gen module spec).

  Generic config (settings.json, pytest.ini, requirements.txt) is written byte-for-byte from the
  previously validated templates. CLAUDE.md/.gitignore/.gitattributes/docs come from
  templates\*.tpl; only {{PROJECT_NAME}}, {{EXECUTION}} and {{DATE}} are replaced, plus
  {{SHELL_SECTION}} in CLAUDE.md.tpl (from claude-shell.<Execution>.tpl).

  tools/deploy.ps1 packer: ALLOWLIST model, shipped as deploy.ps1 next to this script. It is copied,
  never embedded; an existing tools\deploy.ps1 (InPlace mode) is left unchanged.

  Refuses rather than overwrites. Never runs git push or gh. Never changes git identity, except
  repo-locally in the new repo when both -GitUser and -GitEmail are given.
  Runs on Windows PowerShell 5.1 and PowerShell 7+.

  Exit codes: 0 ok, 2 precondition refused, 3 template missing, 4 git identity missing.

.PARAMETER ProjectName
  Project (and skill) name, e.g. "uniswap-mcp" or "lido-skill".

.PARAMETER Type
  Skill (Python stdlib, zip deploy) or MCP (TypeScript, pnpm, Inspector). Default Skill.

.PARAMETER Parent
  Parent directory (alias: -Root). Default C:\web3projects. Ignored with -InPlace.

.PARAMETER Execution
  local (default): /handoff_specs/ gitignored, .claude/settings.json PowerShell lock written.
  cloud: handoff_specs/ tracked (.gitkeep), no .claude/settings.json.

.PARAMETER InPlace
  Scaffold into the current directory. It may contain only an optional tools/ directory and an
  optional .git with zero commits; tools/ becomes part of the scaffold commit.

.PARAMETER Clasp
  Also write .claspignore.

.PARAMETER GitUser
  With -GitEmail: repo-local user.name set in the new repo before the scaffold commit.

.PARAMETER GitEmail
  With -GitUser: repo-local user.email set in the new repo before the scaffold commit.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\init.ps1 -ProjectName lido-skill -Type Skill
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\init.ps1 -ProjectName lido-skill -InPlace -Execution cloud
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)] [string]$ProjectName,
  [ValidateSet("Skill", "MCP")]  [string]$Type = "Skill",
  [Alias("Root")] [string]$Parent = "C:\web3projects",
  [ValidateSet("local", "cloud")] [string]$Execution = "local",
  [switch]$InPlace,
  [switch]$Clasp,
  [string]$GitUser,
  [string]$GitEmail
)
$ErrorActionPreference = "Stop"

function Write-Utf8NoBom([string]$Path, [string]$Content) {
  # No BOM (env_loader/parsers expect clean UTF-8); works on 5.1 and 7.
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Stop-Init([int]$Code, [string]$Message) {
  Write-Host "REFUSED (exit $Code): $Message" -ForegroundColor Red
  exit $Code
}

function Invoke-Native {
  # On 5.1, native stderr can surface as an error record; keep it non-terminating and check exit codes.
  param([string]$Exe, [string[]]$Arguments)
  $ErrorActionPreference = "Continue"
  & $Exe @Arguments
}

# ---------------------------------------------------------------------------
# Preconditions (nothing is written before all of them pass)
# ---------------------------------------------------------------------------
if ($InPlace) {
  $proj = (Get-Location).ProviderPath
  $found = @(Get-ChildItem -LiteralPath $proj -Force | Where-Object {
      -not ($_.PSIsContainer -and ($_.Name -eq "tools" -or $_.Name -eq ".git")) })
  if ($found.Count -gt 0) {
    Write-Host "Current directory is not empty (only tools/ and an empty .git are allowed). Found:"
    foreach ($f in $found) { Write-Host "  $($f.Name)" }
    Stop-Init 2 "InPlace target not empty: $proj"
  }
  if (Test-Path -LiteralPath (Join-Path $proj ".git")) {
    Invoke-Native git @("-C", $proj, "rev-parse", "-q", "--verify", "HEAD") | Out-Null
    if ($LASTEXITCODE -eq 0) { Stop-Init 2 "InPlace target .git already has commits: $proj" }
  }
} else {
  $proj = Join-Path $Parent $ProjectName
  if ((Test-Path -LiteralPath $proj) -and @(Get-ChildItem -LiteralPath $proj -Force).Count -gt 0) {
    Stop-Init 2 "Target exists and is not empty: $proj"
  }
}

$tplDir = Join-Path $PSScriptRoot "templates"
$tplNames = @("CLAUDE.md.tpl", "claude-shell.local.tpl", "claude-shell.cloud.tpl", "gitignore.base.tpl", "gitattributes.tpl", "architecture.md.tpl", "decisions.md.tpl")
if ($Clasp) { $tplNames += "claspignore.tpl" }
foreach ($t in $tplNames) {
  if (-not (Test-Path -LiteralPath (Join-Path $tplDir $t))) {
    Write-Host "Template missing: $(Join-Path $tplDir $t)" -ForegroundColor Red
    exit 3
  }
}
$packerSrc = Join-Path $PSScriptRoot "deploy.ps1"
if ($Type -eq "Skill" -and -not (Test-Path -LiteralPath (Join-Path $proj "tools\deploy.ps1")) -and -not (Test-Path -LiteralPath $packerSrc)) {
  Write-Host "Packer missing: $packerSrc" -ForegroundColor Red
  exit 3
}

if ($GitUser -or $GitEmail) {
  if (-not ($GitUser -and $GitEmail)) { Stop-Init 2 "-GitUser and -GitEmail must be given together" }
} else {
  if (Test-Path -LiteralPath (Join-Path $proj ".git")) {
    $email = Invoke-Native git @("-C", $proj, "config", "user.email")
  } else {
    $email = Invoke-Native git @("config", "--global", "user.email")
    if (-not $email) { $email = Invoke-Native git @("config", "--system", "user.email") }
  }
  if (-not $email) {
    Write-Host "git user.email is not set (any scope). init.ps1 never sets git identity." -ForegroundColor Red
    Write-Host "Set it yourself, or pass -GitUser and -GitEmail for a repo-local identity." -ForegroundColor Red
    exit 4
  }
}

$today = (Get-Date).ToString("yyyy-MM-dd")
function Get-Rendered([string]$Name) {
  $t = [System.IO.File]::ReadAllText((Join-Path $tplDir $Name))
  if ($Name -eq "CLAUDE.md.tpl") {
    $shell = [System.IO.File]::ReadAllText((Join-Path $tplDir "claude-shell.$Execution.tpl"))
    if ($shell.EndsWith("`r`n")) { $shell = $shell.Substring(0, $shell.Length - 2) }
    elseif ($shell.EndsWith("`n")) { $shell = $shell.Substring(0, $shell.Length - 1) }
    $t = $t.Replace("{{SHELL_SECTION}}", $shell)
  }
  return $t.Replace("{{PROJECT_NAME}}", $ProjectName).Replace("{{EXECUTION}}", $Execution).Replace("{{DATE}}", $today)
}

Write-Host "Scaffolding $Type project '$ProjectName' ($Execution) at $proj" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Common directories (both types)
# ---------------------------------------------------------------------------
$commonDirs = @("handoff_specs", "tools", "docs", ".scratch\probe", ".scratch\build", ".scratch\logs", ".scratch\misc")
if ($Execution -eq "local") { $commonDirs += ".claude" }
foreach ($d in $commonDirs) { New-Item -ItemType Directory -Force -Path (Join-Path $proj $d) | Out-Null }

if ($Execution -eq "local") {
  # .claude/settings.json -- generic PowerShell lock (byte-for-byte from validated template)
  Write-Utf8NoBom (Join-Path $proj ".claude\settings.json") @'
{
  "env": { "CLAUDE_CODE_USE_POWERSHELL_TOOL": "1" },
  "defaultShell": "powershell"
}
'@
} else {
  # handoff_specs/ is tracked in cloud mode
  Write-Utf8NoBom (Join-Path $proj "handoff_specs\.gitkeep") ""
}

# .gitattributes -- eol normalization
Write-Utf8NoBom (Join-Path $proj ".gitattributes") (Get-Rendered "gitattributes.tpl")

# .gitignore -- base list (+ MCP extras) (+ /handoff_specs/ in local mode)
$gitignore = Get-Rendered "gitignore.base.tpl"
if (-not $gitignore.EndsWith("`n")) { $gitignore += "`n" }
if ($Type -eq "MCP") { $gitignore += "node_modules/`n*.log`n" }
if ($Execution -eq "local") { $gitignore += "/handoff_specs/`n" }
Write-Utf8NoBom (Join-Path $proj ".gitignore") $gitignore

# CLAUDE.md -- generic skeleton (PowerShell rules + command mapping + read-only + ASCII console).
# Project-specific layout/runtime constraints are added by the project spec; this is the reusable base.
Write-Utf8NoBom (Join-Path $proj "CLAUDE.md") (Get-Rendered "CLAUDE.md.tpl")

# docs/
Write-Utf8NoBom (Join-Path $proj "docs\architecture.md") (Get-Rendered "architecture.md.tpl")
Write-Utf8NoBom (Join-Path $proj "docs\decisions.md") (Get-Rendered "decisions.md.tpl")

if ($Clasp) { Write-Utf8NoBom (Join-Path $proj ".claspignore") (Get-Rendered "claspignore.tpl") }

# ---------------------------------------------------------------------------
if ($Type -eq "Skill") {
  # Skill: Python stdlib, pytest dev-only, zip deploy
  $skillDirs = @("lib", "lib\clients", "scripts", "references", "tests\unit", "tests\acceptance")
  foreach ($d in $skillDirs) { New-Item -ItemType Directory -Force -Path (Join-Path $proj $d) | Out-Null }

  # package markers (only these two, per recon; tests dirs have none)
  Write-Utf8NoBom (Join-Path $proj "lib\__init__.py") ""
  Write-Utf8NoBom (Join-Path $proj "lib\clients\__init__.py") ""

  # requirements.txt -- dev-only (zero runtime deps; stdlib-only skills)
  Write-Utf8NoBom (Join-Path $proj "requirements.txt") @'
pytest>=8.0
'@

  # pytest.ini -- acceptance marker registration (the validated convention)
  Write-Utf8NoBom (Join-Path $proj "pytest.ini") @'
[pytest]
markers =
    acceptance: live-network integration tests
'@

  # SKILL.md -- front-matter stub only (description filled by project spec)
  Write-Utf8NoBom (Join-Path $proj "SKILL.md") @"
---
name: $ProjectName
description: >
  TODO (project spec fills this): one-paragraph trigger description. Read-only.
---

# $ProjectName

Run: python3 scripts/<entry>.py ... (use python on Windows if python3 is not available).
See references/runtime.md for run-time constraints and the output contract.
"@

  # references/runtime.md -- run-time facts ship with the skill (CLAUDE.md is dev-only and never ships)
  Write-Utf8NoBom (Join-Path $proj "references\runtime.md") @'
# Runtime notes
Run-time constraints, data caveats and the output contract of this skill. This file ships with the skill.
Keep it platform-neutral: no PowerShell, no Windows paths. Developer-session rules belong in CLAUDE.md, which does not ship.

## Constraints
## Data sources and caveats
## Output contract
'@

  # tools/deploy.ps1 -- Python-zipfile ALLOWLIST packer (DEFINITIVE: never Compress-Archive).
  # Copied from this bundle; an existing tools\deploy.ps1 (InPlace) is left unchanged.
  $packerDst = Join-Path $proj "tools\deploy.ps1"
  if (-not (Test-Path -LiteralPath $packerDst)) { Copy-Item -LiteralPath $packerSrc -Destination $packerDst }

  Write-Host "Skill scaffold done. Creating venv..." -ForegroundColor Cyan
  Push-Location $proj
  Invoke-Native python @("-m", "venv", ".venv")
  Invoke-Native ".\.venv\Scripts\python.exe" @("-m", "pip", "install", "--upgrade", "pip", "--quiet")
  Invoke-Native ".\.venv\Scripts\python.exe" @("-m", "pip", "install", "-r", "requirements.txt", "--quiet")
  Pop-Location
}
# ---------------------------------------------------------------------------
elseif ($Type -eq "MCP") {
  # MCP: TypeScript, pnpm, Inspector. NOTE: skeleton not yet battle-tested on a real MCP project;
  # validate/refine on the first MCP build, then fold corrections back into this branch.
  $mcpDirs = @("src", "src\tools", "src\sources", "tests")
  foreach ($d in $mcpDirs) { New-Item -ItemType Directory -Force -Path (Join-Path $proj $d) | Out-Null }

  Write-Utf8NoBom (Join-Path $proj "package.json") @"
{
  "name": "$ProjectName",
  "version": "0.1.0",
  "type": "module",
  "bin": { "$ProjectName": "dist/index.js" },
  "scripts": {
    "build": "tsc",
    "test": "vitest run",
    "inspector": "npx @modelcontextprotocol/inspector node dist/index.js"
  },
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0",
    "viem": "^2.0.0",
    "zod": "^3.23.0"
  },
  "devDependencies": {
    "typescript": "^5.4.0",
    "vitest": "^1.6.0",
    "@types/node": "^20.0.0"
  }
}
"@

  Write-Utf8NoBom (Join-Path $proj "tsconfig.json") @'
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "Bundler",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "declaration": true
  },
  "include": ["src/**/*.ts"]
}
'@

  Write-Host "MCP scaffold done. Installing deps via pnpm..." -ForegroundColor Cyan
  Push-Location $proj
  Invoke-Native pnpm @("install")
  Pop-Location
}

# ---------------------------------------------------------------------------
# git init (both types). Never push, never gh.
$version = "dev"
foreach ($v in @((Join-Path $PSScriptRoot "VERSION"), (Join-Path $PSScriptRoot "..\VERSION"), (Join-Path $proj "tools\VERSION"))) {
  if (Test-Path -LiteralPath $v) { $version = ([System.IO.File]::ReadAllText($v)).Trim(); break }
}
Push-Location $proj
Invoke-Native git @("init", "-q", "-b", "main")
# re-init of an existing empty repo ignores -b; point HEAD at main explicitly
Invoke-Native git @("symbolic-ref", "HEAD", "refs/heads/main")
Invoke-Native git @("config", "core.autocrlf", "input")
if ($GitUser -and $GitEmail) {
  Invoke-Native git @("config", "user.name", $GitUser)
  Invoke-Native git @("config", "user.email", $GitEmail)
}
Invoke-Native git @("add", "-A")
Invoke-Native git @("commit", "-q", "-m", "chore: scaffold from web3-dev-tools $version")
$commitExit = $LASTEXITCODE
Pop-Location
if ($commitExit -ne 0) { throw "git commit failed (exit $commitExit)" }

Write-Host ""
Write-Host "DONE. Next: create an empty GitHub repository, add it as origin, push main." -ForegroundColor Green
Write-Host "  Project root: $proj"
exit 0
