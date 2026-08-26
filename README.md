# W32 Time Sync Comparison

This folder contains a PowerShell script for comparing `w32tm /query /configuration /verbose` output across multiple Windows servers and recording each server's `w32tm /query /source` result.

## What it does

`Compare-W32tmConfig.ps1`:

- Reads target server names or IP addresses from `servers.txt`
- Runs `w32tm /query /source`, then `w32tm /query /configuration /verbose`, remotely through WinRM
- Audits Windows Time policy parameters under `HKLM\SOFTWARE\Policies\Microsoft\W32Time` and records applied computer policies with `gpresult`
- Saves the source output, configuration output, and policy audit in the existing per-server text file in `W32TM_Results/`
- Prints a side-by-side comparison table in the console
- Highlights configuration settings that differ between servers
- Exports the full comparison to `W32TM_Results/w32tm_comparison.csv`

The source result is included in each host text file for reference. The comparison table and CSV contain configuration settings only. CSV setting names retain the configuration section and time-provider context, such as `TimeProviders\NtpClient\Enabled`, so duplicate fields from different sections are not overwritten.

### Policy control

The policy audit checks the Windows Time policy registry path `HKLM\SOFTWARE\Policies\Microsoft\W32Time` on each target and records every policy parameter found there. It also includes the applied computer policy summary from `gpresult /scope computer /r`. A parameter reported as `(Policy)` by `w32tm /query /configuration /verbose` is controlled by policy; `(Local)` indicates local configuration.

When the policy contains an `NtpServer` value, the audit labels it as the NTP policy server/URL. Windows does not expose a universal web URL for the originating Group Policy Object through `w32tm`; use the applied GPO names in the `gpresult` section to locate the policy in Group Policy Management.

### Common `w32tm` type values

The `TimeProviders\NtpClient\Type` value identifies the synchronization method:

| Type | Meaning |
| --- | --- |
| `NTP` | Synchronize directly with the configured NTP servers. |
| `NT5DS` | Synchronize through the Active Directory domain hierarchy. Domain members normally use a domain controller, ultimately tracing to the forest-root PDC emulator. |
| `AllSync` | Use all available synchronization mechanisms. |
| `NoSync` | Do not synchronize the system clock. |

`NT5DS` is the standard Windows value for domain-hierarchy synchronization. `NT6DS` is not a standard `w32tm` type; check the raw host output if it appears.

### CSV format

The CSV contains one row per configuration field. The `Setting` column identifies the section and time provider, followed by one column for each server:

```csv
"Setting","server01","server02"
"Configuration\EventLogFlags","2 (Local)","2 (Local)"
"TimeProviders\NtpClient\Enabled","1 (Local)","1 (Local)"
"TimeProviders\NtpClient\Type","NT5DS (Policy)","NTP (Local)"
"TimeProviders\VMICTimeProvider\Enabled","1 (Local)","0 (Local)"
```

Setting rows retain the order in which fields first appear in the queried hosts; they are not alphabetically sorted.

## Requirements

- Windows PowerShell 5.1 or later
- WinRM enabled on the target servers
- Permission to run remote commands on the target servers
- Network access to the servers over WinRM ports 5985 or 5986

### Enabling WinRM on the target server

On each target server, enable PowerShell remoting so `Invoke-Command` can connect:

```powershell
Enable-PSRemoting -Force
```

If needed, also confirm that:

```powershell
Get-Service WinRM
Get-NetFirewallRule -DisplayGroup 'Windows Remote Management' | Select-Object DisplayName, Enabled, Profile, Direction, Action
Test-WSMan localhost
```

- `Get-Service WinRM` confirms that the WinRM service is running.
- `Get-NetFirewallRule` checks that the Windows Remote Management firewall rules are enabled for inbound traffic.
- `Test-WSMan localhost` confirms that the server can respond to WinRM requests locally and that remoting is available.

If `Test-WSMan localhost` succeeds but remote connections still fail, verify that the account running the script has permission to connect and query the remote server.

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

- `*_w32tm.txt` files for each server, with `/source`, `/configuration /verbose`, and policy audit output
- `w32tm_SxS_comparison.txt` containing the same formatted side-by-side table printed in the console
- `w32tm_comparison.csv` for the configuration comparison across servers

## Notes

- The script uses `Invoke-Command`, so the account running it must be allowed to query the remote servers.
- Set `$UseCredential = $true` in the script if you want to be prompted once for credentials.
