
# Define all packages to install
$packages = @{
    "Base Applications" = @(
        "microsoft.visualstudiocode",
        "discord.discord",
        "autohotkey.autohotkey"
    )
    "Development CLI Tools" = @(
        "neovim.neovim",
        "helix.helix",
        "git.git",
        "github.cli",
        "junegunn.fzf",
        "burntsushi.ripgrep.msvc",
        "waterlan.dos2unix",
        "jqlang.jq"
    )
    "C/C++ Tools" = @(
        "microsoft.visualstudio.2022.buildtools"
    )
    "R Tools" = @(
        "rproject.r",
        "posit.quarto",
        "johnmacfarlane.pandoc"
    )
    "Python Tools" = @(
        "python.python.3.13",
        "astral-sh.uv",
        "astral-sh.ruff"
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
}

# Updates
Write-Host "Running updates..." -ForegroundColor Magenta
winget update --all

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
            Write-Host "  - Installing $packageId..." -ForegroundColor Yellow
            winget install $packageId --accept-package-agreements --accept-source-agreements
        }
    }
}


