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

// Built-in role: DocumentDB Account Contributor
resource docDbContributor 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  scope: subscription()
  name: '5bd9cd88-fe45-4216-938b-f97437e15450'
}

// keep your params and account/db/graph resources as-is

var accountId      = resourceId('Microsoft.DocumentDB/databaseAccounts', gremlinAccountName)
var dbFqScope      = '${accountId}/dbs/${gremlinDatabaseName}'
var graphFqScope   = '${dbFqScope}/colls/${gremlinGraphName}'
var roleDefGuid    = guid(accountId, 'service-gremlin-db-data-operator') // stable GUID

// Custom Gremlin data-plane role (definition)
resource serviceGremlinDbDataOperator 'Microsoft.DocumentDB/databaseAccounts/gremlinRoleDefinitions@2025-05-01-preview' = {
  name: roleDefGuid                 // use GUID as the child resource name
  parent: gremlinAccount
  properties: {
    id: roleDefGuid                 // IMPORTANT: set the role definition's Id (GUID)
    roleName: 'Service Gremlin DB Data Operator'
    type: 'CustomRole'
    assignableScopes: [
      dbFqScope                     // MUST be fully-qualified
    ]
    permissions: [
      {
        dataActions: [
          'Microsoft.DocumentDB/databaseAccounts/readMetadata'
          'Microsoft.DocumentDB/databaseAccounts/gremlin/containers/entities/*'
          'Microsoft.DocumentDB/databaseAccounts/gremlin/containers/executeQuery'
          'Microsoft.DocumentDB/databaseAccounts/gremlin/containers/readChangeFeed'
        ]
      }
    ]
  }
}

// Role assignment (scope is RELATIVE to the account)
resource appGremlinDbRWAssign 'Microsoft.DocumentDB/databaseAccounts/gremlinRoleAssignments@2025-05-01-preview' = {
  name: guid(accountId, principalId, gremlinDatabaseName, 'rw')
  parent: gremlinAccount
  properties: {
    principalId: principalId
    roleDefinitionId: roleDefGuid    // pass the GUID, not the ARM resourceId
    scope: '/dbs/${gremlinDatabaseName}' // or '/dbs/${gremlinDatabaseName}/colls/${gremlinGraphName}'
  }
  dependsOn: [
    gremlinDb
    gremlinGraph
    serviceGremlinDbDataOperator
  ]
}


// ---------- Outputs ----------
// output gremlinDatabaseId string = gremlinDb.id
// output gremlinGraphId string = gremlinGraph.id
