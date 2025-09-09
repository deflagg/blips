// cosmos-gremlin-serverless.bicep
// Creates a serverless Azure Cosmos DB account for Gremlin,
// with one Gremlin database and one graph.

// ---------- Parameters ----------
@description('Globally unique name for the Cosmos DB account (3-44 lowercase letters/numbers).')
param gremlinAccountName string

@description('Azure region for the account.')
param location string = resourceGroup().location

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


// ---------- Outputs ----------
output gremlinAccountId string = gremlinAccount.id
output gremlinAccountName string = gremlinAccount.name
