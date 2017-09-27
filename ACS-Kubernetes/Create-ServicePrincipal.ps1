param(
    [Parameter(Mandatory=$false)]
    [string] $ApplicationId = $([System.Guid]::NewGuid()),
     
    [Parameter(Mandatory=$false)]
    [string] $ApplicationSecret = $([System.Guid]::NewGuid())
)

$principal = New-AzureRmADServicePrincipal -ApplicationId $ApplicationId -Password $ApplicationSecret
$principalInfo = Join-Path $env:TEMP $($ApplicationId + ".txt")

"Service Principal ID:      $ApplicationId" | Out-File -FilePath $principalInfo -Append
"Service Principal Secret:  $ApplicationSecret" | Out-File -FilePath $principalInfo -Append

notepad $principalInfo