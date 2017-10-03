
#Requires -Version 3.0
#Requires -Module AzureRM.Resources

function ConvertTo-Array {

    [CmdletBinding()]
    param (
        [switch] $RemoveNull,
        [switch] $RemoveEmpty
    )

    begin { 
        $array = @(); 
    }
    
    process {
        $skip = ($RemoveNull -and $_ -eq $null) -or ($RemoveEmpty -and $_ -eq "")
        if (-not $skip) { $array += $_; }
    }
    
    end { 
        return ,$array; 
    }
}

<# 
 .Synopsis
  Creates a new Azure DevTest Labs environment.

 .Description
  Creates a new Azure DevTest Labs environment. Template parameter values can be passed to the lab using
  function arguments and / or by referencing a ARM parameters file.

 .Parameter LabName
  The name of the Azure DevTest Lab to create the environment in.

 .Parameter RepositoryName
  The name of the template repository to use.

 .Parameter EnvironmentName
  The name of the environment to create.

 .Parameter TemplateName
  The name of the template to use for creating a new environment.

 .Parameter UserId
  The object ID or the user who should become the owner of the environment.  

 .Parameter ParameterFile
  Path to a ARM template parameters file. 
#>

function New-DevTestLabEnvironment {

    [CmdletBinding()]
    param (
        [string] [Parameter(Mandatory=$true)] $LabName,
        [string] [Parameter(Mandatory=$true)] $RepositoryName,
        [string] [Parameter(Mandatory=$true)] $EnvironmentName,
        [string] [Parameter(Mandatory=$true)] $TemplateName,
        
        [string] $UserId = $((Get-AzureRmADUser -UserPrincipalName (Get-AzureRmContext).Account).Id.Guid),
        [string] $ParameterFile,

        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]] $ParameterArgs = $null
    )
    
    begin {
    }
    
    process {

        $SubscriptionId = (Get-AzureRmContext).Subscription.Id

        $lab = Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs" -ResourceNameEquals $LabName 
        if ($lab -eq $null) { throw "Unable to find lab $LabName in subscription $SubscriptionId." } 

        $repository = Get-AzureRmResource -ResourceGroupName $lab.ResourceGroupName -ResourceType 'Microsoft.DevTestLab/labs/artifactsources' -ResourceName $LabName -ApiVersion 2016-05-15 | Where-Object { $RepositoryName -in ($_.Name, $_.Properties.displayName) } | Select-Object -First 1
        if ($repository -eq $null) { throw "Unable to find repository $RepositoryName in lab $LabName." } 

        $template = Get-AzureRmResource -ResourceGroupName $lab.ResourceGroupName -ResourceType "Microsoft.DevTestLab/labs/artifactSources/armTemplates" -ResourceName "$LabName/$($repository.Name)" -ApiVersion 2016-05-15  | Where-Object { $TemplateName -in ($_.Name, $_.Properties.displayName) } | Select-Object -First 1
        if ($template -eq $null) { throw "Unable to find template $TemplateName in lab $LabName." } 

        # init hashtable to create parameter value map
        $ParameterData = @{}

        # read parameter file values into HT
        if ($ParameterFile) {
            "Reading values from parameter file '$ParameterFile' ..."
            $ParameterFileData = Get-Content -Path $ParameterFile | Out-String | ConvertFrom-Json
            $ParameterFileData.parameters | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name | ForEach-Object {
                $ParameterData.Set_Item([string] $_, [string] ($ParameterFileData.parameters | Select-Object -ExpandProperty $_).value)
            }
        }

        # read param_* arg values into HT 
        if ($ParameterArgs) {
            "Reading values from parameter arguments ..."
            $ParameterArgs | ConvertTo-Array -RemoveNull -RemoveEmpty | ForEach-Object {
                if ("$_" -ne "" -and "$_" -match '^-param_(.*)') {
                    [string] $key = $Matches[1]                
                } elseif ( $key ) {
                    $ParameterData.Set_Item($key, [string] $_)
                }
            }
        }

        # read parameter names from termplate
        $ParameterNames = [string[]] (Get-Member -InputObject $template.Properties.contents.parameters -MemberType NoteProperty | Select-Object -ExpandProperty Name)
        
        # remove unknown arguments        
        $ParameterData.Keys | Where-Object { $_ -notin $ParameterNames } | ConvertTo-Array | ForEach-Object { 
            "Removing unknown template argument '$_' ..." | Write-Warning
            $ParameterData.Remove([string] $_) 
        }

        # write some debug output
        $ParameterData | Format-Table

        # combine template parameters and properties (HT)
        $templateParameters = $ParameterData.Keys | ForEach-Object { @{ "name" = "$_"; "value" = "$($ParameterData[$_])" } } | ConvertTo-Array
        $templateProperties = @{ "deploymentProperties" = @{ "armTemplateId" = "$($template.ResourceId)"; "parameters" = $templateParameters }; } 

        # create a new environment
        New-AzureRmResource -Location $Lab.Location -ResourceGroupName $lab.ResourceGroupName -Properties $templateProperties -ResourceType 'Microsoft.DevTestLab/labs/users/environments' -ResourceName "$LabName/$UserId/$EnvironmentName" -ApiVersion '2016-05-15' -Force 
    }
    
    end {
    }
}

Export-ModuleMember -Function New-DevTestLabEnvironment

<# 
 .Synopsis
  Delete a Azure DevTest Labs environment.

 .Description
  Delete a Azure DevTest Labs environment.

 .Parameter LabName
  The name of the Azure DevTest Lab which contains the environment to delete.

 .Parameter EnvironmentName
  The name of the environment to delete.

 .Parameter UserId
  The object ID or the user who owns the environment to delete.  
#>

function Remove-DevTestLabEnvironment {

    [CmdletBinding()]
    param (
        [string] [Parameter(Mandatory=$true)] $LabName,
        [string] $EnvironmentName,
        
        [string] $UserId = $((Get-AzureRmADUser -UserPrincipalName (Get-AzureRmContext).Account).Id.Guid)
    )
    
    begin {
    }
    
    process {

        $SubscriptionId = (Get-AzureRmContext).Subscription.Id
        
        $lab = Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs" -ResourceNameEquals $LabName 
        if ($lab -eq $null) { throw "Unable to find lab $LabName in subscription $SubscriptionId." } 

        if ($EnvironmentName) {

            $env = Get-AzureRmResource -ResourceGroupName $lab.ResourceGroupName -ResourceType 'Microsoft.DevTestLab/labs/users/environments' -ResourceName "$LabName/$UserId/$EnvironmentName" -ApiVersion 2016-05-15 -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($env -eq $null) { throw "Unable to find environent $EnvironmentName in lab $LabName." } 

            "Removing environment ($(env.ResourceId)) ..."
            Remove-AzureRmResource -ResourceId $env.ResourceId -ApiVersion '2016-05-15' -Force

        } else {

            Get-AzureRmResource -ResourceGroupName $lab.ResourceGroupName -ResourceType 'Microsoft.DevTestLab/labs/users/environments' -ResourceName "$LabName/$UserId" -ApiVersion 2016-05-15 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty ResourceId | ForEach-Object { 

                "Removing environment ($_) ..."
                Remove-AzureRmResource -ResourceId $_ -ApiVersion '2016-05-15' -Force 
            }
        }
    }
    
    end {
    }
}

Export-ModuleMember -Function Remove-DevTestLabEnvironment