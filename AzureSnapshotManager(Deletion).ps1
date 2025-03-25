# Add this at the top to ensure required modules are installed
if (-not (Get-Module Az -ListAvailable)) {
    Write-Host "Installing Azure PowerShell module..."
    Install-Module Az -Scope CurrentUser -Force -AllowClobber
    Import-Module Az
}

# Replace the $btnLogin.Add_Click block with this
$btnLogin.Add_Click({
    $btnLogin.Enabled = $false
    Update-Log "Starting Azure authentication..."
    
    try {
        $context = Get-AzContext -ErrorAction SilentlyContinue
        if(-not $context) {
            $authJob = Start-Job -ScriptBlock {
                Connect-AzAccount
            }
            
            Register-ObjectEvent -InputObject $authJob -EventName StateChanged -Action {
                if ($authJob.State -eq 'Completed') {
                    $global:form.Invoke([Action]{
                        $btnExportSubs.Enabled = $true
                        Update-Log "Authentication successful!"
                    })
                }
            } | Out-Null
        }
        else {
            $btnExportSubs.Enabled = $true
            Update-Log "Using existing Azure session"
        }
    }
    catch {
        Update-Log "Authentication failed: $_"
        $btnLogin.Enabled = $true
    }
})

# Replace the $btnStart.Add_Click block with this
$btnStart.Add_Click({
    if(-not $txtFilter.Text) {
        [System.Windows.Forms.MessageBox]::Show("Please enter a snapshot filter pattern!", "Warning")
        return
    }
    
    $confirmation = [System.Windows.Forms.MessageBox]::Show(
        "This will PERMANENTLY DELETE all snapshots matching pattern:`n'$($txtFilter.Text)'`nAcross all exported subscriptions!",
        "Confirm Bulk Deletion",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    
    if($confirmation -eq "Yes") {
        $btnStart.Enabled = $false
        $progressBar.Value = 0
        
        $cleanupJob = Start-Job -ScriptBlock {
            Import-Module Az
            $subscriptionIds = Get-Content -Path $using:global:subscriptionFilePath | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' }
            $totalSubs = $subscriptionIds.Count
            $processed = 0
            
            foreach ($subId in $subscriptionIds) {
                try {
                    Set-AzContext -SubscriptionId $subId | Out-Null
                    $snapshots = Get-AzSnapshot | Where-Object { $_.Name -like "*$($using:txtFilter.Text)*" }
                    
                    foreach ($snapshot in $snapshots) {
                        try {
                            Remove-AzSnapshot -ResourceGroupName $snapshot.ResourceGroupName `
                                -SnapshotName $snapshot.Name -Force
                            $message = "Deleted $($snapshot.Name) in $subId"
                            [System.Windows.Forms.MessageBox]::Show($message) | Out-Null
                        }
                        catch {
                            $errorMsg = "Error deleting $($snapshot.Name): $_"
                            [System.Windows.Forms.MessageBox]::Show($errorMsg) | Out-Null
                        }
                    }
                }
                catch {
                    $errorMsg = "Error processing subscription $subId : $_"
                    [System.Windows.Forms.MessageBox]::Show($errorMsg) | Out-Null
                }
                
                $processed++
                $progress = ($processed / $totalSubs) * 100
                Write-Progress -Activity "Processing Subscriptions" -Status "$progress% Complete" -PercentComplete $progress
            }
        }
        
        if ($cleanupJob) {
            Register-ObjectEvent -InputObject $cleanupJob -EventName StateChanged -Action {
                if ($cleanupJob.State -eq 'Completed') {
                    $global:form.Invoke([Action]{
                        $btnStart.Enabled = $true
                        Update-Log "Cleanup process completed!"
                        $progressBar.Value = 0
                    })
                }
            } | Out-Null
        }
    }
})
