# Import required modules
Import-Module Az.Accounts
Import-Module Az.Compute
Import-Module Az.CostManagement
Import-Module ImportExcel

# Connect to Azure
Connect-AzAccount

# Get all subscriptions
$subscriptions = Get-AzSubscription

# Initialize array to store disk information
$diskInfo = @()

foreach ($subscription in $subscriptions) {
    try {
        # Set context to current subscription
        Set-AzContext -Subscription $subscription.Id | Out-Null
        Write-Host "Processing subscription: $($subscription.Name)" -ForegroundColor Green

        # Get all managed disks in the subscription
        $disks = Get-AzDisk

        foreach ($disk in $disks) {
            # Check if disk is unattached
            if ($null -eq $disk.ManagedBy) {
                # Get disk cost for last 30 days
                $startDate = (Get-Date).AddDays(-30)
                $endDate = Get-Date
                
                try {
                    $costQuery = @{
                        Type = 'Usage'
                        TimeframeType = 'Custom'
                        BillingPeriodStartDate = $startDate
                        BillingPeriodEndDate = $endDate
                        ShowDetails = $true
                        ResourceIdOnly = $false
                    }
                    
                    $costData = Get-AzConsumptionUsageDetail @costQuery | 
                                Where-Object { $_.InstanceId -eq $disk.Id }
                    
                    if ($costData) {
                        $totalCost = ($costData | Measure-Object -Property PretaxCost -Sum).Sum
                        $avgCost = if ($totalCost) { $totalCost / 30 } else { 0 }
                    }
                }
                catch {
                    Write-Warning "Alternative cost fetch failed for disk $($disk.Name): $_"
                    $totalCost = 0
                    $avgCost = 0
                }
                                        
                # Create custom object with disk details
                $diskDetails = [PSCustomObject]@{
                    'Subscription Name' = $subscription.Name
                    'Subscription ID' = $subscription.Id
                    'Resource Group' = $disk.ResourceGroupName
                    'Disk Name' = $disk.Name
                    'Location' = $disk.Location
                    'Disk Size (GB)' = $disk.DiskSizeGB
                    'Disk SKU' = $disk.Sku.Name
                    'Total Cost (30 days)' = [math]::Round($totalCost, 2)
                    'Average Daily Cost' = [math]::Round($avgCost, 2)
                    'Creation Time' = $disk.TimeCreated
                    'Tags' = ($disk.Tags | ConvertTo-Json -Compress)
                }
                
                $diskInfo += $diskDetails
                Write-Host "Processed disk: $($disk.Name)" -ForegroundColor Yellow
            }
        }
    }
    catch {
        Write-Error "Error processing subscription $($subscription.Name): $_"
    }
}

# Create the report only if we have data
if ($diskInfo.Count -gt 0) {
    # Export to Excel with formatting
    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $excelPath = Join-Path -Path $PWD -ChildPath "UnattachedDisksReport_$timestamp.xlsx"
    
    # Export to Excel
    $diskInfo | Export-Excel -Path $excelPath -WorksheetName 'Unattached Disks' -AutoSize -BoldTopRow -AutoFilter -FreezeTopRow

    # Add formatting
    $excel = Open-ExcelPackage -Path $excelPath
    $worksheet = $excel.Workbook.Worksheets['Unattached Disks']

    # Add summary section
    $worksheet.InsertRow(1, 6)
    $worksheet.Cells["A1"].Value = "Azure Unattached Disks Report"
    $worksheet.Cells["A2"].Value = "Report Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $worksheet.Cells["A3"].Value = "Total Unattached Disks: $($diskInfo.Count)"
    
    # Format numbers
    $totalCost = ($diskInfo | Measure-Object 'Total Cost (30 days)' -Sum).Sum
    $totalStorage = ($diskInfo | Measure-Object 'Disk Size (GB)' -Sum).Sum
    
    $worksheet.Cells["A4"].Value = "Total Storage (GB): $totalStorage"
    $worksheet.Cells["A5"].Value = "Total Monthly Cost: $($totalCost.ToString('C2'))"
    $worksheet.Cells["A6"].Value = "Average Daily Cost: $($($totalCost/30).ToString('C2'))"

    # Save and close
    Close-ExcelPackage -ExcelPackage $excel -Show

    Write-Host "`nReport generated successfully at: $excelPath" -ForegroundColor Green
    Write-Host "Total unattached disks found: $($diskInfo.Count)" -ForegroundColor Cyan
    Write-Host "Total monthly cost: $($totalCost.ToString('C2'))" -ForegroundColor Cyan
}
else {
    Write-Host "No unattached disks found in any subscription." -ForegroundColor Yellow
}
