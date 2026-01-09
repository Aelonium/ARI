# Storage Job Performance Optimization

## Issue

The Storage inventory job can get stuck or run for hours when processing environments with many storage accounts. This happens because the StorageAccounts.ps1 module makes synchronous Azure API calls for each storage account to retrieve soft delete properties.

## Root Cause

Lines 133-134 in StorageAccounts.ps1 make Azure Management API calls **inside a foreach loop**:

```powershell
foreach ($1 in $storageacc) {
    # ... other processing ...
    $blobProperties = Get-AzStorageBlobServiceProperty -ResourceGroupName $1.RESOURCEGROUP -Name $1.NAME
    $fileProperties = Get-AzStorageFileServiceProperty -ResourceGroupName $1.RESOURCEGROUP -Name $1.NAME
    # ... more processing ...
}
```

**Performance Impact:**
- Each API call takes 1-3 seconds on average
- With 100 storage accounts: 200-600 seconds (3-10 minutes)
- With 500 storage accounts: 1000-3000 seconds (16-50 minutes)
- With 1000+ storage accounts: Can run for hours

These API calls retrieve:
- Blob soft delete retention days
- Container soft delete retention days
- File share soft delete retention days

## Changes Made

### 1. Added Error Handling

```powershell
try {
    $blobProperties = Get-AzStorageBlobServiceProperty -ResourceGroupName $1.RESOURCEGROUP -Name $1.NAME -ErrorAction Stop
} catch {
    Write-Debug "Failed to get blob properties for $($1.NAME): $($_.Exception.Message)"
    $blobProperties = $null
}
```

**Benefits:**
- Failed API calls don't break the entire job
- Individual storage account errors are logged but don't stop processing
- Job continues even if some storage accounts are inaccessible

### 2. Added Null Checks

```powershell
'Blob Soft Delete Days' = if ($blobProperties -and $blobProperties.DeleteRetentionPolicy.Enabled) { 
    $blobProperties.DeleteRetentionPolicy.Days 
} else { 
    'N/A' 
}
```

**Benefits:**
- Handles cases where API calls fail or return null
- Shows 'N/A' instead of errors for unavailable data
- More resilient to network or permission issues

### 3. Added Progress Tracking

```powershell
Write-Debug "Processing $($storageacc.Count) storage accounts. This may take time due to API calls for soft delete properties."

$storageCount++
if ($storageCount % 10 -eq 0 -or $storageCount -eq 1) {
    Write-Debug "Processing storage account $storageCount of $totalStorage : $($1.NAME)"
}
```

**Benefits:**
- Shows progress every 10 storage accounts
- Helps identify if job is stuck or just slow
- Provides visibility in debug mode

## Performance Expectations

With the changes, the job is still sequential but more resilient:

| Storage Accounts | Estimated Time | Notes |
|-----------------|----------------|-------|
| 1-50 | 1-5 minutes | Should be acceptable |
| 51-200 | 5-20 minutes | May feel slow but will complete |
| 201-500 | 20-50 minutes | Long but with progress tracking |
| 500+ | 50+ minutes | Consider optimizations below |

## Troubleshooting

### Job Still Seems Stuck

If running with `-Debug`, you should see:
```
DEBUG: Processing storage account 1 of 250 : mystorageaccount001
DEBUG: Processing storage account 10 of 250 : mystorageaccount010
DEBUG: Processing storage account 20 of 250 : mystorageaccount020
...
```

If you don't see progress updates:
1. Check if there's a network issue
2. Check if storage accounts are in an error state
3. Consider the optimizations below

### Errors for Specific Storage Accounts

You may see debug messages like:
```
DEBUG: Failed to get blob properties for storageaccount123: Forbidden
```

This is normal for storage accounts where you don't have sufficient permissions. The job will continue and show 'N/A' for those properties.

## Further Optimizations

If you have a large number of storage accounts and need faster processing, consider these approaches:

### Option 1: Skip Soft Delete Properties (Fastest)

Modify the module to skip the API calls entirely and always show 'N/A':

