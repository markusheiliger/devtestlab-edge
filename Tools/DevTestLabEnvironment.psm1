
#Requires -Version 3.0
#Requires -Module AzureRM.Resources

function New-DevTestLabEnvironment {

    [CmdletBinding()]

    param (
        [string] [Parameter(Mandatory=$true)] $LabName,
        [string] [Parameter(Mandatory=$true)] $RepositoryName,
        [string] [Parameter(Mandatory=$true)] $EnvironmentName,
        [string] [Parameter(Mandatory=$true)] $TemplateName,
        
        [string] $UserId = $((Get-AzureRmADUser -UserPrincipalName (Get-AzureRmContext).Account).Id.Guid),

        [Parameter(ValueFromRemainingArguments=$true)]
        $Params
    )
    
    begin {
    }
    
    process {

        $lab = Find-AzureRmResource -ResourceType "Microsoft.DevTestLab/labs" -ResourceNameEquals $LabName 
        if ($lab -eq $null) { throw "Unable to find lab $LabName in subscription $SubscriptionId." } 
    
        $repository = Get-AzureRmResource -ResourceGroupName $lab.ResourceGroupName -ResourceType 'Microsoft.DevTestLab/labs/artifactsources' -ResourceName $LabName -ApiVersion 2016-05-15 | Where-Object { $RepositoryName -in ($_.Name, $_.Properties.displayName) } | Select-Object -First 1
        if ($repository -eq $null) { throw "Unable to find repository $RepositoryName in lab $LabName." } 
    
        $template = Get-AzureRmResource -ResourceGroupName $lab.ResourceGroupName -ResourceType "Microsoft.DevTestLab/labs/artifactSources/armTemplates" -ResourceName "$LabName/$($repository.Name)" -ApiVersion 2016-05-15  | Where-Object { $TemplateName -in ($_.Name, $_.Properties.displayName) } | Select-Object -First 1
        if ($template -eq $null) { throw "Unable to find template $TemplateName in lab $LabName." } 
    
        $parameters = Get-Member -InputObject $template.Properties.contents.parameters -MemberType NoteProperty | Select-Object -ExpandProperty Name
        $templateParameters = @()

        $Params | ForEach-Object {
            if ($_ -match '^-param_(.*)' -and $Matches[1] -in $parameters) {
                $name = $Matches[1]                
            } elseif ( $name ) {
                $templateParameters += @{ "name" = "$name"; "value" = "$_" }
                $name = $null #reset name variable
            }
        }
    
        $templateProperties = @{ "deploymentProperties" = @{ "armTemplateId" = "$($template.ResourceId)"; "parameters" = $templateParameters }; } 
        $templateProperties

        New-AzureRmResource -Location $Lab.Location -ResourceGroupName $lab.ResourceGroupName -Properties $templateProperties -ResourceType 'Microsoft.DevTestLab/labs/users/environments' -ResourceName "$LabName/$UserId/$EnvironmentName" -ApiVersion '2016-05-15' -Force 
    }
    
    end {
    }
}

Export-ModuleMember -Function New-DevTestLabEnvironment
