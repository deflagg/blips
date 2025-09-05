param cosmosAccountName string = 'cosmos-sysdesign'
param principalId string


module cosmos 'cosmosNoSql.bicep' = {
  name: 'cosmosNoSql'
  params: {
    cosmosAccountName: cosmosAccountName
    principalId: principalId
  }
}
