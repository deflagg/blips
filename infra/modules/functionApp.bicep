
@description('Azure region')
param location string = resourceGroup().location

@description('Function App name')
param functionAppName string = 'blipsFuncApp'

@description('Storage account for Functions host (AzureWebJobsStorage) and deployment container')
@minLength(3)
@maxLength(24)
param storageAccountName string = 'stblipsfunctionapp'

@description('Blob container that holds the deployment package (zip) for Flex Consumption OneDeploy')
param deploymentContainerName string = 'app-package'

@description('Application Insights resource name')
param appInsightsName string = 'ai-${functionAppName}'

var planName = '${functionAppName}-fc-plan'

@description('Existing Log Analytics workspace resource ID')
param logAnalyticsWorkspaceId string

// --------------------
// Flex Consumption plan
// --------------------
resource plan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: planName
  location: location
  kind: 'functionapp'
  sku: {
    name: 'FC1'
    tier: 'FlexConsumption'
  }
  properties: {
    reserved: true   // <-- required for Linux
    // zoneRedundant: false | true (optional, where supported)
  }
}

// --------------------
// Storage account + container (private)
// --------------------
resource storage 'Microsoft.Storage/storageAccounts@2025-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2025-01-01' = {
  name: 'default'
  parent: storage
}

resource deployContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2025-01-01' = {
  name: '${storage.name}/${blobService.name}/${deploymentContainerName}'
  properties: {
    publicAccess: 'None'
  }
}

// --------------------
// Application Insights
// --------------------
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspaceId
  }
}

// --------------------
// Function App (Linux, Flex Consumption) with Managed Identity
// --------------------
resource app 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id

    // REQUIRED on create for Flex Consumption
    functionAppConfig: {
      // Where the deployment package lives (OneDeploy). MI will read the blob.
      deployment: {
        storage: {
          type: 'blobContainer'
          // e.g. https://<acct>.blob.core.windows.net/<container>
          value: '${storage.properties.primaryEndpoints.blob}${deploymentContainerName}'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }

      // Runtime: adjust for your stack (dotnet-isolated 8 shown)
      runtime: {
        name: 'dotnet-isolated'
        version: '9.0'
      }

      // Optional scale/concurrency tuning
      scaleAndConcurrency: {
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
    }

    siteConfig: {
      // Flex does not require AlwaysOn
      alwaysOn: false
      // For Linux Functions, DO NOT set linuxFxVersion when using functionAppConfig.runtime
    }
    httpsOnly: true
  }
  dependsOn: [
    deployContainer
  ]
}

// --------------------
// App settings (MI-based AzureWebJobsStorage & App Insights)
// --------------------
resource appSettings 'Microsoft.Web/sites/config@2022-09-01' = {
  name: 'appsettings'
  parent: app
  properties: { 
    // Identity-based connections for Functions host storage:
    'AzureWebJobsStorage__credential': 'managedidentity'
    'AzureWebJobsStorage__blobServiceUri': 'https://${storage.name}.blob.${environment().suffixes.storage}'
    'AzureWebJobsStorage__queueServiceUri': 'https://${storage.name}.queue.${environment().suffixes.storage}'
    // Include table if you use it; otherwise omit. Shown here for completeness.
    // 'AzureWebJobsStorage__tableServiceUri': 'https://${storage.name}.table.${environment().suffixes.storage}'

    // Application Insights
    'APPLICATIONINSIGHTS_CONNECTION_STRING': appInsights.properties.ConnectionString
    'APPLICATIONINSIGHTS_AUTHENTICATION_STRING': 'Authorization=AAD'
  }
}

// --------------------
// Role assignments for the Function App's system-assigned identity
// Scope to the storage account; least-privilege can be refined later.
// --------------------

// Storage Blob Data Contributor
resource roleBlobContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe', app.name)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: app.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Queue Data Contributor
resource roleQueueContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, '974c5e8b-45b9-4653-ba55-5f855dd0fb88', app.name)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88')
    principalId: app.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// If you use Tables with the Functions host, uncomment the Table role below.
// // Storage Table Data Contributor
// resource roleTableContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   name: guid(storage.id, '76199698-08e1-4b93-8e3e-ef28b6d6c9e3', app.name)
//   scope: storage
//   properties: {
//     roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '76199698-08e1-4b93-8e3e-ef28b6d6c9e3')
//     principalId: app.identity.principalId
//     principalType: 'ServicePrincipal'
//   }
// }

// --------------------
// Optional: open access (no IP restrictions). Keep or tighten as needed.
// --------------------
resource webConfig 'Microsoft.Web/sites/config@2022-09-01' = {
  name: 'web'
  parent: app
  properties: {
    ipSecurityRestrictionsDefaultAction: 'Allow'
    scmIpSecurityRestrictionsDefaultAction: 'Allow'
  }
}

output functionAppId string = app.id
output hostName string = app.properties.defaultHostName
