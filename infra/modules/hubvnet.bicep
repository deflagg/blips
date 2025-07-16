@description('Project prefix used for naming.')
param projectName string

@description('Hub VNet name')
param hubVnetName string = '${projectName}-hub'

@description('Address space for hub VNet')
param hubAddressSpace string = '10.1.0.0/16'

@description('GatewaySubnet prefix')
param gatewaySubnetPrefix string = '10.1.0.0/27'


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
        name: 'Allow-APIM-443-Inbound'
        properties: {
          priority: 1001
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource hubVnet 'Microsoft.Network/virtualNetworks@2024-07-01' = {
  name: hubVnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubAddressSpace
      ]
    }
    subnets: [
      {
        name: 'GatewaySubnet'         // this exact name is required
        properties: {
          addressPrefix: gatewaySubnetPrefix
        }
      }
      {
        name: 'dnsforwarder'         // subnet for the DNS forwarder VM
        properties: {
          addressPrefix: '10.1.0.32/27'
        }
      }
      {
        name: 'AzureFirewallSubnet'         // subnet for the DNS forwarder VM
        properties: {
          addressPrefix: '10.1.1.0/24'
        }
      }
      {
        name: 'AzureFirewallManagementSubnet'  // New: required for Basic SKU
        properties: {
          addressPrefix: '10.1.2.0/24'
        }
      }
      {
        name: 'apim-subnet'
        properties: {
          addressPrefix: '10.1.3.0/24'
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



output vnetName string = hubVnet.name
output vnetId   string = hubVnet.id
