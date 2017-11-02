param(

)

Clear-Host

$ContextClassic = [bool] (Get-Command -Name Save-AzureRmProfile -ErrorAction SilentlyContinue) # returns TRUE if AzureRM.profile version 2.7 or older is loaded
$ContextPath = [System.IO.Path]::ChangeExtension($PSCommandPath, '.ctx')

if (Test-Path $ContextPath -PathType Leaf) {
    
    "Removing orphan Azure context ($ContextPath) ..."
    Remove-Item -Path $ContextPath -Force | Out-Null
}

"Persisting Azure context to '$ContextPath' ..."
if ($ContextClassic) { Save-AzureRmProfile -Path $ContextPath } else { Save-AzureRmContext -Path $ContextPath -Force }

$ResourceLocations = Get-AzureRmLocation | Select-Object -ExpandProperty Location
$ResourceGroupPrefix = "DTLENV"

$ResourceLocations | ForEach-Object { 

    "Creating resource group '$ResourceGroupPrefix-$_' ..."
    Start-Job   -ScriptBlock { param ( $contextPath, $contextClassic, $resourceGrouName, $resourceGroupLocation ) if ($contextClassic) { Select-AzureRMProfile -Path $contextPath } else { Import-AzureRmContext -Path $contextPath }; New-AzureRmResourceGroup -Name $resourceGrouName -Location $resourceGroupLocation -Force; } `
                -ArgumentList ( $ContextPath, $ContextClassic, "$ResourceGroupPrefix-$_", $_ ) | Out-Null
}

While (Get-Job -State Running) { Start-Sleep -Seconds 2 }; Get-Job | Remove-Job -Force

try {

    Get-ChildItem -Path (Join-Path $PSScriptRoot "..\environments") -Filter 'azuredeploy.parameters.json' -Recurse | ForEach-Object { 
        
        $EnvironmentPath = Split-Path $_.FullName -Parent 
        $EnvironmentName = Split-Path $EnvironmentPath -Leaf

        "Processing environment '$EnvironmentName' ..."

        $ValidationJobs = @()

        $ResourceLocations | ForEach-Object {

            $script = {

                param( $contextPath, $contextClassic, $environmentPath, $environmentResourceGroup ) 
                
                if ($contextClassic) { Select-AzureRMProfile -Path $contextPath } else { Import-AzureRmContext -Path $contextPath }; 
                
                return Test-AzureRmResourceGroupDeployment -ResourceGroupName $environmentResourceGroup -TemplateFile (Join-Path $environmentPath "azuredeploy.json") -TemplateParameterFile (Join-Path $EnvironmentPath "azuredeploy.parameters.json")    
            }

            "- Validating region '$_' ..."
            $ValidationJobs += Start-Job -Name $_ -ScriptBlock $script -ArgumentList ($ContextPath, $ContextClassic, $EnvironmentPath, "$ResourceGroupPrefix-$_") 
        }

        While (Get-Job -State Running) { Start-Sleep -Seconds 2 }

        $ValidationJobs | Receive-Job -Keep | ForEach-Object {

            "==========================================="
            $_.Output
        }

        return 

        "Valid in the following regions: " + (($ValidationJobs | Receive-Job -Keep | Where-Object { $_ -ne "" }) -join ", ")

        $ValidationJobs | Remove-Job -Force | Out-Null
    } 

} finally {
    
    $ResourceLocations | ForEach-Object { 
        
        "Removing resource group '$ResourceGroupPrefix-$_' ..."
        Start-Job   -ScriptBlock { param ( $contextPath, $contextClassic, $resourceGrouName ) if ($contextClassic) { Select-AzureRMProfile -Path $contextPath } else { Import-AzureRmContext -Path $contextPath }; Remove-AzureRmResourceGroup -Name $resourceGrouName -Force -ErrorAction SilentlyContinue | Out-Null; } `
                    -ArgumentList ( $ContextPath, $ContextClassic, "$ResourceGroupPrefix-$_" ) | Out-Null    
    }

    While (Get-Job -State Running) { Start-Sleep -Seconds 2 }; Get-Job | Remove-Job -Force

    if (Test-Path $ContextPath -PathType Leaf) {

        "Removing persisted Azure context ($ContextPath) ..."
        Remove-Item -Path $ContextPath -Force | Out-Null
    }
}