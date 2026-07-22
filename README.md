# Simple Windows Developer Workstation Setup

## Step 1: Run Install/Update Script

    irm https://raw.githubusercontent.com/lab1702/winsetup/refs/heads/main/install.ps1 | iex

## Optional: Install Claude Code CLI

    irm https://claude.ai/install.ps1 | iex

### Add Claude Code CLI to PATH

    $binPath = "$env:USERPROFILE\.local\bin"
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($userPath -split ";" -notcontains $binPath) {
        [Environment]::SetEnvironmentVariable("PATH", "$userPath;$binPath", "User")
        Write-Host "Added $binPath to PATH"
    } else {
        Write-Host "$binPath is already in PATH"
    }

## Optional: Setup Git

Step A:

    git config --global user.name "abc"

Step B:

    git config --global user.email "abc@gmail.com"

Step C:

    gh auth login

Step D:

    gh auth setup-git
    git config --global core.autocrlf input
    git config --global init.defaultBranch main

## Optional: Configure All Tray Icons As Visible

    Get-ChildItem -path 'HKCU:\Control Panel\NotifyIconSettings' -Recurse | ForEach-Object {New-ItemProperty -Path $_.PSPath -Name 'IsPromoted' -Value '1' -PropertyType DWORD -Force }

## Optional: Reset Windows Terminal Settings

Reset color schemes, sessions etc.

    Remove-Item "$env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -Force
