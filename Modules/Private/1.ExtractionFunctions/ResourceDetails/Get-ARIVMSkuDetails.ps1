<#
.Synopsis
Module responsible for retrieving Azure VM SKU details with parallel processing.

.DESCRIPTION
This module retrieves details about Azure VM SKUs available in specific locations.
Now supports parallel processing for improved performance.

.Link
https://github.com/microsoft/ARI/Modules/Private/1.ExtractionFunctions/ResourceDetails/Get-ARIVMSkuDetails.ps1

.COMPONENT
This PowerShell Module is part of Azure Resource Inventory (ARI).

.NOTES
Version: 3.7.0
First Release Date: 15th Oct, 2024
Updated: Jan 2026 - Added parallel location processing
Authors: Claudio Merola, Olli Uronen (Seppohto)
#>
function Get-ARIVMSkuDetails {
    Param ($Resources)

    $vm = $Resources | Where-Object {$_.TYPE -in 'microsoft.compute/virtualmachines','microsoft.compute/virtualmachinescalesets'}
    $locations = $vm | Select-Object -ExpandProperty location -Unique
    
    # Use thread-safe collection for parallel processing
    $VMskuDataBag = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

    # Process locations in parallel
    $locations | ForEach-Object -ThrottleLimit 5 -Parallel {
        $location = $_
        $SkuDataCollection = $using:VMskuDataBag
        
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"[Parallel] Getting VM SKU Details: $location")
        
        $tmp = [PSCustomObject]@{
            Location    = $location
            SKUs        = Get-AzComputeResourceSku $location -Debug:$false
        }
        
        $SkuDataCollection.Add($tmp)
    }
    
    # Convert ConcurrentBag to array
    $VMskuData = $VMskuDataBag.ToArray()

    $VMSkuDetails = [PSCustomObject]@{
        'type'          = 'ARI/VM/SKU'
        'properties'    = $VMskuData
    }

    return $VMSkuDetails
}