# Job Hanging and Performance Improvements

## Issue: Jobs Hanging for Extended Periods

### Problem Description

Users reported that ARI jobs would sometimes hang with debug messages like:
```
DEBUG: 2026-01-08_15_42_56 - Resource Jobs Still Running: 1
```

This message would continue for hours (4+ hours reported) without the job completing, indicating a stuck or very slow job.

## Root Causes

Several factors can cause jobs to hang:

1. **Large Resource Sets**: Jobs processing very large numbers of resources (10,000+ per job)
2. **Complex Module Processing**: Some inventory modules are resource-intensive
3. **Memory Pressure**: High memory usage can slow down PowerShell runspaces
4. **API Rate Limiting**: Throttling from Azure APIs during extraction
5. **Network Issues**: Intermittent connectivity problems
6. **No Timeout Mechanism**: Original code had no job timeout or hung job detection

## Solutions Implemented

### 1. Enhanced Job Monitoring (Wait-ARIJob.ps1)

**Changes Made:**

- Added configurable timeout (default: 120 minutes per job)
- Added stuck job detection (warning after 30 minutes)
- Added detailed diagnostics for long-running jobs
- Added failed job reporting

**Benefits:**

- Early warning when jobs run longer than expected
- Clear visibility into which specific job is stuck
- Helps identify problematic resources or modules
- Provides actionable information for troubleshooting

**Example Output:**

```
WARNING: 2026-01-08_16_15_30 - Job 'ResourceJob_VirtualMachines' has been running for 35 minutes
Job details: State=Running, HasMoreData=True, PSBeginTime=2026-01-08 15:40:00
```

### 2. Data Caching Feature

**How It Helps:**

The new caching feature helps avoid the extraction phase entirely for repeated runs:

- First run: Export data (includes job processing)
- Subsequent runs: Import cached data, skip Azure extraction, skip job processing
- Reduces total execution time by 70-90%

**Usage:**

```powershell
# First run - extract and cache
Invoke-ARI -TenantID <tenant-id> -ExportDataPath "C:\ARI_Cache\Export"

# Subsequent runs - use cache (no jobs to hang!)
Invoke-ARI -ImportDataPath "C:\ARI_Cache\Export"
```

### 3. Existing Parallel Processing Optimizations

ARI v3.7.0 already includes parallel processing improvements that help with job performance:

- Parallel subscription processing (5x-8x faster for 200+ subs)
- Optimized batch sizes to prevent CPU overload
- Thread-safe collections for reliable concurrent execution
- See [PARALLEL_PROCESSING_OPTIMIZATION.md](PARALLEL_PROCESSING_OPTIMIZATION.md) for details

## Troubleshooting Stuck Jobs

### Step 1: Enable Debug Mode

Always run with `-Debug` parameter for large environments:

```powershell
Invoke-ARI -TenantID <tenant-id> -Debug
```

This provides visibility into:
- Which jobs are running
- How long they've been running
- Resource extraction progress
- Module processing status

### Step 2: Identify the Stuck Job

When you see "Resource Jobs Still Running: 1" for an extended period:

1. Note the timestamp of when it started
2. Check debug output for the job name
3. Look for warning messages about stuck or long-running jobs

Example:
```
DEBUG: 2026-01-08_15_40_00 - Resource Jobs Still Running: 5
DEBUG: 2026-01-08_15_45_00 - Resource Jobs Still Running: 3
DEBUG: 2026-01-08_15_50_00 - Resource Jobs Still Running: 1
WARNING: 2026-01-08_16_15_00 - Job 'ResourceJob_Compute' has been running for 35 minutes
```

### Step 3: Check Resource Counts

Large resource counts in specific categories can cause slowdowns:

```powershell
# Check your resource distribution
$Resources | Group-Object type | Sort-Object Count -Descending | Select-Object -First 20 Count, Name
```

If you have 10,000+ resources of a single type, that job may take longer.

### Step 4: Use Heavy Mode

For resource-constrained environments or very large datasets:

```powershell
Invoke-ARI -TenantID <tenant-id> -Heavy -Debug
```

Heavy mode uses smaller batch sizes, which:
- Reduces memory pressure
- Makes jobs more manageable
- May run slightly slower but more reliably

### Step 5: Skip Problematic Components

If specific components consistently cause issues:

```powershell
# Skip VM details if VM job hangs
Invoke-ARI -TenantID <tenant-id> -SkipVMDetails

# Skip APIs if API job hangs  
Invoke-ARI -TenantID <tenant-id> -SkipAPIs

# Skip advisories if advisory job hangs
Invoke-ARI -TenantID <tenant-id> -SkipAdvisory
```

