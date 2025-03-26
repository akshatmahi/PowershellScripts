# Simplified Orphaned Disk Finder with Safe Permissions Handling

# Interactive browser login
Connect-AzAccount

# Initialize report
$report = [System.Collections.Generic.List[object]]::new()

# Process all accessible subscriptions
foreach ($sub in (Get-AzSubscription)) {
    Set-AzContext -Subscription $sub.Id | Out-Null
    
    # Managed Disks
    Get-AzDisk | Where-Object {$_.DiskState -eq 'Unattached'} | ForEach-Object {
        $report.Add([PSCustomObject]@{
            Subscription    = $sub.Name
            DiskName        = $_.Name
            Type            = "Managed"
            ResourceGroup   = $_.ResourceGroupName
            SizeGB          = $_.DiskSizeGB
            Location        = $_.Location
            LastWriteTime   = $_.TimeCreated
        })
    }

    # Unmanaged Disks - Safe Check
    Get-AzStorageAccount | ForEach-Object {
        try {
            $ctx = New-AzStorageContext -StorageAccountName $_.StorageAccountName -UseConnectedAccount -ErrorAction Stop
            
            # Only check common VHD containers
            $containers = @('vhds', 'osdisks', 'disks') | ForEach-Object {
                Get-AzStorageContainer -Name $_ -Context $ctx -ErrorAction SilentlyContinue
            }

            foreach ($container in $containers) {
                try {
                    Get-AzStorageBlob -Container $container.Name -Context $ctx | Where-Object {
                        $_.Name -like '*.vhd' -and $_.BlobType -eq 'PageBlob'
                    } | ForEach-Object {
                        $report.Add([PSCustomObject]@{
                            Subscription    = $sub.Name
                            DiskName        = $_.Name
                            Type            = "Unmanaged"
                            ResourceGroup   = $_.StorageAccount.ResourceGroupName
                            SizeGB          = [math]::Round($_.Length/1GB, 2)
                            Location        = $ctx.StorageAccount.PrimaryLocation
                            LastWriteTime   = $_.LastModified.DateTime
                        })
                    }
                } catch {
                    Write-Warning "Skipping container $($container.Name) in $($_.StorageAccountName): $_"
                }
            }
        } catch {
            Write-Warning "Skipping storage account $($_.StorageAccountName): $_"
        }
    }
}

# Generate report
$report | Export-Excel -Path "./OrphanedDisks_Report.xlsx" -AutoSize -TableStyle "Medium6"

Write-Host "Report generated: $pwd/OrphanedDisks_Report.xlsx" -ForegroundColor Green
