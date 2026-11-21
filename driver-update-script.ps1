#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Scans driver folders and installs the drivers that match devices in this PC (Windows 10/11)
.DESCRIPTION
    This script recursively searches through driver folders for .inf files. Each INF's hardware
    IDs are compared with the hardware and compatible IDs of the devices present in this PC, and
    only INFs that match a device are added to the driver store and installed with
    "pnputil /add-driver <inf> /install". INFs that match no device are left alone, so the driver
    store doesn't fill up with packages for hardware this PC doesn't have. Results are taken from
    pnputil's exit codes, so they don't depend on the Windows display language.
.PARAMETER DriverPath
    The root path containing driver folders (default: script directory)
.PARAMETER LogPath
    Path for the log file (default: DriverInstall.log in script directory)
.EXAMPLE
    .\driver-update-script.ps1 -DriverPath "C:\Downloads\Drivers"
#>

param(
    [Parameter(Position=0)]
    [string]$DriverPath = $PSScriptRoot,

    [Parameter(Position=1)]
    [string]$LogPath = "$PSScriptRoot\DriverInstall.log"
)

# Initialize logging
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(
        switch($Level) {
            "ERROR" {"Red"}
            "WARNING" {"Yellow"}
            "SUCCESS" {"Green"}
            default {"White"}
        }
    )
    Add-Content -Path $LogPath -Value $logMessage
}

# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Log "This script must be run as Administrator. Exiting..." "ERROR"
    exit 1
}

# pnputil exit codes (see "PnPUtil Return Values" in the Windows driver docs)
$PNPUTIL_SUCCESS          = 0     # added and installed on at least one device
$PNPUTIL_NO_MORE_ITEMS    = 259   # no device took it: no match, or devices already have a better/newer driver
$PNPUTIL_REBOOT_REQUIRED  = 3010  # installed, restart needed to finish

# Architecture name as used in INF model section decorations (NTamd64, NTarm64, NTx86)
$infArch = switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) {
    'X64'   { 'amd64' }
    'Arm64' { 'arm64' }
    'X86'   { 'x86' }
    default { $_.ToLower() }
}

# Returns the hardware and compatible IDs that an INF's model sections list for this
# architecture. An INF without a [Manufacturer] section (e.g. autorun.inf) returns nothing.
function Get-InfHardwareId {
    param([string]$Path)

    # Read the INF into sections, dropping comments and joining "\" continuation lines
    $sections = @{}  # section names are case-insensitive, like PowerShell hashtable keys
    $current = $null
    $pending = ''
    foreach ($rawLine in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        $line = $pending + ($rawLine -replace ';.*$', '').Trim()
        if ($line.EndsWith('\')) {
            $pending = $line.TrimEnd('\')
            continue
        }
        $pending = ''
        if (-not $line) { continue }
        if ($line -match '^\[(.+)\]$') {
            $current = $Matches[1].Trim()
            if (-not $sections.ContainsKey($current)) {
                $sections[$current] = [System.Collections.Generic.List[string]]::new()
            }
        } elseif ($current) {
            $sections[$current].Add($line)
        }
    }

    if (-not $sections.ContainsKey('Manufacturer')) { return }

    # IDs can use %key% tokens from [Strings] (or a localized [Strings.xxxx]), e.g.
    # SWC\%SoftwareComponentId%_VEN8086_IGS
    $strings = @{}
    $stringSections = @($sections.Keys | Where-Object { $_ -like 'Strings.*' }) + @('Strings')
    foreach ($name in $stringSections) {
        if (-not $sections.ContainsKey($name)) { continue }
        foreach ($line in $sections[$name]) {
            if ($line -match '^\s*([^=]+?)\s*=\s*(.*)$') { $strings[$Matches[1]] = $Matches[2].Trim().Trim('"') }
        }
    }
    $expandStrings = [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        $key = $m.Groups[1].Value
        if ($key -eq '') { '%' } elseif ($strings.ContainsKey($key)) { $strings[$key] } else { $m.Value }
    }.GetNewClosure()

    foreach ($entry in $sections['Manufacturer']) {
        # %MfgName% = ModelsSection [, TargetOSVersion, ...]
        $value = if ($entry -match '=') { ($entry -split '=', 2)[1] } else { $entry }
        $parts = @($value -split ',' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ })
        if ($parts.Count -eq 0) { continue }
        $modelsName = $parts[0]

        # Windows only uses the undecorated models section on x86; elsewhere it needs a
        # decoration for the architecture (NTamd64...) or one without any (NT, NT.10.0...)
        $modelSections = @()
        if ($infArch -eq 'x86') { $modelSections += $modelsName }
        $modelSections += @($parts | Select-Object -Skip 1 |
            Where-Object { $_ -match "^NT($infArch)?(\.|$)" } |
            ForEach-Object { "$modelsName.$_" })

        foreach ($name in $modelSections) {
            if (-not $sections.ContainsKey($name)) { continue }
            foreach ($model in $sections[$name]) {
                # DeviceDescription = InstallSection, HardwareId [, CompatibleId ...]
                if ($model -notmatch '=') { continue }
                ($model -split '=', 2)[1] -split ',' | Select-Object -Skip 1 |
                    ForEach-Object { [regex]::Replace($_.Trim().Trim('"'), '%([^%]*)%', $expandStrings) } |
                    Where-Object { $_ }
            }
        }
    }
}

# Returns the hardware and compatible IDs of every device currently present in this PC
function Get-DeviceIdSet {
    $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($device in Get-PnpDevice -PresentOnly) {
        foreach ($id in @($device.HardwareID) + @($device.CompatibleID)) {
            if ($id) { [void]$ids.Add($id) }
        }
    }
    , $ids
}

Write-Log "===== Starting Driver Installation Script ====="
Write-Log "Driver search path: $DriverPath"

# Verify path exists
if (-not (Test-Path $DriverPath)) {
    Write-Log "Driver path does not exist: $DriverPath" "ERROR"
    exit 1
}

# Find all .inf files recursively (the Extension check drops look-alikes such as *.info
# that the "*.inf" filter can match through 8.3 short names)
Write-Log "Searching for driver files (.inf)..."
$infFiles = @(Get-ChildItem -Path $DriverPath -Filter "*.inf" -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -eq '.inf' })

