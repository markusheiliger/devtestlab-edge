#Requires -Version 3.0

[CmdletBinding()]
Param(
    [string] [Parameter(Mandatory=$true)]    $VSTSAccount,
    [string] [Parameter(Mandatory=$true)]    $PersonalAccessToken,
    [string] [Parameter(Mandatory=$true)]    $PoolName,
    [string] [Parameter(Mandatory=$false)]   $AgentName = $($env:COMPUTERNAME),
    [string] [Parameter(Mandatory=$false)]   $ChocoPackages = ""
)

Push-Location $PSScriptRoot

try {

    . .\Install-WindowsAgent.ps1 -vstsAccount $VSTSAccount -personalAccessToken $PersonalAccessToken -PoolName $PoolName -AgentName $AgentName

    if ($ChocoPackages) { . .\Install-Chocolatey.ps1 -Packages $ChocoPackages }

} finally {

    Pop-Location
}