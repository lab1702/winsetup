#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Scans driver folders and installs the drivers that match devices in this PC (Windows 10/11)
.DESCRIPTION
    This script recursively searches through driver folders for .inf files. Each INF's hardware
    IDs (from the device list Windows would use for this PC's architecture and Windows version)
    are compared with the hardware and compatible IDs of the devices present in this PC, and
    only INFs that match a device are added to the driver store and installed with
    "pnputil /add-driver <inf> /install". Installing a driver can bring up new devices (such as
    software components), so INFs that matched nothing are checked again after the others have
    been installed. INFs that still match no device are left alone, so the driver store doesn't
    fill up with packages for hardware this PC doesn't have. Primitive driver packages (no
    device list, only a [DefaultInstall] section decorated for this PC's architecture, such as
    [DefaultInstall.NTamd64]) are installed without a device. Results are
    taken from pnputil's exit codes, so they don't depend on the Windows display language.
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
    Add-Content -LiteralPath $LogPath -Value $logMessage
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

# Windows version, product type (1 workstation, 2 domain controller, 3 server) and suite mask
# of this PC, which INF model section decorations such as NTamd64.10.0...22000 can target
$os = Get-CimInstance -ClassName Win32_OperatingSystem
$osVersion = [version]$os.Version
$osProductType = [int]$os.ProductType
$osSuiteMask = [int]$os.SuiteMask

# Returns the name of the models section Windows uses for a [Manufacturer] entry on this PC,
# or nothing if none applies. A decoration is NT[Arch][.Major[.Minor[.ProductType[.SuiteMask
# [.BuildNumber]]]]]. It applies when it names this architecture (optional on x86 only), its
# Windows version isn't newer than this PC's (the build only counts when major.minor is the
# same), and its product type and suites match. Of those, Windows uses the one with the
# highest version, then the most specific product type and suites; an INF can exclude a
# Windows version with an empty section for it. On x86 the undecorated section is the fallback.
function Select-InfModelsSection {
    param([string]$ModelsName, [string[]]$Decorations)

    $arch = if ($infArch -eq 'x86') { '(x86)?' } else { [regex]::Escape($infArch) }
    $number = '(0x[0-9a-f]+|\d*)'
    $pattern = "^NT$arch(\.(?<major>\d*)(\.(?<minor>\d*)(\.(?<type>$number)(\.(?<suite>$number)(\.(?<build>\d*))?)?)?)?)?`$"
    $osRelease = [version]::new($osVersion.Major, $osVersion.Minor)

    $best = $null
    foreach ($decoration in $Decorations) {
        if (-not ($decoration -match $pattern)) { continue }
        $release = [version]::new([int]$Matches['major'], [int]$Matches['minor'])
        $build = [int]$Matches['build']
        $type = [int]$Matches['type']
        $suite = [int]$Matches['suite']

        if ($release -gt $osRelease -or ($release -eq $osRelease -and $build -gt $osVersion.Build)) { continue }
        if ($type -and $type -ne $osProductType) { continue }
        if (($osSuiteMask -band $suite) -ne $suite) { continue }

        $rank = [version]::new($release.Major, $release.Minor, $build)
        $specificity = [int][bool]$type + [int][bool]$suite
        if (-not $best -or $rank -gt $best.Rank -or ($rank -eq $best.Rank -and $specificity -gt $best.Specificity)) {
            $best = @{ Name = "$ModelsName.$decoration"; Rank = $rank; Specificity = $specificity }
        }
    }

    if ($best) { $best.Name } elseif ($infArch -eq 'x86') { $ModelsName }
}

# Reads an INF into a hashtable of section name -> lines, dropping comments and joining "\"
# continuation lines. Section names are case-insensitive, like PowerShell hashtable keys.
function Read-InfSection {
    param([string]$Path)

    $sections = @{}
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
    $sections
}

