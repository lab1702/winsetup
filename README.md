# Simple Windows Developer Workstation Setup

## Step 1: Run Install/Update Script

```powershell
irm https://raw.githubusercontent.com/lab1702/winsetup/refs/heads/main/install.ps1 | iex
```

## Optional: Setup Git

Step A:

```powershell
git config --global user.name "abc"
```

Step B:

```powershell
git config --global user.email "abc@gmail.com"
```

Step C:

```powershell
gh auth login
```

Step D:

```powershell
gh auth setup-git
git config --global core.autocrlf input
git config --global init.defaultBranch main
```

## Optional: Reset Windows Terminal Settings

Resets profiles, color schemes and key bindings to the defaults. Your old settings are kept as `settings.json.bak` next to the new file. This is for Windows Terminal from the Microsoft Store; for Windows Terminal Preview, use `Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe` in the path.

```powershell
$wtSettings = "$env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
Move-Item -LiteralPath $wtSettings -Destination "$wtSettings.bak" -Force
```
