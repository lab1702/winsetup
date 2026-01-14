
<#
.SYNOPSIS
    Automated setup script for Windows development workstation with common development tools.

.DESCRIPTION
    This script automates the installation of development tools for C, C++, R, Python, 
    DuckDB, NodeJS, Go, and Rust development environments. It uses Windows Package Manager 
    (winget) to install and update packages. The script checks for already installed 
    packages to avoid redundant installations.

.PARAMETER WhatIf
    Shows what changes would be made without actually making them. Useful for previewing
    which packages would be installed or updated.

.EXAMPLE
    .\setup.ps1
    
    Runs the setup script and installs all missing development tools.

.EXAMPLE
    .\setup.ps1 -WhatIf
    
    Shows what packages would be installed/updated without making any actual changes.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\setup.ps1
    
    Runs the script bypassing execution policy restrictions (useful if script execution
    is restricted on your system).

.EXAMPLE
    irm https://raw.githubusercontent.com/lab1702/winsetup/refs/heads/main/setup.ps1 -OutFile setup.ps1; .\setup.ps1 -WhatIf
    
    Downloads the latest version of the script and runs it in WhatIf mode to preview changes.

.NOTES
    Author: lab1702
    Requires: Windows 10/11 with Windows Package Manager (winget) installed
    Version: 1.1.0
    
    The script installs the following categories of tools:
    - Development Tools: VS Code, Git, GitHub CLI, fzf, ripgrep, dos2unix, jq
    - C/C++ Tools: Visual Studio 2022 Build Tools
    - R Tools: R, Quarto, Pandoc
    - Python Tools: Python 3.13, uv, ruff
    - DuckDB Tools: DuckDB CLI
    - NodeJS Tools: Node.js LTS
    - Go Tools: Go programming language
    - Rust Tools: Rust via rustup

.LINK
    https://github.com/lab1702/winsetup

.LINK
    https://learn.microsoft.com/en-us/windows/package-manager/winget/
#>

[CmdletBinding(SupportsShouldProcess)]
param()

# Show mode information
if ($WhatIfPreference) {
    Write-Host "`n=== DRY RUN MODE ===" -ForegroundColor Yellow
    Write-Host "No actual changes will be made. Showing what would be done.`n" -ForegroundColor Yellow
}

# Define all packages to install
$packages = @{
    "Development Tools" = @(
        "microsoft.visualstudiocode",
        "helix.helix",
        "devcom.jetbrainsmononerdfont",
        "git.git",
        "github.cli",
        "kitware.cmake",
        "junegunn.fzf",
        "burntsushi.ripgrep.msvc",
        "waterlan.dos2unix",
        "jqlang.jq",
        "autohotkey.autohotkey"
    )
    "C/C++ Tools" = @(
        "microsoft.visualstudio.buildtools"
    )
    "R Tools" = @(
        "rproject.r",
        "rproject.rtools",
        "posit.quarto",
        "posit.rstudio",
        "johnmacfarlane.pandoc",
        "miktex.miktex"
    )
    "Python Tools" = @(
        "python.python.3.14",
        "astral-sh.uv"
    )
    "DuckDB Tools" = @(
        "duckdb.cli"
    )
    "NodeJS Tools" = @(
        "openjs.nodejs.lts"
    )
    "Go Tools" = @(
        "golang.go"
    )
    "Rust Tools" = @(
        "rustlang.rustup"
    )
    "Zig Tools" = @(
        "zig.zig"
    )
    "Typst Tools" = @(
        "typst.typst",
        "myriad-dreamin.tinymist"
    )
}

# Get list of all installed packages
Write-Host "`nChecking installed packages..." -ForegroundColor Cyan
$installedPackages = winget list --accept-source-agreements | Out-String

# Install missing packages
foreach ($category in $packages.Keys) {
    Write-Host "`n=== Installing $category ===" -ForegroundColor Blue
    
    $toInstall = @()
    foreach ($packageId in $packages[$category]) {
        if ($installedPackages -match [regex]::Escape($packageId)) {
            Write-Host "  [OK] $packageId is already installed" -ForegroundColor Green
        } else {
            $toInstall += $packageId
        }
    }
    
    if ($toInstall.Count -gt 0) {
        foreach ($packageId in $toInstall) {
            if ($PSCmdlet -and $PSCmdlet.ShouldProcess($packageId, "Install package")) {
                Write-Host "  - Installing $packageId..." -ForegroundColor Yellow
                winget install $packageId --accept-package-agreements --accept-source-agreements
            } elseif ($WhatIfPreference) {
                Write-Host "  What if: Would install $packageId" -ForegroundColor Cyan
            } else {
                Write-Host "  - Installing $packageId..." -ForegroundColor Yellow
                winget install $packageId --accept-package-agreements --accept-source-agreements
            }
        }
    }
}

# Show all tray icons
Write-Host "Configuring all tray icons to be visible..." -ForegroundColor Yellow
Get-ChildItem -path 'HKCU:\Control Panel\NotifyIconSettings' -Recurse | ForEach-Object {New-ItemProperty -Path $_.PSPath -Name 'IsPromoted' -Value '1' -PropertyType DWORD -Force }

# End
Write-Host "All done!" -ForegroundColor Green
