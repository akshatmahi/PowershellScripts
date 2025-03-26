#!/bin/bash
# Save as 'Get-DiskCosts.sh' and run in Azure Cloud Shell (Bash)

# Install required CLI extension
az extension add --name costmanagement --yes

# Authenticate
az login --use-device-code

# Configure dates
end_date=$(date -u +"%Y-%m-%d")
start_date=$(date -u -d "30 days ago" +"%Y-%m-%d")

# Initialize CSV
echo "SubscriptionName,DiskName,ResourceGroup,SizeGB,Cost,Currency,ResourceId" > disk_costs.csv

# Process subscriptions
az account list --query "[].id" -o tsv | while read sub_id; do
    sub_name=$(az account show --subscription $sub_id --query "name" -o tsv)
    echo "Processing: $sub_name"
    
    # Get unattached disks
    disks=$(az disk list --subscription $sub_id \
            --query "[?diskState=='Unattached'].{Name:name,Group:resourceGroup,Size:diskSizeGb,Id:id}" \
            -o json)
    
    # Get cost data
    cost_file="cost_$sub_id.json"
    az cost query --scope "subscriptions/$sub_id" \
        --type "ActualCost" \
        --timeframe "Custom" \
        --time-period "start=$start_date,end=$end_date" \
        --dataset '{
            "granularity": "None",
            "aggregation": {
                "totalCost": {
                    "name": "PreTaxCost",
                    "function": "Sum"
                }
            },
            "filter": {
                "and": [
                    {
                        "dimensions": {
                            "name": "ResourceType",
                            "operator": "In",
                            "values": ["Microsoft.Compute/disks"]
                        }
                    }
                ]
            }
        }' \
        -o json > $cost_file

    # Match costs to disks
    echo "$disks" | jq -c '.[]' | while read disk; do
        disk_id=$(echo $disk | jq -r '.Id')
        disk_cost=$(jq -r ".rows[] | select(.[1] | test(\"$disk_id\"; \"i\")) | .[0]" $cost_file)
        
        echo "$sub_name,$(echo $disk | jq -r '.Name'),$(echo $disk | jq -r '.Group'),$(echo $disk | jq -r '.Size'),${disk_cost:-0},USD,$disk_id" >> disk_costs.csv
    done
    
    rm $cost_file
done

echo "Report generated: disk_costs.csv"
