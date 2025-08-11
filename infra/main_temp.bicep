// Thin coordinator – just passes through the params your AKS+AG template needs.
@description('Project (prefix) used for naming and DNS labels.')
@minLength(6)
param projectName string = 'sysdesign'

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Existing or new ACR name.')
param containerRegistryName string = 'acr${projectName}'



@description('ACR SKU')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param containerRegistrySku string = 'Basic'

// You asked for “everything in infrastructure_definition” to live in aks.bicep
// so we forward only those parameters actually defined there.
param hubVnetName            string = 'hubvnet-${projectName}'
param spoke1VnetName         string = 'spoke1Vnet-${projectName}'
param applicationGatewayName string = 'appgateway-${projectName}'
param aksClusterName         string = 'aks-${projectName}'
param dnsPrefix              string =  projectName
param dnsZoneName            string = 'priv.${dnsPrefix}.com'

var apimStaticIp             string = '10.1.3.4'

// --------------------------------------------------
// APIM – extra parameters (only what the module needs)
// --------------------------------------------------
@description('Name of the API Management instance.')
param apimName string = 'apim-${projectName}'

@description('Email of the APIM publisher (required).')
param publisherEmail string = 'api-admin@example.com'

@description('Display name of the APIM publisher (required).')
param publisherName string = 'API Team'

@description('Dedicated subnet name for APIM inside the VNet.')
param apimSubnetName string = 'apim-subnet'

@description('AKS root CA certificate in base64 format.')
param azureAksAppgwRootCertBase64Name string

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

module logAnalyticsModule './modules/loganalytics.bicep' = {
  name: 'logAnalyticsDeployment'
  params: {
    projectName: projectName
    location: location
  }
}

module cosmosdbModule './modules/cosmosdb/main.bicep' = {
  name: 'cosmosdbModule'
  params: {
    projectName: projectName
    location: location
  }
}

module functionAppModule './modules/functionApp.bicep' = {
  name: 'functionAppModule'
  params: {
    functionAppName: 'blipsFuncApp'
    location: location
    logAnalyticsWorkspaceId: logAnalyticsModule.outputs.workspaceId
    cosmosAccountName: 'cosmos-${projectName}'
  }
}



