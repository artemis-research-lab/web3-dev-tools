# Project conventions for Claude Code -- {{PROJECT_NAME}}

> Scope: these rules apply to Claude Code sessions. A Chat/Design session that reads this file does so for context only.
> Execution: {{EXECUTION}}
> In cloud sessions the shell is Bash on Linux; the "PowerShell not Bash" rule applies to Local sessions only.
> Do not run tools/*.ps1 in a cloud session unless `pwsh` is installed. Never write secrets to the repo.
> Every task ends with a commit; in cloud sessions it also ends with a push. Report branch and full commit hash in Block C.

## CRITICAL -- SHELL: PowerShell ONLY (Windows PowerShell 5.1 or 7) -- verify before ANY other action
First tool call: `Get-ChildItem | ConvertTo-Json -Depth 1`
If bash error -> STOP, report shell misconfiguration, do NOT translate to bash.

## HANDOFF SPECS -- how I am invoked
"build the project in handoff_specs/<f>.md" / "build the module in handoff_specs/<f>.md" /
"apply the patch in handoff_specs/<f>.md" / "Do the probe in handoff_specs/<f>.md":
1. Read the file with View. 2. Follow verbatim; section 0 + 0.5 canary bind the session.
3. Return the spec's Block A/B/C/D (or probe return contract), no substitutions.
4. VERBATIM sections are copied character-for-character.

## PowerShell command mapping
| Use | NOT |
| Get-ChildItem | ls |    | Test-Path | test -e | | Remove-Item | rm |
| Get-Content | cat |     | Set-Content | > | | Select-String | grep |
| `$env:VAR = "x"` | export | | Where-Object | awk | | ForEach-Object | xargs |

## Read-only scope (NEVER violate)
Forbidden symbols: signTransaction, sendTransaction, PrivateKey, Keypair, secretKey,
mnemonic, ethers.Wallet, from web3 import, from viem import.

## Console output
ASCII only in Write-Host strings (-> OK WARNING, not arrows/checkmarks) -- avoids codepage mojibake.

## Pre-flight
Before any task: `git status --porcelain` must be empty. If not, STOP and report.

## Scratch files
All temporary files go under `.scratch/{probe,build,logs,misc}/` inside this repo. Never use the OS temp folder or any path outside the repo. Never save request headers or `curl -v` output. Write JSON scratch files as UTF-8 via Python.

## Docs
Read `docs/architecture.md` first, in every session. `docs/` files are English. architecture.md holds Purpose, Modules (Responsibility / Input / Output / Depends on), Known Limits, Coding Notes only: no implementation details.

## PROJECT LAYOUT / runtime constraints
(Filled by the project handoff spec.)
