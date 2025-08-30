
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

// --------------------------------------------------
// Hub - VNet
// --------------------------------------------------
module hubVnetModule './modules/hubvnet.bicep' = {
  name: 'hubVnetDeployment'
  params: {
    projectName : projectName
    hubVnetName : hubVnetName
    location    : location
  }
}

// --------------------------------------------------
// Spoke1 - VNet
// --------------------------------------------------
module spoke1VnetModule './modules/spoke1Vnet.bicep' = {
  name: 'spoke1VnetDeployment'
  params: {
    projectName : projectName
    vnetName    : spoke1VnetName
    location    : location
  }
}

module vnetPeering './modules/peering.bicep' = {
  name: 'hubSpokePeering'
  params: {
    hubVnetName:           hubVnetModule.outputs.vnetName
    spokeVnetName:         spoke1VnetModule.outputs.vnetName
    hubVnetId:             hubVnetModule.outputs.vnetId
    spokeVnetId:           spoke1VnetModule.outputs.vnetId
    hubToSpokePeeringName: 'hub-to-spoke1'
    spokeToHubPeeringName: 'spoke1-to-hub'
  }
  dependsOn: [
    hubVnetModule
    spoke1VnetModule
  ]
}


// -----------------------------------------------------------------------------
//  MODULE: Public DNS Zone (Zone 1)
// -----------------------------------------------------------------------------
module dnsModule './modules/dns.bicep' = {
  name: 'privateDnsDeployment'
  params: {
    dnsZoneName: dnsZoneName          // existing param
    vnetId     : hubVnetModule.outputs.vnetId
  }
}

// --------------------------------------------------
// DNS Forwarder VM (Azure DNS Resolver is available but too expensive ($180/month) for this demo)
// --------------------------------------------------
// module dnsforwarderVMModule './modules/dnsforwarder-vm.bicep' = {
//   name: 'dnsforwarderVMDeployment'
//   params: {
//     projectName : projectName
//     location    : location
//     vnetId    : hubVnetModule.outputs.vnetId
//   }
// }

// --------------------------------------------------
// Azure Firewall
// --------------------------------------------------
// module firewallModule './modules/firewall.bicep' = {
//   name: 'firewallDeployment'
//   params: {
//     projectName : projectName
//     vnetName    : hubVnetName
//     location    : location
//     targetIpAddress   : apimStaticIp //apimModule.outputs.apimPrivateIp
//     logAnalyticsWorkspaceId: logAnalyticsModule.outputs.workspaceId
//   }
//   dependsOn: [
//     hubVnetModule
//   ]
// }

// --------------------------------------------------
// VPN Gateway
// --------------------------------------------------
// module vpngwModule './modules/vpngw.bicep' = {
//   name: 'vpngwDeployment'
//   params: {
//     projectName : projectName
//     location    : location
//     vnetName    : hubVnetName
//   }
// }


// --------------------------------------------------
// ACR
// --------------------------------------------------
module acrModule './modules/acr.bicep' = {
  name: 'acrDeployment'
  params: {
    projectName:           projectName          // already defined in main.bicep
    location:              location
    containerRegistryName: containerRegistryName
    containerRegistrySku:  containerRegistrySku // if you expose this param
  }
}

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


// --------------------------------------------------
// Key Vault
// --------------------------------------------------
module keyVaultModule './modules/keyvault.bicep' = {
  name: 'keyVaultDeployment'
  params: {
    projectName: projectName
    location: location
    keyVaultName: keyVaultName
  }
}

module addCertModule './modules/addAksCerts.bicep' = {
  name: 'addCertModule'
  params: {
    keyVaultName: keyVaultName
    azureAksAppgwRootCertBase64Name: azureAksAppgwRootCertBase64Name
    rootCertBase64: AZURE_AKS_APPGW_ROOT_CERT_BASE64
    certificateName: azureAksAppgwChainPfxBase64Name
    pfxBase64: AZURE_AKS_APPGW_CHAIN_PFX_BASE64
    pfxPassword: ''
    location: location
  }
  dependsOn: [
    keyVaultModule
  ]
}

