<#
DL Manager
Author: Vikas Mahi
#>

# Configuration
$LogFile = "DL_Operations_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Show-Banner {
    Clear-Host
    Write-Host @"
    Distribution List Manager
"@ -ForegroundColor Cyan
}

function Connect-Exchange {
    try {
        if (-not (Get-Module -Name ExchangeOnlineManagement -ErrorAction SilentlyContinue)) {
            Write-Host "Loading Exchange Online module..." -ForegroundColor Yellow
            Import-Module ExchangeOnlineManagement -Force
        }
        
        Write-Host "`nConnecting to Exchange Online..." -ForegroundColor Yellow
        Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
        Write-Host "Connected successfully!" -ForegroundColor Green
    }
    catch {
        Write-Host "`nConnection Error: $($_.Exception.Message)" -ForegroundColor Red
        Exit
    }
}

function Get-UserInput {
    param($prompt)
    Write-Host "`n$prompt" -ForegroundColor Yellow
    Write-Host "Enter values (one per line, blank line to finish):" -ForegroundColor DarkGray
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
        $total = $users.Count
        $current = 0
        
        Write-Host "`nStarting $action operation..." -ForegroundColor Yellow
        foreach ($user in $users) {
            $current++
            $progress = ($current / $total) * 100
            Write-Progress -Activity "$action Members" -Status "Processing $user" `
                -PercentComplete $progress -CurrentOperation "$current of $total"
            
            try {
                & $cmd -Identity $dlGroup -Member $user -Confirm:$false -ErrorAction Stop
                "SUCCESS: $user" | Out-File $LogFile -Append
            }
            catch {
                "ERROR: $user - $($_.Exception.Message)" | Out-File $LogFile -Append
                Write-Host " - Error with $user: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
        
        Write-Host "`nOperation completed with details in log file:" -ForegroundColor Green
        Write-Host $LogFile -ForegroundColor DarkGray
    }
    catch {
        Write-Host "`nFatal Error: $($_.Exception.Message)" -ForegroundColor Red
        Exit
    }
}

# Main Execution
Show-Banner
Connect-Exchange

# Operation Selection
Write-Host "`n[1] Add members to DL" -ForegroundColor Cyan
Write-Host "[2] Remove members from DL`n" -ForegroundColor Cyan
$choice = Read-Host "Enter selection (1/2)"

# Validate input
if ($choice -notmatch '^[12]$') {
    Write-Host "Invalid selection!" -ForegroundColor Red
    Disconnect-ExchangeOnline -Confirm:$false | Out-Null
    Exit
}

# Get inputs
$dlGroup = Read-Host "`nEnter Distribution Group name"
$users = Get-UserInput -prompt "Enter user UPNs (one per line):"

# Execute operation
switch ($choice) {
    '1' { Invoke-DLOperation -action "Add" -dlGroup $dlGroup -users $users }
    '2' { Invoke-DLOperation -action "Remove" -dlGroup $dlGroup -users $users }
}

# Cleanup
Write-Host "`nDisconnecting session..." -ForegroundColor Yellow
Disconnect-ExchangeOnline -Confirm:$false | Out-Null
