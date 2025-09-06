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

// Grant the UAMI permission to list RW keys on the account



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
    assignableScopes: [ '/dbs/${gremlinDatabaseName}']
    permissions: [
      {
        dataActions: [
          // Required by SDKs to list DB/graph metadata (limited by assignment scope)
          'Microsoft.DocumentDB/databaseAccounts/readMetadata'

          // Graph data access (vertices/edges) + traversals
          'Microsoft.DocumentDB/databaseAccounts/gremlin/containers/entities/*'
          'Microsoft.DocumentDB/databaseAccounts/gremlin/containers/executeQuery'

          'Microsoft.DocumentDB/databaseAccounts/gremlin/containers/readChangeFeed'
        ]
        // NOTE: Cosmos data-plane RBAC ignores notDataActions; omit it.
      }
    ]
  }
}

resource appGremlinDbRWAssign 'Microsoft.DocumentDB/databaseAccounts/gremlinRoleAssignments@2025-05-01-preview' = {
  name: guid(gremlinAccount.id, principalId, gremlinDatabaseName, 'rw')
  parent: gremlinAccount
  properties: {
    principalId: principalId
    roleDefinitionId: serviceGremlinDbDataOperator.id
    scope: '/dbs/${gremlinDatabaseName}' // use '/dbs/${gremlinDatabaseName}/colls/${gremlinGraphName}' to limit to one graph
  }
}


// ---------- Outputs ----------
// output gremlinDatabaseId string = gremlinDb.id
// output gremlinGraphId string = gremlinGraph.id
