#Requires -Version 5.1
<#
.SYNOPSIS
    Queries w32tm /query /source and /configuration on multiple Windows Server
    2016 hosts and compares the configuration output side-by-side.

.DESCRIPTION
    Runs 'w32tm /query /source' followed by 'w32tm /query /configuration'
    remotely via Invoke-Command (WinRM) on each server listed in a plain-text
    file (one hostname or IP per line, up to 10 servers), parses the
        configuration key=value pairs, and produces:
            1. A per-server text file containing source output followed by configuration output.
            2. A console comparison table showing configuration settings and each server's value.
            3. A highlighted list of configuration settings that differ across servers.
            4. A CSV export of the configuration comparison.

        The source output is retained in each per-server text file and is not included
        in the configuration comparison table or CSV.

.NOTES
    Prerequisites
    -------------
    - WinRM must be enabled on target servers (Enable-PSRemoting).
    - The account running this script needs admin rights on the target servers.
    - Run this script from a machine that can reach the target servers over the
      network (TCP 5985/5986).
    - Create a plain-text file (default: servers.txt next to this script) with
      one server hostname or IP address per line. Blank lines and lines starting
      with '#' are ignored. Maximum 10 servers are used.

    To skip credential prompts, run from a domain account that already has
    local-admin rights on the targets, or pre-populate $Credential below.
#>

# ---------------------------------------------------------------------------
# CONFIGURATION — edit these values before running
# ---------------------------------------------------------------------------

# Path to a plain-text file containing one server hostname or IP per line.
# Blank lines and lines beginning with '#' are ignored. Max 10 servers are used.
$ServersFile = Join-Path $PSScriptRoot 'servers.txt'

# Optional: set to $true to be prompted for credentials once (used for all servers)
$UseCredential = $false

# Directory where per-server raw output files are saved
$OutputDir = Join-Path $PSScriptRoot 'W32TM_Results'

# ---------------------------------------------------------------------------
# SCRIPT BODY — no edits needed below this line
# ---------------------------------------------------------------------------

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Load server list from file --------------------------------------------

if (-not (Test-Path $ServersFile)) {
    Write-Error "Servers file not found: $ServersFile`nCreate a plain-text file with one hostname or IP per line."
    exit 1
}

$Servers = @(Get-Content -Path $ServersFile |
    Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' } |  # skip blank/comment lines
    ForEach-Object { $_.Trim() } |
    Select-Object -First 10)  # cap at 10 servers

if ($Servers.Count -eq 0) {
    Write-Error "No valid server entries found in: $ServersFile"
    exit 1
}

Write-Host "Loaded $($Servers.Count) server(s) from $ServersFile" -ForegroundColor Cyan
if ($Servers.Count -eq 10) {
    Write-Warning 'Server list capped at 10 entries.'
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
}

$Credential = $null
if ($UseCredential) {
    $Credential = Get-Credential -Message 'Enter credentials for remote servers'
}

# --- Collect results -------------------------------------------------------

$AllResults = [ordered]@{}   # server -> [ordered]@{ key -> value }

foreach ($Server in $Servers) {
    Write-Host "`n[*] Querying $Server ..." -ForegroundColor Cyan

    $invokeParams = @{
        ComputerName = $Server
        ScriptBlock  = {
            w32tm /query /source
            w32tm /query /configuration
        }
        ErrorAction  = 'Stop'
    }
    if ($Credential) { $invokeParams['Credential'] = $Credential }

    try {
        $rawLines = Invoke-Command @invokeParams

        # Save raw output
        $rawFile = Join-Path $OutputDir "$Server`_w32tm.txt"
        $rawLines | Set-Content -Path $rawFile -Encoding UTF8
        Write-Host "    Saved raw output -> $rawFile" -ForegroundColor DarkGray

        # Parse configuration fields while retaining section/provider context.
        $parsed = [ordered]@{}
        $section = ''
        $provider = ''
        foreach ($line in $rawLines) {
            $trimmedLine = $line.Trim()
            if (-not $trimmedLine) { continue }

            if ($trimmedLine -match '^\[(.+)\]$') {
                $section = $Matches[1].Trim()
                $provider = ''
                continue
            }

            if ($trimmedLine -match '^(.+?)\s+\([^)]*\)$' -and $trimmedLine -notmatch ':') {
                $provider = ($Matches[1]).Trim()
                continue
            }

            if ($trimmedLine -match '^(.+?)\s*:\s*(.+?)\s*(\([^)]*\))?\s*$') {
                $field  = $Matches[1].Trim()
                $value = $Matches[2].Trim()
                if ($Matches[3]) { $value += " $($Matches[3].Trim())" }
                $keyParts = @($section, $provider, $field) | Where-Object { $_ }
                $key = $keyParts -join '\'
                $parsed[$key] = $value
            }
        }
        $AllResults[$Server] = $parsed
        Write-Host "    Parsed $($parsed.Count) settings." -ForegroundColor Green
    }
    catch {
        Write-Warning "    FAILED to query $Server : $_"
        $AllResults[$Server] = [ordered]@{ ERROR = $_.ToString() }
    }
}

if ($AllResults.Count -eq 0) {
    Write-Warning 'No results collected. Exiting.'
    exit 1
}

# --- Build a unified key list (superset of all keys) -----------------------

$AllKeys = @()
foreach ($result in $AllResults.Values) {
    foreach ($key in $result.Keys) {
        if ($AllKeys -notcontains $key) {
            $AllKeys += $key
        }
    }
}

# --- Display comparison table ----------------------------------------------

Write-Host "`n`n============================  W32TM CONFIGURATION COMPARISON  ============================" -ForegroundColor Yellow

# Build objects for Format-Table
$tableRows = foreach ($key in $AllKeys) {
    $row = [ordered]@{ Setting = $key }
    foreach ($srv in $AllResults.Keys) {
        $row[$srv] = if ($AllResults[$srv].Contains($key)) { $AllResults[$srv][$key] } else { '<not present>' }
    }
    [PSCustomObject]$row
}

$tableRows | Format-Table -AutoSize -Wrap

# --- Highlight differences -------------------------------------------------

$diffs = foreach ($row in $tableRows) {
    $vals = $AllResults.Keys | ForEach-Object {
        $srv = $_
        if ($AllResults[$srv].Contains($row.Setting)) { $AllResults[$srv][$row.Setting] } else { '<not present>' }
    }
    if (($vals | Select-Object -Unique | Measure-Object).Count -gt 1) {
        $row
    }
}

Write-Host "`n============================  SETTINGS THAT DIFFER  ============================" -ForegroundColor Red

if ($diffs) {
    $diffs | Format-Table -AutoSize -Wrap
} else {
    Write-Host '  All queried servers have identical w32tm configurations.' -ForegroundColor Green
}

# --- Save comparison CSV ---------------------------------------------------

$csvPath = Join-Path $OutputDir 'w32tm_comparison.csv'
$tableRows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
Write-Host "`nFull comparison saved to: $csvPath" -ForegroundColor Cyan

Write-Host "`nDone." -ForegroundColor Green
