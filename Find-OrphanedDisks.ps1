# Interactive browser login
Connect-AzAccount

# Import required modules
Import-Module Az.Accounts, Az.Compute, Az.CostManagement -ErrorAction Stop

# Ensure ImportExcel is installed
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Install-Module -Name ImportExcel -Scope CurrentUser -Force
}
Import-Module ImportExcel -ErrorAction Stop

# Initialize report
$report = [System.Collections.Generic.List[object]]::new()

# Process subscriptions with error handling
$subscriptions = Get-AzSubscription
$totalSubs = $subscriptions.Count
$currentSub = 0

foreach ($sub in $subscriptions) {
    $currentSub++
    Write-Progress -Activity "Processing Subscriptions" -Status "$currentSub/$totalSubs - $($sub.Name)" -PercentComplete ($currentSub/$totalSubs*100)
    
    try {
        Set-AzContext -Subscription $sub.Id -ErrorAction Stop | Out-Null

        # Get all unattached disks
        $unattachedDisks = Get-AzDisk | Where-Object { $_.DiskState -eq 'Unattached' }
        if (-not $unattachedDisks) { continue }

        Write-Host "Processing $($unattachedDisks.Count) disks in $($sub.Name)" -ForegroundColor Cyan

        # Create cost management query (matches portal filters)
        $query = @{
            type = "ActualCost"
            timeframe = "Custom"
            timePeriod = @{
                from = (Get-Date).AddDays(-30).ToString("yyyy-MM-dd")
                to   = (Get-Date).ToString("yyyy-MM-dd")
            }
            dataset = @{
                aggregation = @{
                    totalCost = @{
                        name = "Cost"
                        function = "Sum"
                    }
                }
                granularity = "None"
                filter = @{
                    and = @(
                        @{
                            dimensions = @{
                                name = "ResourceType"
                                operator = "In"
                                values = @("Microsoft.Compute/disks")
                            }
                        },
                        @{
                            dimensions = @{
                                name = "ResourceId"
                                operator = "In"
                                values = $unattachedDisks.Id
                            }
                        }
                    )
                }
            }
        }

        # Execute cost query
        $costs = Invoke-AzCostManagementQuery -Scope "subscriptions/$($sub.Id)" `
                -Query $query -ErrorAction Stop

        # Build cost lookup table
        $costData = @{}
        foreach ($row in $costs.Properties.Rows) {
            $resourceId = $row[1].ToLower()
            $costData[$resourceId] = [decimal]$row[0]
        }

        # Process disks
        foreach ($disk in $unattachedDisks) {
            $diskId = $disk.Id.ToLower()
            $report.Add([PSCustomObject]@{
                Subscription = $sub.Name
                DiskName = $disk.Name
                ResourceGroup = $disk.ResourceGroupName
                SizeGB = $disk.DiskSizeGB
                Location = $disk.Location
                Last30DaysCost = $costData[$diskId] ?? 0
                SKU = $disk.Sku.Name
                DiskState = $disk.DiskState
                ResourceId = $disk.Id
                QueryPeriod = $query.timePeriod
            })
        }
    }
    catch {
        Write-Warning "Error processing $($sub.Name): $($_.Exception.Message)"
    }
}

# Export results
$excelPath = Join-Path $PWD.Path "DiskCosts_Report_$(Get-Date -Format 'yyyyMMdd-HHmmss').xlsx"
$report | Export-Excel -Path $excelPath -AutoSize -TableStyle "Medium6"

Write-Host "Report generated: $excelPath" -ForegroundColor Green
