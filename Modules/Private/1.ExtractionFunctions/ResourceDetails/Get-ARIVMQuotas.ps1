<#
.Synopsis
Module responsible for retrieving Azure VM quotas with parallel processing.

.DESCRIPTION
This module retrieves Azure VM quotas for specific subscriptions and locations.
Now supports parallel processing for improved performance.

.Link
https://github.com/microsoft/ARI/Modules/Private/1.ExtractionFunctions/ResourceDetails/Get-ARIVMQuotas.ps1

.COMPONENT
This PowerShell Module is part of Azure Resource Inventory (ARI).

.NOTES
Version: 3.7.0
First Release Date: 15th Oct, 2024
Updated: Jan 2026 - Added parallel subscription processing
Authors: Claudio Merola
#>
function Get-AriVMQuotas {
    Param ($Subscriptions, $Resources)
    
    # Use thread-safe collection for parallel processing
    $QuotasBag = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    
    # Process subscriptions in parallel
    $Subscriptions | ForEach-Object -ThrottleLimit 5 -Parallel {
        $Sub = $_
        $ResourcesLocal = $using:Resources
        $QuotasCollection = $using:QuotasBag
        
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"[Parallel] Getting VM Quota Details: $($Sub.name)")
        
        $Locs = ($ResourcesLocal | Where-Object {$_.subscriptionId -eq $Sub.id -and $_.Type -in 'microsoft.compute/virtualmachines','microsoft.compute/virtualmachinescalesets'} | Group-Object -Property Location).name
        
        if (![string]::IsNullOrEmpty($Locs))
            {
                Foreach($Loc in $Locs)
                    {
                        if($Loc.count -eq 1)
                            {
                                Set-AzContext -Subscription $Sub.Id -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -Debug:$false
                                $Quota = get-azvmusage -location $Loc -Debug:$false
                                $Quota = $Quota | Where-Object {$_.CurrentValue -ge 1}
                                $tmp = [PSCustomObject]@{
                                    Location = $Loc
                                    SubId = $Sub.id
                                    Subscription = $Sub.name
                                    Data = $Quota
                                }
                                $QuotasCollection.Add($tmp)
                            }
                        else {
                                Set-AzContext -Subscription $Sub.Id -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -InformationAction SilentlyContinue -Debug:$false
                                foreach($Loc1 in $Loc)
                                    {
                                        $Quota = get-azvmusage -location $Loc1 -Debug:$false
                                        $Quota = $Quota | Where-Object {$_.CurrentValue -ge 1}
                                        $tmp = [PSCustomObject]@{
                                            Location = $Loc1
                                            SubId = $Sub.id
                                            Subscription = $Sub.name
                                            Data = $Quota
                                        }
                                        $QuotasCollection.Add($tmp)
                                    }
                        }
                    }
            }
    }
    
    # Convert ConcurrentBag to array
    $Quotas = $QuotasBag.ToArray()

    $VMQuotas = [PSCustomObject]@{
        'type'          = 'ARI/VM/Quotas'
        'properties'    = $Quotas
    }

    return $VMQuotas
}