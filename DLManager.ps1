<#
Distribution List Manager
Author: Vikas Mahi
#>

$LogFile = "DL_Operations_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Connect-Exchange {
    try {
        if (-not (Get-Module -Name ExchangeOnlineManagement -ErrorAction SilentlyContinue)) {
            Import-Module ExchangeOnlineManagement -Force
        }
        Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
    }
    catch {
        Write-Host "Connection Error: $($_.Exception.Message)" -ForegroundColor Red
        Exit
    }
}

function Invoke-DLOperation {
    param($action, $dlGroup, $users)
    try {
        $cmd = $action + "-DistributionGroupMember"
        foreach ($user in $users) {
            try {
                & $cmd -Identity $dlGroup -Member $user -Confirm:$false -ErrorAction Stop
                "SUCCESS: $user" | Out-File $LogFile -Append
                Write-Host "[+] $user" -ForegroundColor Green
            }
            catch {
                "ERROR: $user - $($_.Exception.Message)" | Out-File $LogFile -Append
                Write-Host "[-] $user : $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
    catch {
        Write-Host "Fatal Error: $($_.Exception.Message)" -ForegroundColor Red
        Exit
    }
}

# Main Execution
Clear-Host
Write-Host "`nDistribution List Manager`n" -ForegroundColor Cyan

# Authentication
Connect-Exchange

# Operation Selection
$choice = Read-Host @"
Select operation:
1. Add members
2. Remove members
Choice (1/2)
"@

# Validate input
if ($choice -notmatch '^[12]$') {
    Write-Host "Invalid selection!" -ForegroundColor Red
    Disconnect-ExchangeOnline -Confirm:$false | Out-Null
    Exit
}

# Get inputs
$dlGroup = Read-Host "`nEnter Distribution Group name"
Write-Host "`nEnter user UPNs (one per line, blank line to finish):" -ForegroundColor DarkGray
$users = @()
do {
    $line = Read-Host
    if ($line.Trim()) { $users += $line.Trim() }
} while ($line -ne "")

# Execute operation
switch ($choice) {
    '1' { Invoke-DLOperation -action "Add" -dlGroup $dlGroup -users $users }
    '2' { Invoke-DLOperation -action "Remove" -dlGroup $dlGroup -users $users }
}

# Cleanup
Disconnect-ExchangeOnline -Confirm:$false | Out-Null
Write-Host "`nOperation completed. Log file: $LogFile`n" -ForegroundColor Cyan
