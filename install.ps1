
<#
.SYNOPSIS
    Automated setup script for Windows development workstation with common development tools.

.DESCRIPTION
    This script installs and updates the development tools listed in $packages below using the
    Windows Package Manager (winget). Packages that are missing get installed; packages that are
    already installed get upgraded when winget has a newer version. It also adds a `vi` alias for
    Neovim to your PowerShell profiles and sets PIP_REQUIRE_VIRTUALENV so pip refuses to install
    outside a virtual environment.

.PARAMETER WhatIf
    Shows what changes would be made without actually making them. Useful for previewing
    which packages would be installed or updated.

.PARAMETER Confirm
    Asks before each install, upgrade, or settings change.

.EXAMPLE
    .\install.ps1

    Runs the setup script, installing missing tools and upgrading installed ones.

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
    Version: 1.3.0

    The packages to install are listed, by category, in the $packages table at the top of the
    script body; edit that table to add or remove tools.

.LINK
    https://github.com/lab1702/winsetup

.LINK
    https://learn.microsoft.com/en-us/windows/package-manager/winget/
#>

[CmdletBinding(SupportsShouldProcess)]
param()

# Without winget nothing below can work, and its missing exit codes would look like success
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "`nwinget was not found. Install or update 'App Installer' from the Microsoft Store, then run this script again." -ForegroundColor Red
    # Under "irm | iex" there is no script file, and exit would close the window
    if ($PSCommandPath) { exit 1 } else { return }
}

# Show mode information
if ($WhatIfPreference) {
    Write-Host "`n=== DRY RUN MODE ===" -ForegroundColor Yellow
    Write-Host "No actual changes will be made. Showing what would be done.`n" -ForegroundColor Yellow
}

