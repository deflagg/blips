az group delete --name sysdesign --yes
az group delete --name NetworkWatcherRG --yes
az apim deletedservice purge --service-name apim-sysdesign --location eastus2