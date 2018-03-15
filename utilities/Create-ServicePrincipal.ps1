param(
    [Parameter(Mandatory=$true)]
    [string] $ApplicationName,
     
    [Parameter(Mandatory=$false)]
    [string] $ApplicationSecret = $(-join ((65..90) + (97..122) | Get-Random -Count 20 | % {[char]$_})),

    [switch] $Force
)

Get-AzureRmADServicePrincipal -SearchString $ApplicationName | ForEach-Object { 

    if ($Force -eq $false) { throw "Service Principal '$ApplicationName' already exists." }
    
    $objectId = $_.Id
    
    "Removing Service Principal with object ID '$objectId'"
    Remove-AzureRmADServicePrincipal -ObjectId $objectId -Force 
}

$principal = New-AzureRmADServicePrincipal -DisplayName $ApplicationName -Password (ConvertTo-SecureString $ApplicationSecret -AsPlainText -Force)
$principalInfo = Join-Path $env:TEMP $($principal.DisplayName + ".txt")

Remove-Item -Path $principalInfo -Force -ErrorAction SilentlyContinue | Out-Null

"Service Principal Name:                $($principal.DisplayName)" | Out-File -FilePath $principalInfo -Append
"Service Principal Object ID:           $($principal.Id)" | Out-File -FilePath $principalInfo -Append
"Service Principal Application ID:      $($principal.ApplicationId)" | Out-File -FilePath $principalInfo -Append
"Service Principal Application Secret:  $ApplicationSecret" | Out-File -FilePath $principalInfo -Append

notepad $principalInfo