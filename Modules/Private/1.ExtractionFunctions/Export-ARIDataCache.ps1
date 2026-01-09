<#
.Synopsis
Export Azure Resource Inventory data to cache files

.DESCRIPTION
This module exports extracted Azure data to cache files per subscription for faster subsequent runs.

.Link
https://github.com/microsoft/ARI/Modules/Private/1.ExtractionFunctions/Export-ARIDataCache.ps1

.COMPONENT
This PowerShell Module is part of Azure Resource Inventory (ARI)

.NOTES
Version: 3.7.0
First Release Date: 8th Jan, 2026
Authors: Claudio Merola

#>
function Export-ARIDataCache {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$ExportPath,
        
        [Parameter(Mandatory=$true)]
        $Resources,
        
        [Parameter(Mandatory=$false)]
        $ResourceContainers,
        
        [Parameter(Mandatory=$false)]
        $Advisories,
        
        [Parameter(Mandatory=$false)]
        $Security,
        
        [Parameter(Mandatory=$false)]
        $Retirements,
        
        [Parameter(Mandatory=$true)]
        $Subscriptions
    )

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting data cache export to: ' + $ExportPath)
    
    # Create export directory if it doesn't exist
    if (!(Test-Path -Path $ExportPath)) {
        New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Created export directory: ' + $ExportPath)
    }
    
    # Create a timestamp for this export
    $ExportTimestamp = Get-Date -Format "yyyy-MM-dd_HH_mm_ss"
    
    # Create metadata file
    $Metadata = @{
        ExportDate = $ExportTimestamp
        SubscriptionCount = $Subscriptions.Count
        ResourceCount = $Resources.Count
        AdvisoryCount = if ($Advisories) { $Advisories.Count } else { 0 }
        SecurityCount = if ($Security) { $Security.Count } else { 0 }
        RetirementCount = if ($Retirements) { $Retirements.Count } else { 0 }
        ResourceContainerCount = if ($ResourceContainers) { $ResourceContainers.Count } else { 0 }
        ARIVersion = "3.7.0"
    }
    
    $MetadataFile = Join-Path $ExportPath "ARI_Export_Metadata.json"
    $Metadata | ConvertTo-Json -Depth 5 | Out-File $MetadataFile -Force
    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Created metadata file: ' + $MetadataFile)
    
    # Export data per subscription
    $SubCount = 0
    foreach ($Sub in $Subscriptions) {
        $SubCount++
        $SubId = $Sub.Id
        $SubName = $Sub.Name -replace '[\\\/\:\*\?\"\<\>\|]', '_'  # Sanitize filename
        
        Write-Progress -Activity 'Exporting Data Cache' -Status "Exporting subscription $SubCount of $($Subscriptions.Count)" -PercentComplete (($SubCount / $Subscriptions.Count) * 100)
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Exporting data for subscription: ' + $SubName)
        
        # Create subscription directory
        $SubDir = Join-Path $ExportPath $SubName
        if (!(Test-Path -Path $SubDir)) {
            New-Item -Path $SubDir -ItemType Directory -Force | Out-Null
        }
        
        # Export Resources for this subscription
        $SubResources = $Resources | Where-Object { $_.subscriptionId -eq $SubId }
        if ($SubResources) {
            $ResourceFile = Join-Path $SubDir "Resources.json"
            $SubResources | ConvertTo-Json -Depth 40 -Compress | Out-File $ResourceFile -Force
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Exported $($SubResources.Count) resources")
        }
        
        # Export Resource Containers for this subscription
        if ($ResourceContainers) {
            $SubContainers = $ResourceContainers | Where-Object { $_.subscriptionId -eq $SubId }
            if ($SubContainers) {
                $ContainerFile = Join-Path $SubDir "ResourceContainers.json"
                $SubContainers | ConvertTo-Json -Depth 40 -Compress | Out-File $ContainerFile -Force
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Exported $($SubContainers.Count) containers")
            }
        }
        
        # Export Advisories for this subscription
        if ($Advisories) {
            $SubAdvisories = $Advisories | Where-Object { $_.subscriptionId -eq $SubId }
            if ($SubAdvisories) {
                $AdvisoryFile = Join-Path $SubDir "Advisories.json"
                $SubAdvisories | ConvertTo-Json -Depth 40 -Compress | Out-File $AdvisoryFile -Force
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Exported $($SubAdvisories.Count) advisories")
            }
        }
        
        # Export Security for this subscription
        if ($Security) {
            $SubSecurity = $Security | Where-Object { $_.subscriptionId -eq $SubId }
            if ($SubSecurity) {
                $SecurityFile = Join-Path $SubDir "Security.json"
                $SubSecurity | ConvertTo-Json -Depth 40 -Compress | Out-File $SecurityFile -Force
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Exported $($SubSecurity.Count) security items")
            }
        }
        
        # Export Retirements for this subscription
        if ($Retirements) {
            $SubRetirements = $Retirements | Where-Object { $_.subscriptionId -eq $SubId }
            if ($SubRetirements) {
                $RetirementFile = Join-Path $SubDir "Retirements.json"
                $SubRetirements | ConvertTo-Json -Depth 40 -Compress | Out-File $RetirementFile -Force
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Exported $($SubRetirements.Count) retirements")
            }
        }
        
        # Export subscription info
        $SubInfo = @{
            SubscriptionId = $SubId
            SubscriptionName = $Sub.Name
            TenantId = $Sub.TenantId
            State = $Sub.State
        }
        $SubInfoFile = Join-Path $SubDir "SubscriptionInfo.json"
        $SubInfo | ConvertTo-Json -Depth 5 | Out-File $SubInfoFile -Force
    }
    
    Write-Progress -Activity 'Exporting Data Cache' -Completed
    
    Write-Host ""
    Write-Host "Data cache exported successfully to: " -NoNewline
    Write-Host $ExportPath -ForegroundColor Green
    Write-Host "Total subscriptions exported: " -NoNewline
    Write-Host $Subscriptions.Count -ForegroundColor Cyan
    Write-Host "To reuse this data in future runs, use: " -NoNewline
    Write-Host "-ImportDataPath `"$ExportPath`"" -ForegroundColor Yellow
    Write-Host ""
    
    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Data cache export completed')
}
