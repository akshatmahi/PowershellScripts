<#
.SYNOPSIS
Azure VM Snapshot Creator with Smart Naming and Robust Validation

.DESCRIPTION
Creates Azure VM snapshots with automatic name truncation and enhanced safety checks
#>

#region Initialization
Clear-Host
Write-Host @"
  ____  _  _  ____  _  _     ___  _  _  ____  ____  ____  _  _   
 (_  _)( \/ )( ___)( \( )___/ __)( \/ )( ___)(  _ \(_  _)( \/ )  
  _)(_  \  /  )__)  )  ((___\__ \ \  /  )__)  )   / _)(_  \  /   
 (____)  \/  (____)(_)\_)   (___/  \/  (____)(_)\_)(____)  \/    
                                                                  
"@ -ForegroundColor Cyan

Start-Transcript -Path ".\snapshots_$(Get-Date -Format 'yyyyMMdd_HHmmss').log" -Append

# Configuration
$config = @{
    VMNamesFile       = ".\vmnames.txt"
    SubscriptionsFile = ".\export.txt"
    ReportCSV         = ".\Snapshot_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    MaxNameLength     = 82
}

# Validate inputs
if (-not (Test-Path $config.VMNamesFile)) {
    Write-Host " [×] VM names file not found: $($config.VMNamesFile)" -ForegroundColor Red
    exit 1
}

$productionTicket = Read-Host " [»] PRODOPS Ticket "
if ([string]::IsNullOrWhiteSpace($productionTicket)) {
    Write-Host " [×] PRODOPS Ticket cannot be empty!" -ForegroundColor Red
    exit 1
}

# Initialize report collection
$report = [System.Collections.Generic.List[PSObject]]::new()
#endregion

#region Azure Authentication
try {
    Write-Host " [»] Connecting to Azure..." -ForegroundColor Yellow -NoNewline
    Connect-AzAccount -ErrorAction Stop | Out-Null
    Write-Host "`r [✓] Connected to Azure account    " -ForegroundColor Green
}
catch {
    Write-Host "`r [×] Failed to connect to Azure: $_" -ForegroundColor Red
    exit 1
}
#endregion

