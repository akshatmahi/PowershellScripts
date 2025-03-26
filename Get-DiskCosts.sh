#!/bin/bash
# Save this as 'Get-DiskCosts.sh' and run in Azure Cloud Shell (Bash)

# Authenticate with Azure
az login --use-device-code

# Configure dates
end_date=$(date -u +"%Y-%m-%d")
start_date=$(date -u -d "30 days ago" +"%Y-%m-%d")

# Initialize CSV file
echo "SubscriptionName,DiskName,ResourceGroup,SizeGB,Cost,Currency,ResourceId" > disk_costs.csv

# Process all subscriptions
az account list --query "[].id" -o tsv | while read sub_id; do
    sub_name=$(az account show --subscription $sub_id --query "name" -o tsv)
    echo "Processing subscription: $sub_name"
    
    # Get unattached disks
    disks=$(az disk list --subscription $sub_id --query "[?diskState=='Unattached'].{Name:name,Group:resourceGroup,Size:diskSizeGb,Id:id}" -o json)
    
    # Export cost data
    cost_file="cost_export_$sub_id.json"
    az costmanagement query --usage external --type "ActualCost" \
        --scope "subscriptions/$sub_id" \
        --dataset "{\"aggregation\":{\"totalCost\":{\"name\":\"PreTaxCost\",\"function\":\"Sum\"}},\"granularity\":\"None\",\"filter\":{\"and\":[{\"dimensions\":{\"name\":\"ResourceType\",\"operator\":\"In\",\"values\":[\"Microsoft.Compute/disks\"]}}]}}" \
        --timeframe "Custom" --time-period "start=$start_date,end=$end_date" \
        -o json > $cost_file

    # Match costs to disks
    echo "$disks" | jq -c '.[]' | while read disk; do
        disk_id=$(echo $disk | jq -r '.Id')
        disk_cost=$(jq -r ".rows[] | select(.[1] == \"$disk_id\") | .[0]" $cost_file)
        
        echo "$sub_name,$(echo $disk | jq -r '.Name'),$(echo $disk | jq -r '.Group'),$(echo $disk | jq -r '.Size'),${disk_cost:-0},USD,$disk_id" >> disk_costs.csv
    done
    
    rm $cost_file
done

echo "Report generated: disk_costs.csv"
