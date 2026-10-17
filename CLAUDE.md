# Project conventions for Claude Code -- web3-dev-tools

> Execution: local (PowerShell tooling is verified on Windows)
> Baseline shell: Windows PowerShell 5.1; every script must also run on PowerShell 7+.
> Invoke scripts as `powershell -NoProfile -ExecutionPolicy Bypass -File <script>`.

## Pre-flight
Before any task: `git status --porcelain` must be empty. If not, STOP and report.

## Scratch files
All temporary files go under `.scratch/{probe,build,logs,misc}/` inside this repo. Never use the OS temp folder or any path outside the repo. Never save request headers or `curl -v` output. Write JSON scratch files as UTF-8 via Python.

## Release bundle
Never edit files under `src/` without regenerating `src/MANIFEST.sha256` via `scripts/release.ps1`.

## Public repo
No secrets, no strategy parameters, no account-specific paths or names. ASCII-only text files.
Write text files without a BOM: `[System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))`.
