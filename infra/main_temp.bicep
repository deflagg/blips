@minLength(6)
param projectName string = 'sysdesign'

@description('Azure region for all resources.')
param location string = resourceGroup().location


module cosmosdbModule './modules/cosmosdb/main.bicep' = {
  name: 'cosmosdbModule'
  params: {
    projectName: projectName
    location: location
  }
}
