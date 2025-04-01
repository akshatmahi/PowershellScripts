# ... (previous code remains the same)

    # User Input
    $labelUser = New-Object System.Windows.Forms.Label
    $labelUser.Text = "Enter UPNs (one per line):"
    $labelUser.Location = New-Object System.Drawing.Point(15, 30)
    $labelUser.AutoSize = $true

    $textboxUsers = New-Object System.Windows.Forms.TextBox
    $textboxUsers.Location = New-Object System.Drawing.Point(15, 50)
    $textboxUsers.Size = New-Object System.Drawing.Size(420, 60)  # Increased height
    $textboxUsers.Multiline = $true                               # Enabled multi-line
    $textboxUsers.ScrollBars = "Vertical"                         # Add scrollbars

    # DL Input
    $labelDL = New-Object System.Windows.Forms.Label
    $labelDL.Text = "Target Distribution List:"
    $labelDL.Location = New-Object System.Drawing.Point(15, 120)  # Moved down
    $labelDL.AutoSize = $true

    $textboxDL = New-Object System.Windows.Forms.TextBox
    $textboxDL.Location = New-Object System.Drawing.Point(15, 140) # Moved down
    $textboxDL.Size = New-Object System.Drawing.Size(420, 20)

    # Action Buttons
    $btnAdd = New-Object System.Windows.Forms.Button
    $btnAdd.Text = "Add Members"
    $btnAdd.Location = New-Object System.Drawing.Point(15, 170)    # Moved down
    $btnAdd.Size = New-Object System.Drawing.Size(100, 30)

    $btnRemove = New-Object System.Windows.Forms.Button
    $btnRemove.Text = "Remove Members"
    $btnRemove.Location = New-Object System.Drawing.Point(135, 170) # Moved down
    $btnRemove.Size = New-Object System.Drawing.Size(120, 30)

# ... (remaining code)

    # Modified Input Processing
    $executeOperation = {
        param($action)
        # Split by newlines and clean empty entries
        $users = $textboxUsers.Text.Trim() -split "`r`n|`n" | 
                ForEach-Object { $_.Trim() } | 
                Where-Object { $_ -ne "" }
        
        $dlName = $textboxDL.Text.Trim()
        $logFile = "DL_Operations_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# ... (remaining code remains the same)
