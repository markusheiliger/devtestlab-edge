<##################################################################################################

    Description
    ===========

	Bootstrap for ensuring pre-requisites are validated prior to installing chocolatey packages.

    Usage examples
    ==============
    
    PowerShell -ExecutionPolicy bypass "& ./Artifactfile.ps1"

    Pre-Requisites
    ==============

    - Ensure that the PowerShell execution policy is set to unrestricted.
    - If calling from another process, make sure to execute as script to get the exit code (e.g. "& ./foo.ps1 ...").

    artifactfile.json usage
    =======================

    To correctly report exit codes, make sure to structure the "commandToExecute" as follow:
    
    "commandToExecute": "[concat('powershell.exe -ExecutionPolicy bypass \"& ./Artifactfile.ps1\"')]"
    
    Make sure to only replace the package (i.e. '7zip').

    Known issues / Caveats
    ======================
    
    - Using powershell.exe's -File parameter may incorrectly return 0 as exit code, causing the
      operation to report success, even when it fails.

    Coming soon / planned work
    ==========================

    - N/A.    

##################################################################################################>

#
# Optional parameters to this script file.
#

[CmdletBinding()]
param(
    [Parameter(ParameterSetName='CustomUser')]
    [string] $UserName = 'artifactInstaller',
    [Parameter(ParameterSetName='CustomUser')]
    [string] $Password,
    [int] $PSVersionRequired = 3
)

###################################################################################################

#
# Functions used in this script.
#

function Handle-LastError
{
    [CmdletBinding()]
    param(
    )

    $message = $error[0].Exception.Message
    if ($message)
    {
        Write-Host -Object "ERROR: $message" -ForegroundColor Red
    }
    
    # IMPORTANT NOTE: Throwing a terminating error (using $ErrorActionPreference = "Stop") still
    # returns exit code zero from the PowerShell script when using -File. The workaround is to
    # NOT use -File when calling this script and leverage the try-catch-finally block and return
    # a non-zero exit code from the catch block.
    exit -1
}

function Validate-Environment
{
    [CmdletBinding()]
    param(
    )

    $minVersionServer = [System.Version]::Parse("10.0.14393.0")
    $minVersionClient = [System.Version]::Parse("10.0.14393.222")

    $productType = Get-CimInstance Win32_OperatingSystem | select -ExpandProperty ProductType

    # Product Type Values
    # 1 - Work Station
    # 2 - Domain Controller
    # 3 - Server

    $curVersion = [System.Environment]::OSVersion.Version
    $minVersion = [System.Version]::Parse("0.0.0.0")

    if ($productType -eq 1) {
        $minVersion = $minVersionClient
    } else {
        $minVersion = $minVersionServer
    }
    
    if ($curVersion -lt $minVersion) {

        throw "OS version must at least Windows 10 ($minVersionClient) or Windows Server 2016 ($minVersionServer)."
    }

    $vmSize = Invoke-RestMethod -Headers @{"Metadata"="true"} -URI "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2017-04-02&format=text" -Method Get

    if (-not ($vmSize -match "Standard_[D|E]{1}\d{1,2}[s]?_v3")) {

        throw "The VM size '$vmSize' doesn't support nested virtualization. Please use a Dv3 or Ev3 size instead."
    }
}

function Validate-Params
{
    [CmdletBinding()]
    param(
    )

    if ($PsCmdlet.ParameterSetName -eq 'CustomUser')
    {
        if ([string]::IsNullOrEmpty($UserName))
        {
            throw 'UserName parameter is required when Password is specified.'
        }
        if ([string]::IsNullOrEmpty($Password))
        {
            throw 'Password parameter is required when UserName is specified.'
        }
    }
}

function Ensure-PowerShell
{
    [CmdletBinding()]
    param(
        [int] $Version
    )

    if ($PSVersionTable.PSVersion.Major -lt $Version)
    {
        throw "The current version of PowerShell is $($PSVersionTable.PSVersion.Major). Prior to running this artifact, ensure you have PowerShell $Version or higher installed."
    }
}

function Get-TempPassword
{
    [CmdletBinding()]
    param(
        [int] $length = 43
    )

    $sourceData = $null
    33..126 | % { $sourceData +=,[char][byte]$_ }

    1..$length | % { $tempPassword += ($sourceData | Get-Random) }

    return $tempPassword
}

function Add-LocalAdminUser
{
    [CmdletBinding()]
    param(
        [string] $UserName,
        [string] $Password,
        [string] $Description = 'DevTestLab artifact installer',
        [switch] $Overwrite = $true
    )
    
    if ($Overwrite)
    {
        Remove-LocalAdminUser -UserName $UserName
    }

    $computer = [ADSI]"WinNT://$env:ComputerName"
    $user = $computer.Create("User", $UserName)
    $user.SetPassword($Password)
    $user.Put("Description", $Description)
    $user.SetInfo()

    $group = [ADSI]"WinNT://$env:ComputerName/Administrators,group"
    $group.add("WinNT://$env:ComputerName/$UserName")
    
    return $user
}