# Define all packages to install ([ordered] so categories install in the order listed)
$packages = [ordered]@{
    "Editors" = @(
        "devcom.jetbrainsmononerdfont",
        "microsoft.visualstudiocode",
        "neovim.neovim",
        "helix.helix",
        "blenderfoundation.blender",
        "godotengine.godotengine"
    )
    "Command Line Tools" = @(
        "microsoft.powershell",
        "microsoft.coreutils",
        "git.git",
        "github.cli",
        "caddyserver.caddy",
        "kitware.cmake",
        "junegunn.fzf",
        "burntsushi.ripgrep.msvc",
        "sharkdp.fd",
        "waterlan.dos2unix",
        "jqlang.jq",
        "gyan.ffmpeg",
        "sqlite.sqlite",
        "duckdb.cli",
        "starship.starship"
    )
    "System Tools" = @(
        "autohotkey.autohotkey"
    )
    "C/C++ Language" = @(
        "microsoft.visualstudio.buildtools",
        "brechtsanders.winlibs.posix.ucrt"
    )
    "R Language" = @(
        "rproject.r",
        "rproject.rtools",
        "posit.rstudio"
    )
    "Python Language" = @(
        "9NQ7512CXL7T",
        "astral-sh.uv",
        "astral-sh.ruff",
        "astral-sh.ty"
    )
    "Lua Language" = @(
        "devcom.luajit"
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

# Extra winget arguments for packages whose default install isn't enough (used on first install)
$installArgs = @{
    # By default winget installs Build Tools with no workloads, i.e. without the MSVC compiler.
    # --override replaces winget's own installer switches, so --wait/--passive are repeated here,
    # and --norestart stops a passive install from restarting the PC in the middle of this script.
    "microsoft.visualstudio.buildtools" = @(
        "--override",
        "--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    )
}

# Extra winget arguments for upgrades. --custom adds to the installer switches winget already uses.
$upgradeArgs = @{
    # winget upgrades Build Tools with "--passive ... update", which restarts the PC right away
    # if the update needs a restart; --norestart delays that, as for the first install above.
    "microsoft.visualstudio.buildtools" = @("--custom", "--norestart")
}

# Upgrading the program this script runs in would close it partway through, so those
# upgrades are left for the user to run from another window
$runningHost = @{
    "microsoft.powershell"       = $PSVersionTable.PSEdition -eq 'Core'
    "microsoft.visualstudiocode" = $env:TERM_PROGRAM -eq 'vscode'
}

# Returns $true if $PackageId appears as a whole ID in winget's table output, so that
# "rproject.r" doesn't match "RProject.Rtools" and "microsoft.powershell" doesn't match
# "Microsoft.PowerShell.Preview".
function Test-PackageListed {
    param([string]$List, [string]$PackageId)
    $List -match "(?<![\w.-])$([regex]::Escape($PackageId))(?![\w.-])"
}

# winget exit codes that don't mean the operation failed
$WINGET_UPDATE_NOT_APPLICABLE     = -1978335189  # 0x8A15002B: no applicable upgrade found
$WINGET_PACKAGE_ALREADY_INSTALLED = -1978335135  # 0x8A150061: already installed
$WINGET_REBOOT_REQUIRED_TO_FINISH = -1978334967  # 0x8A150109: installed, restart to finish

$failures = [System.Collections.Generic.List[string]]::new()
$rebootNeeded = [System.Collections.Generic.List[string]]::new()
$deferred = [System.Collections.Generic.List[string]]::new()

function Register-WingetResult {
    param([string]$PackageId, [string]$Action, [int]$ExitCode)
    switch ($ExitCode) {
        0 { }
        $WINGET_UPDATE_NOT_APPLICABLE { }
        $WINGET_PACKAGE_ALREADY_INSTALLED { }
        $WINGET_REBOOT_REQUIRED_TO_FINISH { $rebootNeeded.Add($PackageId) }
        default { $failures.Add("$PackageId ($Action failed, winget exit code $ExitCode)") }
    }
}

# Get list of all installed packages, and of those with an upgrade available
Write-Host "`nChecking installed packages and available upgrades..." -ForegroundColor Cyan
$installedPackages = winget list --accept-source-agreements | Out-String
# Keep only the first table. winget lists packages that need explicit targeting (pinned or
# self-updating) in a second table, and each table has a "-----" line under its header row.
# Splitting on those lines rather than on the heading text works in every display language.
$upgradeTables = (winget upgrade --accept-source-agreements | Out-String) -split '(?m)^-{3,}\s*$'
$upgradablePackages = if ($upgradeTables.Count -gt 1) { $upgradeTables[1] } else { '' }

# Install missing packages and upgrade installed ones.
# $PSCmdlet is $null when the script is run with "irm ... | iex"; then there's no -WhatIf/-Confirm.
foreach ($category in $packages.Keys) {
    Write-Host "`n=== Installing $category ===" -ForegroundColor Blue

    foreach ($packageId in $packages[$category]) {
        if (Test-PackageListed $installedPackages $packageId) {
            if (-not (Test-PackageListed $upgradablePackages $packageId)) {
                Write-Host "  [OK] $packageId is installed and up to date" -ForegroundColor Green
            } elseif ($runningHost[$packageId]) {
                Write-Host "  [SKIP] $packageId has an upgrade, but upgrading it now would close this window" -ForegroundColor Yellow
                $deferred.Add($packageId)
            } elseif (-not $PSCmdlet -or $PSCmdlet.ShouldProcess($packageId, "Upgrade package")) {
                $extraArgs = if ($upgradeArgs.Contains($packageId)) { $upgradeArgs[$packageId] } else { @() }
                Write-Host "  - Upgrading $packageId..." -ForegroundColor Yellow
                winget upgrade $packageId --accept-package-agreements --accept-source-agreements $extraArgs
                Register-WingetResult $packageId "upgrade" $LASTEXITCODE
            }
        } elseif (-not $PSCmdlet -or $PSCmdlet.ShouldProcess($packageId, "Install package")) {
            $extraArgs = if ($installArgs.Contains($packageId)) { $installArgs[$packageId] } else { @() }
            Write-Host "  - Installing $packageId..." -ForegroundColor Yellow
            winget install $packageId --accept-package-agreements --accept-source-agreements $extraArgs
            Register-WingetResult $packageId "install" $LASTEXITCODE
        }
    }
}

# $installArgs only applies to a first install, so Build Tools installed without the C++
# workload (as versions of this script before 1.3.0 did) never got the MSVC compiler. Add it.
$buildToolsId = "microsoft.visualstudio.buildtools"
$vsInstallerDir = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer'
$vswhere = Join-Path $vsInstallerDir 'vswhere.exe'
if (@($packages.Values | ForEach-Object { $_ }) -contains $buildToolsId -and (Test-Path -LiteralPath $vswhere)) {
    $vsProduct = 'Microsoft.VisualStudio.Product.BuildTools'
    $vcTools = 'Microsoft.VisualStudio.Workload.VCTools'
    $buildToolsPath = & $vswhere -products $vsProduct -latest -property installationPath | Select-Object -First 1
    $withVCTools = & $vswhere -products $vsProduct -requires $vcTools -property installationPath
    if ($buildToolsPath -and -not $withVCTools) {
        Write-Host "`n=== Adding the C++ workload to Build Tools ===" -ForegroundColor Blue
        if (-not $PSCmdlet -or $PSCmdlet.ShouldProcess($buildToolsPath, "Add $vcTools")) {
            Write-Host "  - Adding $vcTools to $buildToolsPath..." -ForegroundColor Yellow
            # setup.exe asks for elevation itself; Start-Process -Wait waits for it to finish
            $setupArgs = "modify --installPath `"$buildToolsPath`" --add $vcTools --includeRecommended --passive --norestart"
            try {
                # Under -Confirm, PowerShell 7's Start-Process would ask again (and return nothing if
                # declined); this was already confirmed above. Windows PowerShell's has no -Confirm.
                $setup = & {
                    $ConfirmPreference = 'None'
                    Start-Process -FilePath (Join-Path $vsInstallerDir 'setup.exe') -ArgumentList $setupArgs -Wait -PassThru -ErrorAction Stop
                }
                switch ($setup.ExitCode) {
                    0 { }
                    3010 { $rebootNeeded.Add("$buildToolsId (C++ workload)") }
                    default { $failures.Add("$buildToolsId (adding the C++ workload failed, exit code $($setup.ExitCode))") }
                }
            } catch {
                # e.g. the elevation prompt was declined
                $failures.Add("$buildToolsId (adding the C++ workload failed: $($_.Exception.Message))")
            }
        }
    }
}

# Returns the execution policy that new Windows PowerShell 5.1 windows will use. The Process
# scope is skipped: it only applies to the current window (e.g. -ExecutionPolicy Bypass).
function Get-WindowsPowerShellPolicy {
    $list = powershell.exe -NoProfile -NonInteractive -Command {
        Get-ExecutionPolicy -List | ForEach-Object { "$($_.Scope)=$($_.ExecutionPolicy)" }
    }
    foreach ($scope in 'MachinePolicy', 'UserPolicy', 'CurrentUser', 'LocalMachine') {
        $policy = (@($list) -like "$scope=*" | Select-Object -First 1) -replace '^[^=]*='
        if ($policy -and $policy -ne 'Undefined') { return $policy }
    }
    return 'Restricted'  # the Windows client default when no scope sets a policy
}

# Alias for vi
Write-Host "`n=== Configuring PowerShell profiles ===" -ForegroundColor Blue
$aliasLine = 'Set-Alias -Name vi -Value nvim'

$documents = [Environment]::GetFolderPath('MyDocuments')
$profilePaths = @(
    (Join-Path $documents 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
    (Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1')
)

foreach ($profilePath in $profilePaths) {
    # Windows PowerShell refuses to load an unsigned profile under these policies (Restricted is
    # the default on a fresh install), so creating one would print an error in every new window
    if ($profilePath -like '*\WindowsPowerShell\*') {
        $policy = Get-WindowsPowerShellPolicy
        if ($policy -in 'Restricted', 'AllSigned', 'Default') {
            Write-Host "  Skipping $profilePath" -ForegroundColor Yellow
            Write-Host "    Windows PowerShell's execution policy is $policy, so it wouldn't load this profile." -ForegroundColor Yellow
            Write-Host "    To allow it, run 'Set-ExecutionPolicy -Scope CurrentUser RemoteSigned' in Windows PowerShell, then re-run this script." -ForegroundColor Yellow
            continue
        }
    }

    $lines = if (Test-Path -LiteralPath $profilePath) { @(Get-Content -LiteralPath $profilePath) } else { @() }
    if ($lines | Where-Object { $_.Trim() -eq $aliasLine }) {
        Write-Host "  [OK] vi alias is already in $profilePath" -ForegroundColor Green
        continue
    }

    # Earlier versions of this script could glue the alias onto the end of the last line
    $glued = $lines | Where-Object { $_.TrimEnd().EndsWith($aliasLine) -and -not $_.TrimStart().StartsWith('#') }
    if ($glued) {
        Write-Host "  Warning: '$aliasLine' is joined onto another line in $profilePath :" -ForegroundColor Yellow
        $glued | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
        Write-Host "    Please put it on its own line. Adding a correct copy now." -ForegroundColor Yellow
    }

    if (-not $PSCmdlet -or $PSCmdlet.ShouldProcess($profilePath, "Add vi alias for nvim")) {
        $dir = Split-Path $profilePath -Parent
        if (-not (Test-Path -LiteralPath $dir)) {
            New-Item -Path $dir -ItemType Directory -Force -Confirm:$false | Out-Null
        }

        # Add-Content doesn't start a new line, so add one if the file doesn't end with one
        $prefix = ''
        if (Test-Path -LiteralPath $profilePath) {
            $content = [System.IO.File]::ReadAllText($profilePath)
            if ($content.Length -gt 0 -and -not $content.EndsWith("`n")) { $prefix = [Environment]::NewLine }
        }
        Add-Content -LiteralPath $profilePath -Value "$prefix$aliasLine" -Confirm:$false
        Write-Host "  Added vi alias to $profilePath" -ForegroundColor Yellow
    }
}

# Prevent global pip install
Write-Host "`n=== Preventing pip installs outside virtual environments ===" -ForegroundColor Blue
if ([Environment]::GetEnvironmentVariable('PIP_REQUIRE_VIRTUALENV', 'User') -eq '1') {
    Write-Host "  [OK] PIP_REQUIRE_VIRTUALENV is already set" -ForegroundColor Green
} elseif (-not $PSCmdlet -or $PSCmdlet.ShouldProcess('PIP_REQUIRE_VIRTUALENV=1 (user environment)', 'Set environment variable')) {
    [Environment]::SetEnvironmentVariable('PIP_REQUIRE_VIRTUALENV', '1', 'User')
    $env:PIP_REQUIRE_VIRTUALENV = '1'
    Write-Host "  Set PIP_REQUIRE_VIRTUALENV=1" -ForegroundColor Yellow
}

# End
if ($deferred.Count -gt 0) {
    Write-Host "`nNot upgraded because this window is running them. To upgrade, close this window and run in a new Command Prompt:" -ForegroundColor Yellow
    # No --exact: it makes the ID match case-sensitive, and these IDs are written in lowercase
    $deferred | ForEach-Object { Write-Host "  winget upgrade --id $_" -ForegroundColor Yellow }
}

if ($rebootNeeded.Count -gt 0) {
    Write-Host "`nRestart your PC to finish installing: $($rebootNeeded -join ', ')" -ForegroundColor Yellow
}

if ($failures.Count -gt 0) {
    Write-Host "`nFinished with $($failures.Count) problem(s):" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    # Only exit with an error code when run as a file; under "irm | iex", exit would close the window
    if ($PSCommandPath) { exit 1 }
} else {
    Write-Host "`nAll done!" -ForegroundColor Green
}
