# Simple Windows Developer Workstation Setup

**This is focused around C, C++, R, Python, DuckDB, NodeJS, Go and Rust using Claude Code AI Coding Agent.**

*My setup emphasizes simplicity and minimalism. There is nothing that affects themes and looks here.*

## Step 1: Run Setup Script

    irm https://raw.githubusercontent.com/lab1702/winsetup/refs/heads/main/InstallTools.ps1 | iex

## Step 2: Install Claude Code

    irm https://claude.ai/install.ps1 | iex

## Step 3: Install MCPs

### Context7

    claude mcp add --transport sse context7 https://mcp.context7.com/sse

### Playwright

    claude mcp add playwright npx @playwright/mcp@latest

## Optional: Always Show All System Tray Icons

This has to be re-run every time a new icon (and sometimes a new version) appears. Come on Microsoft, bring back the Always Show All Icons option.

    Get-ChildItem -path 'HKCU:\Control Panel\NotifyIconSettings' -Recurse | ForEach-Object {New-ItemProperty -Path $_.PSPath -Name 'IsPromoted' -Value '1' -PropertyType DWORD -Force }

## Optional: Reset Windows Terminal Settings

Reset color schemes, sessions etc.

    Remove-Item "$env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -Force
