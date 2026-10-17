---
name: new-project
description: Create a new project scaffold in the current EMPTY directory from the pinned web3-dev-tools bundle. Use when the user asks to set up / create / bootstrap a new project, skill or MCP server here. Claude Code local sessions on Windows only.
---

# new-project

Scope: Claude Code local sessions on Windows only. Not for cloud sessions. This skill is not packaged and never ships in a skill zip.

## Inputs
- `ProjectName` (required): lowercase letters, digits and `-`. Ask the user only if it is missing.
- `Type`: `Skill` or `MCP`. Default `Skill`.
- `Execution`: `local` or `cloud`. Default `local`. Use `cloud` only if the user says the project will be built in cloud sessions.

## Step 1 - check the directory
Run `Get-ChildItem -Force | Select-Object Name` in the current directory and show the output.
If it contains anything except an empty `.git` or an empty `tools/`, STOP and tell the user.

## Step 2 - run the bootstrap
Run exactly:

```
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.claude\skills\new-project\bootstrap.ps1" -ProjectName <name> -Type <Skill|MCP> -Execution <local|cloud>
```

## Step 3 - report the result
Show the full output. On a non-zero exit code, report the code and the last lines of output and STOP.
Do not retry with other commands, do not download files with Invoke-WebRequest or curl, do not edit `tools/`,
and do not set git identity yourself.

Exit codes: 0 ok, 2 precondition refused, 3 template missing, 4 git identity missing,
5 integrity or verification failure, 6 ref refused.

## Step 4 - next steps
Report `git log --oneline` and `git status --porcelain` (it must be empty). Then print these next steps
for the user, as text only (do not run them):
1. Create an EMPTY repository on GitHub (no README, no license).
2. `git remote add origin https://github.com/<owner>/<repo>.git`
3. `git push -u origin main`

## Hard rules
- Never run `git push`, `gh`, or anything that needs a credential.
- Never create or print secrets.
- Never pass `-Ref` unless the user explicitly names a tag.
