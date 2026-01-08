<#
.Synopsis
Module responsible for starting automated processing jobs for Azure Resources with parallel execution.

.DESCRIPTION
This module creates and manages automated thread jobs to process Azure Resources using PowerShell script blocks 
for efficient parallel execution. Optimized for automation scenarios.

.Link
https://github.com/microsoft/ARI/Modules/Private/2.ProcessingFunctions/Start-ARIAutProcessJob.ps1

.COMPONENT
This PowerShell Module is part of Azure Resource Inventory (ARI).

.NOTES
Version: 3.7.0
First Release Date: 15th Oct, 2024
Updated: Jan 2026 - Improved parallel processing
Authors: Claudio Merola
#>

function Start-ARIAutProcessJob {
    Param($Resources, $Retirements, $Subscriptions, $Heavy, $InTag, $Unsupported)

    $ParentPath = (get-item $PSScriptRoot).parent.parent
    $InventoryModulesPath = Join-Path $ParentPath 'Public' 'InventoryModules'
    $Modules = Get-ChildItem -Path $InventoryModulesPath -Directory
    $NewResources = ($Resources | ConvertTo-Json -Depth 40 -Compress)
    $JobLoop = 1
    Write-Output ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Starting ARI Automation Processing Jobs...")

    if ($Heavy.IsPresent -or $InTag.IsPresent)
        {
            Write-Output ('Heavy Mode Detected. Jobs will be run in optimized batches.')
            $EnvSizeLooper = 4  # Improved from 2
        }
    else
        {
            $EnvSizeLooper = 8  # Improved from 4
        }

    Foreach ($ModuleFolder in $Modules)
        {
            $ModulePath = Join-Path $ModuleFolder.FullName '*.ps1'
            $ModuleName = $ModuleFolder.Name
            $ModuleFiles = Get-ChildItem -Path $ModulePath
            Write-Output ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Starting Job: $ModuleName")

            Start-ThreadJob -Name ('ResourceJob_'+$ModuleName) -ScriptBlock {

                $ModuleFiles = $($args[0])
                $Subscriptions = $($args[2])
                $InTag = $($args[3])
                $Resources = $($args[4]) | ConvertFrom-Json
                $Retirements = $($args[5])
                $Unsupported = $($args[10])
                
                # Use thread-safe hashtable for parallel module processing
                $SmaResources = [System.Collections.Concurrent.ConcurrentDictionary[string, object]]::new()

                # Process modules in parallel using ForEach-Object -Parallel
                $ModuleFiles | ForEach-Object -ThrottleLimit 5 -Parallel {
                    $Module = $_
                    $PSScriptRootLocal = $using:PSScriptRoot
                    $SubscriptionsLocal = $using:Subscriptions
                    $InTagLocal = $using:InTag
                    $ResourcesLocal = $using:Resources
                    $RetirementsLocal = $using:Retirements
                    $UnsupportedLocal = $using:Unsupported
                    $ResultHash = $using:SmaResources
                    
                    $ModuleFileContent = New-Object System.IO.StreamReader($Module.FullName)
                    $ModuleData = $ModuleFileContent.ReadToEnd()
                    $ModuleFileContent.Dispose()
                    $ModName = $Module.Name.replace(".ps1","")

                    $ScriptBlock = [Scriptblock]::Create($ModuleData)
                    $Result = Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $PSScriptRootLocal, $SubscriptionsLocal, $InTagLocal, $ResourcesLocal, $RetirementsLocal, 'Processing', $null, $null, $null, $UnsupportedLocal

                    # Add result to thread-safe hashtable
                    $ResultHash.TryAdd($ModName, $Result) | Out-Null
                }

                # Convert ConcurrentDictionary to regular Hashtable for compatibility
                $OutputHashtable = New-Object System.Collections.Hashtable
                foreach ($key in $SmaResources.Keys) {
                    $OutputHashtable[$key] = $SmaResources[$key]
                }
                
                $OutputHashtable

            } -ArgumentList $ModuleFiles, $PSScriptRoot, $Subscriptions, $InTag, $NewResources, $Retirements, 'Processing', $null, $null, $null, $Unsupported | Out-Null

            if($JobLoop -eq $EnvSizeLooper)
                {
                    Write-Output ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Processing Batch Jobs in Parallel')

                    Get-Job | Where-Object {$_.name -like 'ResourceJob_*'} | Wait-Job

                    $JobNames = (Get-Job | Where-Object {$_.name -like 'ResourceJob_*'}).Name

                    Start-Sleep -Seconds 5

                    Build-ARICacheFiles -DefaultPath $DefaultPath -JobNames $JobNames

                    $JobLoop = 0
                }
        $JobLoop ++
        }
}