<#
.Synopsis
Extraction orchestration for Azure Resource Inventory

.DESCRIPTION
This module orchestrates the extraction of resources for Azure Resource Inventory.

.Link
https://github.com/microsoft/ARI/Modules/Private/0.MainFunctions/Start-ARIExtractionOrchestration.ps1

.COMPONENT
This PowerShell Module is part of Azure Resource Inventory (ARI)

.NOTES
Version: 3.6.11
First Release Date: 15th Oct, 2024
Authors: Claudio Merola

#>
function Start-ARIExtractionOrchestration {
    Param($ManagementGroup, $Subscriptions, $SubscriptionID, $SkipPolicy, $ResourceGroup, $SecurityCenter, $SkipAdvisory, $IncludeTags, $TagKey, $TagValue, $SkipAPIs, $SkipVMDetails, $IncludeCosts, $Automation, $AzureEnvironment, $ExportDataPath, $ImportDataPath)

    # Check if we should import data from cache instead of querying Azure
    if (![string]::IsNullOrEmpty($ImportDataPath)) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  Importing Data from Cache" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Importing data from cache: ' + $ImportDataPath)
        
        $ImportedData = Import-ARIDataCache -ImportPath $ImportDataPath
        
        if ($null -eq $ImportedData) {
            Write-Error "Failed to import data from cache. Aborting."
            Exit
        }
        
        $Resources = $ImportedData.Resources
        $ResourceContainers = $ImportedData.ResourceContainers
        $Advisories = $ImportedData.Advisories
        $Security = $ImportedData.Security
        $Retirements = $ImportedData.Retirements
        
        # Update subscriptions list if available from cache
        if ($ImportedData.Subscriptions -and $ImportedData.Subscriptions.Count -gt 0) {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Using subscriptions from cache')
        }
        
        Remove-Variable -Name ImportedData -ErrorAction SilentlyContinue
    }
    else {
        # Normal extraction flow - query Azure
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Extracting data from Azure')
        
        $GraphData = Start-ARIGraphExtraction -ManagementGroup $ManagementGroup -Subscriptions $Subscriptions -SubscriptionID $SubscriptionID -ResourceGroup $ResourceGroup -SecurityCenter $SecurityCenter -SkipAdvisory $SkipAdvisory -IncludeTags $IncludeTags -TagKey $TagKey -TagValue $TagValue -AzureEnvironment $AzureEnvironment

        $Resources = $GraphData.Resources
        $ResourceContainers = $GraphData.ResourceContainers
        $Advisories = $GraphData.Advisories
        $Security = $GraphData.Security
        $Retirements = $GraphData.Retirements

        Remove-Variable -Name GraphData -ErrorAction SilentlyContinue
    }

    $ResourcesCount = [string]$Resources.Count
    $AdvisoryCount = [string]$Advisories.Count
    $SecCenterCount = [string]$Security.Count

    # Skip API calls and VM details if importing from cache
    if([string]::IsNullOrEmpty($ImportDataPath)) {
        if(!$SkipAPIs.IsPresent)
            {
                Write-Progress -activity 'Azure Inventory' -Status "12% Complete." -PercentComplete 12 -CurrentOperation "Starting API Extraction.."
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Getting API Resources.')
                $APIResults = Get-ARIAPIResources -Subscriptions $Subscriptions -AzureEnvironment $AzureEnvironment -SkipPolicy $SkipPolicy
                $Resources += $APIResults.ResourceHealth
                $Resources += $APIResults.ManagedIdentities
                $Resources += $APIResults.AdvisorScore
                $Resources += $APIResults.ReservationRecomen
                $PolicyAssign = $APIResults.PolicyAssign
                $PolicyDef = $APIResults.PolicyDef
                $PolicySetDef = $APIResults.PolicySetDef
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'API Resource Inventory Finished.')
                Remove-Variable APIResults -ErrorAction SilentlyContinue
            }

        $PolicyCount = [string]$PolicyAssign.policyAssignments.Count

        if ($IncludeCosts.IsPresent) {
            $Costs = Get-ARICostInventory -Subscriptions $Subscriptions -Days 60 -Granularity 'Monthly'
        }

        if (!$SkipVMDetails.IsPresent)
            {
                Write-Host 'Gathering VM Extra Details: ' -NoNewline
                Write-Host 'Quotas' -ForegroundColor Cyan
                Write-Progress -activity 'Azure Inventory' -Status "13% Complete." -PercentComplete 13 -CurrentOperation "Starting VM Details Extraction.."

                $VMQuotas = Get-AriVMQuotas -Subscriptions $Subscriptions -Resources $Resources

                $Resources += $VMQuotas

                Remove-Variable -Name VMQuotas -ErrorAction SilentlyContinue

                Write-Host 'Gathering VM Extra Details: ' -NoNewline
                Write-Host 'Size SKU' -ForegroundColor Cyan

                $VMSkuDetails = Get-ARIVMSkuDetails -Resources $Resources

                $Resources += $VMSkuDetails

                Remove-Variable -Name VMSkuDetails -ErrorAction SilentlyContinue

            }
    }
    else {
        Write-Host ""
        Write-Host "Skipping API calls and VM details (using imported data)" -ForegroundColor Yellow
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Skipped API extraction and VM details (imported from cache)')
    }

    # Export data to cache if requested
    if (![string]::IsNullOrEmpty($ExportDataPath)) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  Exporting Data to Cache" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Exporting data to cache: ' + $ExportDataPath)
        
        Export-ARIDataCache -ExportPath $ExportDataPath -Resources $Resources -ResourceContainers $ResourceContainers -Advisories $Advisories -Security $Security -Retirements $Retirements -Subscriptions $Subscriptions
    }

    $ReturnData = [PSCustomObject]@{
        Resources = $Resources
        Quotas = $VMQuotas
        Costs = $Costs
        ResourceContainers = $ResourceContainers
        Advisories = $Advisories
        ResourcesCount = $ResourcesCount
        AdvisoryCount = $AdvisoryCount
        SecCenterCount = $SecCenterCount
        Security = $Security
        Retirements = $Retirements
        PolicyCount = $PolicyCount
        PolicyAssign = $PolicyAssign
        PolicyDef = $PolicyDef
        PolicySetDef = $PolicySetDef
    }

    return $ReturnData
}