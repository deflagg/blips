@description('Optional: Log Analytics workspace resource ID for diagnostics')
param logAnalyticsWorkspaceId string?

param location string = resourceGroup().location

@description('Cosmos DB account resource ID')
param cosmosAccountName string

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-02-15-preview' existing = {
  name: cosmosAccountName
}

// ---------- Diagnostic settings (resource logs to Log Analytics) ----------
resource cosmosDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logAnalyticsWorkspaceId != null) {
  name: 'cosmos-to-law'
  scope: cosmosAccount
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'DataPlaneRequests', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
      { category: 'PartitionKeyRUConsumption', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
      { category: 'PartitionKeyStatistics', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
      { category: 'QueryRuntimeStatistics', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
      { category: 'ControlPlaneRequests', enabled: true, retentionPolicy: { enabled: false, days: 0 } }
    ]
  }
}

resource ag 'Microsoft.Insights/actionGroups@2024-10-01-preview' = {
  name: 'blips-ag'
  location: 'global'
  properties: {
    groupShortName: 'blips'
    enabled: true
    emailReceivers: [
      { name: 'Ops', emailAddress: 'deflagg@hotmail.com', useCommonAlertSchema: true }
    ]
  }
}


// Helper for alert actions
var actions = [
  {
    actionGroupId: ag.id
    webHookProperties: {}
  }
]

// ---------- Alert: 429 throttles (request rate pressure) ----------
resource cosmos429 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'cosmos-429-throttles'
  location: location
  properties: {
    description: 'Too many 429 (rate-limited) requests'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [ cosmosAccount.id ]
    targetResourceType: 'Microsoft.DocumentDB/databaseAccounts'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: '429Count'
          metricNamespace: 'Microsoft.DocumentDB/databaseAccounts'
          metricName: 'TotalRequests'
          dimensions: [
            { name: 'StatusCode', operator: 'Include', values: [ '429' ] }
          ]
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 100 // tune for your traffic profile
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: actions
  }
}

// ---------- Alert: Server-side latency (Direct mode) ----------
resource cosmosLatencyDirect 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'cosmos-latency-direct'
  location: location
  properties: {
    description: 'Server-side latency (Direct) above threshold'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [ cosmosAccount.id ]
    targetResourceType: 'Microsoft.DocumentDB/databaseAccounts'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'DirectLatencyAvg'
          metricNamespace: 'Microsoft.DocumentDB/databaseAccounts'
          metricName: 'ServerSideLatencyDirect'
          timeAggregation: 'Average'
          operator: 'GreaterThan'
          threshold: 80 // ms, start conservative; adjust by workload
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: actions
  }
}

// ---------- Alert: RU saturation (Normalized RU%) ----------
resource cosmosRUCap 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'cosmos-normalized-ru-high'
  location: location
  properties: {
    description: 'Normalized RU consumption high (possible hot partition or under-provisioning)'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [ cosmosAccount.id ]
    targetResourceType: 'Microsoft.DocumentDB/databaseAccounts'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'NormRU'
          metricNamespace: 'Microsoft.DocumentDB/databaseAccounts'
          metricName: 'NormalizedRUConsumption'
          timeAggregation: 'Maximum'
          operator: 'GreaterThanOrEqual'
          threshold: 90 // sustained spikes to 100% merit a look
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: actions
  }
}

// ---------- Alert: Provisioned throughput drop or misconfig ----------
resource cosmosThroughput 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'cosmos-provisioned-throughput-low'
  location: location
  properties: {
    description: 'Provisioned Throughput unexpectedly low'
    severity: 3
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    scopes: [ cosmosAccount.id ]
    targetResourceType: 'Microsoft.DocumentDB/databaseAccounts'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ProvisionedRU'
          metricNamespace: 'Microsoft.DocumentDB/databaseAccounts'
          metricName: 'ProvisionedThroughput'
          timeAggregation: 'Maximum'
          operator: 'LessThan'
          threshold: 1000 // RU/s; adjust for your floor
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: actions
  }
}