#region Subscription Handling
Write-Host " [»] Validating subscriptions..." -ForegroundColor Yellow
$validSubscriptions = Get-AzSubscription -ErrorAction SilentlyContinue | 
    Where-Object { $_.Id -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$' }

if (-not $validSubscriptions) {
    Write-Host " [×] No valid subscriptions found!" -ForegroundColor Red
    exit 1
}

$validSubscriptions | Select-Object Id | Out-File -FilePath $config.SubscriptionsFile -Force
$subscriptionIds = $validSubscriptions.Id
Write-Host " [✓] Validated $($subscriptionIds.Count) subscriptions" -ForegroundColor Green
#endregion

#region Main Processing
$vmList = Get-Content $config.VMNamesFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

foreach ($subscriptionId in $subscriptionIds) {
    Write-Host "`n [»] Processing Subscription: $subscriptionId" -ForegroundColor Cyan
    
    try {
        Write-Host " [»] Setting subscription context..." -ForegroundColor Yellow -NoNewline
        $context = Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop
        Write-Host "`r [✓] Context set to: $($context.Subscription.Name)    " -ForegroundColor Green
    }
    catch {
        Write-Host "`r [×] Error setting context: $_" -ForegroundColor Red
        continue
    }

    foreach ($vmName in $vmList) {
        $vmName = $vmName.Trim()
        Write-Progress -Activity "Processing VMs" -Status "Current VM: $vmName" -PercentComplete -1
        
        try {
            Write-Host " [»] Searching for VM: $vmName" -ForegroundColor Yellow -NoNewline
            $vm = Get-AzVM -Name $vmName -Status -ErrorAction Stop
            Write-Host "`r [✓] Found VM: $vmName    " -ForegroundColor Green
        }
        catch {
            $report.Add([PSCustomObject]@{
                Timestamp       = Get-Date
                SubscriptionID = $subscriptionId
                VMName          = $vmName
                DiskName        = "N/A"
                SnapshotName    = "N/A"
                Status          = "NotFound"
                ErrorMessage    = "VM not found in subscription"
                OperationTicket = $productionTicket
            })
            Write-Host "`r [×] VM not found: $vmName    " -ForegroundColor Red
            continue
        }

        # Extract resource group name safely
        $resourceGroupName = $vm.Id.Split('/')[4]
        if ([string]::IsNullOrEmpty($resourceGroupName)) {
            Write-Host " [×] Failed to determine Resource Group for VM: $vmName" -ForegroundColor Red
            continue
        }

        # Process disks with smart naming
        $disks = @($vm.StorageProfile.OsDisk) + $vm.StorageProfile.DataDisks

        foreach ($disk in $disks) {
            # Generate compliant snapshot name
            $ticketPart = $productionTicket.Trim()
            $diskPart = $disk.Name.Trim()
            
            $maxDiskLength = $config.MaxNameLength - $ticketPart.Length - 1  # 1 for underscore
            $truncatedDisk = if ($maxDiskLength -gt 0) {
                $diskPart.Substring(0, [Math]::Min($diskPart.Length, $maxDiskLength))
            } else {
                $diskPart = $null
            }

            $snapshotName = if ($truncatedDisk) {
                "${truncatedDisk}_${ticketPart}"
            } else {
                $ticketPart
            }

            # Final length enforcement
            $snapshotName = $snapshotName.Substring(0, [Math]::Min($snapshotName.Length, $config.MaxNameLength))

            $reportEntry = [PSCustomObject]@{
                Timestamp       = Get-Date
                SubscriptionID = $subscriptionId
                VMName          = $vmName
                DiskName        = $disk.Name
                SnapshotName    = $snapshotName
                Status          = $null
                ErrorMessage    = $null
                OperationTicket = $productionTicket
            }

            try {
                Write-Host " [»] Creating snapshot: $snapshotName" -ForegroundColor Yellow -NoNewline
                $snapshotConfig = New-AzSnapshotConfig -SourceUri $disk.ManagedDisk.Id `
                    -Location $vm.Location `
                    -CreateOption Copy `
                    -ErrorAction Stop

                $null = New-AzSnapshot -Snapshot $snapshotConfig `
                    -SnapshotName $snapshotName `
                    -ResourceGroupName $resourceGroupName `
                    -ErrorAction Stop

                $reportEntry.Status = "Success"
                Write-Host "`r [✓] Snapshot created: $snapshotName    " -ForegroundColor Green
            }
            catch {
                $reportEntry.Status = "Failed"
                $reportEntry.ErrorMessage = $_.Exception.Message
                Write-Host "`r [×] Error creating snapshot: $($_.Exception.Message)    " -ForegroundColor Red
            }
            finally {
                $report.Add($reportEntry)
            }
        }
    }
}
#endregion

#region Reporting & Cleanup
$report | Export-Csv -Path $config.ReportCSV -NoTypeInformation

# Display summary
$successCount = ($report | Where-Object Status -eq 'Success').Count
$failureCount = ($report | Where-Object Status -eq 'Failed').Count
$notFoundCount = ($report | Where-Object Status -eq 'NotFound').Count

Write-Host "`n┌──────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│         Summary Report        │" -ForegroundColor Cyan
Write-Host "├────────────────┬─────────────┤" -ForegroundColor Cyan
Write-Host "│ Successful     │ $($successCount.ToString().PadLeft(11)) │" -ForegroundColor Green
Write-Host "├────────────────┼─────────────┤" -ForegroundColor Cyan
Write-Host "│ Failed         │ $($failureCount.ToString().PadLeft(11)) │" -ForegroundColor Red
Write-Host "├────────────────┼─────────────┤" -ForegroundColor Cyan
Write-Host "│ Not Found      │ $($notFoundCount.ToString().PadLeft(11)) │" -ForegroundColor Yellow
Write-Host "└────────────────┴─────────────┘" -ForegroundColor Cyan

Write-Host "`n [✓] Report generated: $($config.ReportCSV)" -ForegroundColor Green
Stop-Transcript
#endregion
