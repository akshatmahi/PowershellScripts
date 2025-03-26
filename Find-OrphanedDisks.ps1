# Interactive browser login
Connect-AzAccount

# Import required modules
Import-Module Az.Accounts, Az.Compute, Az.Billing -ErrorAction Stop

# Ensure ImportExcel is installed
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Install-Module -Name ImportExcel -Scope CurrentUser -Force
}
Import-Module ImportExcel -ErrorAction Stop

# Date ranges
$endDate = Get-Date
$startDate = $endDate.AddDays(-30)

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

        # Get cost data for ALL disks in the subscription (more efficient)
        $costData = @{}
        Get-AzConsumptionUsageDetail -StartDate $startDate -EndDate $endDate -IncludeMeterDetails |
        Where-Object { $_.ResourceType -eq 'microsoft.compute/disks' } |
        ForEach-Object {
            $costData[$_.ResourceId.ToLower()] = $_.PretaxCost
        }

        # Process each disk
        foreach ($disk in $unattachedDisks) {
            $diskCost = $costData[$disk.Id.ToLower()] | Select-Object -First 1
            $creationDate = $disk.TimeCreated
            
            $report.Add([PSCustomObject]@{
                Subscription = $sub.Name
                DiskName = $disk.Name
                ResourceGroup = $disk.ResourceGroupName
                SizeGB = $disk.DiskSizeGB
                Location = $disk.Location
                CreatedDate = $creationDate
                Last30DaysCost = [decimal]($diskCost ?? 0)
                SKU = $disk.Sku.Name
                DiskState = $disk.DiskState
                ResourceId = $disk.Id
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
