Get-ChildItem -Path $PSScriptRoot | Unblock-File

#support old function name
New-Alias Get-WUList Get-WindowsUpdate
New-Alias Get-WUInstall Get-WindowsUpdate

New-Alias Install-WindowsUpdate Get-WindowsUpdate
New-Alias Download-WindowsUpdate Get-WindowsUpdate
New-Alias Hide-WindowsUpdate Get-WindowsUpdate
New-Alias UnHide-WindowsUpdate Get-WindowsUpdate
New-Alias Show-WindowsUpdate Get-WindowsUpdate
New-Alias Uninstall-WindowsUpdate Remove-WindowsUpdate
New-Alias Clear-WUJob Get-WUJob

$PSDefaultParameterValues.Add("Install-WindowsUpdate:Install",$true)
$PSDefaultParameterValues.Add("Download-WindowsUpdate:Download",$true)
$PSDefaultParameterValues.Add("Hide-WindowsUpdate:Hide",$true)
$PSDefaultParameterValues.Add("UnHide-WindowsUpdate:Hide",$false)
$PSDefaultParameterValues.Add("Show-WindowsUpdate:Hide",$false)
$PSDefaultParameterValues.Add("Clear-WUJob:ClearExpired",$true)

Export-ModuleMember -Cmdlet * -Alias *
