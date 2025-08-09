
@description('Name of the Azure Portal dashboard')
param dashboardName string = 'cosmos-observability'

@description('Location for the dashboard resource')
param location string = resourceGroup().location

@description('Cosmos DB account resource ID (Microsoft.DocumentDB/databaseAccounts)')
param cosmosAccountId string

var ns = 'Microsoft.DocumentDB/databaseAccounts'

resource dashboard 'Microsoft.Portal/dashboards@2025-04-01-preview' = {
  name: dashboardName
  location: location
  // Cast the properties payload to 'any' to avoid Bicep type validation issues for MonitorChartPart.
  properties: any({
    lenses: [
      {
        order: 0
        parts: [
          {
            position: { x: 0, y: 0, colSpan: 6, rowSpan: 3 }
            metadata: {
              inputs: [
                { name: 'options', isOptional: true }
                { name: 'sharedTimeRange', isOptional: true }
              ]
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
              settings: {
                content: {
                  options: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: { id: cosmosAccountId }
                          name: 'TotalRequestUnits'
                          aggregationType: 0
                          namespace: ns
                          metricVisualization: { displayName: 'Total Request Units' }
                        }
                      ]
                      title: 'RU consumed'
                      titleKind: 2
                      visualization: {
                        chartType: 2
                        legendVisualization: { isVisible: true, position: 2, hideSubtitle: false }
                        axisVisualization: {
                          x: { isVisible: true, axisType: 2 }
                          y: { isVisible: true, axisType: 1 }
                        }
                        disablePinning: true
                      }
                    }
                  }
                }
              }
            }
          }
          {
            position: { x: 6, y: 0, colSpan: 6, rowSpan: 3 }
            metadata: {
              inputs: [
                { name: 'options', isOptional: true }
                { name: 'sharedTimeRange', isOptional: true }
              ]
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
              settings: {
                content: {
                  options: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: { id: cosmosAccountId }
                          name: 'NormalizedRUConsumption'
                          aggregationType: 4
                          namespace: ns
                          metricVisualization: { displayName: 'Normalized RU Consumption (%)' }
                        }
                      ]
                      title: 'RU usage percent (max)'
                      titleKind: 2
                      visualization: {
                        chartType: 2
                        legendVisualization: { isVisible: true, position: 2, hideSubtitle: false }
                        axisVisualization: {
                          x: { isVisible: true, axisType: 2 }
                          y: { isVisible: true, axisType: 1 }
                        }
                        disablePinning: true
                      }
                    }
                  }
                }
              }
            }
          }
          {
            position: { x: 12, y: 0, colSpan: 6, rowSpan: 3 }
            metadata: {
              inputs: [
                { name: 'options', isOptional: true }
                { name: 'sharedTimeRange', isOptional: true }
              ]
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
              settings: {
                content: {
                  options: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: { id: cosmosAccountId }
                          name: 'TotalRequests'
                          aggregationType: 1
                          namespace: ns
                          metricVisualization: { displayName: 'Total Requests' }
                        }
                      ]
                      title: 'Total requests'
                      titleKind: 2
                      visualization: {
                        chartType: 2
                        legendVisualization: { isVisible: true, position: 2, hideSubtitle: false }
                        axisVisualization: {
                          x: { isVisible: true, axisType: 2 }
                          y: { isVisible: true, axisType: 1 }
                        }
                        disablePinning: true
                      }
                    }
                  }
                }
              }
            }
          }
          {
            position: { x: 0, y: 3, colSpan: 6, rowSpan: 3 }
            metadata: {
              filters: {
                StatusCode: {
                  model: {
                    operator: 'equals'
                    values: [ '429' ]
                  }
                }
              }
              inputs: [
                { name: 'options', isOptional: true }
                { name: 'sharedTimeRange', isOptional: true }
              ]
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
              settings: {
                content: {
                  options: {
                    chart: {
                      filterCollection: {
                        filters: [
                          {
                            key: 'StatusCode'
                            operator: 'Equals'
                            values: [ '429' ]
                          }
                        ]
                      }
                      metrics: [
                        {
                          resourceMetadata: { id: cosmosAccountId }
                          name: 'TotalRequests'
                          aggregationType: 1
                          namespace: ns
                          metricVisualization: { displayName: '429s' }
                        }
                      ]
                      title: 'Throttled requests (HTTP 429)'
                      titleKind: 2
                      visualization: {
                        chartType: 2
                        legendVisualization: { isVisible: true, position: 2, hideSubtitle: false }
                        axisVisualization: {
                          x: { isVisible: true, axisType: 2 }
                          y: { isVisible: true, axisType: 1 }
                        }
                        disablePinning: true
                      }
                    }
                  }
                }
              }
            }
          }
          {
            position: { x: 6, y: 3, colSpan: 6, rowSpan: 3 }
            metadata: {
              inputs: [
                { name: 'options', isOptional: true }
                { name: 'sharedTimeRange', isOptional: true }
              ]
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
              settings: {
                content: {
                  options: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: { id: cosmosAccountId }
                          name: 'ServerSideLatencyDirect'
                          aggregationType: 3
                          namespace: ns
                          metricVisualization: { displayName: 'Latency Direct (ms)' }
                        }
                        {
                          resourceMetadata: { id: cosmosAccountId }
                          name: 'ServerSideLatencyGateway'
                          aggregationType: 3
                          namespace: ns
                          metricVisualization: { displayName: 'Latency Gateway (ms)' }
                        }
                      ]
                      title: 'Server-side latency (avg ms)'
                      titleKind: 2
                      visualization: {
                        chartType: 2
                        legendVisualization: { isVisible: true, position: 2, hideSubtitle: false }
                        axisVisualization: {
                          x: { isVisible: true, axisType: 2 }
                          y: { isVisible: true, axisType: 1 }
                        }
                        disablePinning: true
                      }
                    }
                  }
                }
              }
            }
          }
          {
            position: { x: 12, y: 3, colSpan: 6, rowSpan: 3 }
            metadata: {
              inputs: [
                { name: 'options', isOptional: true }
                { name: 'sharedTimeRange', isOptional: true }
              ]
              type: 'Extension/HubsExtension/PartType/MonitorChartPart'
              settings: {
                content: {
                  options: {
                    chart: {
                      metrics: [
                        {
                          resourceMetadata: { id: cosmosAccountId }
                          name: 'ServiceAvailability'
                          aggregationType: 3
                          namespace: ns
                          metricVisualization: { displayName: 'Service availability (%)' }
                        }
                      ]
                      title: 'Availability (hourly)'
                      titleKind: 2
                      visualization: {
                        chartType: 2
                        legendVisualization: { isVisible: true, position: 2, hideSubtitle: false }
                        axisVisualization: {
                          x: { isVisible: true, axisType: 2 }
                          y: { isVisible: true, axisType: 1 }
                        }
                        disablePinning: true
                      }
                    }
                  }
                }
              }
            }
          }
        ]
      }
    ]
    metadata: {
      model: {
        timeRange: {
          value: {
            relative: { duration: 24, timeUnit: 1 }
          }
          type: 'MsPortalFx.Composition.Configuration.ValueTypes.TimeRange'
        }
        filterLocale: { value: 'en-us' }
        filters: {
          value: {
            MsPortalFx_TimeRange: {
              model: { format: 'local', granularity: 'auto', relative: '24h' }
              displayCache: { name: 'Local Time', value: 'Past 24 hours' }
            }
          }
        }
      }
    }
  })
}
