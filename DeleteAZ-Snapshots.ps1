# Assuming Azure PowerShell module is already installed and automation accounts have necessary permissions for login
Start-Transcript -Path ".\Logs.txt"

# Interactive login (Azure portal login)
Function Silent-Login {
    Connect-AzAccount
}

# Function to silently set subscription context
Function Silent-SetSubscriptionContext($subscriptionId) {
    try {
        if ($subscriptionId) {
            $null = Set-AzContext -SubscriptionId $subscriptionId
            Write-Host "Context set to subscription: $subscriptionId"
        } else {
            Write-Host "Skipping empty subscription ID."
        }
    } catch {
        Write-Host "Error: Unable to set context for subscription $subscriptionId"
        return
    }
}

# Script starts here

# Silent login via Azure portal authentication
Silent-Login

# Path where subscription IDs will be exported
$subscriptionFilePath = ".\export.txt"

# Clean the file to remove unwanted content (like headers and separators)
$subscriptionIds = Get-Content -Path $subscriptionFilePath | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' } 

# If no valid subscription IDs are found, stop the script
if ($subscriptionIds.Count -eq 0) {
    Write-Host "No valid subscription IDs found in $subscriptionFilePath"
    Stop-Transcript
    return
}

# Prompt user to enter the snapshot name(s) (or part of the name)
$snapshotNameFilter = Read-Host "Enter the snapshot name (or part of it) to search for"

# Prepare an array to store results
$results = @()

# Ask for one-time confirmation before deletion
$confirmation = Read-Host "Do you want to delete all matching snapshots? (Y/N)"

# Proceed only if the user confirms
if ($confirmation -eq 'Y' -or $confirmation -eq 'y') {
    Write-Host "Proceeding with snapshot deletion..."

    # Script starts processing each subscription
    $serialNumber = 1

    foreach ($subscriptionId in $subscriptionIds) {
        $subscriptionId = $subscriptionId.Trim() # Remove any whitespace

        # Set subscription context silently
        Silent-SetSubscriptionContext -subscriptionId $subscriptionId

        # Retrieve and filter snapshots based on user input
        try {
            $snapshots = Get-AzSnapshot | Where-Object { $_.Name -like "*$snapshotNameFilter*" }
        } catch {
            Write-Host "Error retrieving snapshots for subscription $subscriptionId"
            continue
        }

        # Check and output for available snapshots to be deleted
        if ($snapshots) {
            foreach ($snapshot in $snapshots) {
                Write-Host "Subscription: $($subscriptionId)"
                Write-Host "Snapshot Name: $($snapshot.Name)"
                Write-Host "Resource Group: $($snapshot.ResourceGroupName)"
                Write-Host "Snapshot ID: $($snapshot.Id)"
                Write-Host "Creation Time: $($snapshot.TimeCreated)`n"

                try {
                    # Remove the snapshot without asking for confirmation each time
                    Remove-AzSnapshot -ResourceGroupName $snapshot.ResourceGroupName -SnapshotName $snapshot.Name
                    Write-Host "Snapshot $($snapshot.Name) deleted.`n"

                    # Add the result to the results array
                    $results += [PSCustomObject]@{
                        "S.No."        = $serialNumber++
                        "SnapshotName" = $snapshot.Name
                        "Status" = "Deleted"
                    }
                } catch {
                    Write-Host "Error deleting snapshot $($snapshot.Name)"
                    $results += [PSCustomObject]@{
                        "S.No."        = $serialNumber++
                        "SnapshotName" = $snapshot.Name
                        "Status" = "Failed to delete"
                    }
                }
            }
        } else {
            Write-Host "No snapshots found matching filter: $snapshotNameFilter"
        }
    }

    # Output the results as a table or export to CSV
    Write-Host "Operation complete. Exporting results..."

    # Display results in a table format
    $results | Format-Table -AutoSize

    # Optionally export the results to a CSV file (without VMName and Disk)
    $results | Export-Csv -Path ".\SnapshotDeletionResults.csv" -NoTypeInformation
} else {
    Write-Host "Operation cancelled. No snapshots were deleted."
}

Stop-Transcript