# Returns the hardware and compatible IDs that an INF lists in the models sections Windows
# uses on this PC. An INF without a [Manufacturer] section (e.g. autorun.inf) returns nothing.
function Get-InfHardwareId {
    param([hashtable]$Sections)

    if (-not $Sections.ContainsKey('Manufacturer')) { return }

    # IDs can use %key% tokens from [Strings], e.g. SWC\%SoftwareComponentId%_VEN8086_IGS.
    # Like Windows, a [Strings.LLLL] section for the display language wins over one for its
    # primary language (e.g. Strings.0009), which wins over plain [Strings].
    $lcid = (Get-UICulture).LCID
    $stringSections = 'Strings', ('Strings.{0:x4}' -f ($lcid -band 0x3FF)), ('Strings.{0:x4}' -f $lcid)
    $strings = @{}
    foreach ($name in $stringSections) {
        if (-not $Sections.ContainsKey($name)) { continue }
        foreach ($line in $Sections[$name]) {
            if ($line -match '^\s*([^=]+?)\s*=\s*(.*)$') { $strings[$Matches[1]] = $Matches[2].Trim().Trim('"') }
        }
    }
    $expandStrings = [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        $key = $m.Groups[1].Value
        if ($key -eq '') { '%' } elseif ($strings.ContainsKey($key)) { $strings[$key] } else { $m.Value }
    }.GetNewClosure()

    foreach ($entry in $Sections['Manufacturer']) {
        # %MfgName% = ModelsSection [, TargetOSVersion, ...]
        $value = if ($entry -match '=') { ($entry -split '=', 2)[1] } else { $entry }
        $parts = @($value -split ',' | ForEach-Object { $_.Trim().Trim('"') } | Where-Object { $_ })
        if ($parts.Count -eq 0) { continue }

        $name = Select-InfModelsSection -ModelsName $parts[0] -Decorations @($parts | Select-Object -Skip 1)
        if (-not $name -or -not $Sections.ContainsKey($name)) { continue }
        foreach ($model in $Sections[$name]) {
            # DeviceDescription = InstallSection, HardwareId [, CompatibleId ...]
            if ($model -notmatch '=') { continue }
            ($model -split '=', 2)[1] -split ',' | Select-Object -Skip 1 |
                ForEach-Object { [regex]::Replace($_.Trim().Trim('"'), '%([^%]*)%', $expandStrings) } |
                Where-Object { $_ }
        }
    }
}

