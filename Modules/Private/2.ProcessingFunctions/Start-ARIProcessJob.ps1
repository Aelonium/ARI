<#
.Synopsis
Module responsible for starting the processing jobs for Azure Resources with parallel execution.

.DESCRIPTION
This module creates and manages jobs to process Azure Resources in batches based on the environment size. 
It now uses ThreadJobs for better parallelization and ensures efficient resource processing while avoiding CPU overload.

.Link
https://github.com/microsoft/ARI/Modules/Private/2.ProcessingFunctions/Start-ARIProcessJob.ps1

.COMPONENT
This PowerShell Module is part of Azure Resource Inventory (ARI).

.NOTES
Version: 3.7.0
First Release Date: 15th Oct, 2024
Updated: Jan 2026 - Improved parallel processing
Authors: Claudio Merola
#>

function Start-ARIProcessJob {
    Param($Resources, $Retirements, $Subscriptions, $DefaultPath, $Heavy, $InTag, $Unsupported)

    Write-Progress -activity 'Azure Inventory' -Status "22% Complete." -PercentComplete 22 -CurrentOperation "Creating Jobs to Process Data.."

    # Improved batch sizing for parallel processing
    switch ($Resources.count)
    {
        {$_ -le 12500}
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Regular Size Environment. All jobs will be run in parallel.')
                $EnvSizeLooper = 50  # Reasonable limit to prevent resource exhaustion
            }
        {$_ -gt 12500 -and $_ -le 50000}
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Medium Size Environment. Jobs will be run in batches of 15.')
                $EnvSizeLooper = 15  # Increased batch size
            }
        {$_ -gt 50000}
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Large Environment Detected. Jobs will be run in batches of 10.')
                $EnvSizeLooper = 10  # Improved from 5
                Write-Host ('Jobs will be run in optimized batches for large environments.') -ForegroundColor Yellow
            }
    }

    if ($Heavy.IsPresent -or $InTag.IsPresent)
        {
            Write-Host ('Heavy Mode or InTag Mode Detected. Jobs will be run in smaller batches to avoid CPU and Memory Overload.') -ForegroundColor Yellow
            $EnvSizeLooper = 8  # Improved from 5
        }

    $ParentPath = (get-item $PSScriptRoot).parent.parent
    $InventoryModulesPath = Join-Path $ParentPath 'Public' 'InventoryModules'
    $ModuleFolders = Get-ChildItem -Path $InventoryModulesPath -Directory

    $JobLoop = 1
    $TotalFolders = $ModuleFolders.count

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Preparing resource data for parallel processing')
    
    # Note: ThreadJob can serialize objects automatically without JSON conversion
    # This avoids the expensive JSON serialization/deserialization step
    
    Remove-Variable -Name NewResources -ErrorAction SilentlyContinue
    Clear-ARIMemory

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting to Create Jobs to Process the Resources.')
    Write-Host ""
    Write-Host "Creating processing jobs for resource types..." -ForegroundColor Cyan

    #Foreach ($ModuleFolder in $ModuleFolders)
    $ModuleFolders | ForEach-Object -Process {
            $ModuleFolder = $_
            $ModulePath = Join-Path $ModuleFolder.FullName '*.ps1'
            $ModuleName = $ModuleFolder.Name
            $ModuleFiles = Get-ChildItem -Path $ModulePath

            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Creating Job: '+$ModuleName)
            Write-Host "  [Job Created] " -NoNewline -ForegroundColor Green
            Write-Host $ModuleName -ForegroundColor Yellow

            $c = (($JobLoop / $TotalFolders) * 100)
            $c = [math]::Round($c)
            Write-Progress -Id 1 -activity "Creating Jobs" -Status "$c% Complete." -PercentComplete $c

            # Use ThreadJob for better parallel performance
            Start-ThreadJob -Name ('ResourceJob_'+$ModuleName) -ScriptBlock {

                $ModuleFiles = $($args[0])
                $Subscriptions = $($args[2])
                $InTag = $($args[3])
                $Resources = $($args[4])  # No JSON conversion needed - ThreadJob handles serialization
                $Retirements = $($args[5])
                $Task = $($args[6])
                $Unsupported = $($args[10])

                # Use thread-safe hashtable for parallel module processing
                $Hashtable = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()

                # Process modules in parallel using ForEach-Object -Parallel
                $ModuleFiles | ForEach-Object -ThrottleLimit 5 -Parallel {
                    $Module = $_
                    $PSScriptRootLocal = $using:PSScriptRoot
                    $SubscriptionsLocal = $using:Subscriptions
                    $InTagLocal = $using:InTag
                    $ResourcesLocal = $using:Resources
                    $RetirementsLocal = $using:Retirements
                    $TaskLocal = $using:Task
                    $UnsupportedLocal = $using:Unsupported
                    $ResultHash = $using:Hashtable
                    
                    $ModuleFileContent = New-Object System.IO.StreamReader($Module.FullName)
                    $ModuleData = $ModuleFileContent.ReadToEnd()
                    $ModuleFileContent.Dispose()
                    $ModName = $Module.Name.replace(".ps1","")

                    $ScriptBlock = [Scriptblock]::Create($ModuleData)
                    $Result = Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $PSScriptRootLocal, $SubscriptionsLocal, $InTagLocal, $ResourcesLocal, $RetirementsLocal, $TaskLocal, $null, $null, $null, $UnsupportedLocal

                    # Add result to thread-safe hashtable
                    $ResultHash.TryAdd($ModName, $Result) | Out-Null
                }

                # Convert ConcurrentDictionary to regular Hashtable for compatibility
                $OutputHashtable = New-Object System.Collections.Hashtable
                foreach ($key in $Hashtable.Keys) {
                    $OutputHashtable[$key] = $Hashtable[$key]
                }
                
                $OutputHashtable

            } -ArgumentList $ModuleFiles, $PSScriptRoot, $Subscriptions, $InTag, $Resources, $Retirements, 'Processing', $null, $null, $null, $Unsupported | Out-Null

        if($JobLoop -eq $EnvSizeLooper)
            {
                Write-Host 'Processing Batch Jobs in Parallel' -ForegroundColor Cyan -NoNewline
                Write-Host '. Optimized for large environments' -ForegroundColor Cyan

                $InterJobNames = (Get-Job | Where-Object {$_.name -like 'ResourceJob_*' -and $_.State -eq 'Running'}).Name

                Wait-ARIJob -JobNames $InterJobNames -JobType 'Resource Batch' -LoopTime 5

                $JobNames = (Get-Job | Where-Object {$_.name -like 'ResourceJob_*'}).Name

                Build-ARICacheFiles -DefaultPath $DefaultPath -JobNames $JobNames

                $JobLoop = 0
            }
        $JobLoop ++

        }

        Remove-Variable -Name Resources -ErrorAction SilentlyContinue
        Clear-ARIMemory
}