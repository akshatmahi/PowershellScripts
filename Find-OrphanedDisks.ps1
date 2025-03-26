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

# Process subscriptions
$subscriptions = Get-AzSubscription
$totalSubs = $subscriptions.Count
$currentSub = 0

foreach ($sub in $subscriptions) {
    $currentSub++
    Write-Progress -Activity "Processing Subscriptions" -Status "$currentSub/$totalSubs - $($sub.Name)" -PercentComplete ($currentSub/$totalSubs*100)
    
    try {
        Set-AzContext -Subscription $sub.Id -ErrorAction Stop | Out-Null

        # Get unattached disks
        $unattachedDisks = Get-AzDisk | Where-Object { $_.DiskState -eq 'Unattached' }
        if (-not $unattachedDisks) { continue }

        Write-Host "Processing $($unattachedDisks.Count) disks in $($sub.Name)" -ForegroundColor Cyan

        # Build cost query parameters (modified for API compatibility)
        $params = @{
            Timeframe      = "Custom"
            TimePeriod     = @{
                From = (Get-Date).AddDays(-30).ToString("yyyy-MM-dd")
                To   = (Get-Date).ToString("yyyy-MM-dd")
            }
            Dataset = @{
                Aggregation = @{
                    TotalCost = @{
                        Name     = "PreTaxCost"
                        Function = "Sum"
                    }
                }
                Granularity = "None"
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
            Type = "ActualCost"
        }

        try {
            # Execute cost query
            $costResponse = Invoke-AzCostManagementQuery -Scope "subscriptions/$($sub.Id)" `
                            -Parameter $params -ErrorAction Stop

            # Process cost data
            $costData = @{}
            if ($costResponse.Properties.Rows.Count -gt 0) {
                foreach ($row in $costResponse.Properties.Rows) {
                    $resourceId = $row[1].ToLower()
                    $costData[$resourceId] = [decimal]$row[0]
                }
            }

            # Generate report entries
            foreach ($disk in $unattachedDisks) {
                $diskCost = if ($costData.ContainsKey($disk.Id.ToLower())) { $costData[$disk.Id.ToLower()] } else { 0 }
                
                $report.Add([PSCustomObject]@{
                    Subscription = $sub.Name
                    DiskName = $disk.Name
                    ResourceGroup = $disk.ResourceGroupName
                    SizeGB = $disk.DiskSizeGB
                    Location = $disk.Location
                    Last30DaysCost = $diskCost
                    SKU = $disk.Sku.Name
                    DiskState = $disk.DiskState
                    ResourceId = $disk.Id
                    QueryPeriod = "$($params.TimePeriod.From) to $($params.TimePeriod.To)"
                })
            }
        }
        catch {
            Write-Warning "Cost query failed for $($sub.Name): $($_.Exception.Message)"
            Write-Host "Try these troubleshooting steps:"
            Write-Host "1. Verify Cost Management Reader role is assigned"
            Write-Host "2. Check if costs exist in portal for these disks"
            Write-Host "3. Test with smaller date range"
        }
    }
    catch {
        Write-Warning "Subscription context error: $($_.Exception.Message)"
    }
}

# Export results
$excelPath = Join-Path $PWD.Path "DiskCosts_Report_$(Get-Date -Format 'yyyyMMdd-HHmmss').xlsx"
$report | Export-Excel -Path $excelPath -AutoSize -TableStyle "Medium6"
Write-Host "Report generated: $excelPath" -ForegroundColor Green
