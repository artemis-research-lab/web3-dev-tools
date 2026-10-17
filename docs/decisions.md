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
- D11 - Execution-specific shell section - 2026-10-17 - The CLAUDE.md shell section depends on the execution mode: `-Execution local` gets the PowerShell rules, `-Execution cloud` gets Bash rules; the rest of CLAUDE.md is shared.
- D12 - Keep tools bytes - 2026-10-17 - Scaffolded projects keep `tools/**` byte-for-byte (`-text`), so the bundle manifest stays verifiable after a clone.
- D13 - Neutral comments - 2026-10-17 - Comments in the public bundle name no internal project and state no incident details beyond "an earlier blocklist design failed in practice".
- D14 - Run-time-only skill package - 2026-10-17 - A skill package contains only what the skill needs at run time and is platform-neutral: `SKILL.md`, `scripts/` and `lib/` (`*.py`), and optionally `references/`, `data/`, `config/` with data-type files; `CLAUDE.md`, `requirements.txt`, `pytest.ini`, `tests/`, `docs/`, `tools/`, `handoff_specs/`, `.scratch/`, `.claude/` never ship.
- D15 - Allowlist plus hard deny list - 2026-10-17 - The packer applies the allowlist first, then a hard deny list that holds even inside allowed directories (`.env*`, `*.key`, `*.pem`, names containing `secret` or `credential`, `*.pyc`, `__pycache__`, `.git*`); the shipped file list is printed on every run and the build fails if a denied name would ship.
- D16 - Run-time facts outside CLAUDE.md - 2026-10-17 - Run-time constraints, data caveats and output contracts of a skill live in `SKILL.md` or `references/`, never in `CLAUDE.md`; skill code and `SKILL.md` run instructions are OS-neutral (no PowerShell; `pathlib`; interpreter named as "python3, or python on Windows").
- D17 - new-project is a local skill - 2026-10-17 - `skills/new-project` is a Claude Code LOCAL skill (Windows PowerShell 5.1). It is not a packaged skill: it never goes through `deploy.ps1`, D14 does not apply to it, and it lives outside `src/`, so it is not in the manifest.
- D18 - Logic in bootstrap.ps1 - 2026-10-17 - All logic is in `bootstrap.ps1`; `SKILL.md` only tells Claude Code when to call it and forbids workarounds. Claude Code must not download or copy tool files by hand.
- D19 - Bootstrap trust chain - 2026-10-17 - A pinned tag (`vX.Y.Z` only, floating refs refused) plus `MANIFEST.sha256`, per-file SHA-256, and a manifest hash pinned inside `bootstrap.ps1` (`$DefaultManifestSha256`, rewritten by `scripts/release.ps1`). Tags are mutable, so the pinned manifest hash is what detects a moved tag.
- D20 - Git identity outside the repo - 2026-10-17 - Git identity is never stored in the repo. `bootstrap.ps1` reads `identity.json` next to itself (installed by the user, never committed) or `-GitUser`/`-GitEmail`, and passes both to `init.ps1`. Missing identity exits 4.
- D1 clarification - 2026-10-17 - The repo's own `owner/repo` slug may appear in `bootstrap.ps1`; secrets, emails and noreply ids may not.

## Validation records

## Incidents

## Baselines
