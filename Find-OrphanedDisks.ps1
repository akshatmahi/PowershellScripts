# Interactive browser login
Connect-AzAccount

# Import required modules
Import-Module Az.Accounts, Az.Compute, Az.CostManagement -ErrorAction Stop

# Ensure ImportExcel is installed
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Write-Host "Installing ImportExcel module..." -ForegroundColor Yellow
    Install-Module -Name ImportExcel -Scope CurrentUser -Force
}
Import-Module ImportExcel -ErrorAction Stop

# Define date ranges
$endDate = Get-Date
$thirtyDaysAgo = $endDate.AddDays(-30)

# Function to get disk costs aggregated by ResourceId
function Get-DiskCosts {
    param (
        [string]$SubscriptionId,
        [datetime]$FromDate,
        [datetime]$ToDate
    )

    $queryParams = @{
        Type      = "ActualCost"
        Timeframe = "Custom"
        TimePeriod = @{
            From = $FromDate.ToString("yyyy-MM-dd")
            To   = $ToDate.ToString("yyyy-MM-dd")
        }
        Dataset = @{
            Granularity = "None"
            Aggregation = @{
                TotalCost = @{
                    Name     = "Cost"
                    Function = "Sum"
                }
            }
            Grouping = @(
                @{
                    Type = "Dimension"
                    Name = "ResourceId"
                }
            )
            Filter = @{
                And = @(
                    @{
                        Dimensions = @{
                            Name     = "ResourceType"
                            Operator = "In"
                            Values   = @("Microsoft.Compute/disks")
                        }
                    }
                )
            }
        }
    }

    try {
        $result = Get-AzCostManagementQuery -Scope "/subscriptions/$SubscriptionId" `
                    -Query ($queryParams | ConvertTo-Json -Depth 10)
        
        $costData = @{}
        foreach ($row in $result.Properties.Rows) {
            $costData[$row[1]] = [decimal]$row[0]  # ResourceId:Cost
        }
        return $costData
    }
    catch {
        Write-Warning "Failed to retrieve costs for subscription $SubscriptionId ($($_.Exception.Message))"
        return @{}
    }
}

# Function to get cost for individual resource (for custom date ranges)
function Get-ResourceCost {
    param (
        [string]$SubscriptionId,
        [string]$ResourceId,
        [datetime]$FromDate,
        [datetime]$ToDate
    )

    $queryParams = @{
        Type      = "ActualCost"
        Timeframe = "Custom"
        TimePeriod = @{
            From = $FromDate.ToString("yyyy-MM-dd")
            To   = $ToDate.ToString("yyyy-MM-dd")
        }
        Dataset = @{
            Granularity = "None"
            Aggregation = @{
                TotalCost = @{
                    Name     = "Cost"
                    Function = "Sum"
                }
            }
            Filter = @{
                And = @(
                    @{
                        Dimensions = @{
                            Name     = "ResourceId"
                            Operator = "In"
                            Values   = @($ResourceId)
                        }
                    }
                )
            }
        }
    }

    try {
        $result = Get-AzCostManagementQuery -Scope "/subscriptions/$SubscriptionId" `
                    -Query ($queryParams | ConvertTo-Json -Depth 10)
        
        if ($result.Properties.Rows.Count -gt 0) {
            return [decimal]$result.Properties.Rows[0][0]
        }
    }
    catch {
        Write-Warning "Failed to get cost for $ResourceId ($($_.Exception.Message))"
    }
    return 0
}

# Initialize report collection
$report = [System.Collections.Generic.List[object]]::new()

# Process all subscriptions
$subscriptions = Get-AzSubscription
$totalSubs = $subscriptions.Count
$currentSub = 0

foreach ($sub in $subscriptions) {
    $currentSub++
    Write-Progress -Activity "Processing Subscriptions" -Status "$currentSub/$totalSubs - $($sub.Name)" `
                   -PercentComplete ($currentSub/$totalSubs*100)

    try {
        Set-AzContext -Subscription $sub.Id -ErrorAction Stop | Out-Null
        
        # Get all unattached disks
        $unattachedDisks = Get-AzDisk | Where-Object { $_.DiskState -eq 'Unattached' }
        if (-not $unattachedDisks) { continue }

        Write-Host "Processing $($unattachedDisks.Count) unattached disks in $($sub.Name)" -ForegroundColor Cyan

        # Get bulk costs for last 30 days
        $bulkCosts = Get-DiskCosts -SubscriptionId $sub.Id -FromDate $thirtyDaysAgo -ToDate $endDate

        # Process each disk
        foreach ($disk in $unattachedDisks) {
            Write-Host "  Analyzing disk: $($disk.Name)" -ForegroundColor DarkGray

            # Get cost from bulk data
            $monthlyCost = if ($bulkCosts.ContainsKey($disk.Id)) { $bulkCosts[$disk.Id] } else { 0 }

            # Get cost since creation
            $creationCost = Get-ResourceCost -SubscriptionId $sub.Id -ResourceId $disk.Id `
                            -FromDate $disk.TimeCreated -ToDate $endDate

            $report.Add([PSCustomObject]@{
                Subscription       = $sub.Name
                DiskName           = $disk.Name
                ResourceGroup      = $disk.ResourceGroupName
                SizeGB             = $disk.DiskSizeGB
                Location           = $disk.Location
                CreatedDate        = $disk.TimeCreated
                CostLast30Days     = $monthlyCost
                CostSinceCreation = $creationCost
                DiskState          = $disk.DiskState
                SKU                = $disk.Sku.Name
            })
        }
    }
    catch {
        Write-Warning "Error processing subscription $($sub.Name): $($_.Exception.Message)"
    }
}

# Export results
$excelPath = Join-Path $PWD.Path "UnattachedDisks_CostReport_$(Get-Date -Format 'yyyyMMdd-HHmmss').xlsx"
$report | Export-Excel -Path $excelPath -AutoSize -TableStyle "Medium6" -FreezeTopRow -BoldTopRow

Write-Host "`nReport generated successfully: $excelPath" -ForegroundColor Green
Write-Host "Total unattached disks found: $($report.Count)" -ForegroundColor Cyan
