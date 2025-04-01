<#
Distribution List Manager - Optimized
Author: Vikas Mahi
#>

$LogFile = "DL_Operations_$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$BatchSize = 250  # Optimal batch size for Exchange Online operations

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

function Invoke-BatchOperation {
    param($cmd, $dlGroup, $batch)
    try {
        & $cmd -Identity $dlGroup -Members $batch -Confirm:$false -ErrorAction Stop
        $batch | ForEach-Object {
            "SUCCESS: $_" | Out-File $LogFile -Append
            Write-Host "[+] $_" -ForegroundColor Green
        }
        return $true
    }
    catch {
        $errorMsg = $_.Exception.Message
        "BATCH ERROR: $errorMsg" | Out-File $LogFile -Append
        
        # Parse individual errors from message
        $pattern = "'([\w\.\-@]+)'"
        $failedUsers = [regex]::Matches($errorMsg, $pattern).Groups[1].Value | Select-Object -Unique
        
        if ($failedUsers) {
            $failedUsers | ForEach-Object {
                "FAILED: $_" | Out-File $LogFile -Append
                Write-Host "[-] $_" -ForegroundColor Red
            }
            # Retry successful users from batch
            $successUsers = $batch | Where-Object { $_ -notin $failedUsers }
            if ($successUsers) {
                Invoke-BatchOperation $cmd $dlGroup $successUsers
            }
        }
        else {
            Write-Host "[-] Batch failed: $errorMsg" -ForegroundColor Red
        }
        return $false
    }
}

function Invoke-DLOperation {
    param($action, $dlGroup, $users)
    $cmd = $action + "-DistributionGroupMember"
    $totalUsers = $users.Count
    $processed = 0

    # Process in batches
    0..($users.Count/$BatchSize) | ForEach-Object {
        $batch = $users[$processed..($processed + $BatchSize - 1)]
        $processed += $batch.Count
        
        Write-Host "Processing batch $($_ + 1) ($($batch.Count) users)" -ForegroundColor Cyan
        Invoke-BatchOperation $cmd $dlGroup $batch | Out-Null
    }
}

# Main Execution
Clear-Host
Write-Host "`nDistribution List Manager (Optimized)`n" -ForegroundColor Cyan

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
$operation = @('Add', 'Remove')[$choice - 1]
Invoke-DLOperation -action $operation -dlGroup $dlGroup -users $users

# Cleanup
Disconnect-ExchangeOnline -Confirm:$false | Out-Null
Write-Host "`nOperation completed. Log file: $LogFile`n" -ForegroundColor Cyan
