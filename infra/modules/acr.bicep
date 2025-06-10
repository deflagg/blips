// --------------------------------------------------
// Azure Container Registry (stand-alone module)
// --------------------------------------------------
@description('Project prefix ­– used in resource names.')
param projectName string

@description('Azure region for the registry.')
param location string = resourceGroup().location

@description('Registry name (leave default to keep it predictable).')
param containerRegistryName string = 'acr${projectName}'

@description('SKU for the registry.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param containerRegistrySku string = 'Standard'

// --------------------------------------------------
// Resource
// --------------------------------------------------
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name:  containerRegistryName
  location: location
  sku: {
    name: containerRegistrySku
  }
  properties: {
    adminUserEnabled: false       // flip to true only for PoCs
  }
}

// --------------------------------------------------
// Outputs (exposed to parent template)
// --------------------------------------------------
output registryId   string = containerRegistry.id
output registryName string = containerRegistry.name
