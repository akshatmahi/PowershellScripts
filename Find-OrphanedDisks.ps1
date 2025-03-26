# Interactive browser login
Connect-AzAccount

# Import required modules
Import-Module Az.Accounts
Import-Module Az.Compute

# Ensure Az.CostManagement is installed
if (-not (Get-Module -ListAvailable -Name Az.CostManagement)) {
    Write-Host "Az.CostManagement module not found. Installing now..." -ForegroundColor Yellow
    Install-Module -Name Az.CostManagement -Scope CurrentUser -Force
}
Import-Module Az.CostManagement

# Ensure ImportExcel is installed
if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    Write-Host "ImportExcel module not found. Installing now..." -ForegroundColor Yellow
    Install-Module -Name ImportExcel -Scope CurrentUser -Force
}
Import-Module ImportExcel

# Define date ranges for cost retrieval
$today = Get-Date
$endDate = $today
$thirtyDaysAgo = $today.AddDays(-30)

# Function to query cost for a given resource and time period using Az.CostManagement
function Get-CostForResource {
    param (
        [Parameter(Mandatory=$true)]
        [string]$SubscriptionId,
        [Parameter(Mandatory=$true)]
        [string]$ResourceId,
        [Parameter(Mandatory=$true)]
        [datetime]$FromDate,
        [Parameter(Mandatory=$true)]
        [datetime]$ToDate
    )

    $query = @{
        type      = "ActualCost"
        timeframe = "Custom"
        timePeriod = @{
            from = $FromDate.ToString("yyyy-MM-dd")
            to   = $ToDate.ToString("yyyy-MM-dd")
        }
        dataset = @{
            granularity = "None"
            aggregation = @{
                totalCost = @{
                    name     = "Cost"
                    function = "Sum"
                }
            }
            filter = @{
                and = @(
                    @{
                        dimensions = @{
                            name     = "ResourceId"
                            operator = "In"
                            values   = @($ResourceId)
                        }
                    }
                )
            }
        }
    }

    # Increase the depth to ensure full JSON serialization
    $queryJson = $query | ConvertTo-Json -Depth 10

    try {
        $result = Get-AzCostManagementQuery -Scope "/subscriptions/$SubscriptionId" -Query $queryJson -ErrorAction Stop
        if ($result.Properties.rows -and $result.Properties.rows.Count -gt 0) {
            return [decimal]$result.Properties.rows[0][0]
        }
        else {
            return 0
        }
    }
    catch {
        Write-Verbose "Error querying cost for resource $($ResourceId): $_"
        return 0
    }
}

# Initialize the report collection
$report = [System.Collections.Generic.List[object]]::new()

# Process all accessible subscriptions
foreach ($sub in Get-AzSubscription) {
    # Set context to the current subscription
    Set-AzContext -Subscription $sub.Id | Out-Null

    # Retrieve unattached managed disks
    Get-AzDisk | Where-Object { $_.DiskState -eq 'Unattached' } | ForEach-Object {
        $disk = $_
        $resourceId = $disk.Id

        # Calculate cost for the last 30 days
        $costLast30Days = Get-CostForResource -SubscriptionId $sub.Id -ResourceId $resourceId -FromDate $thirtyDaysAgo -ToDate $endDate

        # Calculate cost since the last write (using TimeCreated as a proxy for last write)
        $costSinceLastWrite = Get-CostForResource -SubscriptionId $sub.Id -ResourceId $resourceId -FromDate $disk.TimeCreated -ToDate $endDate

        # Add disk info along with cost details to the report
        $report.Add([PSCustomObject]@{
            Subscription       = $sub.Name
            DiskName           = $disk.Name
            Type               = "Managed"
            ResourceGroup      = $disk.ResourceGroupName
            SizeGB             = $disk.DiskSizeGB
            Location           = $disk.Location
            LastWriteTime      = $disk.TimeCreated
            CostLast30Days     = $costLast30Days
            CostSinceLastWrite = $costSinceLastWrite
        })
    }
}

# Define the output Excel file path
$excelFilePath = Join-Path -Path (Get-Location) -ChildPath "OrphanedDisks_Report.xlsx"

# Export the report to an Excel file without converting the data into an Excel table.
# This avoids the automatic creation of features (AutoFilter, Table) that Excel later removes.
$report | Export-Excel -Path $excelFilePath -AutoSize -TableStyle "None"

Write-Host "Report generated: $excelFilePath" -ForegroundColor Green
