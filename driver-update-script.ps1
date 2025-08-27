#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Scans driver folders and installs applicable drivers for Windows 11
.DESCRIPTION
    This script recursively searches through driver folders, identifies .inf files,
    and attempts to install drivers that are applicable to the current system.
.PARAMETER DriverPath
    The root path containing driver folders (default: current directory)
.PARAMETER LogPath
    Path for the log file (default: DriverInstall.log in script directory)
.EXAMPLE
    .\Update-Drivers.ps1 -DriverPath "C:\Downloads\Drivers"
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

Write-Log "===== Starting Driver Installation Script ====="
Write-Log "Driver search path: $DriverPath"

# Verify path exists
if (-not (Test-Path $DriverPath)) {
    Write-Log "Driver path does not exist: $DriverPath" "ERROR"
    exit 1
}

# Find all .inf files recursively
Write-Log "Searching for driver files (.inf)..."
$infFiles = Get-ChildItem -Path $DriverPath -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue

if ($infFiles.Count -eq 0) {
    Write-Log "No driver files (.inf) found in $DriverPath" "WARNING"
    exit 0
}

Write-Log "Found $($infFiles.Count) driver file(s)"

# Statistics
$installed = 0
$skipped = 0
$failed = 0

# Process each driver
foreach ($inf in $infFiles) {
    Write-Log "----------------------------------------"
    Write-Log "Processing: $($inf.FullName)"
    
    try {
        # First, test if the driver is applicable to this system
        Write-Log "Testing driver compatibility..."
        
        # Use pnputil to test the driver (dry run)
        $testResult = pnputil /add-driver $inf.FullName 2>&1
        
        if ($testResult -match "Published name|successfully installed") {
            Write-Log "Driver is compatible with this system" "SUCCESS"
            
            # Check if driver is already installed and up-to-date
            $driverName = $inf.Name
            $installedDrivers = pnputil /enum-drivers
            
            # Try to install/update the driver
            Write-Log "Installing driver..."
            $installResult = pnputil /add-driver $inf.FullName /install 2>&1
            
            if ($installResult -match "successfully|installed") {
                Write-Log "Driver installed successfully!" "SUCCESS"
                $installed++
                
                # Log installation details
                $installResult | ForEach-Object { 
                    if ($_ -match "Published name|Driver package") {
                        Write-Log "  $_"
                    }
                }
            } else {
                Write-Log "Driver installation returned: $installResult" "WARNING"
                $skipped++
            }
        } elseif ($testResult -match "already in the driver store") {
            Write-Log "Driver already exists in driver store" "WARNING"
            
            # Attempt to update if newer version
            Write-Log "Attempting to update existing driver..."
            $updateResult = pnputil /add-driver $inf.FullName /install 2>&1
            
            if ($updateResult -match "successfully|updated") {
                Write-Log "Driver updated successfully!" "SUCCESS"
                $installed++
            } else {
                Write-Log "Driver is already up-to-date or cannot be updated" "WARNING"
                $skipped++
            }
        } elseif ($testResult -match "No matching device") {
            Write-Log "No matching device found for this driver" "WARNING"
            $skipped++
        } else {
            Write-Log "Driver not applicable to this system" "WARNING"
            Write-Log "  Reason: $testResult"
            $skipped++
        }
    }
    catch {
        Write-Log "Error processing driver: $_" "ERROR"
        $failed++
    }
}

Write-Log "========================================="
Write-Log "===== Driver Installation Complete ====="
Write-Log "Summary:"
Write-Log "  Installed/Updated: $installed"
Write-Log "  Skipped: $skipped"
Write-Log "  Failed: $failed"
Write-Log "========================================="

# Optional: Suggest restart if drivers were installed
if ($installed -gt 0) {
    Write-Log ""
    Write-Log "IMPORTANT: Some drivers were installed. A system restart is recommended." "WARNING"
    
    $restart = Read-Host "Would you like to restart now? (Y/N)"
    if ($restart -eq 'Y' -or $restart -eq 'y') {
        Write-Log "Initiating system restart in 10 seconds..."
        Start-Sleep -Seconds 10
        Restart-Computer
    }
}

# Create summary report
$summaryFile = "$PSScriptRoot\DriverInstallSummary.txt"
@"
Driver Installation Summary
Generated: $(Get-Date)
==========================

Search Path: $DriverPath
Total Drivers Found: $($infFiles.Count)

Results:
- Successfully Installed/Updated: $installed
- Skipped (already installed/not applicable): $skipped  
- Failed: $failed

Processed Drivers:
$($infFiles | ForEach-Object { "  - $($_.FullName)" } | Out-String)

For detailed information, see: $LogPath
"@ | Out-File -FilePath $summaryFile

Write-Log "Summary report saved to: $summaryFile"
