@description('Name of the hub virtual network')
param hubVnetName           string
@description('Name of the spoke virtual network')
param spokeVnetName         string

@description('Resource ID of the hub virtual network')
param hubVnetId             string
@description('Resource ID of the spoke virtual network')
param spokeVnetId           string

@description('Peering name from hub → spoke')
param hubToSpokePeeringName string = 'hub-to-spoke'
@description('Peering name from spoke → hub')
param spokeToHubPeeringName string = 'spoke-to-hub'

@description('Allow VMs in the two VNets to talk (recommended)')
param allowVirtualNetworkAccess bool = true
@description('Allow forwarded traffic (if using NVAs / UDRs)')
param allowForwardedTraffic    bool = true


// Import the existing VNets
resource hubVnet   'Microsoft.Network/virtualNetworks@2024-07-01' existing = { name: hubVnetName }
resource spokeVnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = { name: spokeVnetName }

// 1) Hub → Spoke
resource hubToSpoke 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-07-01' = {
  parent: hubVnet
  name:   hubToSpokePeeringName
  properties: {
    remoteVirtualNetwork: {
      id: spokeVnetId
    }
    allowVirtualNetworkAccess: allowVirtualNetworkAccess
    allowForwardedTraffic:    allowForwardedTraffic
    allowGatewayTransit:      true  // true if you want spoke to use hub's gateway
    useRemoteGateways:        false
  }
}

// 2) Spoke → Hub
resource spokeToHub 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-07-01' = {
  parent: spokeVnet
  name:   spokeToHubPeeringName
  properties: {
    remoteVirtualNetwork: {
      id: hubVnetId
    }
    allowVirtualNetworkAccess: allowVirtualNetworkAccess
    allowForwardedTraffic:    allowForwardedTraffic
    allowGatewayTransit:      false     // rarely want spoke exporting back to hub
    useRemoteGateways:        true
  }
}