// --------------------------------------------------
// App Gateway
// --------------------------------------------------
module appGwModule './modules/agw.bicep' = {
  name: 'appGwDeployment'
  params: {
    projectName               : projectName
    applicationGatewayName    : applicationGatewayName
    vnetName                  : spoke1VnetName
    location                  : location
    keyVaultName              : keyVaultModule.outputs.keyVaultName
    certSecretId              : azureAksAppgwChainPfxBase64Name
    rootCertName              : azureAksAppgwRootCertBase64Name
  }
  dependsOn: [
    spoke1VnetModule
  ]
}


// --------------------------------------------------
// AKS
// --------------------------------------------------
module aksModule './modules/aks.bicep' = {
  name: 'aksDeployment'
  params: {
    projectName            : projectName
    location               : location
    containerRegistryId    : acrModule.outputs.containerRegistryId
    vnetId                 : spoke1VnetModule.outputs.vnetId
    aksSubnetId            : spoke1VnetModule.outputs.aksSubnetId
    appGatewaySubnetId     : spoke1VnetModule.outputs.appGatewaySubnetId
    appGatewayId           : appGwModule.outputs.appGatewayId
    appGatewayIdentityId   : appGwModule.outputs.appGatewayIdentityId
    aksClusterName         : aksClusterName
    dnsPrefix              : dnsPrefix
    keyVaultName           : keyVaultModule.outputs.keyVaultName
    cosmosAccountName      : 'cosmos-${projectName}'
  }
  dependsOn: [
    cosmosdbModule
  ]
}

module cosmosdbModule './modules/cosmosdb/main.bicep' = {
  name: 'cosmosdbModule'
  params: {
    projectName: 'cosmos-${projectName}'
    location: location
    logAnalyticsWorkspaceId: logAnalyticsModule.outputs.workspaceId
  }
}

// APIM sits in front of the App Gateway created by the AKS module.
// module apimModule './modules/apim.bicep' = {
//   name: 'apimDeployment'
//   params: {
//     apimName        : apimName
//     location        : location
//     publisherEmail  : publisherEmail
//     publisherName   : publisherName
//     // VNet containing both AKS & App Gateway (resource already created by aksModule)
//     vnetResourceId  : resourceId('Microsoft.Network/virtualNetworks', hubVnetName)
//     subnetName      : apimSubnetName
//     // Forward traffic from APIM to the App Gateway listener
//     appGatewayFqdn  : 'www.theblips.com' //applicationGatewayName // adjust if you use a different DNS label
//     apimStaticIp    : apimStaticIp // Static IP for the APIM private endpoint (PE)
//   }
//   dependsOn: [
//     //appGwModule // ensure App Gateway exists before APIM backend registration
//     dnsModule
//   ]
// }

// --------------------------------------------------
// App Service
// --------------------------------------------------
module web './modules/appsvc.bicep' = {
  name: 'webAppModule'
  params: {
    location: location
    appServicePlanName: '${projectName}-plan'
    appServicePlanSkuName: 'B1'
    siteName: 'react-${uniqueString(resourceGroup().id)}'
    integrationSubnetId: spoke1VnetModule.outputs.appSvcIntegrationSubnetId
    defaultSubnetId: spoke1VnetModule.outputs.aksSubnetId
    webAppPrivateDnsZoneId: dnsModule.outputs.websitesPrivZoneResourceId
  }
}


// --------------------------------------------------
// Log Analytics Workspace
// --------------------------------------------------
module logAnalyticsModule './modules/loganalytics.bicep' = {
  name: 'logAnalyticsDeployment'
  params: {
    projectName: projectName
    location: location
  }
}

// --------------------------------------------------
// Outputs
// --------------------------------------------------
// output aksClusterId   string = aksModule.outputs.aksClusterId
// output apimServiceId  string = apimModule.outputs.apimResourceId
//output pfxSecretUriWithVersion string = keyVaultModule.outputs.pfxSecretUriWithVersion
