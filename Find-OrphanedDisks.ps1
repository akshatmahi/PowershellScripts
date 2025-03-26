# Interactive browser login
Connect-AzAccount

# Import required modules
Import-Module Az.Accounts, Az.Compute, Az.Billing -ErrorAction Stop

# Ensure ImportExcel is installed
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Install-Module -Name ImportExcel -Scope CurrentUser -Force
}
Import-Module ImportExcel -ErrorAction Stop

# Initialize report
$report = [System.Collections.Generic.List[object]]::new()

# Process all subscriptions
foreach ($sub in Get-AzSubscription) {
    try {
        Set-AzContext -Subscription $sub.Id | Out-Null
        
        # Get unattached disks
        $unattachedDisks = Get-AzDisk | Where-Object { $_.DiskState -eq 'Unattached' }
        if (-not $unattachedDisks) { continue }

        Write-Host "Processing $($unattachedDisks.Count) unattached disks in $($sub.Name)" -ForegroundColor Cyan

        # Get cost data for last 30 days using portal-like logic
        $billingPeriod = @{
            # Azure typically uses UTC dates for billing
            StartDate = (Get-Date).AddDays(-30).ToUniversalTime().Date
            EndDate   = (Get-Date).ToUniversalTime().Date
        }

        # Get consumption details with proper date formatting
        $costEntries = Get-AzConsumptionUsageDetail -StartDate $billingPeriod.StartDate.ToString("yyyy-MM-dd") `
                                                    -EndDate $billingPeriod.EndDate.ToString("yyyy-MM-dd") `
                                                    -ErrorAction SilentlyContinue

        if (-not $costEntries) {
            Write-Warning "No cost data found for subscription $($sub.Name)"
            continue
        }

        # Create cost lookup table
        $costData = @{}
        $costEntries | Where-Object { $_.ResourceType -eq 'microsoft.compute/disks' } | ForEach-Object {
            $resourceId = $_.ResourceId.ToLower()
            $costData[$resourceId] = [decimal]$_.PretaxCost
        }

        # Process each disk
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
                BillingPeriod = "{0:yyyy-MM-dd} to {1:yyyy-MM-dd}" -f $billingPeriod.StartDate, $billingPeriod.EndDate
            })
        }
    }
    catch {
        Write-Warning "Error processing subscription $($sub.Name): $_"
    }
}

# Export results
$excelPath = Join-Path $PWD.Path "DiskCosts_Report_$(Get-Date -Format 'yyyyMMdd-HHmmss').xlsx"
$report | Export-Excel -Path $excelPath -AutoSize -TableStyle "Medium6"

Write-Host "Report generated: $excelPath" -ForegroundColor Green
