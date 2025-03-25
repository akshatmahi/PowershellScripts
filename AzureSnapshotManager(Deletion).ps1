Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Check for Azure Module
if (-not (Get-Module Az -ListAvailable)) {
    $result = [System.Windows.Forms.MessageBox]::Show(
        "Azure PowerShell module is required. Install now?",
        "Module Missing",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    
    if ($result -eq "Yes") {
        Start-Process powershell -ArgumentList "Install-Module Az -Scope CurrentUser -Force -AllowClobber" -Verb RunAs
    }
    exit
}

# Global Variables
$global:subscriptionFilePath = Join-Path $PSScriptRoot "subscriptions.txt"
$global:logFilePath = Join-Path $PSScriptRoot "SnapshotManagerLog.txt"
$global:form = $null
$global:jobs = [System.Collections.ArrayList]::new()

# Main Form Configuration
$global:form = New-Object System.Windows.Forms.Form
$global:form.Text = "Azure Snapshot Manager v4.0"
$global:form.Size = New-Object System.Drawing.Size(800, 600)
$global:form.StartPosition = "CenterScreen"
$global:form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$global:form.MinimizeBox = $false
$global:form.MaximizeBox = $false

# UI Layout
$mainLayout = New-Object System.Windows.Forms.TableLayoutPanel
$mainLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainLayout.ColumnCount = 1
$mainLayout.RowCount = 5
$global:form.Controls.Add($mainLayout)

# Authentication Section
$authGroup = New-Object System.Windows.Forms.GroupBox
$authGroup.Text = "Step 1: Azure Authentication"
$authGroup.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainLayout.Controls.Add($authGroup)

$btnLogin = New-Object System.Windows.Forms.Button
$btnLogin.Text = "Connect to Azure"
$btnLogin.Size = New-Object System.Drawing.Size(150, 30)
$btnLogin.Location = New-Object System.Drawing.Point(20, 20)
$authGroup.Controls.Add($btnLogin)

# Subscription Management
$subGroup = New-Object System.Windows.Forms.GroupBox
$subGroup.Text = "Step 2: Subscription Export"
$subGroup.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainLayout.Controls.Add($subGroup)

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = "Export Subscriptions"
$btnExport.Size = New-Object System.Drawing.Size(150, 30)
$btnExport.Location = New-Object System.Drawing.Point(20, 20)
$btnExport.Enabled = $false
$subGroup.Controls.Add($btnExport)

# Snapshot Filter
$filterGroup = New-Object System.Windows.Forms.GroupBox
$filterGroup.Text = "Step 3: Snapshot Filter"
$filterGroup.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainLayout.Controls.Add($filterGroup)

$txtFilter = New-Object System.Windows.Forms.TextBox
$txtFilter.Location = New-Object System.Drawing.Point(20, 20)
$txtFilter.Size = New-Object System.Drawing.Size(300, 20)
$txtFilter.Enabled = $false
$filterGroup.Controls.Add($txtFilter)

# Progress Section
$progressGroup = New-Object System.Windows.Forms.GroupBox
$progressGroup.Text = "Progress"
$progressGroup.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainLayout.Controls.Add($progressGroup)

$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Dock = [System.Windows.Forms.DockStyle]::Top
$progressBar.Height = 20
$progressGroup.Controls.Add($progressBar)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = "Vertical"
$progressGroup.Controls.Add($txtLog)

# Action Controls
$actionPanel = New-Object System.Windows.Forms.Panel
$actionPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainLayout.Controls.Add($actionPanel)

$btnStart = New-Object System.Windows.Forms.Button
$btnStart.Text = "Start Cleanup"
$btnStart.Size = New-Object System.Drawing.Size(100, 30)
$btnStart.Location = New-Object System.Drawing.Point(20, 10)
$btnStart.Enabled = $false
$actionPanel.Controls.Add($btnStart)

$btnCopy = New-Object System.Windows.Forms.Button
$btnCopy.Text = "Copy Log"
$btnCopy.Size = New-Object System.Drawing.Size(100, 30)
$btnCopy.Location = New-Object System.Drawing.Point(140, 10)
$actionPanel.Controls.Add($btnCopy)

$btnExit = New-Object System.Windows.Forms.Button
$btnExit.Text = "Exit"
$btnExit.Size = New-Object System.Drawing.Size(100, 30)
$btnExit.Location = New-Object System.Drawing.Point(260, 10)
$actionPanel.Controls.Add($btnExit)

# Functions
function Update-Log {
    param([string]$message)
    $global:form.Invoke([action]{
        $txtLog.AppendText("$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $message`r`n")
    })
}

function Update-Progress {
    param([int]$percent)
    $global:form.Invoke([action]{
        $progressBar.Value = $percent
    })
}

function Reset-UI {
    $global:form.Invoke([action]{
        $btnLogin.Enabled = $true
        $btnExport.Enabled = $false
        $txtFilter.Enabled = $false
        $btnStart.Enabled = $false
        $progressBar.Value = 0
    })
}

# Event Handlers
$btnLogin.Add_Click({
    $btnLogin.Enabled = $false
    Update-Log "Initiating Azure authentication..."
    
    try {
        $authJob = Start-Job -ScriptBlock {
            Connect-AzAccount
        }
        
        $global:jobs.Add($authJob) | Out-Null
        
        Register-ObjectEvent -InputObject $authJob -EventName StateChanged -Action {
            if ($authJob.State -eq "Completed") {
                Update-Log "Authentication successful!"
                $global:form.Invoke({ $btnExport.Enabled = $true })
                $global:jobs.Remove($authJob)
            }
            elseif ($authJob.State -eq "Failed") {
                Update-Log "Authentication failed"
                Reset-UI
            }
        } | Out-Null
    }
    catch {
        Update-Log "Error initiating authentication: $_"
        Reset-UI
    }
})

$btnExport.Add_Click({
    try {
        Get-AzSubscription | Select-Object -ExpandProperty Id | Out-File $global:subscriptionFilePath
        Update-Log "Subscriptions exported to $global:subscriptionFilePath"
        $txtFilter.Enabled = $true
    }
    catch {
        Update-Log "Error exporting subscriptions: $_"
    }
})

$txtFilter.Add_TextChanged({
    $btnStart.Enabled = (-not [string]::IsNullOrWhiteSpace($txtFilter.Text))
})

$btnStart.Add_Click({
    $confirmation = [System.Windows.Forms.MessageBox]::Show(
        "This will permanently delete all snapshots matching: '$($txtFilter.Text)'. Continue?",
        "Confirm Deletion",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    
    if ($confirmation -eq "Yes") {
        $btnStart.Enabled = $false
        $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Marquee
        
        $cleanupJob = Start-Job -ScriptBlock {
            Import-Module Az
            $subs = Get-Content $using:global:subscriptionFilePath
            $total = $subs.Count
            $processed = 0
            
            foreach ($sub in $subs) {
                try {
                    Set-AzContext -SubscriptionId $sub | Out-Null
                    $snapshots = Get-AzSnapshot | Where-Object Name -like "*$($using:txtFilter.Text)*"
                    
                    foreach ($snap in $snapshots) {
                        Remove-AzSnapshot -ResourceGroupName $snap.ResourceGroupName `
                            -SnapshotName $snap.Name -Force
                    }
                    
                    $processed++
                    [Math]::Round(($processed / $total) * 100)
                }
                catch {
                    Write-Error $_
                }
            }
        }
        
        $global:jobs.Add($cleanupJob) | Out-Null
        
        Register-ObjectEvent -InputObject $cleanupJob -EventName StateChanged -Action {
            if ($cleanupJob.State -eq "Completed") {
                Update-Log "Cleanup process completed"
                $global:form.Invoke({
                    $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
                    $progressBar.Value = 100
                    $btnStart.Enabled = $true
                })
                $global:jobs.Remove($cleanupJob)
            }
        } | Out-Null
    }
})

$btnCopy.Add_Click({
    [System.Windows.Forms.Clipboard]::SetText($txtLog.Text)
    Update-Log "Log contents copied to clipboard"
})

$btnExit.Add_Click({
    if ($global:jobs.Count -gt 0) {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Active operations are running. Exit anyway?",
            "Confirm Exit",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        
        if ($confirm -eq "Yes") {
            $global:jobs | Stop-Job
            $global:form.Close()
        }
    }
    else {
        $global:form.Close()
    }
})

# Initialize
Start-Transcript -Path $global:logFilePath
[void]$global:form.ShowDialog()
Stop-Transcript
