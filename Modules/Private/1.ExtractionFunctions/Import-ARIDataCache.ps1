<#
.Synopsis
Import Azure Resource Inventory data from cache files

.DESCRIPTION
This module imports previously exported Azure data from cache files to speed up subsequent runs.

.Link
https://github.com/microsoft/ARI/Modules/Private/1.ExtractionFunctions/Import-ARIDataCache.ps1

.COMPONENT
This PowerShell Module is part of Azure Resource Inventory (ARI)

.NOTES
Version: 3.7.0
First Release Date: 8th Jan, 2026
Authors: Claudio Merola

#>
function Import-ARIDataCache {
    Param(
        [Parameter(Mandatory=$true)]
        [string]$ImportPath
    )

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting data cache import from: ' + $ImportPath)
    
    # Verify import directory exists
    if (!(Test-Path -Path $ImportPath)) {
        Write-Error "Import path does not exist: $ImportPath"
        return $null
    }
    
    # Read metadata file
    $MetadataFile = Join-Path $ImportPath "ARI_Export_Metadata.json"
    if (!(Test-Path -Path $MetadataFile)) {
        Write-Warning "Metadata file not found. Import may not be complete."
        $Metadata = $null
    } else {
        $Metadata = Get-Content -Path $MetadataFile -Raw | ConvertFrom-Json
        Write-Host ""
        Write-Host "Loading cached data from export:" -ForegroundColor Cyan
        Write-Host "  Export Date: " -NoNewline
        Write-Host $Metadata.ExportDate -ForegroundColor Yellow
        Write-Host "  Subscriptions: " -NoNewline
        Write-Host $Metadata.SubscriptionCount -ForegroundColor Yellow
        Write-Host "  Resources: " -NoNewline
        Write-Host $Metadata.ResourceCount -ForegroundColor Yellow
        Write-Host ""
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Metadata loaded: ' + $Metadata.ExportDate)
    }
    
    # Get all subscription directories
    $SubDirs = Get-ChildItem -Path $ImportPath -Directory
    
    if ($SubDirs.Count -eq 0) {
        Write-Error "No subscription directories found in import path: $ImportPath"
        return $null
    }
    
    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Found ' + $SubDirs.Count + ' subscription directories')
    
    # Initialize collections
    $AllResources = @()
    $AllResourceContainers = @()
    $AllAdvisories = @()
    $AllSecurity = @()
    $AllRetirements = @()
    $AllSubscriptions = @()
    
    # Import data from each subscription
    $SubCount = 0
    foreach ($SubDir in $SubDirs) {
        $SubCount++
        Write-Progress -Activity 'Importing Data Cache' -Status "Importing subscription $SubCount of $($SubDirs.Count)" -PercentComplete (($SubCount / $SubDirs.Count) * 100)
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Importing data from: ' + $SubDir.Name)
        
        # Import subscription info
        $SubInfoFile = Join-Path $SubDir.FullName "SubscriptionInfo.json"
        if (Test-Path -Path $SubInfoFile) {
            $SubInfo = Get-Content -Path $SubInfoFile -Raw | ConvertFrom-Json
            $AllSubscriptions += $SubInfo
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Imported subscription info: ' + $SubInfo.SubscriptionName)
        }
        
        # Import Resources
        $ResourceFile = Join-Path $SubDir.FullName "Resources.json"
        if (Test-Path -Path $ResourceFile) {
            $Resources = Get-Content -Path $ResourceFile -Raw | ConvertFrom-Json
            $AllResources += $Resources
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Imported $($Resources.Count) resources")
        }
        
        # Import Resource Containers
        $ContainerFile = Join-Path $SubDir.FullName "ResourceContainers.json"
        if (Test-Path -Path $ContainerFile) {
            $Containers = Get-Content -Path $ContainerFile -Raw | ConvertFrom-Json
            $AllResourceContainers += $Containers
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Imported $($Containers.Count) containers")
        }
        
        # Import Advisories
        $AdvisoryFile = Join-Path $SubDir.FullName "Advisories.json"
        if (Test-Path -Path $AdvisoryFile) {
            $Advisories = Get-Content -Path $AdvisoryFile -Raw | ConvertFrom-Json
            $AllAdvisories += $Advisories
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Imported $($Advisories.Count) advisories")
        }
        
        # Import Security
        $SecurityFile = Join-Path $SubDir.FullName "Security.json"
        if (Test-Path -Path $SecurityFile) {
            $Security = Get-Content -Path $SecurityFile -Raw | ConvertFrom-Json
            $AllSecurity += $Security
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Imported $($Security.Count) security items")
        }
        
        # Import Retirements
        $RetirementFile = Join-Path $SubDir.FullName "Retirements.json"
        if (Test-Path -Path $RetirementFile) {
            $Retirements = Get-Content -Path $RetirementFile -Raw | ConvertFrom-Json
            $AllRetirements += $Retirements
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Imported $($Retirements.Count) retirements")
        }
    }
    
    Write-Progress -Activity 'Importing Data Cache' -Completed
    
    Write-Host "Data cache imported successfully!" -ForegroundColor Green
    Write-Host "  Total Resources: " -NoNewline
    Write-Host $AllResources.Count -ForegroundColor Cyan
    Write-Host "  Total Advisories: " -NoNewline
    Write-Host $AllAdvisories.Count -ForegroundColor Cyan
    Write-Host "  Total Security Items: " -NoNewline
    Write-Host $AllSecurity.Count -ForegroundColor Cyan
    Write-Host "  Total Retirements: " -NoNewline
    Write-Host $AllRetirements.Count -ForegroundColor Cyan
    Write-Host ""
    
    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Data cache import completed')
    
    # Return imported data
    $ImportedData = [PSCustomObject]@{
        Resources = $AllResources
        ResourceContainers = $AllResourceContainers
        Advisories = $AllAdvisories
        Security = $AllSecurity
        Retirements = $AllRetirements
        Subscriptions = $AllSubscriptions
    }
    
    return $ImportedData
}
