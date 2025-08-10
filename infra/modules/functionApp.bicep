@description('Azure region')
param location string = resourceGroup().location

@description('Function App name')
param functionAppName string = 'blipsFuncApp'

var planName = '${functionAppName}-fc-plan'
var aiName = 'ai-${functionAppName}'
var storageName = 'stblipsfunctionapp' 

resource plan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: planName
  location: location
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
    size: 'FC1'
    capacity: 0
  }
  properties: {
    reserved: true // Linux
    perSiteScaling: false
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Enabled'
  }
}

var storageKey = listKeys(storage.id, '2025-01-01').keys[0].value
var storageConn = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};AccountKey=${storageKey};EndpointSuffix=${environment().suffixes.storage}'

resource ai 'Microsoft.Insights/components@2020-02-02' = {
  name: aiName
  location: location
  kind: 'web'
  tags: {
    'hidden-link:${resourceId('Microsoft.Web/sites', functionAppName)}': 'Resource'
  }
  properties: {
    Application_Type: 'web'
  }
}

resource app 'Microsoft.Web/sites@2024-11-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      http20Enabled: true
      ftpsState: 'Disabled'
      appSettings: [
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME',  value: 'dotnet-isolated' } // .NET Core (.NET 8 isolated)
        { name: 'AzureWebJobsStorage',       value: storageConn }        // Auth type: secrets (connection string)
        { name: 'WEBSITE_RUN_FROM_PACKAGE',  value: '1' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: ai.properties.ConnectionString }
        { name: 'APPINSIGHTS_INSTRUMENTATIONKEY',        value: ai.properties.InstrumentationKey }
      ]
    }
  }
}

resource webConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  name: 'web'
  parent: app
  properties: {
    // Public access (no access restrictions). No VNet integration configured.
    ipSecurityRestrictionsDefaultAction: 'Allow'
    scmIpSecurityRestrictionsDefaultAction: 'Allow'
  }
}

output functionAppId string = app.id
output hostName string = app.properties.defaultHostName
