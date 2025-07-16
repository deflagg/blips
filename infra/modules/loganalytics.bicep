@description('Project prefix used for naming.')
param projectName string

@description('Azure region for the Log Analytics Workspace.')
param location string = resourceGroup().location

var workspaceName = 'log-${projectName}'

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018' // Pay-per-GB pricing tier; adjust as needed (e.g., to 'Standalone' for per-node)
    }
    retentionInDays: 30 // Default retention; can be increased up to 730 days
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true // Recommended for RBAC
    }
  }
}

output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name
