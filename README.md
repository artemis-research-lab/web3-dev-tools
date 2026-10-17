# web3-dev-tools

One versioned, checksummed bundle of the tooling every new Web3 project starts from:
the scaffold script (`src/init.ps1`), the Skill packer (`src/deploy.ps1`) and the templates.
Consumers take the `src/` directory of a pinned release tag; integrity is `src/MANIFEST.sha256`.

## Consume a pinned release

Download the manifest of the tag, then every file it lists, and compare hashes
(Windows PowerShell 5.1 or PowerShell 7):

```powershell
$tag  = "v0.1.0"
$base = "https://raw.githubusercontent.com/artemis-research-lab/web3-dev-tools/$tag/src"
$dst  = ".\tools"
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Invoke-WebRequest -UseBasicParsing "$base/MANIFEST.sha256" -OutFile "$dst\MANIFEST.sha256"
$bad = 0
foreach ($line in Get-Content "$dst\MANIFEST.sha256") {
  $hash, $rel = $line -split ' ', 2
  $out = Join-Path $dst ($rel -replace '/', '\')
  New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
  Invoke-WebRequest -UseBasicParsing "$base/$rel" -OutFile $out
  if ((Get-FileHash $out -Algorithm SHA256).Hash.ToLower() -ne $hash) { Write-Host "MISMATCH $rel"; $bad++ }
}
if ($bad -eq 0) { Write-Host "OK all files match the manifest" }
```

Then scaffold, for example into the current directory (which may contain only `tools/`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\init.ps1 -ProjectName my-skill -Type Skill -InPlace
```

`init.ps1` refuses rather than overwrites and never pushes. Exit codes: 0 ok, 2 precondition
refused, 3 template missing, 4 git identity missing.

## Install the new-project skill

The `new-project` skill lets a local Claude Code session on Windows bootstrap a project in an
empty directory from the pinned release. Install it from a checkout of this repo, then put your
git name and GitHub noreply email into `identity.json` (it stays on your machine, never in a repo):

```powershell
Copy-Item -Recurse -Force .\skills\new-project "$env:USERPROFILE\.claude\skills\"
Copy-Item "$env:USERPROFILE\.claude\skills\new-project\identity.example.json" "$env:USERPROFILE\.claude\skills\new-project\identity.json"
notepad "$env:USERPROFILE\.claude\skills\new-project\identity.json"
```

## Smoke test

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\smoke.ps1
```

It works under `.scratch/build/` only and prints `SMOKE PASS` or `SMOKE FAIL <n>`.

## Versioning

Consumers pin a release tag `vX.Y.Z` and never track `main`. A release is cut by running
`scripts/release.ps1` (regenerates the manifest, checks `VERSION`) and then creating the tag it prints.
