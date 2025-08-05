# Windows Config Tools

## Install Dev Tools etc.

    Invoke-Expression (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lab1702/winsetup/refs/heads/main/InstallTools.ps1").Content

## Install Claude Code

    irm https://claude.ai/install.ps1 | iex

## Always Show All System Tray Icons

This has to be re-run every time a new icon (and sometimes a new version) appears. Come on Microsoft, bring back the Always Show All Icons option.

    Invoke-Expression (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/lab1702/winsetup/refs/heads/main/ShowTrayIcons.ps1").Content

## Reset Windows Terminal

    Remove-Item "$env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -Force

## NPM

    mkdir ~/.npm-global
    npm config set prefix '~/.npm-global'

Then add to path.
