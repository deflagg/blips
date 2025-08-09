@description('Location for the workbook')
param location string = resourceGroup().location

@description('Display name in the portal')
param workbookDisplayName string = 'Cosmos DB – Deep Dive'

@description('Log Analytics workspace resource ID (scope for KQL)')
param workspaceResourceId string

@description('Cosmos DB account resource ID')
param cosmosAccountId string

var wb = {
  version: 'Notebook/1.0'
  items: [
    {
      type: 1
      content: { json: '# Cosmos DB – Overview' }
      name: 'title'
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'AzureMetrics | where tolower(ResourceId) == tolower("${cosmosAccountId}") | where MetricName in ("TotalRequests","TotalRequestUnits") | summarize Value=sum(Total) by MetricName, bin(TimeGenerated, 5m) | render timechart'
        title: 'Requests & Request Units'
        queryType: 0
      }
      name: 'reqsRus'
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'AzureMetrics | where tolower(ResourceId) == tolower("${cosmosAccountId}") | where MetricName in ("ServerSideLatencyDirect","ServerSideLatencyGateway") | summarize AvgLatencyMs=avg(Average) by MetricName, bin(TimeGenerated, 5m) | render timechart'
        title: 'Server-side latency (Direct vs Gateway)'
        queryType: 0
      }
      name: 'latency'
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'AzureMetrics | where tolower(ResourceId) == tolower("${cosmosAccountId}") | where MetricName == "NormalizedRUConsumption" | summarize MaxPct=max(Maximum) by bin(TimeGenerated, 5m) | render timechart'
        title: 'Normalized RU consumption (%)'
        queryType: 0
      }
      name: 'normalizedru'
    }
    {
      type: 3
      content: {
        version: 'KqlItem/1.0'
        query: 'AzureMetrics | where tolower(ResourceId) == tolower("${cosmosAccountId}") | where MetricName == "RateLimitedRequests" | summarize Throttles=sum(Total) by bin(TimeGenerated, 5m) | render columnchart'
        title: '429 rate-limited requests'
        queryType: 0
      }
      name: 'throttles'
    }
  ]
  isLocked: false
  fallbackResourceIds: [ workspaceResourceId ]
}

resource workbook 'Microsoft.Insights/workbooks@2022-04-01' = {
  name: guid(workbookDisplayName, workspaceResourceId)
  location: location
  kind: 'shared'
  properties: {
    displayName: workbookDisplayName
    category: 'workbook'
    sourceId: workspaceResourceId
    serializedData: string(wb)
    version: '1.0'
  }
}
