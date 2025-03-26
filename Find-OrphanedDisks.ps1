# Enforce strict error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Authenticate with Azure
Connect-AzAccount -UseDeviceAuthentication

# Import required modules
Import-Module Az.Accounts, Az.Compute, Az.Billing

# Configure dates (UTC required for Azure cost API)
$endDate = (Get-Date).ToUniversalTime().Date
$startDate = $endDate.AddDays(-30).ToString("yyyy-MM-dd")
$endDate = $endDate.ToString("yyyy-MM-dd")

# Initialize report
$report = [System.Collections.Generic.List[object]]::new()

# Process all subscriptions
$subscriptions = Get-AzSubscription
foreach ($sub in $subscriptions) {
    try {
        Write-Host "Processing subscription: $($sub.Name)" -ForegroundColor Cyan
        
        # Set subscription context
        Set-AzContext -Subscription $sub.Id | Out-Null

        # Get unattached managed disks
        $unattachedDisks = Get-AzDisk | Where-Object { $_.DiskState -eq 'Unattached' }
        if (-not $unattachedDisks) { continue }

        # Retrieve cost data
        $costData = @{}
        Get-AzConsumptionUsageDetail -StartDate $startDate -EndDate $endDate |
            Where-Object { 
                $_.ResourceType -eq 'microsoft.compute/disks' -and
                $_.ResourceId -in $unattachedDisks.Id
            } |
            ForEach-Object { 
                $costData[$_.ResourceId] = [decimal]($costData[$_.ResourceId] + $_.PretaxCost)
            }

        # Build report
        foreach ($disk in $unattachedDisks) {
            $report.Add([PSCustomObject]@{
                Subscription    = $sub.Name
                DiskName        = $disk.Name
                ResourceGroup   = $disk.ResourceGroupName
                SizeGB          = $disk.DiskSizeGB
                Location        = $disk.Location
                CostLast30Days  = $costData[$disk.Id]
                SKU             = $disk.Sku.Name
                DiskState       = $disk.DiskState
                ResourceId      = $disk.Id
                BillingPeriod   = "$startDate to $endDate"
            })
        }
    }
    catch {
        Write-Warning "Error processing $($sub.Name): $_"
        Write-Host "Verify you have 'Cost Management Reader' permissions on this subscription" -ForegroundColor Red
    }
}

# Export results
$excelPath = Join-Path $env:USERPROFILE "Downloads\DiskCosts_Report_$(Get-Date -Format 'yyyyMMdd-HHmmss').xlsx"
$report | Export-Excel -Path $excelPath -AutoSize -TableStyle "Medium6" -FreezeTopRow

Write-Host "Report generated: $excelPath" -ForegroundColor Green
