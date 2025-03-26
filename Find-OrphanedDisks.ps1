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

        # Build cost query
        $queryDefinition = @{
            type = "ActualCost"
            timeframe = "Custom"
            timePeriod = @{
                from = (Get-Date).AddDays(-30).ToString("yyyy-MM-dd")
                to   = (Get-Date).ToString("yyyy-MM-dd")
            }
            dataset = @{
                granularity = "None"
                aggregation = @{
                    totalCost = @{
                        name = "PreTaxCost"
                        function = "Sum"
                    }
                }
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
                                values = @($unattachedDisks.Id)
                            }
                        }
                    )
                }
            }
        }

        # Convert to JSON with proper depth
        $queryJson = $queryDefinition | ConvertTo-Json -Depth 10

        # Execute cost query
        $costResponse = Invoke-AzCostManagementQuery -Scope "subscriptions/$($sub.Id)" `
                        -QueryObject $queryJson -ErrorAction Stop

        # Process cost data
        $costData = @{}
        if ($costResponse.Properties.Rows.Count -gt 0) {
            foreach ($row in $costResponse.Properties.Rows) {
                $costData[$row[1].ToLower()] = [decimal]$row[0]
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
                QueryPeriod = "$((Get-Date).AddDays(-30).ToString('yyyy-MM-dd')) to $((Get-Date).ToString('yyyy-MM-dd'))"
            })
        }
    }
    catch {
        Write-Warning "Error processing $($sub.Name): $($_.Exception.Message)"
        Write-Host "Verify cost permissions for this subscription" -ForegroundColor Red
    }
}

# Export results
$excelPath = Join-Path $PWD.Path "DiskCosts_Report_$(Get-Date -Format 'yyyyMMdd-HHmmss').xlsx"
$report | Export-Excel -Path $excelPath -AutoSize -TableStyle "Medium6"

Write-Host "Report generated: $excelPath" -ForegroundColor Green
