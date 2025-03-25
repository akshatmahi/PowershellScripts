# Azure Snapshot Cleanup Script (Console Version)
# Usage: Run in PowerShell with Az module installed

# Check for Azure Module
if (-not (Get-Module Az -ListAvailable)) {
    Write-Host "Installing Azure PowerShell module..." -ForegroundColor Yellow
    Install-Module Az -Scope CurrentUser -Force -AllowClobber
    Import-Module Az
}

# Initialize Logging
$logFile = "SnapshotCleanupLog_$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
Start-Transcript -Path $logFile

# Main Process
try {
    # Step 1: Azure Login
    Write-Host "`n=== Azure Authentication ===" -ForegroundColor Cyan
    $context = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $context) {
        Connect-AzAccount
    }
    else {
        Write-Host "Using existing session: $($context.Account.Id)" -ForegroundColor Green
    }

    # Step 2: Subscription Export
    Write-Host "`n=== Subscription Management ===" -ForegroundColor Cyan
    $subFile = "subscriptions_$(Get-Date -Format 'yyyyMMdd').txt"
    
    if (-not (Test-Path $subFile)) {
        Write-Host "Exporting subscriptions to $subFile..." -ForegroundColor Yellow
        Get-AzSubscription | Select-Object -ExpandProperty Id | Out-File $subFile
    }
    else {
        Write-Host "Using existing subscription file: $subFile" -ForegroundColor Green
    }

    $subscriptions = Get-Content $subFile | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' }
    if (-not $subscriptions) {
        throw "No valid subscriptions found in $subFile"
    }

    # Step 3: Snapshot Filter
    Write-Host "`n=== Snapshot Selection ===" -ForegroundColor Cyan
    $filter = Read-Host "Enter snapshot name filter (use * for wildcards)"
    if (-not $filter) {
        throw "No filter specified"
    }

    # Step 4: Confirmation
    Write-Host "`n=== Final Confirmation ===" -ForegroundColor Red
    Write-Host "This will DELETE ALL snapshots matching:" -ForegroundColor Red
    Write-Host "Filter: $filter" -ForegroundColor Yellow
    Write-Host "Across $($subscriptions.Count) subscriptions!" -ForegroundColor Yellow
    
    $confirm = Read-Host "`nType 'DELETE' to confirm"
    if ($confirm -ne "DELETE") {
        throw "Operation cancelled by user"
    }

    # Step 5: Processing
    Write-Host "`n=== Processing Subscriptions ===" -ForegroundColor Cyan
    $totalSubs = $subscriptions.Count
    $processed = 0

    foreach ($subId in $subscriptions) {
        $processed++
        $percentComplete = [math]::Round(($processed / $totalSubs) * 100)
        Write-Progress -Activity "Processing Subscriptions" -Status "$percentComplete% Complete" -PercentComplete $percentComplete

        try {
            Write-Host "`nProcessing subscription: $subId" -ForegroundColor Cyan
            Set-AzContext -SubscriptionId $subId | Out-Null

            $snapshots = Get-AzSnapshot | Where-Object { $_.Name -like $filter }
            if (-not $snapshots) {
                Write-Host "No matching snapshots found" -ForegroundColor Yellow
                continue
            }

            foreach ($snap in $snapshots) {
                Write-Host "Deleting snapshot: $($snap.Name)" -ForegroundColor Magenta
                Remove-AzSnapshot -ResourceGroupName $snap.ResourceGroupName `
                    -SnapshotName $snap.Name -Force
                Write-Host "Deleted successfully" -ForegroundColor Green
            }
        }
        catch {
            Write-Host "Error processing subscription: $_" -ForegroundColor Red
        }
    }

    Write-Host "`n=== Operation Complete ===" -ForegroundColor Green
    Write-Host "Log file: $logFile"
}
catch {
    Write-Host "`nError: $_" -ForegroundColor Red
}
finally {
    Stop-Transcript
}