# Returns $true for a primitive driver package, which pnputil installs without a device.
# As "Creating a Primitive Driver" in the Windows driver docs requires, that is an INF with
# no [Manufacturer] section, a [DefaultInstall] section decorated for this architecture
# (e.g. [DefaultInstall.NTamd64]) and no undecorated one, no [DefaultUninstall] section unless
# it is decorated and sets LegacyUninstall=1, and Provider, Class and ClassGuid in [Version].
# Other [DefaultInstall] INFs are legacy setup scripts that pnputil doesn't install. An INF
# without a catalog file can't go into the driver store, so it isn't a driver package.
function Test-PrimitiveInf {
    param([hashtable]$Sections)

    if ($Sections.ContainsKey('Manufacturer')) { return $false }
    if (-not $Sections.ContainsKey("DefaultInstall.NT$infArch")) { return $false }
    if ($Sections.ContainsKey('DefaultInstall') -or $Sections.ContainsKey('DefaultUninstall')) { return $false }
    $uninstall = "DefaultUninstall.NT$infArch"
    if ($Sections.ContainsKey($uninstall) -and -not ($Sections[$uninstall] -match '^LegacyUninstall\s*=\s*1$')) { return $false }
    $version = @($Sections['Version'])
    foreach ($directive in 'CatalogFile(\.[^=]*)?', 'Provider', 'Class', 'ClassGuid') {
        if (-not ($version -match "^$directive\s*=\s*\S")) { return $false }
    }
    $true
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

# Returns the IDs in $Ids that belong to a device in $deviceIds
function Get-MatchingId {
    param([string[]]$Ids)
    $Ids | Where-Object { $deviceIds.Contains($_) } | Sort-Object -Unique
}

# Adds an INF to the driver store and installs it (on the matching devices, or through its
# [DefaultInstall] section for a primitive driver), then records the result.
# Returns $true if the driver was installed.
function Install-Inf {
    param([System.IO.FileInfo]$Inf)

    Write-Log "Installing driver..."
    $output = pnputil /add-driver $Inf.FullName /install 2>&1
    $exitCode = $LASTEXITCODE
    $output | Where-Object { "$_".Trim() } | ForEach-Object { Write-Log "  $_" }

    switch ($exitCode) {
        $PNPUTIL_SUCCESS {
            Write-Log "Driver installed successfully!" "SUCCESS"
            $script:installed++
            $results.Add("  [Installed] $($Inf.FullName)")
        }
        $PNPUTIL_REBOOT_REQUIRED {
            Write-Log "Driver installed successfully; a restart is needed to finish" "SUCCESS"
            $script:installed++
            $script:rebootRequired = $true
            $results.Add("  [Installed] $($Inf.FullName) (restart required)")
        }
        $PNPUTIL_NO_MORE_ITEMS {
            Write-Log "Matching devices already use a better or newer driver" "WARNING"
            $script:skipped++
            $results.Add("  [Skipped]   $($Inf.FullName) (devices already have a better or newer driver)")
        }
        default {
            Write-Log "pnputil failed with exit code $exitCode" "ERROR"
            $script:failed++
            $results.Add("  [Failed]    $($Inf.FullName) (pnputil exit code $exitCode)")
        }
    }

    $exitCode -in $PNPUTIL_SUCCESS, $PNPUTIL_REBOOT_REQUIRED
}

Write-Log "===== Starting Driver Installation Script ====="
Write-Log "Driver search path: $DriverPath"

# Verify path exists
if (-not (Test-Path -LiteralPath $DriverPath)) {
    Write-Log "Driver path does not exist: $DriverPath" "ERROR"
    exit 1
}

# Find all .inf files recursively (the Extension check drops look-alikes such as *.info
# that the "*.inf" filter can match through 8.3 short names)
Write-Log "Searching for driver files (.inf)..."
$infFiles = @(Get-ChildItem -LiteralPath $DriverPath -Filter "*.inf" -Recurse -File -ErrorAction SilentlyContinue |
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

# INFs that match no device yet. A driver installed later can bring up the devices they're
# for (e.g. software components), so they're checked again once the others are done.
$waiting = [System.Collections.Generic.List[object]]::new()
$installedSinceCheck = $false

# Process each driver
foreach ($inf in $infFiles) {
    Write-Log "----------------------------------------"
    Write-Log "Processing: $($inf.FullName)"

    try {
        $sections = Read-InfSection -Path $inf.FullName
        $infIds = @(Get-InfHardwareId -Sections $sections)
    }
    catch {
        Write-Log "Could not read the INF file: $_" "ERROR"
        $failed++
        $results.Add("  [Failed]    $($inf.FullName) (could not read INF)")
        continue
    }

    if ($infIds.Count -eq 0) {
        if (Test-PrimitiveInf -Sections $sections) {
            Write-Log "Primitive driver package (no device list, only [DefaultInstall.NT$infArch]); installing it without a device"
            if (Install-Inf $inf) {
                $installedSinceCheck = $true
                $deviceIds = Get-DeviceIdSet
            }
        } else {
            Write-Log "No hardware IDs for this architecture ($infArch) and Windows version ($osVersion) in this INF; skipping" "WARNING"
            $skipped++
            $results.Add("  [Skipped]   $($inf.FullName) (no hardware IDs for $infArch, Windows $osVersion)")
        }
        continue
    }

    $matchingIds = @(Get-MatchingId $infIds)
    if ($matchingIds.Count -eq 0) {
        Write-Log "No matching device found yet; will check again after the other drivers are installed"
        $waiting.Add([pscustomobject]@{ Inf = $inf; Ids = $infIds })
        continue
    }
    Write-Log "Matches device ID(s): $($matchingIds -join ', ')"

    if (Install-Inf $inf) {
        # A new driver can bring up new devices (e.g. software components) that later INFs match
        $installedSinceCheck = $true
        $deviceIds = Get-DeviceIdSet
    }
}

# Check the INFs that matched nothing again, for as long as each pass installs something
while ($installedSinceCheck -and $waiting.Count -gt 0) {
    $installedSinceCheck = $false
    Start-Sleep -Seconds 5  # devices a new driver brings up can appear after pnputil returns
    $deviceIds = Get-DeviceIdSet

    foreach ($entry in @($waiting)) {
        $matchingIds = @(Get-MatchingId $entry.Ids)
        if ($matchingIds.Count -eq 0) { continue }
        [void]$waiting.Remove($entry)

        Write-Log "----------------------------------------"
        Write-Log "Processing again: $($entry.Inf.FullName)"
        Write-Log "Now matches device ID(s): $($matchingIds -join ', ')"
        if (Install-Inf $entry.Inf) {
            $installedSinceCheck = $true
            $deviceIds = Get-DeviceIdSet
        }
    }
}

foreach ($entry in $waiting) {
    Write-Log "No matching device for $($entry.Inf.FullName); not adding it to the driver store" "WARNING"
    $skipped++
    $results.Add("  [Skipped]   $($entry.Inf.FullName) (no matching device)")
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
"@ | Out-File -LiteralPath $summaryFile

Write-Log "Summary report saved to: $summaryFile"

# Offer a restart only when pnputil reported that one is needed
if ($rebootRequired) {
    Write-Log ""
    Write-Log "IMPORTANT: Some drivers need a system restart to finish installing." "WARNING"

    # With no user to answer (e.g. a scheduled task that runs whether or not anyone is signed
    # in), Read-Host would wait forever and the caller would never get the exit code
    if ([Environment]::UserInteractive) {
        $restart = Read-Host "Would you like to restart now? (Y/N)"
        if ($restart -eq 'Y') {
            Write-Log "Initiating system restart in 10 seconds..."
            Start-Sleep -Seconds 10
            Restart-Computer
        }
    } else {
        Write-Log "Restart this PC to finish installing them." "WARNING"
    }
}

# Let callers (e.g. a scheduled task) see that some drivers failed
if ($failed -gt 0) { exit 1 }
