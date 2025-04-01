<#
Distribution List Manager - Fast Input Version
Author: Vikas Mahi
#>

$LogFile = "DL_Operations_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Connect-Exchange {
    try {
        if (-not (Get-Module -Name ExchangeOnlineManagement -ErrorAction SilentlyContinue)) {
            Import-Module ExchangeOnlineManagement -Force
        }
        Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Host "Connection Error: $($_.Exception.Message)" -ForegroundColor Red
        Exit
    }
}

function Invoke-DLOperation {
    param($action, $dlGroup, $users)
    $cmd = $action + "-DistributionGroupMember"
    
    # Start timing
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    
    foreach ($user in $users) {
        try {
            & $cmd -Identity $dlGroup -Member $user -Confirm:$false -ErrorAction Stop
            Add-Content $LogFile -Value "SUCCESS: $user"
        }
        catch {
            Add-Content $LogFile -Value "ERROR: $user - $($_.Exception.Message)"
            Write-Host " - Error with $user: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
    
    # Show performance summary
    $sw.Stop()
    Write-Host "Processed $($users.Count) users in $($sw.Elapsed.TotalSeconds.ToString('0.00')) seconds"
}

# Main Execution
Clear-Host
Write-Host "`nDistribution List Manager`n" -ForegroundColor Cyan

# Authentication
Connect-Exchange

# Fast operation selection
$choice = $null
while ($choice -notin '1','2') {
    $choice = Read-Host @"
Select operation (1-2):
1. Add members
2. Remove members
"@
}

# Bulk input for UPNs
$dlGroup = Read-Host "`nEnter Distribution Group name"
Write-Host "`nPaste user UPNs (one per line) and press Enter:" -ForegroundColor Yellow
[Console]::TreatControlCAsInput = $true
$inputText = $Host.UI.ReadLine() -replace "^","`n"  # Allow multi-line paste

# Process input
$users = $inputText.Trim() -split "`r`n|`n|," | 
         Where-Object { $_ -ne "" } | 
         ForEach-Object { $_.Trim() }

# Execute operation
if ($users.Count -gt 0) {
    $operation = @('Add', 'Remove')[$choice - 1]
    Invoke-DLOperation -action $operation -dlGroup $dlGroup -users $users
}
else {
    Write-Host "No valid users provided!" -ForegroundColor Red
}

# Cleanup
Disconnect-ExchangeOnline -Confirm:$false | Out-Null
Write-Host "`nOperation completed. Log file: $LogFile`n" -ForegroundColor Cyan
