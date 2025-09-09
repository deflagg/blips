param cosmosAccountName string = 'cosmos-sysdesign'
param databaseName string = 'UserAdminDB'
param containerName string = 'Accounts'
param partitionKeyPath string = '/AccountId'



// The UAMI (User Assigned Managed Identity) principal ID
param principalId string


resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' existing = {
  name: cosmosAccountName
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

// Custom "read metadata" role scoped at the account root
resource serviceSqlReadMetadataRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions@2025-05-01-preview' = {
  name: guid(cosmosAccount.id, principalId, 'service-sql-read-metadata-role')
  parent: cosmosAccount
  properties: {
    roleName: 'Service SQL DB Read Metadata Role'
    type: 'CustomRole'
    assignableScopes: [
      cosmosAccount.id
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

// Assign the metadata-only role at the account root
resource sqlReadMetaAssign 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2025-05-01-preview' = {
  name: guid(cosmosAccount.id, principalId, 'readmeta-at-root')
  parent: cosmosAccount
  properties: {
    principalId:    principalId
    roleDefinitionId: serviceSqlReadMetadataRole.id
    scope:          cosmosAccount.id
  }
}

var keyVaultName string = 'kv-primary-sysdesign'
resource keyVault 'Microsoft.KeyVault/vaults@2024-12-01-preview' existing = {
  name: keyVaultName
}

resource aksKvSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, principalId, 'kv-secrets-user')
  scope: keyVault
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

resource aksKvCertificatesUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, principalId, 'kv-certificates-user')
  scope: keyVault
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'db79e9a7-68ee-4b58-9aeb-b90e7c24fcba')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

output dbId string = sqlDb.id
output containerId string = sqlContainer.id
