param gremlinAccountName string = 'gremlin-sysdesign'
param principalId string


module gremlindbModule 'gremlindb.bicep' = {
  name: 'gremlindb'
  params: {
    gremlinAccountName: gremlinAccountName
    principalId: principalId
  }
}
