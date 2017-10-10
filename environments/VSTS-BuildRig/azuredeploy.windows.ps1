#Requires -Version 3.0

[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]$VSTSAccount,
    [Parameter(Mandatory=$true)]$PersonalAccessToken,
    [Parameter(Mandatory=$true)]$PoolName,
    [Parameter(Mandatory=$false)]$AgentName = $($env:COMPUTERNAME)
)

try     { Start-Transcript -Path ([System.IO.Path]::ChangeExtension($PSCommandPath, '.log')) -Force -ErrorAction SilentlyContinue }
catch   { }

try {

    $currentLocation = $PS
    Write-Output "Current folder: $currentLocation"

    $agentTempFolderName = Join-Path $env:temp ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Force -Path $agentTempFolderName | Out-Null
    Write-Output "Temporary Agent download folder: $agentTempFolderName"

    $serverUrl = "https://$VSTSAccount.visualstudio.com"
    Write-Output "Server URL: $serverUrl"

    $retryCount = 3
    $retries = 1
    Write-Output "Downloading Agent install files"
    do {

        try {

            Write-Output "Trying to get download URL for latest VSTS agent release..."
            $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/Microsoft/vsts-agent/releases/latest"
            $latestReleaseDownloadUrl = ($latestRelease.assets | ? { $_.name -like "*win7-x64*" }).browser_download_url
            Invoke-WebRequest -Uri $latestReleaseDownloadUrl -Method Get -OutFile "$agentTempFolderName\agent.zip"
            Write-Output "Downloaded agent successfully on attempt $retries"
            break
        }
        catch {

            $exceptionText = ($_ | Out-String).Trim()
            Write-Warning "Exception occured downloading agent: $exceptionText in try number $retries"
            $retries++
            Start-Sleep -Seconds 30 
        }
    
    } while ($retries -le $retryCount)

    # Construct the agent folder under the main (hardcoded) C: drive.
    $agentInstallationPath = Join-Path "C:" $AgentName 

    # Create the directory for this agent.
    New-Item -ItemType Directory -Force -Path $agentInstallationPath | Out-Null

    # Create a folder for the build work
    New-Item -ItemType Directory -Force -Path (Join-Path $agentInstallationPath $WorkFolder) | Out-Null

    Write-Output "Extracting the zip file for the agent"
    $destShellFolder = (new-object -com shell.application).namespace("$agentInstallationPath")
    $destShellFolder.CopyHere((new-object -com shell.application).namespace("$agentTempFolderName\agent.zip").Items(),16)

    # Removing the ZoneIdentifier from files downloaded from the internet so the plugins can be loaded
    # Don't recurse down _work or _diag, those files are not blocked and cause the process to take much longer
    Write-Output "Unblocking files"
    Get-ChildItem -Recurse -Path $agentInstallationPath | Unblock-File | Out-Null

    # Retrieve the path to the config.cmd file.
    $agentConfigPath = [System.IO.Path]::Combine($agentInstallationPath, 'config.cmd')
    Write-Output "Agent Location = $agentConfigPath"

    if (![System.IO.File]::Exists($agentConfigPath))
    {
        Write-Error "File not found: $agentConfigPath"
        return
    }

    # Call the agent with the configure command and all the options (this creates the settings file) without prompting
    # the user or blocking the cmd execution

    Write-Output "Configuring agent"

    # Set the current directory to the agent dedicated one previously created.
    Push-Location -Path $agentInstallationPath

    .\config.cmd --unattended --url $serverUrl --auth PAT --token $PersonalAccessToken --pool $PoolName --agent $AgentName --runasservice

    Pop-Location

    Write-Output "Agent install output: $LASTEXITCODE"
}
catch {

    try     { Stop-Transcript -ErrorAction SilentlyContinue }
    catch   { }
}