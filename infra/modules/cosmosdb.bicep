// cosmosServerless.bicep
// Creates a free-tier, serverless Cosmos DB account with one database and container.

@description('Name for the Cosmos DB account (must be globally unique, 3-44 lowercase letters, numbers).')
param cosmosAccountName string

@description('Azure region for the account and its replicas.')
param location string = resourceGroup().location

var databaseName  = 'blips'
var containerName = 'UserFollowers'

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15-preview' = {
  name: cosmosAccountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    // Required for Cosmos DB (SQL) accounts
    databaseAccountOfferType: 'Standard'

    // **Free Tier** – only one per subscription
    enableFreeTier: true

    // **Serverless** capability
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]

    // At least one write region is required
    locations: [
      {
        locationName: location          // primary write region
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
  }
}

resource sqlDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15-preview' = {
  name: databaseName
  parent: cosmosAccount
  properties: {
    resource: {
      id: databaseName
    }
    options: {}                         // default options
  }
  dependsOn: [
    cosmosAccount
  ]
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15-preview' = {
  name: containerName
  parent: sqlDb
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [
          '/UserId'                     // **partition key**
        ]
        kind: 'Hash'
      }
      // Default throughput = PAYG (serverless) – no RU/s setting needed
    }
    options: {}                         // keep empty for serverless
  }
  dependsOn: [
    sqlDb
  ]
}
