
@description('Project (prefix) used for naming and DNS labels.')
@minLength(6)
param projectName string = 'sysdesign'

@description('Azure region for all resources.')
param location string = resourceGroup().location


@description('Name of the Key Vault.')
param keyVaultName string = 'kv-primary-${projectName}'

// Optional: Params for secrets (secure, so they can be passed at deployment time)
@description('Name of the secret for the base64-encoded PFX.')
@secure()
param azureAksAppgwChainPfxBase64Name string = ''

// passed in from GitHub environment secrets
@description('Value of the base64-encoded PFX secret.')
param AZURE_AKS_APPGW_CHAIN_PFX_BASE64 string

@description('Value of the base64-encoded root CA certificate.')
param AZURE_AKS_APPGW_ROOT_CERT_BASE64 string

@description('AKS root CA certificate in base64 format.')
param azureAksAppgwRootCertBase64Name string


module keyVaultModule './modules/keyvault.bicep' = {
  name: 'keyVaultDeployment'
  params: {
    projectName: projectName
    location: location
    keyVaultName: keyVaultName
  }
}
