function Export-AzureRmContext {
    [CmdletBinding()]
    param (
        
    )
    
    begin {
    }
    
    process {
        $ContextClassic = [bool] (Get-Command -Name Save-AzureRmProfile -ErrorAction SilentlyContinue) # returns TRUE if AzureRM.profile version 2.7 or older is loaded
        $ContextPath = [System.IO.Path]::ChangeExtension($PSCommandPath, '.ctx')

        if (Test-Path $ContextPath -PathType Leaf) {
            "Removing orphan Azure context ($ContextPath) ..."
            Remove-Item -Path $ContextPath -Force | Out-Null
        }

        "Persist Azure context to '$ContextPath' ..."
        if ($ContextClassic) { Save-AzureRmProfile -Path $ContextPath } else { Save-AzureRmContext -Path $ContextPath -Force }
    }
    
    end {
    }
}

function Import-AzureRmContext {
    [CmdletBinding()]
    param (
    )
    
    begin {
    }
    
    process {
        $ContextClassic = [bool] (Get-Command -Name Save-AzureRmProfile -ErrorAction SilentlyContinue) # returns TRUE if AzureRM.profile version 2.7 or older is loaded
        $ContextPath = [System.IO.Path]::ChangeExtension($PSCommandPath, '.ctx')
        "Loading Azure context from '$ContextPath' ..."
        if  ($contextClassic) { 
            Select-AzureRMProfile -Path $ContextPath 
        } else { 
            Import-AzureRmContext -Path $ContextPath 
        }
    }
    
    end {
    }
}

function New-DTLPackerImage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string] $PackerFile,

        [Parameter(Mandatory=$false)]
        [hashtable] $PackerVariables
    )
    
    begin {
    }
    
    process {        

        $varFile = $(Split-Path ([System.IO.Path]::ChangeExtension($PackerFile, ".var")) -Leaf)
        $logFile = $(Split-Path ([System.IO.Path]::ChangeExtension($PackerFile, ".log")) -Leaf)

        try {

            Push-Location (Split-Path $PackerFile -Parent); 

            if ($PackerVariables) {

                $PackerVariables | ConvertTo-Json | Out-File $varFile -Force
                
                packer build -var-file="$varFile" "$(Split-Path $PackerFile -Leaf)" | Tee-Object $logFile -Append

            } else {

                packer build "$(Split-Path $PackerFile -Leaf)" | Tee-Object $logFile -Append
            }            
        } 
        finally {

            Remove-Item $varFile -Force -ErrorAction SilentlyContinue | Out-Null
            Remove-Item $logFile -Force -ErrorAction SilentlyContinue | Out-Null

            Pop-Location
        }
    }
    
    end {
    }
}

Export-ModuleMember -Function Push-PackerImageToDTLCustomImages