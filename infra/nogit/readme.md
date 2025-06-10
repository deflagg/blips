# Azure Resource Cleanup Commands

The following commands help manage and clean up Azure resources for this project:

```sh
# Set the Azure subscription
az account set --subscription 400acf99-3ce6-4ee6-8bf7-9b209093ac5f

# Log in to Azure with a specific tenant
az login --tenant 35d231ad-d70d-43bf-bc50-c2e8bbc10537

# Delete resource groups
az group delete --name sysdesign --yes
az group delete --name NetworkWatcherRG --yes

# Purge a deleted API Management service
az apim deletedservice purge --service-name apim-sysdesign --location eastus
```