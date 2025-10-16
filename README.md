# Simple Windows Developer Workstation Setup

**This is focused around C, C++, R, Python, DuckDB, NodeJS, Go, Rust and Zig.**

## Step 1: Run Install Script

    irm https://raw.githubusercontent.com/lab1702/winsetup/refs/heads/main/install.ps1 | iex

## Optional: Always Show All System Tray Icons

This has to be re-run every time a new icon (and sometimes a new version) appears. Come on Microsoft, bring back the Always Show All Icons option.

    Get-ChildItem -path 'HKCU:\Control Panel\NotifyIconSettings' -Recurse | ForEach-Object {New-ItemProperty -Path $_.PSPath -Name 'IsPromoted' -Value '1' -PropertyType DWORD -Force }

## Optional: Reset Windows Terminal Settings

Reset color schemes, sessions etc.

    Remove-Item "$env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -Force
