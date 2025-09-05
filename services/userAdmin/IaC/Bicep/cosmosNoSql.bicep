param cosmosAccountName string = 'cosmos-sysdesign'
param databaseName string = 'UserAdminDB'
param containerName string = 'Accounts'
param partitionKeyPath string = '/AccountId'


// The UAMI (User Assigned Managed Identity) principal ID
param principalId string
  

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' existing = {
  name: cosmosAccountName
}


// get existing role definition
// resource roleDefinition 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions@2025-05-01-preview' existing = {
//   name: guid(resourceGroup().id, cosmosAccount.id, 'Cosmos-DB-Db-Container-Manager')
//   parent: cosmosAccount
// }

resource sqlDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  name: databaseName
  parent: cosmosAccount
  properties: {
    resource: { id: databaseName }
    options: {}
  }
}

resource sqlContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  name: containerName
  parent: sqlDb
  properties: {
    resource: {
      id: containerName
      partitionKey: { paths: [partitionKeyPath], kind: 'Hash', version: 2 }
      // add TTL/uniqueKeys/indexing policy here if your service owns them
    }
    options: {}
  }
}


// Build FULL data-plane scopes (ARM requires the fully-qualified path)
var dbScope = '${cosmosAccount.id}/dbs/${databaseName}'

resource assign 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2023-04-15' = {
  name: guid(cosmosAccount.id, principalId, dbScope, 'nosql-rbac')
  parent: cosmosAccount
  properties: {
    principalId: principalId       // objectId (GUID) of your UAMI
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002' // Cosmos DB Built-in Data Contributor (data plane)
    scope: dbScope                 // scope at DB level
  }
  // Ensure the DB exists before we create the assignment
  dependsOn: [ sqlDb ]
}

output dbId string = sqlDb.id
output containerId string = sqlContainer.id
