# web3-dev-tools - Decisions and Records

## Decisions
- D1 - Public repo - 2026-10-17 - Public repo with no secrets, no strategy parameters and no account-specific paths or names, so any project can fetch it without credentials.
- D2 - Pinned tags - 2026-10-17 - Consumers pin a release tag `vX.Y.Z` and never track `main`, so a scaffold is reproducible.
- D3 - Bundle and integrity - 2026-10-17 - The consumable bundle is `src/` only; `src/MANIFEST.sha256` holds the SHA-256 of every other file in `src/` (relative paths, forward slashes) so downloads can be verified.
- D4 - PowerShell baseline - 2026-10-17 - Every script runs on Windows PowerShell 5.1 and PowerShell 7+ (`#requires -Version 5.1`, no PS7-only syntax); `init.ps1` is parameterised and refuses rather than overwrites.
- D5 - No push - 2026-10-17 - `init.ps1` never runs `git push` or `gh`; remote creation is a separate human step.
- D6 - Execution modes - 2026-10-17 - `-Execution local` (default) and `-Execution cloud` differ only in `/handoff_specs/` (ignored in local, tracked in cloud) and `.claude/settings.json` (PowerShell lock in local, absent in cloud, because it would break Linux cloud sessions).
- D7 - Text format - 2026-10-17 - All text files are ASCII-only; line endings come from `.gitattributes` (`* text=auto`, `*.ps1` CRLF, `*.py`/`*.md`/`*.sh` LF). In this repo `src/**` is `-text` so served bytes match the manifest.
- D8 - v2.0 compatibility - 2026-10-17 - `init.ps1` keeps v2.0 behaviour byte-for-byte for the generic Skill/MCP files unless a later decision changes it.
- D9 - No BOM - 2026-10-17 - Text files are written with .NET UTF-8 without BOM (`System.Text.UTF8Encoding($false)`), never `Out-File`/`Set-Content -Encoding utf8`, and `Invoke-WebRequest` always gets `-UseBasicParsing`, because 5.1 writes a BOM and needs basic parsing.
- D10 - Allowlist packer - 2026-10-17 - The canonical packer is the allowlist packer from `init.ps1` v2.0, shipped as `src/deploy.ps1`; the older blocklist packer is rejected because a previous skill zip leaked `.env`.

## Validation records

## Incidents

## Baselines
