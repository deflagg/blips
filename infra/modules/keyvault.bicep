// modules/keyvault.bicep

@description('Name of the Key Vault.')
param keyVaultName string = 'kv-${projectName}'

@description('Azure region for the Key Vault.')
param location string = resourceGroup().location

@description('Project prefix used for naming.')
param projectName string

@description('SKU for the Key Vault.')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'

@description('Enable soft delete for the Key Vault.')
param enableSoftDelete bool = false

@description('Enable purge protection for the Key Vault.')
param enablePurgeProtection bool = false

// Optional: If you want to create secrets during deployment
@description('Name of the secret for the base64-encoded PFX.')
@secure()
param pfxSecretName string = ''

@description('Value of the base64-encoded PFX secret.')
@secure()
param AZURE_AKS_APPGW_PFX_BASE64 string = ''


resource keyVault 'Microsoft.KeyVault/vaults@2024-12-01-preview' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: skuName
    }
    tenantId: subscription().tenantId
    enabledForDeployment: true
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true
    enableSoftDelete: enableSoftDelete
    softDeleteRetentionInDays: 2
    enablePurgeProtection: enablePurgeProtection
    accessPolicies: [] // Add access policies as needed; for demo, assuming deployer has access
    networkAcls: {
      defaultAction: 'Allow' // Adjust for production (e.g., 'Deny' with IP/VNet rules)
      bypass: 'AzureServices'
    }
  }
}

// Optional: Create PFX secret if provided
resource pfxSecret 'Microsoft.KeyVault/vaults/secrets@2024-12-01-preview' = if (!empty(pfxSecretName) && !empty(AZURE_AKS_APPGW_PFX_BASE64)) {
  parent: keyVault
  name: pfxSecretName
  properties: {
    value: AZURE_AKS_APPGW_PFX_BASE64
  }
}


output keyVaultId string = keyVault.id
output keyVaultName string = keyVault.name
