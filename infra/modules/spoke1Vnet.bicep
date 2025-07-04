@description('Project prefix used for naming.')
param projectName string

@description('Name of the VNet.')
param vnetName string = 'vnet-${projectName}'

@description('Deployment location.')
param location string = resourceGroup().location

// -------------------------
// Network-security group for APIM
// -------------------------
resource nsgApim 'Microsoft.Network/networkSecurityGroups@2024-03-01' = {
  name: 'nsg-${projectName}-apim'
  location: location
  // Default rules are fine for now; add custom rules later if you need them
  properties: {
    securityRules: [
      {
        name: 'Allow-APIM-3443-Inbound'
        properties: {
          priority: 1001
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// ✱ NEW subnet (next free /24 in 10.0.x.0/24)
//    – delegated to Microsoft.Web/serverFarms
//    – no route-table or NSG required
resource appSvcIntegrationSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-03-01' = {
  name: 'appsvc-integration'
  parent: vnet
  properties: {
    addressPrefix: '10.0.4.0/24'
    delegations: [
      {
        name: 'webDelegation'
        properties: {
          serviceName: 'Microsoft.Web/serverFarms'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'default-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'appgateway-subnet'
        properties: {
          addressPrefix: '10.0.2.0/24'
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'apim-subnet'
        properties: {
          addressPrefix: '10.0.3.0/24'
          networkSecurityGroup: {
            id: nsgApim.id
          }
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

output vnetName string = vnet.name
output vnetId   string = vnet.id
output aksSubnetId                string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'default-subnet')
output appGatewaySubnetId         string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'appgateway-subnet')
output apimSubnetId               string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'apim-subnet')
output appSvcIntegrationSubnetId  string = appSvcIntegrationSubnet.id