```powershell
# Comment out or remove these lines:
# $blobProperties = Get-AzStorageBlobServiceProperty ...
# $fileProperties = Get-AzStorageFileServiceProperty ...

# Set to null:
$blobProperties = $null
$fileProperties = $null
```

**Impact:**
- Near-instant processing of storage accounts
- Soft delete days will show as 'N/A' in reports
- Other storage account data still captured

### Option 2: Batch API Calls (Advanced)

Implement parallel API calls using `ForEach-Object -Parallel`:

```powershell
$allProperties = $storageacc | ForEach-Object -Parallel {
    $storageAccount = $_
    try {
        @{
            Name = $storageAccount.NAME
            ResourceGroup = $storageAccount.RESOURCEGROUP
            BlobProperties = Get-AzStorageBlobServiceProperty -ResourceGroupName $storageAccount.RESOURCEGROUP -Name $storageAccount.NAME
            FileProperties = Get-AzStorageFileServiceProperty -ResourceGroupName $storageAccount.RESOURCEGROUP -Name $storageAccount.NAME
        }
    } catch {
        @{
            Name = $storageAccount.NAME
            ResourceGroup = $storageAccount.RESOURCEGROUP
            BlobProperties = $null
            FileProperties = $null
        }
    }
} -ThrottleLimit 5
```

**Impact:**
- 5x faster with ThrottleLimit 5
- More complex implementation
- Requires significant code refactoring

### Option 3: Use Azure Resource Graph (Best Long-term)

Azure Resource Graph doesn't currently expose soft delete properties, but if it does in the future, replace the API calls with Resource Graph queries.

### Option 4: Cache Storage Properties

Export storage properties separately and import them:

```powershell
# First run - cache properties
$storageProperties = @{}
foreach ($sa in $storageacc) {
    $storageProperties[$sa.id] = @{
        Blob = Get-AzStorageBlobServiceProperty -ResourceGroupName $sa.RESOURCEGROUP -Name $sa.NAME
        File = Get-AzStorageFileServiceProperty -ResourceGroupName $sa.RESOURCEGROUP -Name $sa.NAME
    }
}
$storageProperties | Export-Clixml -Path "StorageProperties.xml"

# Subsequent runs - import properties
$storageProperties = Import-Clixml -Path "StorageProperties.xml"
```

## Monitoring Job Progress

When running with `-Debug`:

```powershell
Invoke-ARI -TenantID <id> -Debug
```

Watch for:
```
DEBUG: Processing 250 storage accounts. This may take time due to API calls for soft delete properties.
DEBUG: Processing storage account 1 of 250 : storageaccount001
...
DEBUG: Processing storage account 10 of 250 : storageaccount010
...
```

This confirms the job is making progress, even if slowly.

## Recommended Actions

### For Small Environments (<100 storage accounts)
- No action needed, current implementation is fine

### For Medium Environments (100-500 storage accounts)
- Monitor progress with `-Debug` flag
- Be patient - job will complete in 20-50 minutes
- Consider running during off-hours

### For Large Environments (500+ storage accounts)
- Consider Option 1 (Skip Soft Delete) if that data isn't critical
- Implement Option 2 (Parallel API Calls) for best results
- Split inventory by subscription or resource group
- Use data caching feature to avoid re-running extraction

## Using Data Caching

You can use the data caching feature to avoid re-running the slow storage extraction:

```powershell
# First run - export (slow, includes storage API calls)
Invoke-ARI -TenantID <id> -ExportDataPath "C:\ARI_Cache\Export"

# Subsequent runs - import (fast, no API calls)
Invoke-ARI -ImportDataPath "C:\ARI_Cache\Export"
```

This way, you only pay the performance cost once.

## Version History

- **v3.7.0** (January 2026): Added error handling and progress tracking for storage accounts

## Related Documentation

- [JOB_PERFORMANCE.md](JOB_PERFORMANCE.md) - General job troubleshooting
- [DATA_CACHING.md](DATA_CACHING.md) - Using cache to speed up reruns
- [VERBOSE_OUTPUT.md](VERBOSE_OUTPUT.md) - Understanding progress output
