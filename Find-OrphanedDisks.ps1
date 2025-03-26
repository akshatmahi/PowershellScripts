# Enforce strict mode and error handling
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# Connect with explicit authentication
Connect-AzAccount -UseDeviceAuthentication

# Check critical modules
$requiredModules = 'Az.Accounts', 'Az.Compute', 'Az.Billing'
foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable $module)) {
        Install-Module $module -Force -Scope CurrentUser
    }
    Import-Module $module -Force
}

# Date configuration (critical for Azure cost API)
$endDate = [DateTime]::UtcNow.Date
$startDate = $endDate.AddDays(-30)
$dateFormat = "yyyy-MM-dd"

# Initialize report with error tracking
$report = [System.Collections.Generic.List[object]]::new()
$errors = [System.Collections.Generic.List[string]]::new()

# Process subscriptions with enhanced logging
foreach ($sub in Get-AzSubscription) {
    try {
        Write-Host "`nProcessing subscription: $($sub.Name)" -ForegroundColor Cyan
        Set-AzContext -Subscription $sub.Id | Out-Null

        # Get disks with state validation
        $disks = Get-AzDisk | Where-Object { 
            $_.DiskState -eq 'Unattached' -and
            $_.TimeCreated -lt $endDate.AddDays(-2)  # Exclude disks <48h old
        }

        if (-not $disks) {
            Write-Host "No unattached disks found." -ForegroundColor Yellow
            continue
        }

        # Cost retrieval with explicit permissions check
        try {
            Write-Host "Checking cost permissions..."
            $testCost = Get-AzConsumptionUsageDetail -StartDate $startDate.ToString($dateFormat) `
                        -EndDate $endDate.ToString($dateFormat) -Top 1 -ErrorAction Stop
        }
        catch {
            $errors.Add("Permission error in $($sub.Name): $($_.Exception.Message)")
            continue
        }

        # Get costs with resource ID normalization
        $costData = @{}
        Get-AzConsumptionUsageDetail -StartDate $startDate.ToString($dateFormat) `
                                     -EndDate $endDate.ToString($dateFormat) |
            Where-Object {
                $_.ResourceType -eq 'microsoft.compute/disks' -and
                $disks.Id.Contains($_.ResourceId.Trim().ToLower())
            } |
            ForEach-Object {
                $key = $_.ResourceId.Trim().ToLower()
                $costData[$key] = [math]::Round([decimal]$_.PretaxCost, 2)
            }

        # Build report with fallback values
        foreach ($disk in $disks) {
            $diskId = $disk.Id.Trim().ToLower()
            $report.Add([PSCustomObject]@{
                Subscription    = $sub.Name
                DiskName       = $disk.Name
                ResourceGroup   = $disk.ResourceGroupName
                SizeGB         = $disk.DiskSizeGB
                CostLast30Days = $costData.ContainsKey($diskId) ? $costData[$diskId] : 0
                SKU            = $disk.Sku.Name
                DiskState      = $disk.DiskState
                ResourceId     = $diskId
                LastModified   = $disk.TimeCreated.ToString("yyyy-MM-dd")
            })
        }
    }
    catch {
        $errors.Add("Error in $($sub.Name): $($_.Exception.Message)")
    }
}

# Output results
if ($report.Count -gt 0) {
    $excelPath = Join-Path $env:USERPROFILE "Downloads\DiskCosts_$(Get-Date -Format 'yyyyMMdd-HHmmss').xlsx"
    $report | Export-Excel -Path $excelPath -AutoSize -TableStyle Medium2
    Write-Host "`nReport generated: $excelPath" -ForegroundColor Green
}
else {
    Write-Host "`nNo cost data found for any disks." -ForegroundColor Yellow
}

# Show errors if any
if ($errors.Count -gt 0) {
    Write-Host "`nEncountered errors:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host " - $_" }
}
