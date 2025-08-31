// cosmos-gremlin-serverless.bicep
// Creates a serverless Azure Cosmos DB account for Gremlin,
// with one Gremlin database and one graph.

// ---------- Parameters ----------
@description('Globally unique name for the Cosmos DB account (3-44 lowercase letters/numbers).')
param gremlinAccountName string

@description('Azure region for the account.')
param location string = resourceGroup().location

@description('Gremlin database name.')
param gremlinDatabaseName string = 'PersonGraphDb'

@description('Gremlin graph (container) name.')
param gremlinGraphName string = 'PersonGraph'

@description('Partition key path for the graph (e.g., /partitionKey).')
param graphPartitionKeyPath string = '/PersonId'

// ---------- Resources ----------
resource gremlinAccount 'Microsoft.DocumentDB/databaseAccounts@2025-05-01-preview' = {
  name: gremlinAccountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    // Required
    databaseAccountOfferType: 'Standard'

    // Serverless capacity mode (do not use legacy EnableServerless capability)
    capacityMode: 'Serverless'

    // API selection: Gremlin
    capabilities: [
      { name: 'EnableGremlin' }
    ]

    // Serverless accounts must be single-region
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
  }
}

resource gremlinDb 'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases@2025-05-01-preview' = {
  name: gremlinDatabaseName
  parent: gremlinAccount
  properties: {
    resource: {
      id: gremlinDatabaseName
    }
    // In serverless, do NOT set throughput
    options: {}
  }
}

resource gremlinGraph 'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases/graphs@2025-05-01-preview' = {
  name: gremlinGraphName
  parent: gremlinDb
  properties: {
    resource: {
      id: gremlinGraphName
      partitionKey: {
        paths: [
          graphPartitionKeyPath
        ]
        kind: 'Hash'
        version: 2
      }
    }
    // No throughput in serverless
    options: {}
  }
}

// ---------- Outputs ----------
output gremlinAccountId string = gremlinAccount.id
output gremlinAccountName string = gremlinAccount.name
output gremlinDatabaseId string = gremlinDb.id
output gremlinGraphId string = gremlinGraph.id
