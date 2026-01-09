# Verbose Output Improvements

## Overview

Enhanced verbose output has been added to provide better visibility into what ARI is doing during execution, especially useful for large environments with many subscriptions.

## What's New

### 1. Extraction Phase - Clear Progress Indicators

The extraction phase now shows exactly what type of data is being extracted:

```
Extracting: Resources
Extracting: Network Resources
Extracting: Support Tickets
Extracting: Backup Items
Extracting: Virtual Desktop Resources
Extracting: Subscriptions and Resource Groups
Extracting: Azure Advisor Recommendations
Extracting: Security Center Assessments
Extracting: Resource Retirements
```

**Benefits:**
- Know which extraction step is running
- Understand progress through extraction phases
- Identify slow extraction queries

### 2. API Inventory - Real-Time Subscription Progress

The API inventory phase now provides detailed progress across all subscriptions:

```
Running API Inventory in parallel across 188 subscriptions...
  - ResourceHealth Events
  - Managed Identities
  - Advisor Scores
  - Reservation Recommendations
  - Policy Assignments & Definitions

  [API Inventory] Processing: Production-Sub-001
  [API Inventory] Completed: Production-Sub-001 (1/188)
  [API Inventory] Processing: Dev-Sub-002
  [API Inventory] Processing: Test-Sub-003
  [API Inventory] Completed: Dev-Sub-002 (2/188)
  [API Inventory] Completed: Test-Sub-003 (3/188)
  ...
  [API Inventory] Completed: Final-Sub-188 (188/188)
```

**Benefits:**
- See which subscriptions are being processed
- Track completion progress (X/Total)
- Identify which subscriptions might be slow
- Know API is making progress (not stuck)

### 3. Job Creation - Visibility into Processing Jobs

Job creation phase now shows each resource type job as it's created:

```
Creating processing jobs for resource types...
  [Job Created] Compute
  [Job Created] Networking
  [Job Created] Storage
  [Job Created] Database
  [Job Created] Container
  [Job Created] Analytics
  [Job Created] Integration
  [Job Created] Security
  [Job Created] Monitoring
  ...
```

**Benefits:**
- Know how many jobs are being created
- See which resource types will be processed
- Understand job distribution across resource types

### 4. Job Processing - Active Job Display

During job processing, see which jobs are actively running:

```
Processing Resource Jobs...
  [Running Jobs] Compute, Storage, Database
  [Running Jobs] Compute, Database
  [Running Jobs] Compute
```

**Benefits:**
- Know which specific jobs are still running
- Identify potential bottlenecks
- Understand which resource types take longer
- Only shown when ≤10 jobs running (avoids clutter)

## Output Visibility

### Without -Debug Flag

All the improvements above are visible **without using the -Debug flag**. This provides a better default user experience:

```powershell
# Normal run - now shows progress
Invoke-ARI -TenantID <tenant-id>
```

### With -Debug Flag

The -Debug flag adds even more detailed information:

```powershell
# Debug run - shows everything + timestamps and technical details
Invoke-ARI -TenantID <tenant-id> -Debug
```

Debug output includes:
- Timestamps for every operation
- Azure Graph query details
- Subscription IDs being processed
- Job state information
- Memory usage warnings
- Detailed error messages

## Color Coding

The output uses consistent color coding for better readability:

| Color | Usage | Example |
|-------|-------|---------|
| **Cyan** | Action labels | "Extracting:", "[API Inventory]", "[Job Created]" |
| **Yellow** | Item names | Resource type names, subscription names, job names |
| **Green** | Completion | "Completed:", successful operations |
| **Gray** | Supplementary info | Progress counts, metadata |
| **Red** | Errors | Error messages, warnings |

## Before vs After

### Before (Limited Output)

```
Running API Inventory in parallel across 188 subscriptions...
Azure Inventory [4% Complete.]
```

**Issues:**
- No visibility into what's happening
- Can't tell if it's stuck or progressing
- Don't know which subscription is being processed
- Unclear what "4% Complete" refers to

### After (Enhanced Output)

```
Running API Inventory in parallel across 188 subscriptions...
  - ResourceHealth Events
  - Managed Identities
  - Advisor Scores
  - Reservation Recommendations
  - Policy Assignments & Definitions

  [API Inventory] Processing: Production-Sub-001
  [API Inventory] Completed: Production-Sub-001 (1/188)
  [API Inventory] Processing: Production-Sub-002
  [API Inventory] Completed: Production-Sub-002 (2/188)
  ...
Azure Inventory [4% Complete.]
```

**Benefits:**
- Clear list of what's being collected
- See each subscription as it's processed
- Know exact progress (2/188)
- Can identify slow subscriptions
- Confidence that progress is being made

## Usage Examples

### Standard Run

```powershell
# Regular run with enhanced output
Invoke-ARI -TenantID <tenant-id>
```

Output will show:
- Extraction progress
- API inventory with subscription names
- Job creation list
- Running jobs (when few enough)

### Debug Run

```powershell
# Debug run with maximum detail
Invoke-ARI -TenantID <tenant-id> -Debug
```

Output will show everything above plus:
- Timestamps
- Technical details
- Query information
- Detailed diagnostics

### Quiet Run

If you need minimal output (e.g., for automation), redirect the informational streams:

```powershell
# Suppress informational output
Invoke-ARI -TenantID <tenant-id> -InformationAction SilentlyContinue
```

## Performance Impact

The verbose output improvements have minimal performance impact:

- **Output operations**: Negligible (microseconds per message)
- **No additional API calls**: All output is from existing operations
- **No serialization overhead**: Simple string formatting
- **Concurrent-safe**: Uses thread-safe collections for progress tracking

**Estimated impact**: <0.1% of total runtime

## Troubleshooting with Enhanced Output

### Scenario 1: Stuck During API Inventory

**Before**: Would just see "Running API Inventory..." with no updates

**After**: You can see:
```
  [API Inventory] Processing: Problem-Subscription
```

If this stays for a long time, you know which subscription to investigate.

### Scenario 2: Long Job Processing

**Before**: Would see "Resource Jobs Still Running: 1" with no details

**After**: You can see:
```
  [Running Jobs] DatabaseComplexQuery
```

Now you know which specific resource type is taking long.

### Scenario 3: Slow Extraction

**Before**: Would wait at 4% with no indication of what's happening

**After**: You can see:
```
Extracting: Network Resources
```

Now you know network resources extraction is in progress and network data might be large.

## Future Enhancements

Potential improvements for future versions:

1. **Progress percentages per phase** - Show % complete for each extraction type
2. **Time estimates** - Show estimated time remaining based on current progress
3. **Resource counts** - Display how many resources extracted per type
4. **Parallel batch progress** - Show progress within parallel batches
5. **Export/Import progress** - Show progress during cache export/import

## Feedback

The verbose output improvements aim to make ARI more transparent and user-friendly. If you have suggestions for additional output that would be helpful, please open an issue on the [ARI GitHub repository](https://github.com/microsoft/ARI/issues).

## Version History

- **v3.7.0** (January 2026): Initial verbose output improvements
  - Extraction phase progress
  - API inventory subscription tracking
  - Job creation visibility
  - Running jobs display

## Authors

Implementation by: Aelonium (with Copilot assistance)
Based on user feedback and requirements
