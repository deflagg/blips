// cosmos-gremlin-serverless.bicep
// Creates a serverless Azure Cosmos DB account for Gremlin,
// with one Gremlin database and one graph.

// ---------- Parameters ----------
@description('Globally unique name for the Cosmos DB account (3-44 lowercase letters/numbers).')
param gremlinAccountName string
// The UAMI (User Assigned Managed Identity) principal ID
param principalId string

var gremlinDatabaseName string = 'PersonGraphDb'
var gremlinGraphName string = 'PersonGraph'
var graphPartitionKeyPath string = '/PersonId'

// get existing gremlin account
resource gremlinAccount 'Microsoft.DocumentDB/databaseAccounts@2025-05-01-preview' existing = {
  name: gremlinAccountName
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

// (Option A) Reference the built-in Gremlin Data Contributor role under this account
// Built-in Data Reader = 00000000-0000-0000-0000-000000000001
// Built-in Data Contributor = 00000000-0000-0000-0000-000000000002
resource gremlinDataContributor 'Microsoft.DocumentDB/databaseAccounts/gremlinRoleDefinitions@2025-05-01-preview' existing = {
  parent: gremlinAccount
  name: '00000000-0000-0000-0000-000000000002'
}


// helpful IDs
var accountId         = resourceId('Microsoft.DocumentDB/databaseAccounts', gremlinAccountName)
var dbFqScope         = '${accountId}/dbs/${gremlinDatabaseName}'
//var graphFqScope      = '${dbFqScope}/colls/${gremlinGraphName}'
//var roleDefGuid       = guid(accountId, principalId, 'service-gremlin-db-data-operator')
//var roleDefArmId = resourceId('Microsoft.DocumentDB/databaseAccounts/gremlinRoleDefinitions', gremlinAccountName, roleDefGuid)

// Custom Gremlin data-plane role
// resource serviceGremlinDbDataOperator 'Microsoft.DocumentDB/databaseAccounts/gremlinRoleDefinitions@2025-05-01-preview' = {
//   name: roleDefGuid
//   parent: gremlinAccount
//   properties: {
//     id: roleDefGuid
//     roleName: 'Service Gremlin DB Data Operator'
//     type: 'CustomRole'
//     assignableScopes: [
//       dbFqScope
//     ]
//     permissions: [
//       {
//         dataActions: [
//           'Microsoft.DocumentDB/databaseAccounts/readMetadata'
//           'Microsoft.DocumentDB/databaseAccounts/gremlin/containers/entities/*'
//           'Microsoft.DocumentDB/databaseAccounts/gremlin/containers/executeQuery'
//           'Microsoft.DocumentDB/databaseAccounts/gremlin/containers/readChangeFeed'
//         ]
//       }
//     ]
//   }
// }

// Role assignment (scope is RELATIVE to the account)
resource appGremlinDbRWAssign 'Microsoft.DocumentDB/databaseAccounts/gremlinRoleAssignments@2025-05-01-preview' = {
  name: guid(accountId, principalId, gremlinDatabaseName, 'rw')
  parent: gremlinAccount
  properties: {
    principalId: principalId
    roleDefinitionId: gremlinDataContributor.id // roleDefArmId             // <-- use the ARM id, not just the GUID
    scope: dbFqScope   // or '/dbs/${gremlinDatabaseName}/colls/${gremlinGraphName}'
  }
  dependsOn: [
    gremlinDb
    gremlinGraph
    //serviceGremlinDbDataOperator               // ensure role def exists first
  ]
}

// ---------- Outputs ----------
// output gremlinDatabaseId string = gremlinDb.id
// output gremlinGraphId string = gremlinGraph.id