if ($infFiles.Count -eq 0) {
    Write-Log "No driver files (.inf) found in $DriverPath" "WARNING"
    exit 0
}

Write-Log "Found $($infFiles.Count) driver file(s)"

Write-Log "Reading the hardware IDs of devices in this PC..."
$deviceIds = Get-DeviceIdSet
Write-Log "Found $($deviceIds.Count) device hardware/compatible ID(s); INF architecture: $infArch"

# Statistics
$installed = 0
$skipped = 0
$failed = 0
$rebootRequired = $false
$results = [System.Collections.Generic.List[string]]::new()

# Process each driver
foreach ($inf in $infFiles) {
    Write-Log "----------------------------------------"
    Write-Log "Processing: $($inf.FullName)"

    try {
        $infIds = @(Get-InfHardwareId -Path $inf.FullName)
    }
    catch {
        Write-Log "Could not read the INF file: $_" "ERROR"
        $failed++
        $results.Add("  [Failed]    $($inf.FullName) (could not read INF)")
        continue
    }

    if ($infIds.Count -eq 0) {
        Write-Log "No hardware IDs for this architecture ($infArch) in this INF; skipping" "WARNING"
        $skipped++
        $results.Add("  [Skipped]   $($inf.FullName) (no hardware IDs for $infArch)")
        continue
    }

    $matchingIds = @($infIds | Where-Object { $deviceIds.Contains($_) } | Sort-Object -Unique)
    if ($matchingIds.Count -eq 0) {
        Write-Log "No matching device found for this driver; not adding it to the driver store" "WARNING"
        $skipped++
        $results.Add("  [Skipped]   $($inf.FullName) (no matching device)")
        continue
    }
    Write-Log "Matches device ID(s): $($matchingIds -join ', ')"

    # Add the package to the driver store and install it on the matching devices
    Write-Log "Installing driver..."
    $output = pnputil /add-driver $inf.FullName /install 2>&1
    $exitCode = $LASTEXITCODE
    $output | Where-Object { "$_".Trim() } | ForEach-Object { Write-Log "  $_" }

    switch ($exitCode) {
        $PNPUTIL_SUCCESS {
            Write-Log "Driver installed successfully!" "SUCCESS"
            $installed++
            $results.Add("  [Installed] $($inf.FullName)")
        }
        $PNPUTIL_REBOOT_REQUIRED {
            Write-Log "Driver installed successfully; a restart is needed to finish" "SUCCESS"
            $installed++
            $rebootRequired = $true
            $results.Add("  [Installed] $($inf.FullName) (restart required)")
        }
        $PNPUTIL_NO_MORE_ITEMS {
            Write-Log "Matching devices already use a better or newer driver" "WARNING"
            $skipped++
            $results.Add("  [Skipped]   $($inf.FullName) (devices already have a better or newer driver)")
        }
        default {
            Write-Log "pnputil failed with exit code $exitCode" "ERROR"
            $failed++
            $results.Add("  [Failed]    $($inf.FullName) (pnputil exit code $exitCode)")
        }
    }

    # A new driver can bring up new devices (e.g. software components) that later INFs match
    if ($exitCode -in $PNPUTIL_SUCCESS, $PNPUTIL_REBOOT_REQUIRED) {
        $deviceIds = Get-DeviceIdSet
    }
}

Write-Log "========================================="
Write-Log "===== Driver Installation Complete ====="
Write-Log "Summary:"
Write-Log "  Installed/Updated: $installed"
Write-Log "  Skipped: $skipped"
Write-Log "  Failed: $failed"
Write-Log "========================================="

# Create summary report (before any restart, which would end the script)
$summaryFile = "$PSScriptRoot\DriverInstallSummary.txt"
@"
Driver Installation Summary
Generated: $(Get-Date)
==========================

Search Path: $DriverPath
Total Drivers Found: $($infFiles.Count)

Results:
- Successfully Installed/Updated: $installed
- Skipped (no matching device / already up to date): $skipped
- Failed: $failed
- Restart required: $(if ($rebootRequired) { 'Yes' } else { 'No' })

Processed Drivers:
$($results | Out-String)
For detailed information, see: $LogPath
"@ | Out-File -FilePath $summaryFile

Write-Log "Summary report saved to: $summaryFile"

# Offer a restart only when pnputil reported that one is needed
if ($rebootRequired) {
    Write-Log ""
    Write-Log "IMPORTANT: Some drivers need a system restart to finish installing." "WARNING"

    $restart = Read-Host "Would you like to restart now? (Y/N)"
    if ($restart -eq 'Y') {
        Write-Log "Initiating system restart in 10 seconds..."
        Start-Sleep -Seconds 10
        Restart-Computer
    }
}
