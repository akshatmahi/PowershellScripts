# Require Azure PowerShell module
# Install-Module -Name Az -Scope CurrentUser -Force
# Install-Module -Name ImportExcel -Scope CurrentUser -Force

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
            LastWriteTime  = $_.TimeCreated
        })
    }

    # Unmanaged Disks (VHDs)
    Get-AzStorageAccount | ForEach-Object {
        $ctx = New-AzStorageContext -StorageAccountName $_.StorageAccountName -UseConnectedAccount
        Get-AzStorageContainer -Context $ctx | ForEach-Object {
            Get-AzStorageBlob -Container $_.Name -Context $ctx | Where-Object {
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
        }
    }
}

# Generate Excel report with formatting
$report | Export-Excel -Path "./OrphanedDisks_Report.xlsx" -AutoSize -AutoFilter -BoldTopRow -FreezeTopRow -TableStyle "Medium6" -WorksheetName "OrphanedDisks" -ClearSheet
