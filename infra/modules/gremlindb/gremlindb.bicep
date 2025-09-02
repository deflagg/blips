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

// =========================================================
// CONTROL-PLANE: custom Azure RBAC role (ARM) to create/list/manage Gremlin DBs & graphs
// Grants ONLY the account-level management actions needed for DB + graph lifecycle.
// Define at RG scope; assign at the Cosmos account scope.
// =========================================================
resource gremlinDbGraphManager 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(resourceGroup().id, gremlinAccount.id, 'Cosmos-Gremlin-Db-Graph-Manager')
  scope: resourceGroup()
  properties: {
    roleName: 'Cosmos Gremlin Database & Graph Manager'
    description: 'Create, read, update, delete Cosmos Gremlin databases and graphs (plus throughput ops) under this account.'
    assignableScopes: [ resourceGroup().id ]
    permissions: [
      {
        actions: [
          // Gremlin role assignments (control-plane)
          'Microsoft.DocumentDB/databaseAccounts/gremlinRoleAssignments/write'
          'Microsoft.DocumentDB/databaseAccounts/gremlinRoleAssignments/read'
          'Microsoft.DocumentDB/databaseAccounts/gremlinRoleDefinitions/read'

          // Gremlin databases (control-plane)
          'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases/write'
          'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases/read'
          'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases/delete'
          'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases/operationResults/read'
          'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases/throughputSettings/*'

          // Gremlin graphs (control-plane)
          'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases/graphs/write'
          'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases/graphs/read'
          'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases/graphs/delete'
          'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases/graphs/operationResults/read'
          'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases/graphs/throughputSettings/*'
        ]
        notActions: [
          // Keep this role scoped to DB/graph lifecycle; no keys or account-wide writes.
          'Microsoft.DocumentDB/databaseAccounts/listKeys/action'
          'Microsoft.DocumentDB/databaseAccounts/regenerateKey/action'
          'Microsoft.DocumentDB/databaseAccounts/write'
          'Microsoft.DocumentDB/databaseAccounts/delete'
        ]
      }
    ]
  }
}


// =========================================================
/* DATA-PLANE: custom Cosmos Gremlin role to work INSIDE one database
   Includes readMetadata (required by SDKs) + graph/entity operations.
   Assign it at: scope = '${cosmosAccount.id}/dbs/${gremlinDbName}'
*/
// =========================================================
resource serviceGremlinDbDataOperator 'Microsoft.DocumentDB/databaseAccounts/gremlinRoleDefinitions@2025-05-01-preview' = {
  name: guid(gremlinAccount.id, 'service-gremlin-db-data-operator')
  parent: gremlinAccount
  properties: {
    roleName: 'Service Gremlin DB Data Operator'
    type: 'CustomRole'
    assignableScopes: [ gremlinAccount.id ]
    permissions: [
      {
        dataActions: [
          // Required by SDKs to list DB/graph metadata (limited by assignment scope)
          'Microsoft.DocumentDB/databaseAccounts/readMetadata'

          // Graph data access (vertices/edges) + traversals
          'Microsoft.DocumentDB/databaseAccounts/gremlin/containers/entities/*'
          'Microsoft.DocumentDB/databaseAccounts/gremlin/containers/executeQuery'
        ]
        // NOTE: Cosmos data-plane RBAC ignores notDataActions; omit it.
      }
    ]
  }
}



// resource gremlinDb 'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases@2025-05-01-preview' = {
//   name: gremlinDatabaseName
//   parent: gremlinAccount
//   properties: {
//     resource: {
//       id: gremlinDatabaseName
//     }
//     // In serverless, do NOT set throughput
//     options: {}
//   }
// }

// resource gremlinGraph 'Microsoft.DocumentDB/databaseAccounts/gremlinDatabases/graphs@2025-05-01-preview' = {
//   name: gremlinGraphName
//   parent: gremlinDb
//   properties: {
//     resource: {
//       id: gremlinGraphName
//       partitionKey: {
//         paths: [
//           graphPartitionKeyPath
//         ]
//         kind: 'Hash'
//         version: 2
//       }
//     }
//     // No throughput in serverless
//     options: {}
//   }
// }

// ---------- Outputs ----------
output gremlinAccountId string = gremlinAccount.id
output gremlinAccountName string = gremlinAccount.name
// output gremlinDatabaseId string = gremlinDb.id
// output gremlinGraphId string = gremlinGraph.id
