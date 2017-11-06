param(

)

Clear-Host

$ContextClassic = [bool] (Get-Command -Name Save-AzureRmProfile -ErrorAction SilentlyContinue) # returns TRUE if AzureRM.profile version 2.7 or older is loaded
$ContextPath = [System.IO.Path]::ChangeExtension($PSCommandPath, '.ctx')

if (Test-Path $ContextPath -PathType Leaf) { Remove-Item -Path $ContextPath -Force | Out-Null }
if ($ContextClassic) { Save-AzureRmProfile -Path $ContextPath } else { Save-AzureRmContext -Path $ContextPath -Force }

$ResourceLocations = Get-AzureRmLocation | Select-Object -ExpandProperty Location
$ResourceLocationsCount = ($ResourceLocations | Measure-Object).Count
$ResourceGroupPrefix = "DTLENV"

$ResourceLocations | ForEach-Object -Begin { $I = 0; Get-Job | Remove-Job -Force } -Process { 

    Write-Progress -Activity "Creating resource groups ..." -Status "Enqueueing '$ResourceGroupPrefix-$_'" -PercentComplete (++$I / $ResourceLocationsCount * 100)
    Start-Job   -ScriptBlock { param ( $contextPath, $contextClassic, $resourceGrouName, $resourceGroupLocation ) if ($contextClassic) { Select-AzureRMProfile -Path $contextPath } else { Import-AzureRmContext -Path $contextPath }; New-AzureRmResourceGroup -Name $resourceGrouName -Location $resourceGroupLocation -Force; } `
                -ArgumentList ( $ContextPath, $ContextClassic, "$ResourceGroupPrefix-$_", $_ ) | Out-Null
}

While ($jobs = Get-Job -State Running) {

    Write-Progress -Activity "Creating resource groups ..." -Status "Processing" -PercentComplete (($ResourceLocationsCount - ($jobs | Measure-Object).Count) / $ResourceLocationsCount * 100)
    #Start-Sleep -Seconds 2 
}

Write-Progress -Activity "Creating resource groups ..." -Status "Processing" -PercentComplete 100
Write-Progress -Activity "Creating resource groups ..." -Completed

try {

    Get-ChildItem -Path (Join-Path $PSScriptRoot "..\environments") -Filter 'azuredeploy.parameters.json' -Recurse | ForEach-Object { 
        
        $EnvironmentPath = Split-Path $_.FullName -Parent 
        $EnvironmentName = Split-Path $EnvironmentPath -Leaf

        "Processing environment '$EnvironmentName' ..."

        $ValidationJobs = @()

        $ResourceLocations | ForEach-Object -Begin { $I = 0; Get-Job | Remove-Job -Force } -Process {

            $script = {

                param( $contextPath, $contextClassic, $environmentPath, $environmentResourceGroup ) 
                
                if ($contextClassic) { Select-AzureRMProfile -Path $contextPath | Out-Null } else { Import-AzureRmContext -Path $contextPath | Out-Null }; 
                
                $results = Test-AzureRmResourceGroupDeployment -ResourceGroupName $environmentResourceGroup -TemplateFile (Join-Path $environmentPath "azuredeploy.json") -TemplateParameterFile (Join-Path $EnvironmentPath "azuredeploy.parameters.json");

                $errorCodes = @("LocationNotAvailableForResourceType")
                $errorCount = ($results | Where-Object { $_.Code -in $errorCodes } | Measure-Object).Count

                $object = New-Object -TypeName PSObject
                $object | Add-Member -MemberType NoteProperty -Name EnvironmentName -Value (Split-Path $environmentPath -Leaf)
                $object | Add-Member -MemberType NoteProperty -Name EnvironmentPath -Value $environmentPath
                $object | Add-Member -MemberType NoteProperty -Name ResourceGroupName -Value $environmentResourceGroup
                $object | Add-Member -MemberType NoteProperty -Name ResourceGroupLocation -Value ([string] (Get-AzureRmResourceGroup -Name $environmentResourceGroup).Location)
                $object | Add-Member -MemberType NoteProperty -Name ErrorCount -Value $errorCount
                $object | ConvertTo-Json | Write-Output
            }

            Write-Progress -Activity "Validating environment template '$EnvironmentName' ..." -Status "Testing in region '$_'" -PercentComplete (++$I / $ResourceLocationsCount * 100)
            $ValidationJobs += Start-Job -Name $_ -ScriptBlock $script -ArgumentList ($ContextPath, $ContextClassic, $EnvironmentPath, "$ResourceGroupPrefix-$_") 
        }

        While ($jobs = Get-Job -State Running) {
        
            Write-Progress -Activity "Validating environment template '$EnvironmentName' ..." -Status "Processing" -PercentComplete (($ResourceLocationsCount - ($jobs | Measure-Object).Count) / $ResourceLocationsCount * 100)
            Start-Sleep -Seconds 2 
        }
        
        Write-Progress -Activity "Validating environment template '$EnvironmentName' ..." -Status "Processing" -PercentComplete 100
        Write-Progress -Activity "Validating environment template '$EnvironmentName' ..." -Completed

        $availableRegions = ($ValidationJobs | Receive-Job | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object { $_.ErrorCount -eq 0 } | Select-Object -ExpandProperty ResourceGroupLocation)

        "> Works in the following regions: " + (($availableRegions | Sort-Object ) -join ", ")
    } 

} finally {

    $ResourceLocations | ForEach-Object -Begin { $I = 0; Get-Job | Remove-Job -Force } -Process { 
        
        Write-Progress -Activity "Removing resource groups ..." -Status "Enqueueing '$ResourceGroupPrefix-$_'" -PercentComplete (++$I / $ResourceLocationsCount * 100)
        Start-Job   -ScriptBlock { param ( $contextPath, $contextClassic, $resourceGrouName ) if ($contextClassic) { Select-AzureRMProfile -Path $contextPath } else { Import-AzureRmContext -Path $contextPath }; Remove-AzureRmResourceGroup -Name $resourceGrouName -Force -ErrorAction SilentlyContinue | Out-Null; } `
                    -ArgumentList ( $ContextPath, $ContextClassic, "$ResourceGroupPrefix-$_" ) | Out-Null  
    }
    
    While ($jobs = Get-Job -State Running) {
    
        Write-Progress -Activity "Removing resource groups ..." -Status "Processing" -PercentComplete (($ResourceLocationsCount - ($jobs | Measure-Object).Count) / $ResourceLocationsCount * 100)
        Start-Sleep -Seconds 2 
    }

    Write-Progress -Activity "Removing resource groups ..." -Status "Processing" -PercentComplete 100
    Write-Progress -Activity "Removing resource groups ..." -Completed

    if (Test-Path $ContextPath -PathType Leaf) { Remove-Item -Path $ContextPath -Force | Out-Null }
}