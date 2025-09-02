// cosmosServerless.bicep
// Creates a free-tier, serverless Cosmos DB account with one database and container.

@description('Name for the Cosmos DB account (must be globally unique, 3-44 lowercase letters, numbers).')
param cosmosAccountName string

@description('Azure region for the account and its replicas.')
param location string = resourceGroup().location

var databaseName  = 'blipsdb'
var containerName = 'blips'

param cosmosLeasesContainerName string = 'leases'

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-02-15-preview' = {
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

// =========================================================
// CONTROL-PLANE: custom Azure RBAC role (ARM) to create/list/manage SQL DBs & containers
// Grants ONLY the account-level management actions needed for DB + container lifecycle.
// Define at RG scope; assign at the Cosmos account scope.
// =========================================================
resource cosmosDbDbContainerManager 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(resourceGroup().id, cosmosAccount.id, 'Cosmos-DB-Db-Container-Manager')
  scope: resourceGroup()
  properties: {
    roleName: 'Cosmos DB Database & Container Manager'
    description: 'Create, read, update, delete Cosmos SQL databases and containers (plus throughput ops) under this account.'
    assignableScopes: [ resourceGroup().id ]
    permissions: [
      {
        actions: [
          // Gremlin role assignments (control-plane)
          'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments/write'
          'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments/read'
          'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments/read'
          
          // SQL databases (control-plane)
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/write'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/read'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/delete'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/operationResults/read'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/throughputSettings/*'

          // SQL containers (control-plane)
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/write'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/read'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/delete'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/operationResults/read'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/throughputSettings/*'
        ]
        notActions: [
          // Keep this role scoped to DB/container lifecycle; no keys or account-wide writes.
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
/* DATA-PLANE: custom Cosmos (NoSQL) role to work INSIDE one database
   Includes readMetadata (required by SDK) + all container & item operations.
   Assign it at: scope = '${cosmos.id}/dbs/${serviceDbName}'
*/
// =========================================================
resource serviceDbDataOperator 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions@2025-05-01-preview' = {
  name: guid(cosmosAccount.id, 'service-db-data-operator')
  parent: cosmosAccount
  properties: {
    roleName: 'Service DB Data Operator'
    type: 'CustomRole'
    assignableScopes: [
      cosmosAccount.id
    ]
    permissions: [
      {
        dataActions: [
          // Required by SDKs to list DBs/containers metadata (limited by assignment scope)
          'Microsoft.DocumentDB/databaseAccounts/readMetadata'

          // Containers + items inside the DB
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/*'
          'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers/items/*'
        ]
        // NOTE: Cosmos data-plane RBAC ignores notDataActions; omit it.
      }
    ]
  }
}

// resource sqlDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-02-15-preview' = {
//   name: databaseName
//   parent: cosmosAccount
//   properties: {
//     resource: {
//       id: databaseName
//     }
//     options: {}
//   }
//   dependsOn: [
//     cosmosAccount
//   ]
// }

// resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-02-15-preview' = {
//   name: containerName
//   parent: sqlDb
//   properties: {
//     resource: {
//       id: containerName
//       partitionKey: {
//         paths: [
//           '/userId'
//         ]
//         kind: 'Hash'
//       }
//     }
//     options: {}
//   }
//   dependsOn: [
//     sqlDb
//   ]
// }

// resource leases 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-02-15-preview' = {
//   name: cosmosLeasesContainerName
//   parent: sqlDb
//   properties: {
//     resource: {
//       id: cosmosLeasesContainerName
//       partitionKey: {
//         paths: ['/id']
//         kind: 'Hash'
//         version: 2
//       }
//     }
//     options: { }
//   }
//   dependsOn: [
//     sqlDb
//   ]
// }


output cosmosAccountId string = cosmosAccount.id
output cosmosAccountName string = cosmosAccount.name
// output sqlDatabaseId string = sqlDb.id
// output containerId string = container.id
