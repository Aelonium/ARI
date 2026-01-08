# Data Caching Feature

## Overview

The Data Caching feature allows you to export extracted Azure data to disk and reuse it in subsequent runs, dramatically reducing execution time by skipping Azure API calls.

## Use Cases

1. **Development and Testing**: Export data once and iterate on report generation without hitting Azure APIs
2. **Multiple Report Formats**: Generate different report variations from the same dataset
3. **Offline Analysis**: Work with Azure data without an active Azure connection
4. **Incremental Updates**: Update only specific subscriptions while reusing cached data for others
5. **Performance**: Skip lengthy data extraction when you only need to regenerate reports

## How It Works

### Export Flow

1. Run ARI with `-ExportDataPath` parameter
2. ARI extracts all data from Azure as normal
3. Data is saved to disk organized by subscription:
   ```
   ExportPath/
   ├── ARI_Export_Metadata.json
   ├── Subscription1/
   │   ├── SubscriptionInfo.json
   │   ├── Resources.json
   │   ├── ResourceContainers.json
   │   ├── Advisories.json
   │   ├── Security.json
   │   └── Retirements.json
   ├── Subscription2/
   │   └── ...
   ```
4. Report generation continues as normal

### Import Flow

1. Run ARI with `-ImportDataPath` parameter
2. ARI loads all data from cached files
3. Skips all Azure API calls (Graph queries, REST APIs, VM details)
4. Proceeds directly to report generation
5. Execution time is reduced by 70-90% depending on environment size

## Usage Examples

### Basic Export

```powershell
# Export data during regular run
Invoke-ARI -TenantID <tenant-id> -ExportDataPath "C:\ARI_Cache\Export_$(Get-Date -Format 'yyyy-MM-dd')"
```

### Basic Import

```powershell
# Import from previously exported data
Invoke-ARI -ImportDataPath "C:\ARI_Cache\Export_2026-01-08"
```

### Export with Specific Scope

```powershell
# Export only specific subscriptions
Invoke-ARI -TenantID <tenant-id> -SubscriptionID "sub-id-1","sub-id-2" -ExportDataPath "C:\ARI_Cache\TwoSubs"

# Export with tags included
Invoke-ARI -TenantID <tenant-id> -IncludeTags -ExportDataPath "C:\ARI_Cache\WithTags"

# Export with security center data
Invoke-ARI -TenantID <tenant-id> -SecurityCenter -ExportDataPath "C:\ARI_Cache\WithSecurity"
```

### Workflow: Extract Once, Generate Multiple Reports

```powershell
# Step 1: Extract and export data (slow - queries Azure)
Invoke-ARI -TenantID <tenant-id> -IncludeTags -SecurityCenter -ExportDataPath "C:\ARI_Cache\Full_2026-01-08"

# Step 2: Generate standard report (fast - uses cache)
Invoke-ARI -ImportDataPath "C:\ARI_Cache\Full_2026-01-08" -ReportName "StandardReport"

# Step 3: Generate lite report (fast - uses cache)
Invoke-ARI -ImportDataPath "C:\ARI_Cache\Full_2026-01-08" -ReportName "LiteReport" -Lite

# Step 4: Generate report without diagrams (fast - uses cache)
Invoke-ARI -ImportDataPath "C:\ARI_Cache\Full_2026-01-08" -ReportName "NoDiagram" -SkipDiagram
```

## Performance Comparison

| Environment Size | Normal Extraction | With Import | Time Saved |
|-----------------|-------------------|-------------|------------|
| Small (1-10 subs, <5K resources) | 5-10 minutes | 1-2 minutes | 70-80% |
| Medium (10-50 subs, 5-25K resources) | 15-30 minutes | 3-5 minutes | 75-85% |
| Large (50-200 subs, 25-100K resources) | 30-60 minutes | 5-10 minutes | 80-85% |
| Extra Large (200+ subs, 100K+ resources) | 60-180 minutes | 10-20 minutes | 85-90% |

## Data Included in Cache

The following data is exported per subscription:

1. **Resources**: All Azure resources from Resource Graph
2. **Resource Containers**: Subscriptions and Resource Groups
3. **Advisories**: Azure Advisor recommendations (if not skipped)
4. **Security**: Security Center assessments (if enabled)
5. **Retirements**: Resource retirement notices
6. **Subscription Info**: Basic subscription metadata

## Data NOT Included in Cache

When importing from cache, the following are skipped:

- API-based resources (ResourceHealth, ManagedIdentities, AdvisorScore, Reservation recommendations)
- Azure Policy data (unless it was in the original export)
- VM Quota and SKU details (unless it was in the original export)
- Cost data (unless it was in the original export)

