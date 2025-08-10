// Thin coordinator – just passes through the params your AKS+AG template needs.
@description('Project (prefix) used for naming and DNS labels.')
@minLength(6)
param projectName string = 'sysdesign'

@description('Azure region for all resources.')
param location string = resourceGroup().location


module logAnalyticsModule '../loganalytics.bicep' = {
  name: 'logAnalyticsDeployment'
  params: {
    projectName: projectName
    location: location
  }
}

module cosmosdbModule 'cosmosdb.bicep' = {
  name: 'cosmosdbDeployment'
  params: {
    cosmosAccountName: 'cosmos-${projectName}'
    location: 'centralus'
  }
}

module metricsModule 'metrics.bicep' = {
  name: 'cosmosMetricsDeployment'
  params: {
    cosmosAccountName: cosmosdbModule.outputs.cosmosAccountName
    logAnalyticsWorkspaceId: logAnalyticsModule.outputs.workspaceId
    location: location
  }
}

module workbookModule 'workbook.bicep' = {
  name: 'cosmosWorkbookDeployment'
  params: {
    location: location
    workbookDisplayName: 'Cosmos DB - Deep Dive'
    workspaceResourceId: logAnalyticsModule.outputs.workspaceId
    cosmosAccountId: cosmosdbModule.outputs.cosmosAccountId
  }
}

module dashboardModule 'dashboard.bicep' = {
  name: 'cosmosDashboardDeployment'
  params: {
    dashboardName: 'cosmos-observability'
    location: location
    cosmosAccountId: cosmosdbModule.outputs.cosmosAccountId
  }
}
