<# USER MANAGEMENT SCRIPT v2.1 #>
<# FEATURES:
- Multi-line user input support
- Improved UI layout with vertical spacing
- Input validation and error handling
- Activity logging
#>

try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    public class MsgBox {
        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern int MessageBox(IntPtr hWnd, String text, String caption, int options);
    }
"@

    # GUI VERSION
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "DL Manager v2.1"
    $form.Size = New-Object System.Drawing.Size(500, 400)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog

    # Input Group
    $groupBox = New-Object System.Windows.Forms.GroupBox
    $groupBox.Text = "Distribution List Operations"
    $groupBox.Location = New-Object System.Drawing.Point(10, 10)
    $groupBox.Size = New-Object System.Drawing.Size(460, 250)

    # User Input
    $labelUser = New-Object System.Windows.Forms.Label
    $labelUser.Text = "Enter UPNs (one per line):"
    $labelUser.Location = New-Object System.Drawing.Point(15, 30)
    $labelUser.AutoSize = $true

    $textboxUsers = New-Object System.Windows.Forms.TextBox
    $textboxUsers.Location = New-Object System.Drawing.Point(15, 50)
    $textboxUsers.Size = New-Object System.Drawing.Size(420, 60)
    $textboxUsers.Multiline = $true
    $textboxUsers.ScrollBars = "Vertical"

    # DL Input
    $labelDL = New-Object System.Windows.Forms.Label
    $labelDL.Text = "Target Distribution List:"
    $labelDL.Location = New-Object System.Drawing.Point(15, 120)
    $labelDL.AutoSize = $true

    $textboxDL = New-Object System.Windows.Forms.TextBox
    $textboxDL.Location = New-Object System.Drawing.Point(15, 140)
    $textboxDL.Size = New-Object System.Drawing.Size(420, 20)

    # Action Buttons
    $btnAdd = New-Object System.Windows.Forms.Button
    $btnAdd.Text = "Add Members"
    $btnAdd.Location = New-Object System.Drawing.Point(15, 170)
    $btnAdd.Size = New-Object System.Drawing.Size(100, 30)

    $btnRemove = New-Object System.Windows.Forms.Button
    $btnRemove.Text = "Remove Members"
    $btnRemove.Location = New-Object System.Drawing.Point(135, 170)
    $btnRemove.Size = New-Object System.Drawing.Size(120, 30)

    # Status Bar
    $statusBar = New-Object System.Windows.Forms.StatusBar
    $statusBar.Text = "Ready"
    
    # Add controls
    $groupBox.Controls.AddRange(@($labelUser, $textboxUsers, $labelDL, $textboxDL, $btnAdd, $btnRemove))
    $form.Controls.Add($groupBox)
    $form.Controls.Add($statusBar)

    # Input Validation
    $validateInputs = {
        $btnAdd.Enabled = $btnRemove.Enabled = (
            $textboxUsers.Text.Trim() -ne "" -and 
            $textboxDL.Text.Trim() -ne ""
        )
    }

    $textboxUsers.Add_TextChanged($validateInputs)
    $textboxDL.Add_TextChanged($validateInputs)

    # Button Actions
    $executeOperation = {
        param($action)
        # Process multi-line input
        $users = $textboxUsers.Text.Trim() -split "`r`n|`n" | 
                ForEach-Object { $_.Trim() } | 
                Where-Object { $_ -ne "" }
        
        $dlName = $textboxDL.Text.Trim()
        $logFile = "DL_Operations_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

        try {
            $statusBar.Text = "Executing $action operation..."
            $command = "$action-DistributionGroupMember -Identity '$dlName' -Members " + ($users -join ',') + " -Confirm:`$false"
            $result = Invoke-Expression $command *>&1
            
            $result | Out-File $logFile -Append
            [MsgBox]::MessageBox([IntPtr]::Zero, "Operation completed. Log saved to $logFile", "Success", 0)
        }
        catch {
            $errorMessage = $_.Exception.Message
            $statusBar.Text = "Error: $errorMessage"
            [MsgBox]::MessageBox([IntPtr]::Zero, "Operation failed: $errorMessage", "Error", 0)
        }
        finally {
            $statusBar.Text = "Ready"
        }
    }

    $btnAdd.Add_Click({ & $executeOperation 'Add' })
    $btnRemove.Add_Click({ & $executeOperation 'Remove' })

    $form.ShowDialog() | Out-Null
}
catch {
    # TEXT-BASED FALLBACK
    Write-Host "GUI unavailable. Switching to text mode..."
    $users = Read-Host "Enter UPNs (comma-separated)"
    $dlName = Read-Host "Enter Distribution List name"
    
    $action = Read-Host "Choose action (A)dd/(R)emove"
    $logFile = "DL_Operations_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
    
    try {
        $command = @{
            'A' = 'Add-DistributionGroupMember'
            'R' = 'Remove-DistributionGroupMember'
        }[$action.ToUpper()[0]]
        
        if (-not $command) { throw "Invalid action selected" }
        
        $users -split ',' | ForEach-Object {
            $user = $_.Trim()
            Invoke-Expression "$command -Identity '$dlName' -Member '$user' -Confirm:`$false" *>&1 | 
                Tee-Object -FilePath $logFile -Append
        }
        
        Write-Host "Operation completed. Log saved to $logFile"
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)"
    }
}