> **Note**: If you need these in your cached data, include them in the original export (don't use `-SkipAPIs`, `-SkipPolicy`, `-SkipVMDetails`).

## Cache Metadata

Each export includes a metadata file (`ARI_Export_Metadata.json`) with:

```json
{
  "ExportDate": "2026-01-08_15_45_30",
  "SubscriptionCount": 25,
  "ResourceCount": 12543,
  "AdvisoryCount": 142,
  "SecurityCount": 89,
  "RetirementCount": 5,
  "ResourceContainerCount": 156,
  "ARIVersion": "3.7.0"
}
```

This helps you identify what's in the cache and when it was created.

## Best Practices

### 1. Naming Convention

Use descriptive names with dates for easy identification:

```powershell
$ExportName = "ARI_Cache_Production_$(Get-Date -Format 'yyyy-MM-dd')"
Invoke-ARI -TenantID <tenant-id> -ExportDataPath "C:\ARI_Exports\$ExportName"
```

### 2. Regular Updates

Cache data becomes stale over time. Update your cache regularly:

```powershell
# Weekly export (e.g., via scheduled task)
$WeekNumber = Get-Date -UFormat %V
$ExportPath = "C:\ARI_Cache\Week_$WeekNumber"
Invoke-ARI -TenantID <tenant-id> -IncludeTags -SecurityCenter -ExportDataPath $ExportPath
```

### 3. Cleanup Old Exports

```powershell
# Remove exports older than 30 days
Get-ChildItem "C:\ARI_Cache" -Directory | 
    Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-30) } | 
    Remove-Item -Recurse -Force
```

### 4. Verify Export Before Relying On It

```powershell
# Export and verify
Invoke-ARI -TenantID <tenant-id> -ExportDataPath "C:\ARI_Cache\Verify" -Debug

# Check metadata
Get-Content "C:\ARI_Cache\Verify\ARI_Export_Metadata.json" | ConvertFrom-Json

# Test import
Invoke-ARI -ImportDataPath "C:\ARI_Cache\Verify" -Debug
```

### 5. Storage Requirements

Plan for storage space based on your environment:

| Environment Size | Approximate Cache Size |
|-----------------|------------------------|
| Small (1-10 subs) | 10-50 MB |
| Medium (10-50 subs) | 50-200 MB |
| Large (50-200 subs) | 200-800 MB |
| Extra Large (200+ subs) | 800 MB - 3 GB |

## Troubleshooting

### Issue: Import fails with "Import path does not exist"

**Solution**: Verify the path is correct and accessible:
```powershell
Test-Path "C:\ARI_Cache\Export_2026-01-08"
```

### Issue: Import succeeds but shows zero resources

**Solution**: Check if the export completed successfully. Look for subscription directories:
```powershell
Get-ChildItem "C:\ARI_Cache\Export_2026-01-08" -Directory
```

### Issue: Import is slower than expected

**Solution**: Ensure you're on fast storage (SSD). Large JSON files can be slow to parse from HDD. Also check that Windows Defender or antivirus isn't scanning the files.

### Issue: Export fails with disk space error

**Solution**: Check available disk space:
```powershell
Get-PSDrive C | Select-Object Used, Free
```

### Issue: Cached data is outdated

**Solution**: Re-export with fresh data:
```powershell
# Delete old cache
Remove-Item "C:\ARI_Cache\Export_2026-01-08" -Recurse -Force

# Create new export
Invoke-ARI -TenantID <tenant-id> -ExportDataPath "C:\ARI_Cache\Export_$(Get-Date -Format 'yyyy-MM-dd')"
```

## Integration with CI/CD

### Azure DevOps Pipeline Example

```yaml
# Export stage (runs weekly)
- stage: ExportData
  jobs:
  - job: Export
    steps:
    - task: PowerShell@2
      inputs:
        targetType: 'inline'
        script: |
          Import-Module AzureResourceInventory
          Connect-AzAccount -Identity
          Invoke-ARI -ExportDataPath "$(Pipeline.Workspace)/ARI_Cache"
    - publish: $(Pipeline.Workspace)/ARI_Cache
      artifact: ARICache

# Report generation stage (runs daily)
- stage: GenerateReports
  jobs:
  - job: Generate
    steps:
    - download: current
      artifact: ARICache
    - task: PowerShell@2
      inputs:
        targetType: 'inline'
        script: |
          Import-Module AzureResourceInventory
          Invoke-ARI -ImportDataPath "$(Pipeline.Workspace)/ARICache"
```

## Security Considerations

1. **Sensitive Data**: Cache files contain your Azure infrastructure details. Store them securely.
2. **Access Control**: Restrict access to cache directories using NTFS permissions.
3. **Encryption**: Consider encrypting cache directories if they contain sensitive information.
4. **Transmission**: If sharing cache files, use secure methods (encrypted archives, secure file transfer).

## Limitations

1. **No Delta Updates**: You cannot update individual subscriptions in a cache; you must re-export entirely.
2. **Version Compatibility**: Cache format may change between ARI versions. Use cache with the same version that created it.
3. **No Validation**: ARI doesn't validate that cached data matches your current Azure state.
4. **Size**: Very large environments (1000+ subscriptions) may produce multi-GB caches that are slow to import.

## Future Enhancements

Potential improvements being considered:

1. Delta updates (update only changed subscriptions)
2. Compressed cache format for reduced storage
3. Cache versioning and migration tools
4. Parallel import for faster loading
5. Cache expiration warnings

## Version History

- **v3.7.0** (January 2026): Initial data caching implementation

## Feedback

If you encounter issues or have suggestions for the caching feature, please open an issue on the [ARI GitHub repository](https://github.com/microsoft/ARI/issues).
