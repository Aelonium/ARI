<#
.Synopsis
Module responsible for looping through Azure Resource Graph queries with parallel subscription processing.

.DESCRIPTION
This module is used to loop through Azure Resource Graph queries and retrieve resources in batches.
It now supports parallel processing of subscription batches to improve performance for large environments.

.Link
https://github.com/microsoft/ARI/Modules/Private/1.ExtractionFunctions/Invoke-ARIInventoryLoop.ps1

.COMPONENT
This PowerShell Module is part of Azure Resource Inventory (ARI).

.NOTES
Version: 3.7.0
First Release Date: 15th Oct, 2024
Updated: Jan 2026 - Added parallel subscription processing
Authors: Claudio Merola
#>
function Invoke-ARIInventoryLoop {
    param($GraphQuery, $FSubscri, $LoopName)

    Write-Progress -Id 1 -activity 'Azure Inventory' -Status "1% Complete." -PercentComplete 1 -CurrentOperation ('Extracting: ' + $LoopName)
    
    # Use thread-safe collection for parallel processing
    $LocalResults = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
    
    if($FSubscri.count -gt 200)
        {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Processing subscriptions in parallel batches for: '+ $LoopName)
            
            # Calculate number of batches
            $SubLoop = [Math]::Ceiling($FSubscri.count / 200)
            $SubBatches = @()
            
            # Create subscription batches
            for ($i = 0; $i -lt $SubLoop; $i++) {
                $NStart = $i * 200
                $NEnd = [Math]::Min(($i + 1) * 200 - 1, $FSubscri.count - 1)
                $SubBatches += ,@($FSubscri[$NStart..$NEnd])
            }
            
            # Process batches in parallel using ForEach-Object -Parallel
            $SubBatches | ForEach-Object -ThrottleLimit 10 -Parallel {
                $Sub = $_
                $Query = $using:GraphQuery
                $Name = $using:LoopName
                $Results = $using:LocalResults
                
                try {
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Parallel Extracting First 1000 '+ $Name)
                    $QueryResult = Search-AzGraph -Query $Query -first 1000 -Subscription $Sub -Debug:$false
                }
                catch {
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Parallel Extracting First 200 ' + $Name)
                    $QueryResult = Search-AzGraph -Query $Query -first 200 -Subscription $Sub -Debug:$false
                }
                
                # Add initial results
                foreach ($item in $QueryResult) {
                    $Results.Add($item)
                }
                
                # Process remaining pages
                while ($QueryResult.SkipToken) {
                    try {
                        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Parallel Extracting Next 1000 ' + $Name)
                        $QueryResult = Search-AzGraph -Query $Query -SkipToken $QueryResult.SkipToken -Subscription $Sub -first 1000 -Debug:$false
                    }
                    catch {
                        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Parallel Extracting Next 200 ' + $Name)
                        $QueryResult = Search-AzGraph -Query $Query -SkipToken $QueryResult.SkipToken -Subscription $Sub -first 200 -Debug:$false
                    }
                    
                    foreach ($item in $QueryResult) {
                        $Results.Add($item)
                    }
                }
            }
        }
    else
        {
            try
                {
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Extracting First 1000 ' + $LoopName)
                    $QueryResult = Search-AzGraph -Query $GraphQuery -first 1000 -Subscription $FSubscri -Debug:$false
                }
            catch
                {
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Extracting First 200 ' + $LoopName)
                    $QueryResult = Search-AzGraph -Query $GraphQuery -first 200 -Subscription $FSubscri -Debug:$false
                }

            foreach ($item in $QueryResult) {
                $LocalResults.Add($item)
            }
            
            $ReportCounter = 1
            while ($QueryResult.SkipToken) {
                $ReportCounterVar = [string]$ReportCounter
                try
                    {
                        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Extracting Next 1000 ' + $LoopName + '. Loop Number: ' + $ReportCounterVar)
                        Write-Progress -Id 1 -activity ('Extracting: ' + $LoopName) -Status "$ReportCounter% Complete." -PercentComplete $ReportCounter
                        $QueryResult = Search-AzGraph -Query $GraphQuery -SkipToken $QueryResult.SkipToken -Subscription $FSubscri -first 1000 -Debug:$false
                    }
                catch
                    {
                        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Extracting Next 200 ' + $LoopName + '. Loop Number: ' + $ReportCounterVar)
                        Write-Progress -Id 1 -activity ('Extracting: ' + $LoopName) -Status "$ReportCounter% Complete." -PercentComplete $ReportCounter
                        $QueryResult = Search-AzGraph -Query $GraphQuery -SkipToken $QueryResult.SkipToken -Subscription $FSubscri -first 200 -Debug:$false
                    }
                foreach ($item in $QueryResult) {
                    $LocalResults.Add($item)
                }
                $ReportCounter ++
            }
        }
    
    Write-Progress -Id 1 -activity ('Extracting: ' + $LoopName) -Status "100% Complete." -Completed
    
    # Convert ConcurrentBag to array for return
    return $LocalResults.ToArray()
}