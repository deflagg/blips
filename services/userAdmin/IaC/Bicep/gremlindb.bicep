// ---------- Parameters ----------
@description('Globally unique name for the Cosmos DB account (3-44 lowercase letters/numbers).')
param gremlinAccountName string
// The UAMI (User Assigned Managed Identity) principal ID
param principalId string

var gremlinDatabaseName string = 'PersonGraphDb'
var gremlinGraphName string = 'PersonGraph'
var graphPartitionKeyPath string = '/personId'

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

// helpful IDs
var accountId         = resourceId('Microsoft.DocumentDB/databaseAccounts', gremlinAccountName)
var dbFqScope         = '${accountId}/dbs/${gremlinDatabaseName}'
var graphFqScope      = '${dbFqScope}/colls/${gremlinGraphName}'
var gremlinMetaGuid       = guid(accountId, principalId, 'service-gremlin-read-metadata-role')
var gremlinRWGuid       = guid(accountId, principalId, 'service-gremlin-read-write-role')


resource serviceGremlinDbDataOperator 'Microsoft.DocumentDB/databaseAccounts/gremlinRoleDefinitions@2025-05-01-preview' = {
  name: gremlinRWGuid
  parent: gremlinAccount
  properties: {
    id: gremlinRWGuid
    roleName: 'Service Gremlin DB Data Operator'
    type: 'CustomRole'
    assignableScopes: [
      dbFqScope
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
    roleDefinitionId: serviceGremlinDbDataOperator.id 
    scope: dbFqScope
  }
  dependsOn: [
    gremlinDb
    gremlinGraph
  ]
}

// Custom Gremlin data-plane role
resource serviceGremlinDbReadMetadataRole 'Microsoft.DocumentDB/databaseAccounts/gremlinRoleDefinitions@2025-05-01-preview' = {
  name: gremlinMetaGuid
  parent: gremlinAccount
  properties: {
    id: gremlinMetaGuid
    roleName: 'Service Gremlin DB Read Metadata Role'
    type: 'CustomRole'
    assignableScopes: [
      gremlinAccount.id
    ]
    permissions: [
      {
        dataActions: [
          'Microsoft.DocumentDB/databaseAccounts/readMetadata'
        ]
      }
    ]
  }
}

resource gremlinReadMetaAssign 'Microsoft.DocumentDB/databaseAccounts/gremlinRoleAssignments@2025-05-01-preview' = {
  name: guid(gremlinAccount.id, principalId, 'readmeta-at-root')
  parent: gremlinAccount
  properties: {
    principalId: principalId
    roleDefinitionId: serviceGremlinDbReadMetadataRole.id
    scope: gremlinAccount.id
  }
}

// ---------- Outputs ----------
// output gremlinDatabaseId string = gremlinDb.id
// output gremlinGraphId string = gremlinGraph.id
