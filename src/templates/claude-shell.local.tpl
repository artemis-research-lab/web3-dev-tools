## CRITICAL -- SHELL: PowerShell ONLY (Windows PowerShell 5.1 or 7) -- verify before ANY other action
First tool call: `Get-ChildItem | ConvertTo-Json -Depth 1`
If bash error -> STOP, report shell misconfiguration, do NOT translate to bash.

## PowerShell command mapping
| Use | NOT |
| Get-ChildItem | ls |    | Test-Path | test -e | | Remove-Item | rm |
| Get-Content | cat |     | Set-Content | > | | Select-String | grep |
| `$env:VAR = "x"` | export | | Where-Object | awk | | ForEach-Object | xargs |

## Console output
ASCII only in Write-Host strings (-> OK WARNING, not arrows/checkmarks) -- avoids codepage mojibake.
