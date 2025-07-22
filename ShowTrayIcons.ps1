$RegistryPath = 'HKCU:\Control Panel\NotifyIconSettings'
$Name = 'IsPromoted'
$Value = '1'
Get-ChildItem -path $RegistryPath -Recurse | ForEach-Object {New-ItemProperty -Path $_.PSPath -Name $Name -Value $Value -PropertyType DWORD -Force }