function Remove-LocalAdminUser
{
    [CmdletBinding()]
    param(
        [string] $UserName
    )

    if ([ADSI]::Exists('WinNT://./' + $UserName))
    {
        $computer = [ADSI]"WinNT://$env:ComputerName"
        $computer.Delete('User', $UserName)
        try
        {
            gwmi win32_userprofile | ? { $_.LocalPath -like "*$UserName*" -and -not $_.Loaded } | % { $_.Delete() | Out-Null }
        }
        catch
        {
            # Ignore any errors, specially with locked folders/files. It will get cleaned up at a later time, when another artifact is installed.
        }
    }
}

function Set-LocalAccountTokenFilterPolicy
{
    [CmdletBinding()]
    param(
        [int] $Value = 1
    )

    $oldValue = 0

    $regPath ='HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System'
    $policy = Get-ItemProperty -Path $regPath -Name LocalAccountTokenFilterPolicy -ErrorAction SilentlyContinue

    if ($policy)
    {
        $oldValue = $policy.LocalAccountTokenFilterPolicy
    }

    if ($oldValue -ne $Value)
    {
        Set-ItemProperty -Path $regPath -Name LocalAccountTokenFilterPolicy -Value $Value
    }

    return $oldValue
}

function Invoke-ChocolateyPackageInstaller
{
    [CmdletBinding()]
    param(
        [string] $UserName,
        [string] $Password,
        [string] $PackageList
    )

    $secPassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential("$env:COMPUTERNAME\$($UserName)", $secPassword)
    $command = "$PSScriptRoot\ChocolateyPackageInstaller.ps1"

    $oldPolicyValue = Set-LocalAccountTokenFilterPolicy
    try
    {
        Invoke-Command -ComputerName $env:COMPUTERNAME -Credential $credential -FilePath $command -ArgumentList $PackageList
    }
    finally
    {
        Set-LocalAccountTokenFilterPolicy -Value $oldPolicyValue | Out-Null
    }
}

function Invoke-MinikubeConfigurator
{
    [CmdletBinding()]
    param(
        [string] $UserName,
        [string] $Password
    )

    $secPassword = ConvertTo-SecureString -String $Password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential("$env:COMPUTERNAME\$($UserName)", $secPassword)

    $oldPolicyValue = Set-LocalAccountTokenFilterPolicy
    try
    {
        Invoke-Command -ComputerName $env:COMPUTERNAME -Credential $credential -ScriptBlock { Set-Location $args[0] ; . .\MinikubeConfigurator.ps1 } -ArgumentList ( $PSScriptRoot )
    }
    finally
    {
        Set-LocalAccountTokenFilterPolicy -Value $oldPolicyValue | Out-Null
    }
}

###################################################################################################

#
# PowerShell configurations
#

# NOTE: Because the $ErrorActionPreference is "Stop", this script will stop on first failure.
#       This is necessary to ensure we capture errors inside the try-catch-finally block.
$ErrorActionPreference = "Stop"

###################################################################################################

#
# Main execution block.
#

try
{
    Validate-Params
    Validate-Environment

    Ensure-PowerShell -Version $PSVersionRequired
    
    Install-PackageProvider -Name NuGet -Force -ErrorAction SilentlyContinue | Out-Null
    Install-Module -Name DockerMsftProvider -Repository PSGallery -Force -ErrorAction SilentlyContinue | Out-Null
    Install-Package -Name docker -ProviderName DockerMsftProvider -Force -ErrorAction SilentlyContinue | Out-Null

    Enable-PSRemoting -Force -SkipNetworkProfileCheck

    if ($PsCmdlet.ParameterSetName -ne 'CustomUser')
    {
        $Password = Get-TempPassword
        Add-LocalAdminUser -UserName $UserName -Password $password | Out-Null
    }

    $productType = Get-CimInstance Win32_OperatingSystem | Select-Object -ExpandProperty ProductType

    # Product Type Values
    # 1 - Work Station
    # 2 - Domain Controller
    # 3 - Server

    if ($productType -eq 1)
    {
        # Windows 10
        if ((Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V | Select-Object -ExpandProperty State) -eq "Disabled")
        {
            Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart
        }
    }
    else 
    {
        # Windows Server 2016
        if ((Get-WindowsFeature -Name Hyper-V | Select-Object -ExpandProperty InstallState) -eq "Available")
        {
            Install-WindowsFeature –Name Hyper-V -IncludeManagementTools | Out-Null
        }            
    }

    Invoke-ChocolateyPackageInstaller -UserName $UserName -Password $Password -PackageList "minikube, kubernetes-cli"

    Invoke-MinikubeConfigurator -UserName $UserName -Password $Password 
}
catch
{
    Handle-LastError
}
finally
{
    if ($PsCmdlet.ParameterSetName -ne 'CustomUser')
    {
        Remove-LocalAdminUser -UserName $UserName
    }
}
