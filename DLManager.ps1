<#
DL Manager v3.0
Author: Vikas Mahi
Features:
- Simple text-based interface
- Exchange Online authentication
- Multi-line user input
- Activity logging
- Error handling
#>

# Configuration
$LogFile = "DL_Operations_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Show-Banner {
    Clear-Host
    Write-Host @"
    
    ██████╗ ██╗      ███╗   ███╗ ██████╗ 
    ██╔══██╗██║      ████╗ ████║██╔═══██╗
    ██║  ██║██║█████╗██╔████╔██║██║   ██║
    ██║  ██║██║╚════╝██║╚██╔╝██║██║   ██║
    ██████╔╝██║      ██║ ╚═╝ ██║╚██████╔╝
    ╚═════╝ ╚═╝      ╚═╝     ╚═╝ ╚═════╝ 
          Distribution List Manager v3.0
"@ -ForegroundColor Cyan
}

function Connect-Exchange {
    try {
        # Check if EXO module is installed
        if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
            Write-Host "Installing Exchange Online module..." -ForegroundColor Yellow
            Install-Module ExchangeOnlineManagement -Force -Scope CurrentUser
        }

        # Connect to Exchange Online
        Write-Host "`nConnecting to Exchange Online..." -ForegroundColor Yellow
        Connect-ExchangeOnline -ShowBanner:$false
        Write-Host "Connected successfully!" -ForegroundColor Green
    }
    catch {
        Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
        Exit
    }
}

function Get-UserInput {
    param($prompt)
    Write-Host "`n$prompt" -ForegroundColor Yellow
    Write-Host "Enter values (press Enter twice to finish):" -ForegroundColor DarkGray
    $inputValues = @()
    do {
        $line = Read-Host
        if ($line.Trim()) { $inputValues += $line.Trim() }
    } while ($line -ne "")
    return $inputValues
}

function Invoke-DLOperation {
    param($action, $dlGroup, $users)
    try {
        $cmd = $action + "-DistributionGroupMember"
        $batch = $users -join ","
        
        Write-Host "`nExecuting $action operation..." -ForegroundColor Yellow
        Invoke-Command -ScriptBlock {
            & $cmd -Identity $dlGroup -Members $batch -Confirm:$false -ErrorAction Stop
        }

        # Log results
        "SUCCESS: $action operation completed for $dlGroup at $(Get-Date)" | Out-File $LogFile -Append
        $users | ForEach-Object { "Processed: $_" | Out-File $LogFile -Append }
        
        Write-Host "`nOperation completed successfully!" -ForegroundColor Green
        Write-Host "Log file created: $LogFile" -ForegroundColor DarkGray
    }
    catch {
        "ERROR: $($_.Exception.Message)" | Out-File $LogFile -Append
        Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Main Execution
Show-Banner

# Authentication
Connect-Exchange

# Operation Selection
Write-Host "`nOperation Menu:" -ForegroundColor Yellow
Write-Host "1. Add members to DL" -ForegroundColor Cyan
Write-Host "2. Remove members from DL" -ForegroundColor Cyan
$choice = Read-Host "`nEnter your choice (1/2)"

# Validate choice
if ($choice -notin @('1','2')) {
    Write-Host "Invalid selection!" -ForegroundColor Red
    Exit
}

# Get inputs
$dlGroup = Read-Host "`nEnter Distribution Group name"
$users = Get-UserInput -prompt "Enter user UPNs to process:"

# Execute operation
switch ($choice) {
    '1' { Invoke-DLOperation -action "Add" -dlGroup $dlGroup -users $users }
    '2' { Invoke-DLOperation -action "Remove" -dlGroup $dlGroup -users $users }
}

# Cleanup
Write-Host "`nDisconnecting session..." -ForegroundColor Yellow
Disconnect-ExchangeOnline -Confirm:$false | Out-Null
