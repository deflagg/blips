@description('Project prefix used for naming.')
param projectName string

@description('Name of the Application Gateway.')
param applicationGatewayName string = 'appgateway-${projectName}'

@description('Name of the VNet that already contains **appgateway-subnet**.')
param vnetName string = 'vnet-${projectName}'

@description('Deployment location.')
param location string = resourceGroup().location

// -----------------------------------------------------------------------------
// Common IDs
// -----------------------------------------------------------------------------
var appGwSubnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'appgateway-subnet')
var publicIpName  = '${applicationGatewayName}-pip'

// -----------------------------------------------------------------------------
// Managed identity (needed by AGIC & diagnostics)
// -----------------------------------------------------------------------------
resource applicationGatewayIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: '${applicationGatewayName}-identity'
  location: location
}

// -----------------------------------------------------------------------------
// Public IP address — Standard SKU (required for *v2* gateways)
// -----------------------------------------------------------------------------
resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: publicIpName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
  }
}

// -----------------------------------------------------------------------------
// Application Gateway v2
// -----------------------------------------------------------------------------
resource applicationGateway 'Microsoft.Network/applicationGateways@2024-05-01' = {
  name: applicationGatewayName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${applicationGatewayIdentity.id}': {}
    }
  }
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
    }

    gatewayIPConfigurations: [
      {
        name: 'appGatewayIpConfig'
        properties: {
          subnet: {
            id: appGwSubnetId
          }
        }
      }
    ]

    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          publicIPAddress: {
            id: publicIPAddress.id
          }
        }
      }
      // {
      //   name: 'appGwPrivateFrontendIp'
      //   properties: {
      //     subnet: {
      //       id: appGwSubnetId
      //     }
      //     privateIPAllocationMethod: 'Dynamic' // or 'Static' with privateIPAddress
      //   }
      // }
    ]

    frontendPorts: [
      {
        name: 'port_443'
        properties: {
          port: 443
        }
      }
    ]

    backendAddressPools: [
      {
        name: 'myBackendPool'
        properties: {}
      }
    ]

    backendHttpSettingsCollection: [
      {
        name: 'myHTTPSetting'
        properties: {
          port: 443
          protocol: 'Https'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: false
          requestTimeout: 20
        }
      }
    ]

    httpListeners: [
      {
        name: 'myListener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', applicationGatewayName, 'appGwPublicFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', applicationGatewayName, 'port_443')
          }
          protocol: 'Https'
          requireServerNameIndication: false
        }
      }
    ]

    requestRoutingRules: [
      {
        name: 'myRoutingRule'
        properties: {
          ruleType: 'Basic'
          priority: 1
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', applicationGatewayName, 'myListener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', applicationGatewayName, 'myBackendPool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', applicationGatewayName, 'myHTTPSetting')
          }
        }
      }
    ]

    enableHttp2: false
    autoscaleConfiguration: {
      minCapacity: 0
      maxCapacity: 10
    }
  }
}

// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------
output appGatewayId                 string = applicationGateway.id
output appGatewayIdentityId         string = applicationGatewayIdentity.id
output publicIpId                   string = publicIPAddress.id
//output privateIpAddress             string = applicationGateway.properties.frontendIPConfigurations[1].properties.privateIPAddress
