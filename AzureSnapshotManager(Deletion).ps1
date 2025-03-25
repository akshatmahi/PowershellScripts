Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Global Variables
$global:subscriptionFilePath = ".\subscriptions.txt"
$global:logFilePath = ".\SnapshotManagerLog.txt"
$global:results = @()
$global:form = $null

# Initialize Logging
Start-Transcript -Path $global:logFilePath

# Main Form
$global:form = New-Object System.Windows.Forms.Form
$global:form.Text = "Azure Snapshot Manager"
$global:form.Size = New-Object System.Drawing.Size(800,600)
$global:form.StartPosition = "CenterScreen"

# Snapshot Name Filter
$lblFilter = New-Object System.Windows.Forms.Label
$lblFilter.Location = New-Object System.Drawing.Point(20,20)
$lblFilter.Size = New-Object System.Drawing.Size(160,20)
$lblFilter.Text = "Snapshot Name Filter:"
$global:form.Controls.Add($lblFilter)

$txtFilter = New-Object System.Windows.Forms.TextBox
$txtFilter.Location = New-Object System.Drawing.Point(180,20)
$txtFilter.Size = New-Object System.Drawing.Size(200,20)
$global:form.Controls.Add($txtFilter)

# Subscription Management
$btnExportSubs = New-Object System.Windows.Forms.Button
$btnExportSubs.Location = New-Object System.Drawing.Point(20,60)
$btnExportSubs.Size = New-Object System.Drawing.Size(160,30)
$btnExportSubs.Text = "Export Subscriptions"
$btnExportSubs.Add_Click({
    try {
        Get-AzSubscription | Select-Object -ExpandProperty Id | Out-File $global:subscriptionFilePath
        Update-Log "Subscriptions exported to $global:subscriptionFilePath"
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Please login first!", "Error")
    }
})
$global:form.Controls.Add($btnExportSubs)

# Results Display
$txtResults = New-Object System.Windows.Forms.TextBox
$txtResults.Multiline = $true
$txtResults.ScrollBars = "Vertical"
$txtResults.Location = New-Object System.Drawing.Point(20,150)
$txtResults.Size = New-Object System.Drawing.Size(740,350)
$global:form.Controls.Add($txtResults)

# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20,510)
$progressBar.Size = New-Object System.Drawing.Size(740,20)
$global:form.Controls.Add($progressBar)

# Action Buttons
$btnLogin = New-Object System.Windows.Forms.Button
$btnLogin.Location = New-Object System.Drawing.Point(20,550)
$btnLogin.Size = New-Object System.Drawing.Size(100,30)
$btnLogin.Text = "Login"
$btnLogin.Add_Click({ Silent-Login })
$global:form.Controls.Add($btnLogin)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Location = New-Object System.Drawing.Point(140,550)
$btnStart.Size = New-Object System.Drawing.Size(100,30)
$btnStart.Text = "Start"
$btnStart.Add_Click({ Start-Process })
$global:form.Controls.Add($btnStart)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Location = New-Object System.Drawing.Point(260,550)
$btnCancel.Size = New-Object System.Drawing.Size(100,30)
$btnCancel.Text = "Cancel"
$btnCancel.Add_Click({ $global:form.Close() })
$global:form.Controls.Add($btnCancel)

# Functions
function Update-Log {
    param([string]$message)
    $txtResults.AppendText("$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $message`r`n")
}

function Silent-Login {
    try {
        Connect-AzAccount -ErrorAction Stop
        Update-Log "Login successful"
        $btnExportSubs.Enabled = $true
    } catch {
        Update-Log "Login failed: $_"
    }
}

function Start-Process {
    $snapshotNameFilter = $txtFilter.Text
    if(-not $snapshotNameFilter) {
        [System.Windows.Forms.MessageBox]::Show("Please enter a snapshot name filter!", "Warning")
        return
    }

    $confirmation = [System.Windows.Forms.MessageBox]::Show(
        "This will delete all snapshots matching '$snapshotNameFilter'. Continue?", 
        "Confirm", 
        [System.Windows.Forms.MessageBoxButtons]::YesNo
    )
    
    if($confirmation -eq "Yes") {
        $subscriptionIds = Get-Content -Path $global:subscriptionFilePath -ErrorAction SilentlyContinue | 
            Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' }
        
        if(-not $subscriptionIds) {
            Update-Log "No valid subscriptions found in $global:subscriptionFilePath"
            return
        }

        $progressBar.Maximum = $subscriptionIds.Count
        $serialNumber = 1

        foreach ($subId in $subscriptionIds) {
            try {
                Set-AzContext -SubscriptionId $subId | Out-Null
                $snapshots = Get-AzSnapshot | Where-Object { $_.Name -like "*$snapshotNameFilter*" }
                
                foreach ($snapshot in $snapshots) {
                    try {
                        Remove-AzSnapshot -ResourceGroupName $snapshot.ResourceGroupName `
                            -SnapshotName $snapshot.Name -Force
                        $global:results += [PSCustomObject]@{
                            SNo = $serialNumber++
                            Subscription = $subId
                            SnapshotName = $snapshot.Name
                            Status = "Deleted"
                        }
                        Update-Log "Deleted $($snapshot.Name) in $subId"
                    } catch {
                        $global:results += [PSCustomObject]@{
                            SNo = $serialNumber++
                            Subscription = $subId
                            SnapshotName = $snapshot.Name
                            Status = "Error: $_"
                        }
                        Update-Log "Error deleting $($snapshot.Name): $_"
                    }
                }
            } catch {
                Update-Log "Error processing subscription $subId : $_"
            }
            $progressBar.Value++
        }
        
        $global:results | Export-Csv -Path ".\SnapshotDeletionResults.csv" -NoTypeInformation
        Update-Log "Process completed. Results exported to CSV."
        $progressBar.Value = 0
    }
}

# Run the form
[void]$global:form.ShowDialog()
Stop-Transcript