// appservice.bicep
// Deploys an Azure App Service Plan (Linux) and a Web App ready to host a basic React app.
// The Web App is configured to run Node 18‑LTS for a typical React build output and exposes the
// default hostname as an output.

@description('Location for all resources')
param location string = resourceGroup().location

@description('App Service Plan name')
param appServicePlanName string = 'appsvc‑plan'

@description('SKU name for the App Service Plan (e.g. B1, P1v3, S1)')
param appServicePlanSkuName string = 'B1'

@description('Number of workers for the plan')
param appServicePlanCapacity int = 1

@description('Web App name (must be globally unique)')
param siteName string = 'react‑webapp‑${uniqueString(resourceGroup().id)}'

@description('Enable system‑assigned managed identity for the Web App')
param enableIdentity bool = true

@description('Tags to apply to all resources')
param tags object = {
  project: 'sysdesign'
}

@description('Subnet to use for Regional VNet Integration')
param integrationSubnetId string


@description('Resource ID of the subnet that will host the Private Endpoint (default-subnet in the spoke VNet).')
param defaultSubnetId string

@description('Resource ID of an existing Private DNS zone: privatelink.azurewebsites.net')
param webAppPrivateDnsZoneId string


// --------------------
// App Service Plan
// --------------------
resource appPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: appServicePlanName
  location: location
  kind: 'linux'
  sku: {
    name: appServicePlanSkuName 
    tier: contains(appServicePlanSkuName, 'P') ? 'PremiumV3'
          : contains(appServicePlanSkuName, 'S') ? 'Standard'
          : 'Basic'
    capacity: appServicePlanCapacity
  }
  properties: {
    reserved: true       // <---- required for every Linux plan
  }
  tags: tags
}

// --------------------
// Web App
// --------------------
resource webApp 'Microsoft.Web/sites@2024-11-01' = {
  name: siteName
  location: location
  kind: 'app,linux'
  identity: enableIdentity ? {
    type: 'SystemAssigned'
  } : null

  properties: {
    serverFarmId: appPlan.id
    httpsOnly: true
    publicNetworkAccess: 'Enabled' // (optional) only allowed *after* PE exists
    outboundVnetRouting: {  // New object for VNet routing configs
        imagePullTraffic: true  // Enables image pulls over VNet (formerly vnetImagePullEnabled)
        allTraffic: true  // Enables all outbound traffic over VNet
    }
    siteConfig: {
      linuxFxVersion: 'NODE|18-lts'
      http20Enabled: true
      alwaysOn: true
      appSettings: [
        // Enables ZIP/package deployments from your CI pipeline
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'WEBSITES_ENABLE_APP_SERVICE_STORAGE'
          value: 'false'
        }
      ]
    }
  }
  tags: tags
}

resource vnetIntegration 'Microsoft.Web/sites/networkConfig@2024-11-01' = {
  name: 'virtualNetwork'
  parent: webApp
  properties: {
    subnetResourceId: integrationSubnetId
    swiftSupported: true 
  }
}

// -----------------------------------------------------------------------------
// Private Endpoint – Web App  ↔  Spoke default subnet
// -----------------------------------------------------------------------------


resource webAppPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-07-01' = {
  name: '${siteName}-pep'
  location: location
  properties: {
    subnet: {
      id: defaultSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${siteName}-plsc'
        properties: {
          privateLinkServiceId: webApp.id
          groupIds: [
            // Primary endpoint for the site; include 'scm' as well
            // if you need Kudu via Private Link.
            'sites'
          ]
        }
      }
    ]
  }
}

// -----------------------------------------------------------------------------
// OPTIONAL – automatic A‑record registration in privatelink.azurewebsites.net
// Uncomment if you are *also* passing the private DNS zone’s resource ID.
// -----------------------------------------------------------------------------
//resource webAppPeDnsZoneGroup 'Microsoft.Network/privateDnsZoneGroups@2024-07-01' = {
resource webAppPeDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-07-01' = {
  name: 'default'
  parent: webAppPrivateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'azurewebsitesZone'
        properties: {
          privateDnsZoneId: webAppPrivateDnsZoneId
        }
      }
    ]
  }
}


// --------------------
// Outputs
// --------------------
@description('The default hostname of the Web App')
output webAppHostname string = webApp.properties.defaultHostName
