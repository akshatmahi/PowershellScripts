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

# Date configuration
$endDate = Get-Date
$startDate = $endDate.AddDays(-30)

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

        # Get cost data for all disks in subscription
        $costData = @{}
        Get-AzConsumptionUsageDetail -StartDate $startDate -EndDate $endDate |
        Where-Object {
            $_.ResourceType -eq 'microsoft.compute/disks' -and
            $_.ResourceId -in $unattachedDisks.Id
        } | ForEach-Object {
            $costData[$_.ResourceId] = [decimal]$_.PretaxCost
        }

        # Generate report entries
        foreach ($disk in $unattachedDisks) {
            $diskCost = if ($costData.ContainsKey($disk.Id)) { $costData[$disk.Id] } else { 0 }
            
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
                BillingPeriod = "$($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))"
            })
        }
    }
    catch {
        Write-Warning "Error processing $($sub.Name): $_"
        Write-Host "Verify you have 'Cost Management Reader' permissions" -ForegroundColor Red
    }
}

# Export results
$excelPath = Join-Path $PWD.Path "DiskCosts_Report_$(Get-Date -Format 'yyyyMMdd-HHmmss').xlsx"
$report | Export-Excel -Path $excelPath -AutoSize -TableStyle "Medium6"

Write-Host "Report generated: $excelPath" -ForegroundColor Green
