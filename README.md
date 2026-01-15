# Simple Windows Developer Workstation Setup

## Step 1: Run Install/Update Script

    irm https://raw.githubusercontent.com/lab1702/winsetup/refs/heads/main/install.ps1 | iex

## Optional: Install Claude Code

    irm https://claude.ai/install.ps1 | iex

## Optional: Configure All Tray Icons As Visible

    Get-ChildItem -path 'HKCU:\Control Panel\NotifyIconSettings' -Recurse | ForEach-Object {New-ItemProperty -Path $_.PSPath -Name 'IsPromoted' -Value '1' -PropertyType DWORD -Force }

## Optional: Reset Windows Terminal Settings

Reset color schemes, sessions etc.

    Remove-Item "$env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -Force
