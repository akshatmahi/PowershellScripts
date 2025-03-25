Start-Transcript -Path .\snapshot.log -Append

# Input text file path
$textFilePath = ".\vmnames.txt"
$productionTicket = Read-Host "PRODOPS Ticket "

# Login to Azure
Connect-AzAccount

# Path where subscription IDs are stored - Ensure this file exists and is properly formatted
$subscriptionFilePath = ".\export.txt"

#Exporting Subscription Ids
Get-AzSubscription | Select-Object Id | Out-File -FilePath $subscriptionFilePath -Force

# Read subscription IDs
$subscriptionIds = @()
$subscriptionIds = Get-Content -Path $subscriptionFilePath

foreach ($subscriptionId in $subscriptionIds) {
    $subscriptionId = $subscriptionId.Trim() # Remove any whitespace if necessary

    if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
        Write-Output "Invalid subscription ID found in the file."
        continue
    }
    
    # Set subscription context
    try {
        $context = Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop
    } catch {
        Write-Output "Failed to set context for subscription ID: $subscriptionId"
        continue
    }

    $vmNames = Get-Content $textFilePath
    foreach ($vmName in $vmNames) {
        $vmName = $vmName.Trim()
        # Get the VM object
        $vm = Get-AzVM -Name $vmName -ErrorAction SilentlyContinue
        
        if ($null -eq $vm) {
            Write-Output "VM not found: $vmName in Subscription: $subscriptionId"
            continue
        }
        
        # Dynamic location based on VM's actual location
        $location = $vm.Location
        
        # Snapshot each disk (OS and Data disks)
        $disks = @($vm.StorageProfile.OsDisk)
        $disks += $vm.StorageProfile.DataDisks

        foreach ($disk in $disks) {
            $snapshotName = "$($disk.Name)_$($productionTicket)"
            $snapshotConfig = New-AzSnapshotConfig -SourceUri $disk.ManagedDisk.Id -Location $location -CreateOption Copy

            # Create the snapshot
            try {
                $snapshot = New-AzSnapshot -Snapshot $snapshotConfig -SnapshotName $snapshotName -ResourceGroupName $vm.ResourceGroupName -ErrorAction Stop
                Write-Output "Snapshot created successfully: $snapshotName"
            } catch {
                Write-Output "Failed to create snapshot: $snapshotName"
            }
        }
    }
}

Stop-Transcript