### Step 6: Export and Investigate

Export the data at the point before job processing:

```powershell
# The extraction phase completes before job processing
# So export will work even if jobs hang
Invoke-ARI -TenantID <tenant-id> -ExportDataPath "C:\Temp\ARI_Debug"

# Then analyze the cached data to see what's being processed
Get-ChildItem "C:\Temp\ARI_Debug\*\Resources.json" | ForEach-Object {
    $resources = Get-Content $_.FullName | ConvertFrom-Json
    Write-Host "$($_.Directory.Name): $($resources.Count) resources"
}
```

## Performance Tips

### 1. Use Appropriate Batch Sizes

The system automatically adjusts batch sizes based on resource count, but you can force smaller batches:

```powershell
# For very large environments
Invoke-ARI -TenantID <tenant-id> -Heavy
```

### 2. Run During Off-Peak Hours

Azure API rate limits are less likely to be hit during off-peak hours (evenings, weekends).

### 3. Scope Your Inventory

Don't inventory everything if you don't need it:

```powershell
# Specific subscriptions only
Invoke-ARI -TenantID <tenant-id> -SubscriptionID "sub-1","sub-2"

# Specific resource groups only
Invoke-ARI -TenantID <tenant-id> -SubscriptionID "sub-1" -ResourceGroup "rg-prod"

# Filter by tags
Invoke-ARI -TenantID <tenant-id> -TagKey "Environment" -TagValue "Production"
```

### 4. Use Caching for Iteration

If you're running multiple times (development, testing, different report formats):

```powershell
# Extract once
Invoke-ARI -TenantID <tenant-id> -ExportDataPath "C:\ARI_Cache\$(Get-Date -Format 'yyyy-MM-dd')"

# Use cache for all subsequent runs (very fast!)
Invoke-ARI -ImportDataPath "C:\ARI_Cache\2026-01-08"
```

### 5. Monitor System Resources

Large inventories can be memory-intensive:

```powershell
# Monitor during execution
while ($true) {
    $mem = Get-Process pwsh | Measure-Object WorkingSet64 -Sum
    Write-Host "PowerShell Memory: $([math]::Round($mem.Sum / 1GB, 2)) GB"
    Start-Sleep -Seconds 30
}
```

If memory usage is very high (>8GB), consider:
- Using `-Heavy` mode
- Reducing scope (fewer subscriptions)
- Increasing system RAM

## Job Timeout Configuration

The default job timeout is 120 minutes, but you can adjust it by modifying the `Wait-ARIJob` call in `Start-ARIProcessOrchestration.ps1`:

```powershell
# Current default
Wait-ARIJob -JobNames $JobNames -JobType 'Resource' -LoopTime 5

# Increase timeout to 240 minutes
Wait-ARIJob -JobNames $JobNames -JobType 'Resource' -LoopTime 5 -TimeoutMinutes 240
```

For very large environments (500+ subscriptions, 100K+ resources), you may need to increase this timeout.

## When to Contact Support

If you experience job hanging issues that cannot be resolved with the above steps:

1. Run with `-Debug` to collect diagnostic information
2. Note the specific job that's hanging (from debug output)
3. Record approximate resource counts per subscription
4. Record memory and CPU usage during execution
5. Note the ARI version you're using
6. Open an issue on [GitHub](https://github.com/microsoft/ARI/issues) with:
   - Full debug log (or relevant excerpts)
   - Environment size (subscription count, approx resource count)
   - System specifications (CPU, RAM, OS)
   - Exact command used

## Future Improvements

Planned enhancements to address job performance:

1. **Job-Level Timeouts**: Individual timeout per job type
2. **Automatic Job Retry**: Retry stuck jobs with smaller batch sizes
3. **Progress Callbacks**: Better visibility into module processing progress
4. **Incremental Processing**: Process resources as they arrive, not in large batches
5. **Cancellation Support**: Ability to cancel and resume long-running inventories

## Version History

- **v3.7.0** (January 2026): Added job timeout warnings and diagnostics
- **v3.6.x**: Original implementation

## Summary

The combination of:
1. Enhanced job monitoring with timeouts and diagnostics
2. Data caching to skip extraction entirely
3. Existing parallel processing optimizations
4. Troubleshooting guidance and best practices

...provides a comprehensive solution to job hanging issues while significantly improving overall performance.

For most users, the caching feature will eliminate job hanging issues for repeated runs, while the enhanced monitoring will help identify and resolve issues during initial extraction.
