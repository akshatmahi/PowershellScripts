Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Global Variables
$global:subscriptionFilePath = ".\subscriptions.txt"
$global:logFilePath = ".\SnapshotManagerLog.txt"
$global:results = @()
$global:form = $null

# Initialize Logging
Start-Transcript -Path $global:logFilePath

# Main Form Configuration
$global:form = New-Object System.Windows.Forms.Form
$global:form.Text = "Azure Snapshot Manager v3.0"
$global:form.Size = New-Object System.Drawing.Size(800,600)
$global:form.StartPosition = "CenterScreen"
$global:form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$global:form.MinimizeBox = $false
$global:form.MaximizeBox = $false

# UI Layout Table
$tableLayout = New-Object System.Windows.Forms.TableLayoutPanel
$tableLayout.ColumnCount = 2
$tableLayout.RowCount = 5
$tableLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$tableLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 30)))
$tableLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 70)))
$global:form.Controls.Add($tableLayout)

# Step 1: Login Section
$loginGroup = New-Object System.Windows.Forms.GroupBox
$loginGroup.Text = "Step 1: Azure Authentication"
$loginGroup.Dock = [System.Windows.Forms.DockStyle]::Fill
$tableLayout.Controls.Add($loginGroup, 0, 0)
$tableLayout.SetColumnSpan($loginGroup, 2)

$btnLogin = New-Object System.Windows.Forms.Button
$btnLogin.Text = "Connect to Azure"
$btnLogin.Size = New-Object System.Drawing.Size(150,30)
$btnLogin.Location = New-Object System.Drawing.Point(20,20)
$btnLogin.Add_Click({ Start-Job -ScriptBlock { Connect-AzAccount } -Name "AzureLogin" })
$loginGroup.Controls.Add($btnLogin)

# Step 2: Subscription Management
$subGroup = New-Object System.Windows.Forms.GroupBox
$subGroup.Text = "Step 2: Subscription Management"
$subGroup.Dock = [System.Windows.Forms.DockStyle]::Fill
$tableLayout.Controls.Add($subGroup, 0, 1)
$tableLayout.SetColumnSpan($subGroup, 2)

$btnExportSubs = New-Object System.Windows.Forms.Button
$btnExportSubs.Text = "Export Subscriptions"
$btnExportSubs.Size = New-Object System.Drawing.Size(150,30)
$btnExportSubs.Location = New-Object System.Drawing.Point(20,20)
$btnExportSubs.Enabled = $false
$btnExportSubs.Add_Click({
    try {
        Get-AzSubscription | Select-Object -ExpandProperty Id | Out-File $global:subscriptionFilePath
        Update-Log "Subscriptions exported to $global:subscriptionFilePath"
        $txtFilter.Enabled = $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Please login first!", "Error")
    }
})
$subGroup.Controls.Add($btnExportSubs)

# Step 3: Snapshot Filter
$filterGroup = New-Object System.Windows.Forms.GroupBox
$filterGroup.Text = "Step 3: Specify Snapshot Filter"
$filterGroup.Dock = [System.Windows.Forms.DockStyle]::Fill
$tableLayout.Controls.Add($filterGroup, 0, 2)
$tableLayout.SetColumnSpan($filterGroup, 2)

$lblFilter = New-Object System.Windows.Forms.Label
$lblFilter.Text = "Snapshot name pattern:"
$lblFilter.Location = New-Object System.Drawing.Point(20,25)
$filterGroup.Controls.Add($lblFilter)

$txtFilter = New-Object System.Windows.Forms.TextBox
$txtFilter.Location = New-Object System.Drawing.Point(160,20)
$txtFilter.Size = New-Object System.Drawing.Size(200,20)
$txtFilter.Enabled = $false
$filterGroup.Controls.Add($txtFilter)

# Progress and Results
$progressGroup = New-Object System.Windows.Forms.GroupBox
$progressGroup.Text = "Progress & Results"
$progressGroup.Dock = [System.Windows.Forms.DockStyle]::Fill
$tableLayout.Controls.Add($progressGroup, 0, 3)
$tableLayout.SetColumnSpan($progressGroup, 2)

$txtResults = New-Object System.Windows.Forms.TextBox
$txtResults.Multiline = $true
$txtResults.ScrollBars = "Vertical"
$txtResults.Dock = [System.Windows.Forms.DockStyle]::Fill
$progressGroup.Controls.Add($txtResults)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Dock = [System.Windows.Forms.DockStyle]::Bottom
$progressBar.Height = 20
$progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
$progressGroup.Controls.Add($progressBar)

# Action Controls
$actionPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$actionPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$actionPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::RightToLeft
$tableLayout.Controls.Add($actionPanel, 0, 4)
$tableLayout.SetColumnSpan($actionPanel, 2)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start Cleanup"
$btnStart.Size = New-Object System.Drawing.Size(120,30)
$btnStart.Enabled = $false
$btnStart.BackColor = [System.Drawing.Color]::LightGreen
$actionPanel.Controls.Add($btnStart)

$btnCancel = New-Object System.Windows.Forms.Button
$btnCancel.Text = "Exit"
$btnCancel.Size = New-Object System.Drawing.Size(120,30)
$btnCancel.Add_Click({ $global:form.Close() })
$actionPanel.Controls.Add($btnCancel)

# Functions
function Update-Log {
    param([string]$message)
    $global:form.Invoke([Action]{
        $txtResults.AppendText("$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $message`r`n")
    })
}

function Update-Progress {
    param([int]$value)
    $global:form.Invoke([Action]{ $progressBar.Value = $value })
}

# Event Handlers
$btnLogin.Add_Click({
    Start-Job -ScriptBlock { Connect-AzAccount } -Name "AzureLogin"
    Update-Log "Starting Azure authentication..."
})

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
        Start-ThreadJob -ScriptBlock {
            $subscriptionIds = Get-Content -Path $global:subscriptionFilePath | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' }
            $progressBar.Maximum = $subscriptionIds.Count
            
            foreach ($subId in $subscriptionIds) {
                try {
                    Set-AzContext -SubscriptionId $subId | Out-Null
                    $snapshots = Get-AzSnapshot | Where-Object { $_.Name -like "*$($using:txtFilter.Text)*" }
                    
                    foreach ($snapshot in $snapshots) {
                        try {
                            Remove-AzSnapshot -ResourceGroupName $snapshot.ResourceGroupName `
                                -SnapshotName $snapshot.Name -Force
                            Update-Log "Deleted $($snapshot.Name) in $subId"
                        } catch {
                            Update-Log "Error deleting $($snapshot.Name): $_"
                        }
                    }
                } catch {
                    Update-Log "Error processing subscription $subId : $_"
                }
                Update-Progress (++$script:currentProgress)
            }
        }
    }
})

# Status Check Timer
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    if (Get-Job -Name "AzureLogin" -ErrorAction SilentlyContinue) {
        if ((Get-Job "AzureLogin").State -eq "Completed") {
            $btnExportSubs.Enabled = $true
            $btnLogin.Enabled = $false
            Update-Log "Authentication successful!"
            Remove-Job -Name "AzureLogin"
        }
    }
})
$timer.Start()

# Run the form
[void]$global:form.ShowDialog()
Stop-Transcript
