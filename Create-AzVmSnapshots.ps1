<#
.SYNOPSIS
Azure VM Snapshot Creator with Enhanced Reporting

.DESCRIPTION
This script creates snapshots for Azure VMs across multiple subscriptions with detailed logging and CSV reporting.
#>

#region Initialization
Start-Transcript -Path ".\snapshots_$(Get-Date -Format 'yyyyMMdd_HHmmss').log" -Append

# Configuration
$config = @{
    VMNamesFile      = ".\vmnames.txt"
    SubscriptionsFile = ".\export.txt"
    ReportCSV        = ".\Snapshot_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    LogFile          = ".\snapshots_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
}

# Validate inputs
if (-not (Test-Path $config.VMNamesFile)) {
    Write-Host "VM names file not found: $($config.VMNamesFile)" -ForegroundColor Red
    exit
}

$productionTicket = Read-Host "PRODOPS Ticket "
if ([string]::IsNullOrWhiteSpace($productionTicket)) {
    Write-Host "PRODOPS Ticket cannot be empty!" -ForegroundColor Red
    exit
}

# Initialize report collection
$report = [System.Collections.Generic.List[PSObject]]::new()
#endregion

#region Azure Authentication
try {
    Connect-AzAccount -ErrorAction Stop
    Write-Host "Successfully connected to Azure account" -ForegroundColor Green
}
catch {
    Write-Host "Failed to connect to Azure: $_" -ForegroundColor Red
    exit
}
#endregion

#region Subscription Handling
# Export subscriptions if file doesn't exist
if (-not (Test-Path $config.SubscriptionsFile)) {
    Get-AzSubscription | Select-Object Id | Out-File -FilePath $config.SubscriptionsFile -Force
}

$subscriptionIds = Get-Content -Path $config.SubscriptionsFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
#endregion

#region Main Processing
$vmList = Get-Content $config.VMNamesFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

foreach ($subscriptionId in $subscriptionIds) {
    $subscriptionId = $subscriptionId.Trim()
    Write-Host "`nProcessing Subscription: $subscriptionId" -ForegroundColor Cyan

    try {
        $context = Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop
        Write-Host "Context set to subscription: $($context.Subscription.Name)" -ForegroundColor Cyan
    }
    catch {
        Write-Host "Error setting context for subscription $subscriptionId : $_" -ForegroundColor Red
        continue
    }

    foreach ($vmName in $vmList) {
        $vmName = $vmName.Trim()
        Write-Progress -Activity "Processing VMs" -Status "Current VM: $vmName"

        try {
            $vm = Get-AzVM -Name $vmName -ErrorAction Stop
        }
        catch {
            $reportEntry = [PSCustomObject]@{
                Timestamp        = Get-Date
                SubscriptionID    = $subscriptionId
                VMName           = $vmName
                DiskName         = "N/A"
                SnapshotName     = "N/A"
                Status           = "Failed"
                ErrorMessage     = "VM not found"
                OperationTicket = $productionTicket
            }
            $report.Add($reportEntry)
            Write-Host "VM not found: $vmName" -ForegroundColor Yellow
            continue
        }

        $disks = @($vm.StorageProfile.OsDisk)
        $disks += $vm.StorageProfile.DataDisks

        foreach ($disk in $disks) {
            $snapshotName = "$($disk.Name)_$($productionTicket)_$(Get-Date -Format 'yyyyMMdd')"
            $snapshotParams = @{
                SourceUri          = $disk.ManagedDisk.Id
                Location          = $vm.Location
                CreateOption      = 'Copy'
                ErrorAction       = 'Stop'
            }

            $reportEntry = [PSCustomObject]@{
                Timestamp        = Get-Date
                SubscriptionID    = $subscriptionId
                VMName           = $vmName
                DiskName         = $disk.Name
                SnapshotName     = $snapshotName
                Status           = $null
                ErrorMessage     = $null
                OperationTicket = $productionTicket
            }

            try {
                $snapshotConfig = New-AzSnapshotConfig @snapshotParams
                $snapshot = New-AzSnapshot -Snapshot $snapshotConfig `
                                          -SnapshotName $snapshotName `
                                          -ResourceGroupName $vm.ResourceGroupName `
                                          -ErrorAction Stop

                $reportEntry.Status = "Success"
                Write-Host "Snapshot created: $snapshotName" -ForegroundColor Green
            }
            catch {
                $reportEntry.Status = "Failed"
                $reportEntry.ErrorMessage = $_.Exception.Message
                Write-Host "Error creating snapshot $snapshotName : $_" -ForegroundColor Red
            }
            finally {
                $report.Add($reportEntry)
            }
        }
    }
}
#endregion

#region Reporting
$report | Export-Csv -Path $config.ReportCSV -NoTypeInformation
Write-Host "`nReport generated: $($config.ReportCSV)" -ForegroundColor Cyan

# Display summary
$successCount = ($report | Where-Object { $_.Status -eq 'Success' }).Count
$failureCount = ($report | Where-Object { $_.Status -eq 'Failed' }).Count

Write-Host "`nOperation Summary:" -ForegroundColor Cyan
Write-Host "Total Snapshots Attempted: $($report.Count)"
Write-Host "Successful: $successCount" -ForegroundColor Green
Write-Host "Failed: $failureCount" -ForegroundColor Red
#endregion

Stop-Transcript
