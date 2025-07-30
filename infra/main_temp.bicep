@description('Project (prefix) used for naming and DNS labels.')
@minLength(6)
param projectName string = 'sysdesign'

@description('Azure region for all resources.')
param location string = resourceGroup().location


@description('Name of the Key Vault.')
param keyVaultName string = 'kv-primary-${projectName}'


module keyVaultModule './modules/keyvault.bicep' = {
  name: 'keyVaultDeployment'
  params: {
    projectName: projectName
    location: location
    keyVaultName: keyVaultName
  }
}
