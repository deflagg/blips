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
param vnetName               string = 'vnet-${projectName}'
param applicationGatewayName string = 'appgateway-${projectName}'
param aksClusterName         string = 'aks-${projectName}'
param dnsPrefix              string = 'dns-${projectName}'

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


// --------------------------------------------------
// VNet
// --------------------------------------------------
module vnetModule './modules/vnet.bicep' = {
  name: 'vnetDeployment'
  params: {
    projectName : projectName
    vnetName    : vnetName
    location    : location
  }
}
// --------------------------------------------------
// App Gateway
// --------------------------------------------------
module appGwModule './modules/agw.bicep' = {
  name: 'appGwDeployment'
  params: {
    projectName           : projectName
    applicationGatewayName: applicationGatewayName
    vnetName              : vnetName
    location              : location
  }
  dependsOn: [
    vnetModule  //  Remember I uncommented this.
  ]
}

// --------------------------------------------------
// Modules
// --------------------------------------------------
module aksModule './modules/aks.bicep' = {
  name: 'aksDeployment'
  params: {
    projectName            : projectName
    location               : location
    containerRegistryName  : containerRegistryName
    containerRegistrySku   : containerRegistrySku
    vnetSubnetId           : vnetModule.outputs.defaultSubnetId
    applicationGatewayId   : appGwModule.outputs.applicationGatewayId
    aksClusterName         : aksClusterName
    dnsPrefix              : dnsPrefix
  }
}

// APIM sits in front of the App Gateway created by the AKS module.
module apimModule './modules/apim.bicep' = {
  name: 'apimDeployment'
  params: {
    apimName        : apimName
    location        : location
    publisherEmail  : publisherEmail
    publisherName   : publisherName
    // VNet containing both AKS & App Gateway (resource already created by aksModule)
    vnetResourceId  : resourceId('Microsoft.Network/virtualNetworks', vnetName)
    subnetName      : apimSubnetName
    // Forward traffic from APIM to the App Gateway listener
    appGatewayFqdn  : applicationGatewayName // adjust if you use a different DNS label
  }
  dependsOn: [
    appGwModule // ensure App Gateway exists before APIM backend registration
  ]
}

// --------------------------------------------------
// Outputs
// --------------------------------------------------
//output aksClusterId   string = aksModule.outputs.aksClusterId
// output apimServiceId  string = apimModule.outputs.apimResourceId
