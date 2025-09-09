// Thin coordinator – just passes through the params your AKS+AG template needs.
@description('Project (prefix) used for naming and DNS labels.')
@minLength(6)
param projectName string = 'sysdesign'

@description('Azure region for all resources.')
param location string = resourceGroup().location

// get existing log analytics workspace
@description('Existing Log Analytics workspace resource ID')
param logAnalyticsWorkspaceId string

module gremlindbModule 'gremlindb.bicep' = {
  name: 'gremlindbDeployment'
  params: {
    gremlinAccountName: 'gremlin-${projectName}'
    location: location
  }
}
