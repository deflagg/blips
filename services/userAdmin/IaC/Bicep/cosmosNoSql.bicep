param resourceGroupName string = 'sysdesign'
param cosmosAccountName string = 'cosmos-sysdesign'
param databaseName string = 'UserAdminDB'
param containerName string = 'Accounts'
param partitionKeyPath string = '/AccountId'

// Scope under the account, e.g. /dbs/<db> or /dbs/<db>/colls/<container>
param scope string = '/dbs/${databaseName}'

// The UAMI (User Assigned Managed Identity) principal ID
param principalId string


// Build role definition id for 'Cosmos-DB-Db-Container-Manager'
//var coreRgId        = subscriptionResourceId('Microsoft.Resources/resourceGroups', resourceGroupName)
//var cosmosAccountId = resourceId(resourceGroupName, 'Microsoft.DocumentDB/databaseAccounts', cosmosAccountName)
//var roleDefGuid = guid(coreRgId, cosmosAccountId, 'Cosmos-DB-Db-Container-Manager')
//var roleDefinitionId   = resourceId(resourceGroupName, 'Microsoft.Authorization/roleDefinitions', roleDefGuid)
//var roleDefinitionId = '${resourceId(resourceGroupName, 'Microsoft.DocumentDB/databaseAccounts', cosmosAccountName)}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002' // Data Contributor

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' existing = {
  name: cosmosAccountName
}

// get existing role definition
resource roleDefinition 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions@2025-05-01-preview' existing = {
  name: guid(resourceGroup().id, cosmosAccount.id, 'Cosmos-DB-Db-Container-Manager')
  parent: cosmosAccount
}

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

resource assign 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2023-04-15' = {
  name: guid(cosmosAccount.id, principalId, scope, 'nosql-rbac')
  parent: cosmosAccount
  properties: {
    principalId: principalId
    roleDefinitionId: roleDefinition.id
    scope: scope
  }
}

output dbId string = sqlDb.id
output containerId string = sqlContainer.id
