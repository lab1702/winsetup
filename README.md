# Simple Windows Developer Workstation Setup

**This is focused around C, C++, R, Python, DuckDB, NodeJS, Go, Rust and Zig.**

## Step 1: Run Install/Update Script

    irm https://raw.githubusercontent.com/lab1702/winsetup/refs/heads/main/install.ps1 | iex

## Optional: Install Claude Code

    irm https://claude.ai/install.ps1 | iex

## Optional: Reset Windows Terminal Settings

Reset color schemes, sessions etc.

    Remove-Item "$env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -Force
