# W32 Time Sync Comparison

This folder contains a PowerShell script for comparing `w32tm /query /configuration` output across multiple Windows servers.

## What it does

`Compare-W32tmConfig.ps1`:

- Reads target server names or IP addresses from `servers.txt`
- Runs `w32tm /query /configuration` remotely through WinRM
- Saves the raw output for each server in `W32TM_Results/`
- Prints a side-by-side comparison table in the console
- Highlights configuration settings that differ between servers
- Exports the full comparison to `W32TM_Results/w32tm_comparison.csv`

## Requirements

- Windows PowerShell 5.1 or later
- WinRM enabled on the target servers
- Permission to run remote commands on the target servers
- Network access to the servers over WinRM ports 5985 or 5986

## How to use

1. Edit `servers.txt` and list one hostname or IP address per line.
2. Open PowerShell in this folder.
3. Run:

```powershell
.\Compare-W32tmConfig.ps1
```

## Server list format

`servers.txt` supports:

- One hostname or IP address per line
- Blank lines
- Comment lines beginning with `#`

The script uses the first 10 valid entries.

## Output

Results are written to `W32TM_Results/`:

- `*_w32tm.txt` files for each server
- `w32tm_comparison.csv` for the combined comparison

## Notes

- The script uses `Invoke-Command`, so the account running it must be allowed to query the remote servers.
- Set `$UseCredential = $true` in the script if you want to be prompted once for credentials.
