<#
.SYNOPSIS
Azure VM Snapshot Creator with Smart Naming and Robust Validation

.DESCRIPTION
Creates Azure VM snapshots with automatic name truncation and enhanced safety checks,
and only reports “NotFound” if a VM truly isn’t in any subscription.
#>

#region Initialization
Clear-Host
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

$validSubscriptions |
    Select-Object Id |
    Out-File -FilePath $config.SubscriptionsFile -Force

$subscriptionIds = $validSubscriptions.Id
Write-Host " [✓] Validated $($subscriptionIds.Count) subscriptions" -ForegroundColor Green
#endregion

#region Main Processing
$vmNames = Get-Content $config.VMNamesFile |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

foreach ($vmName in $vmNames) {
    $vmName = $vmName.Trim()
    $foundAnywhere = $false

    foreach ($subscriptionId in $subscriptionIds) {
        # Set context for this subscription
        try {
            Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop | Out-Null
        }
        catch {
            Write-Host " [×] Could not set context to ${subscriptionId}: $_" -ForegroundColor Red
            continue
        }

        # Try to retrieve the VM
        try {
            $vm = Get-AzVM -Name $vmName -Status -ErrorAction Stop
        }
        catch {
            # VM not in this subscription → skip quietly
            continue
        }

        # We found the VM here
        $foundAnywhere = $true
        Write-Host "`n [✓] Found VM '$vmName' in subscription $subscriptionId" -ForegroundColor Green

        # Determine resource group
        $rg = $vm.ResourceGroupName
        if ([string]::IsNullOrWhiteSpace($rg)) {
            Write-Host " [×] VM has no ResourceGroupName, skipping snapshots here." -ForegroundColor Yellow
            continue
        }

        # Collect disks
        $disks = @($vm.StorageProfile.OsDisk) + $vm.StorageProfile.DataDisks
        $disks = $disks | Where-Object { $_ -and $_.Name }

        foreach ($disk in $disks) {
            # Get disk location
            try {
                $diskObj  = Get-AzDisk -ResourceGroupName $rg -DiskName $disk.Name -ErrorAction Stop
                $location = $diskObj.Location
            }
            catch {
                $location = $vm.Location
            }

            # Build truly unique snapshot name: VMName_DiskName_Ticket
            $ticketPart    = $productionTicket.Trim()
            $rawBase       = "{0}_{1}" -f $vmName, $disk.Name.Trim()
            $spaceForBase  = $config.MaxNameLength - ($ticketPart.Length + 1)
            if ($spaceForBase -lt 0) { $spaceForBase = 0 }
            $truncatedBase = if ($rawBase.Length -gt $spaceForBase) {
                $rawBase.Substring(0, $spaceForBase)
            } else {
                $rawBase
            }
            $snapshotName  = "{0}_{1}" -f $truncatedBase, $ticketPart

            $entry = [PSCustomObject]@{
                Timestamp       = Get-Date
                SubscriptionID  = $subscriptionId
                VMName          = $vmName
                DiskName        = $disk.Name
                SnapshotName    = $snapshotName
                Status          = $null
                ErrorMessage    = $null
                OperationTicket = $productionTicket
            }

            # Create the snapshot
            try {
                Write-Host " [»] Creating snapshot '$snapshotName' ..." -ForegroundColor Yellow -NoNewline
                $cfg = New-AzSnapshotConfig `
                    -SourceUri       $disk.ManagedDisk.Id `
                    -Location        $location `
                    -CreateOption    Copy `
                    -ErrorAction     Stop

                New-AzSnapshot `
                    -Snapshot          $cfg `
                    -SnapshotName      $snapshotName `
                    -ResourceGroupName $rg `
                    -ErrorAction       Stop | Out-Null

                $entry.Status = "Success"
                Write-Host "`r [✓] Created: $snapshotName" -ForegroundColor Green
            }
            catch {
                $entry.Status       = "Failed"
                $entry.ErrorMessage = $_.Exception.Message
                Write-Host "`r [×] Error: $($_.Exception.Message)" -ForegroundColor Red
            }
            finally {
                $report.Add($entry)
            }
        }
        # end foreach disk
    }
    # end foreach subscription

    # If we never found the VM, record one NotFound entry
    if (-not $foundAnywhere) {
        Write-Host "`n [×] VM not found in any subscription: $vmName" -ForegroundColor Red
        $report.Add([PSCustomObject]@{
            Timestamp       = Get-Date
            SubscriptionID  = "N/A"
            VMName          = $vmName
            DiskName        = "N/A"
            SnapshotName    = "N/A"
            Status          = "NotFound"
            ErrorMessage    = "VM not found in any subscription"
            OperationTicket = $productionTicket
        })
    }
}
#endregion

#region Reporting & Cleanup
$report | Export-Csv -Path $config.ReportCSV -NoTypeInformation

$succ = ($report | Where-Object Status -eq 'Success').Count
$fail = ($report | Where-Object Status -eq 'Failed').Count
$none = ($report | Where-Object Status -eq 'NotFound').Count

Write-Host "`n+-------------------+-----------+" -ForegroundColor Cyan
Write-Host "|   Summary Report  |    Count  |" -ForegroundColor Cyan
Write-Host "+-------------------+-----------+" -ForegroundColor Cyan
Write-Host "| Successful        | $($succ.ToString().PadLeft(9)) |" -ForegroundColor Green
Write-Host "| Failed            | $($fail.ToString().PadLeft(9)) |" -ForegroundColor Red
Write-Host "| Not Found         | $($none.ToString().PadLeft(9)) |" -ForegroundColor Yellow
Write-Host "+-------------------+-----------+" -ForegroundColor Cyan

Write-Host "`n [✓] Report generated: $($config.ReportCSV)" -ForegroundColor Green
Stop-Transcript
#endregion
