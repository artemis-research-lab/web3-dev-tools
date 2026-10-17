# web3-dev-tools - Architecture

## Purpose
Maintain one versioned, checksummed bundle (`src/`) of the scaffold script, Skill packer and templates that new Web3 projects consume by pinned release tag; it does not hold project code.

## Modules
### Scaffold
- Responsibility: Create a new Skill or MCP project tree, rendered from the templates, in local or cloud execution mode, and make its first commit. The CLAUDE.md shell section is execution-specific: PowerShell rules for local, Bash rules for cloud.
- Input: Project name, type, execution mode, target (parent directory or current directory) and optional repo-local git identity.
- Output: A scaffolded git repository with one commit, or a refusal exit code with nothing written.
- Depends on: Packer.

### Packer
- Responsibility: Package a Skill project into a forward-slash zip and/or sync it to the local skills folder from an allowlist.
- Input: The Skill project's working tree.
- Output: `dist/<name>.zip` and/or a synced skill folder.
- Depends on: none.

### Release
- Responsibility: Regenerate the bundle manifest and check that the repo and bundle versions agree.
- Input: The `src/` directory and both VERSION files.
- Output: `src/MANIFEST.sha256` and the tag command to run.
- Depends on: Scaffold, Packer.

### Smoke tests
- Responsibility: Prove scaffold, refusal, packer allowlist and manifest integrity end to end.
- Input: The working tree of this repo.
- Output: `SMOKE PASS` or `SMOKE FAIL <n>` with a matching exit code.
- Depends on: Scaffold, Packer, Release.

## Known Limits
- Windows only; verified on Windows PowerShell 5.1, must also run on PowerShell 7+.
- The packer targets Skill projects only.
- The MCP scaffold is unvalidated (v2.0 11.1).

## Coding Notes
- ASCII only in every text file; no BOM.
- Refuse, never overwrite.
- Exit codes are part of the contract: 0 ok, 2 precondition refused, 3 template missing, 4 git identity missing.
- Scripts never push and never call `gh`.
