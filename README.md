# Windows Config Tools

## Install Dev Tools etc.

    irm https://raw.githubusercontent.com/lab1702/winsetup/refs/heads/main/InstallTools.ps1 | iex

## Install / Update Claude Code

    irm https://claude.ai/install.ps1 | iex

## Always Show All System Tray Icons

This has to be re-run every time a new icon (and sometimes a new version) appears. Come on Microsoft, bring back the Always Show All Icons option.

    irm https://raw.githubusercontent.com/lab1702/winsetup/refs/heads/main/ShowTrayIcons.ps1 | iex

## Reset Windows Terminal

    Remove-Item "$env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -Force
