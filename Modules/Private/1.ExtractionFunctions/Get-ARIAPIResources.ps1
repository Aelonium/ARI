<#
.Synopsis
Module responsible for retrieving Azure API resources with parallel processing.

.DESCRIPTION
This module retrieves Azure API resources, including Resource Health, Managed Identities, Advisor Scores, and Policies.
Now supports parallel subscription processing for improved performance.

.Link
https://github.com/microsoft/ARI/Modules/Private/1.ExtractionFunctions/Get-ARIAPIResources.ps1

.COMPONENT
This PowerShell Module is part of Azure Resource Inventory (ARI).

.NOTES
Version: 3.7.0
First Release Date: 15th Oct, 2024
Updated: Jan 2026 - Added parallel subscription processing
Authors: Claudio Merola
#>
function Get-ARIAPIResources {
    Param($Subscriptions, $AzureEnvironment, $SkipPolicy)

    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Starting API Inventory')

    try
        {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Acquiring Token')
            $Token = Get-AzAccessToken -AsSecureString -InformationAction SilentlyContinue -WarningAction SilentlyContinue -Debug:$false

            $TokenData = $Token.Token | ConvertFrom-SecureString -AsPlainText

            $header = @{
                'Authorization' = 'Bearer ' + $TokenData
            }
        }
    catch
        {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+'Error: ' + $_.Exception.Message)
            return
        }
    

    if ($AzureEnvironment -eq 'AzureCloud') {
        $AzURL = 'management.azure.com'
    } 
    elseif ($AzureEnvironment -eq 'AzureUSGovernment') {
        $AzURL = 'management.usgovcloudapi.net'
    }
    elseif ($AzureEnvironment -eq 'AzureChinaCloud') {
        $AzURL = 'management.chinacloudapi.cn'
    }
    else {
        Write-Host ('Invalid Azure Environment for API Rest Inventory: ' + $AzureEnvironment) -ForegroundColor Red
        return
    }
    $ResourceHealthHistoryDate = (Get-Date).AddMonths(-6)
    
    # Use thread-safe collection for parallel processing
    $APIResults = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

    Write-Host 'Running API Inventory in parallel across ' -NoNewline
    Write-Host $Subscriptions.Count -ForegroundColor Cyan -NoNewline
    Write-Host ' subscriptions...'

    # Process subscriptions in parallel with throttle limit
    $Subscriptions | ForEach-Object -ThrottleLimit 5 -Parallel {
        $Subscription = $_
        $AzURLLocal = $using:AzURL
        $headerLocal = $using:header
        $ResourceHealthHistoryDateLocal = $using:ResourceHealthHistoryDate
        $SkipPolicyLocal = $using:SkipPolicy
        $ResultsCollection = $using:APIResults
        
        $ResourceHealth = ""
        $Identities = ""
        $ADVScore = ""
        $ReservationRecon = ""
        $PolicyAssign = ""
        $PolicySetDef = ""
        $PolicyDef = ""

        $SubName = $Subscription.Name
        $Sub = $Subscription.id

        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"[Parallel] Processing API Inventory for: $SubName")

        #ResourceHealth Events
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"[Parallel] Getting ResourceHealth Events for: $SubName")
        $url = ('https://' + $AzURLLocal + '/subscriptions/' + $Sub + '/providers/Microsoft.ResourceHealth/events?api-version=2022-10-01&queryStartTime=' + $ResourceHealthHistoryDateLocal)
        try {
            $ResourceHealth = Invoke-RestMethod -Uri $url -Headers $headerLocal -Method GET
        }
        catch {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"[Parallel] Error: $($_.Exception.Message)")
            $ResourceHealth = ""
        }
        
        Start-Sleep -Milliseconds 100

        #Managed Identities
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"[Parallel] Getting Managed Identities for: $SubName")
        $url = ('https://' + $AzURLLocal + '/subscriptions/' + $Sub + '/providers/Microsoft.ManagedIdentity/userAssignedIdentities?api-version=2023-01-31')
        try {
            $Identities = Invoke-RestMethod -Uri $url -Headers $headerLocal -Method GET
        }
        catch {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"[Parallel] Error: $($_.Exception.Message)")
            $Identities = ""
        }
        Start-Sleep -Milliseconds 100

        #Advisor Score
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"[Parallel] Getting Advisor Score for: $SubName")
        $url = ('https://' + $AzURLLocal + '/subscriptions/' + $Sub + '/providers/Microsoft.Advisor/advisorScore?api-version=2023-01-01')
        try {
            $ADVScore = Invoke-RestMethod -Uri $url -Headers $headerLocal -Method GET
        }
        catch {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"[Parallel] Error: $($_.Exception.Message)")
            $ADVScore = ""
        }
        Start-Sleep -Milliseconds 100

        #VM Reservation Recommendation
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"[Parallel] Getting VM Reservation Recommendation for: $SubName")
        $url = ('https://' + $AzURLLocal + '/subscriptions/' + $Sub + '/providers/Microsoft.Consumption/reservationRecommendations?api-version=2023-05-01')
        try {
            $ReservationRecon = Invoke-RestMethod -Uri $url -Headers $headerLocal -Method GET
        }
        catch {
            Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"[Parallel] Error: $($_.Exception.Message)")
            $ReservationRecon = ""
        }
        Start-Sleep -Milliseconds 100

        if (!$SkipPolicyLocal.isPresent)
            {
                Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"[Parallel] Getting Policies for: $SubName")
                #Policies
                try {
                    $url = ('https://'+ $AzURLLocal +'/subscriptions/'+$sub+'/providers/Microsoft.PolicyInsights/policyStates/latest/summarize?api-version=2019-10-01')
                    $PolicyAssign = (Invoke-RestMethod -Uri $url -Headers $headerLocal -Method POST).value
                    Start-Sleep -Milliseconds 100
                    $url = ('https://'+ $AzURLLocal +'/subscriptions/'+$sub+'/providers/Microsoft.Authorization/policySetDefinitions?api-version=2023-04-01')
                    $PolicySetDef = (Invoke-RestMethod -Uri $url -Headers $headerLocal -Method GET).value
                    Start-Sleep -Milliseconds 100
                    $url = ('https://'+ $AzURLLocal +'/subscriptions/'+$sub+'/providers/Microsoft.Authorization/policyDefinitions?api-version=2023-04-01')
                    $PolicyDef = (Invoke-RestMethod -Uri $url -Headers $headerLocal -Method GET).value
                }
                catch {
                    Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"[Parallel] Error: $($_.Exception.Message)")
                    $PolicyAssign = ""
                    $PolicySetDef = ""
                    $PolicyDef = ""
                }
            }

        Start-Sleep -Milliseconds 100

        $tmp = @{
            'Subscription'          = $Sub;
            'ResourceHealth'        = $ResourceHealth.value;
            'ManagedIdentities'     = $Identities.value;
            'AdvisorScore'          = $ADVScore.value;
            'ReservationRecomen'    = $ReservationRecon.value;
            'PolicyAssign'          = $PolicyAssign;
            'PolicyDef'             = $PolicyDef;
            'PolicySetDef'          = $PolicySetDef
        }
        
        # Thread-safe add to collection
        $ResultsCollection.Add($tmp)
        
        Write-Debug ((get-date -Format 'yyyy-MM-dd_HH_mm_ss')+' - '+"[Parallel] Completed API Inventory for: $SubName")
    }
    
    Write-Host 'Completed parallel API Inventory across all subscriptions' -ForegroundColor Green

        <#
        $Body = @{
            reportType = "OverallSummaryReport"
            subscriptionList = @($Subscri)
            carbonScopeList = @("Scope1")
            dateRange = @{
                start = "2024-06-01"
                end = "2024-06-30"
            }
        }
        $url = 'https://management.azure.com/providers/Microsoft.Carbon/carbonEmissionReports?api-version=2023-04-01-preview'
        #$url = 'https://management.azure.com/providers/Microsoft.Carbon/queryCarbonEmissionDataAvailableDateRange?api-version=2023-04-01-preview'

        $Carbon = Invoke-RestMethod -Uri $url -Headers $header -Body ($Body | ConvertTo-Json) -Method POST -ContentType 'application/json'

        

        $Today = Get-Date
        $EndDate = Get-Date -Year $Today.Year -Month $Today.Month -Day $Today.Day -Hour 23 -Minute 59 -Second 59 -Millisecond 0
        $Days = 60
        $StartDate = ($EndDate).AddDays(-$Days)

        $Hash = @{name="PreTaxCost";function="Sum"}
        $MHash = @{totalCost=$Hash}
        $Granularity = 'Monthly'

        $Grouping = @()
        $GTemp = @{Name='ResourceType';Type='Dimension'}
        $Grouping += $GTemp
        $GTemp = @{Name='ResourceGroup';Type='Dimension'}
        $Grouping += $GTemp

        $Body = @{
                type = "ActualCost"
                timeframe = "Custom"
                dataset = @{
                    granularity = $Granularity
                    aggregation = @($MHash)
                    }
                grouping = $Grouping
                timePeriod = @{
                    startDate = $StartDate
                    endDate = $EndDate
                }
        }

        $url = 'https://management.azure.com/subscriptions/$sub/providers/Microsoft.CostManagement/query?api-version=2019-11-01'

        $Cost = Invoke-RestMethod -Uri $url -Headers $header -Body ($Body | ConvertTo-Json -Depth 10) -Method POST -ContentType 'application/json'

        #>

        # Convert ConcurrentBag to array for return
        return $APIResults.ToArray()
}