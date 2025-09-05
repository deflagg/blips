param cosmosAccountName string = 'cosmos-sysdesign'
param principalId string
param objectId string


module cosmos 'cosmosNoSql.bicep' = {
  name: 'cosmosNoSql'
  params: {
    cosmosAccountName: cosmosAccountName
    principalId: principalId
    objectId: objectId
  }
}
