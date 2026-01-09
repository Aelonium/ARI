<#
.Synopsis
Wait for ARI Jobs to Complete

.DESCRIPTION
This script waits for the completion of specified ARI jobs with timeout and diagnostics.

.Link
https://github.com/microsoft/ARI/Modules/Public/PublicFunctions/Jobs/Wait-ARIJob.ps1

.COMPONENT
    This powershell Module is part of Azure Resource Inventory (ARI)

.NOTES
Version: 3.7.0
First Release Date: 15th Oct, 2024
Updated: 8th Jan, 2026 - Added timeout and diagnostics
Authors: Claudio Merola

#>
function Wait-ARIJob {
    Param(
        $JobNames, 
        $JobType, 
        $LoopTime,
        [int]$TimeoutMinutes = 120  # Default 2 hour timeout per job
    )

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting Jobs Collector.')

    $c = 0
    $StuckJobWarningThreshold = 30  # Minutes before warning about stuck job
    $JobStateTracker = @{}
    
    # Initialize job state tracker
    foreach ($JobName in $JobNames) {
        $JobStateTracker[$JobName] = @{
            LastStateChange = Get-Date
            StuckWarningIssued = $false
            TimeoutWarningIssued = $false
        }
    }

    while (get-job -Name $JobNames -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Running' }) {
        $jb = get-job -Name $JobNames -ErrorAction SilentlyContinue
        $runningJobs = $jb | Where-Object { $_.State -eq 'Running' }
        $c = (((($jb.count - $runningJobs.Count)) / $jb.Count) * 100)
        
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"$JobType Jobs Still Running: "+[string]$runningJobs.count)
        
        # Show currently running jobs (verbose output)
        if ($runningJobs.Count -gt 0 -and $runningJobs.Count -le 10) {
            $runningJobNames = ($runningJobs | ForEach-Object { $_.Name -replace 'ResourceJob_','' }) -join ', '
            Write-Host "  [Running Jobs] " -NoNewline -ForegroundColor Cyan
            Write-Host $runningJobNames -ForegroundColor Yellow
        }
        
        # Check for stuck jobs
        foreach ($job in $runningJobs) {
            $jobName = $job.Name
            $timeSinceStart = (Get-Date) - $job.PSBeginTime
            $tracker = $JobStateTracker[$jobName]
            
            # Check if job has been running too long
            if ($timeSinceStart.TotalMinutes -gt $TimeoutMinutes -and !$tracker.TimeoutWarningIssued) {
                Write-Warning ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Job '$jobName' has been running for $([math]::Round($timeSinceStart.TotalMinutes)) minutes (timeout: $TimeoutMinutes minutes)")
                Write-Warning "Job State: $($job.State) | PSBeginTime: $($job.PSBeginTime)"
                Write-Warning "Consider investigating this job or increasing the timeout value."
                $tracker.TimeoutWarningIssued = $true
            }
            # Check if job appears stuck (running for more than warning threshold)
            elseif ($timeSinceStart.TotalMinutes -gt $StuckJobWarningThreshold -and !$tracker.StuckWarningIssued) {
                Write-Warning ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"Job '$jobName' has been running for $([math]::Round($timeSinceStart.TotalMinutes)) minutes")
                Write-Debug "Job details: State=$($job.State), HasMoreData=$($job.HasMoreData), PSBeginTime=$($job.PSBeginTime)"
                $tracker.StuckWarningIssued = $true
            }
        }
        
        $c = [math]::Round($c)
        Write-Progress -Id 1 -activity "Processing $JobType Jobs" -Status "$c% Complete. ($($runningJobs.Count) running)" -PercentComplete $c
        Start-Sleep -Seconds $LoopTime
    }
    
    Write-Progress -Id 1 -activity "Processing $JobType Jobs" -Status "100% Complete." -Completed

    # Check for failed jobs
    $failedJobs = get-job -Name $JobNames -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Failed' }
    if ($failedJobs) {
        Write-Warning ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"$($failedJobs.Count) $JobType job(s) failed:")
        foreach ($failedJob in $failedJobs) {
            Write-Warning "  - $($failedJob.Name): $($failedJob.State)"
            Write-Debug "Failed job details: $($failedJob | Format-List | Out-String)"
        }
    }

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Jobs Complete.')
}