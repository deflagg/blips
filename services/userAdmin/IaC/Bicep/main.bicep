param cosmosAccountName string = 'cosmos-sysdesign'
param gremlinAccountName string = 'gremlin-sysdesign'
param principalId string


module cosmos 'cosmosNoSql.bicep' = {
  name: 'cosmosNoSql'
  params: {
    cosmosAccountName: cosmosAccountName
    principalId: principalId
  }
}

module gremlindbModule 'gremlindb.bicep' = {
  name: 'gremlindb'
  params: {
    gremlinAccountName: gremlinAccountName
    principalId: principalId
  }
}
