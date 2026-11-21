# Simple Windows Developer Workstation Setup

## Step 1: Run Install/Update Script

```powershell
irm https://raw.githubusercontent.com/lab1702/winsetup/refs/heads/main/install.ps1 | iex
```

## Optional: Install Claude Code CLI

```powershell
irm https://claude.ai/install.ps1 | iex
```

### Add Claude Code CLI to PATH

```powershell
$binPath = "$env:USERPROFILE\.local\bin"
# Read the raw value so entries like %USERPROFILE%\... stay unexpanded
$userPath = (Get-Item 'HKCU:\Environment').GetValue('Path', '', 'DoNotExpandEnvironmentNames')
$entries = @($userPath -split ';' | Where-Object { $_ })
$expanded = $entries | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') }
if ($expanded -notcontains $binPath) {
    Set-ItemProperty -Path 'HKCU:\Environment' -Name 'Path' -Value (($entries + $binPath) -join ';') -Type ExpandString
    # Tell Explorer the environment changed (deleting an unused variable sends the notification)
    [Environment]::SetEnvironmentVariable('WINSETUP_PATH_REFRESH', $null, 'User')
    $env:Path += ";$binPath"
    Write-Host "Added $binPath to PATH"
} else {
    Write-Host "$binPath is already in PATH"
}
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

## Optional: Configure All Tray Icons As Visible

```powershell
Get-ChildItem -path 'HKCU:\Control Panel\NotifyIconSettings' -Recurse | ForEach-Object {New-ItemProperty -Path $_.PSPath -Name 'IsPromoted' -Value '1' -PropertyType DWORD -Force }
```

## Optional: Reset Windows Terminal Settings

Reset color schemes, sessions etc.

```powershell
Remove-Item "$env:LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" -Force
```
