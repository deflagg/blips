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
        name: 'l4firewall'         // subnet for the DNS forwarder VM
        properties: {
          addressPrefix: '10.1.1.0/24'
        }
      }
    ]
  }
}



output vnetName string = hubVnet.name
output vnetId   string = hubVnet.id
