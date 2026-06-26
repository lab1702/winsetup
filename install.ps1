
<#
.SYNOPSIS
    Automated setup script for Windows development workstation with common development tools.

.DESCRIPTION
    This script automates the installation of development tools for C, C++, R, Python,
    Julia, DuckDB, NodeJS, Go, Rust, and Typst development environments. It uses Windows
    Package Manager (winget) to install and update packages. The script checks for already
    installed packages to avoid redundant installations.

.PARAMETER WhatIf
    Shows what changes would be made without actually making them. Useful for previewing
    which packages would be installed or updated.

.EXAMPLE
    .\install.ps1

    Runs the setup script and installs all missing development tools.

.EXAMPLE
    .\install.ps1 -WhatIf

    Shows what packages would be installed/updated without making any actual changes.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install.ps1

    Runs the script bypassing execution policy restrictions (useful if script execution
    is restricted on your system).

.EXAMPLE
    irm https://raw.githubusercontent.com/lab1702/winsetup/refs/heads/main/install.ps1 -OutFile install.ps1; .\install.ps1 -WhatIf

    Downloads the latest version of the script and runs it in WhatIf mode to preview changes.

.NOTES
    Author: lab1702
    Requires: Windows 10/11 with Windows Package Manager (winget) installed
    Version: 1.2.0
    
    The script installs the following categories of tools:
    - Development Tools: VS Code, Git, GitHub CLI, CMake, fzf, ripgrep, dos2unix, jq, AutoHotkey
    - C/C++ Tools: Visual Studio Build Tools
    - R Tools: R, Rtools, RStudio, Quarto, Pandoc, MiKTeX
    - Python Tools: Python, uv, ruff, ty
    - Julia Tools: Julia
    - DuckDB Tools: DuckDB CLI
    - NodeJS Tools: Node.js LTS
    - Go Tools: Go programming language
    - Rust Tools: Rust via rustup
    - Typst Tools: Typst

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
    "Editors" = @(
        "microsoft.visualstudiocode",
        "neovim.neovim",
        "helix.helix"
    )
    "Command Line Tools" = @(
        "microsoft.powershell",
        "microsoft.coreutils"
        "git.git",
        "github.cli",
        "kitware.cmake",
        "junegunn.fzf",
        "burntsushi.ripgrep.msvc",
        "waterlan.dos2unix",
        "jqlang.jq",
        "sqlite.sqlite",
        "duckdb.cli"
    )
    "AI Tools" = @(
        "anthropic.claude"
    )
    "System Tools" = @(
        "autohotkey.autohotkey"
    )
    "C/C++ Language" = @(
        "microsoft.visualstudio.buildtools"
    )
    "R Language" = @(
        "rproject.r",
        "rproject.rtools",
        "posit.rstudio"
    )
    "Python Language" = @(
        "9NQ7512CXL7T"
    )
    "Julia Language" = @(
        "9NJNWW8PVKMN"
    )
    "Markdown Tools" = @(
        "johnmacfarlane.pandoc",
        "posit.quarto"
    )
    "NodeJS Tools" = @(
        "openjs.nodejs.lts"
    )
    "Go Language" = @(
        "golang.go"
    )
    "Rust Language" = @(
        "rustlang.rustup"
    )
    "Typesetting Tools" = @(
        "miktex.miktex",
        "typst.typst"
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

# End
Write-Host "All done!" -ForegroundColor Green
