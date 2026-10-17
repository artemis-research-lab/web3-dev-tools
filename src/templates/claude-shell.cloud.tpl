## SHELL -- Bash on Linux (cloud session)
First tool call: `ls -la | head -20`
This project runs in a cloud environment (Linux, Bash). PowerShell cmdlets do not exist here: do not use them and do not try to install PowerShell.
Use forward-slash paths. Do not run tools/*.ps1 (they are verified on Windows only).
Run Python as `python3`; install dev dependencies with `pip install -r requirements.txt` only if the task needs them.
Never print environment variables, tokens or request headers.
Finish every task with a commit and a push; report branch and full commit hash.
