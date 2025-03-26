# Connect to Azure
Connect-AzAccount

# Export all subscription IDs
$subscriptionFilePath = "./subscriptions.txt"
$null = Get-AzSubscription | Select-Object Id | Out-File -FilePath $subscriptionFilePath -Force
$subscriptionIds = Get-Content -Path $subscriptionFilePath

# Prepare data for Excel report
$DiskReport = @()

foreach ($SubscriptionId in $subscriptionIds) {
    $SubscriptionId = $SubscriptionId.Trim()
    Set-AzContext -SubscriptionId $SubscriptionId
    
    # Get all managed disks
    $ManagedDisks = Get-AzDisk

    # Find unattached managed disks
    $UnattachedManagedDisks = $ManagedDisks | Where-Object { $_.DiskState -eq 'Unattached' }
    
    # Get all storage accounts
    $StorageAccounts = Get-AzStorageAccount
    
    # Add managed disks to report
    foreach ($disk in $UnattachedManagedDisks) {
        $DiskReport += [PSCustomObject]@{
            SubscriptionId = $SubscriptionId
            DiskName = $disk.Name
            ResourceGroup = $disk.ResourceGroupName
            DiskType = "Managed"
            Location = $disk.Location
            SizeGB = $disk.DiskSizeGB
        }
    }
    
    # Loop through each storage account to find unmanaged VHDs
    foreach ($StorageAccount in $StorageAccounts) {
        $Context = $StorageAccount.Context
        $Containers = Get-AzStorageContainer -Context $Context
        
        foreach ($Container in $Containers) {
            $Blobs = Get-AzStorageBlob -Container $Container.Name -Context $Context | Where-Object { $_.Name -match '\.vhd$' }
            
            foreach ($Blob in $Blobs) {
                $DiskReport += [PSCustomObject]@{
                    SubscriptionId = $SubscriptionId
                    DiskName = $Blob.Name
                    ResourceGroup = "N/A"
                    DiskType = "Unmanaged"
                    Location = $StorageAccount.PrimaryLocation
                    SizeGB = "Unknown"
                }
            }
        }
    }
}

# Export to Excel
$DiskReport | Export-Excel -Path "UnattachedDisksReport.xlsx" -AutoSize -TableName "DisksReport"
