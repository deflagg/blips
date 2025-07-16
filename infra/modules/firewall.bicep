@description('Project / prefix for all names.')
param projectName string

@description('Azure region for the firewall.')
param location string = resourceGroup().location

@description('Name of the virtual network that will host Azure Firewall.')
param vnetName string


@description('IPv4 address of target.  Used as the DNAT translation target.')
param targetIpAddress string

var firewallName = 'azfw-${projectName}'
var fwPipName    = '${firewallName}-pip'

// ─────────────────────────────────────────────────────────────────────────────
// Networking - ensure the required subnet exists inside the hub VNet
// ─────────────────────────────────────────────────────────────────────────────
resource vnet 'Microsoft.Network/virtualNetworks@2024-07-01' existing = {
  name: vnetName
}

// Get subnet for the Azure Firewall
resource firewallSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' existing = {
  name: 'AzureFirewallSubnet' // this exact name is required
  parent: vnet
}

// New: Get subnet for the Azure Firewall management plane (required for Basic SKU)
resource firewallMgmtSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-07-01' existing = {
  name: 'AzureFirewallManagementSubnet' // this exact name is required
  parent: vnet
}

// ─────────────────────────────────────────────────────────────────────────────
// Public IP for the firewall (data plane)
// ─────────────────────────────────────────────────────────────────────────────
resource firewallPip 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: fwPipName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// New: Public IP for the firewall management plane (required for Basic SKU)
resource firewallMgmtPip 'Microsoft.Network/publicIPAddresses@2023-04-01' = {
  name: '${firewallName}-mgmt-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Azure Firewall
// ─────────────────────────────────────────────────────────────────────────────
resource azureFirewall 'Microsoft.Network/azureFirewalls@2023-04-01' = {
  name: firewallName
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Basic'
    }
    ipConfigurations: [
      {
        name: 'config'
        properties: {
          subnet: {
            id: firewallSubnet.id
          }
          publicIPAddress: {
            id: firewallPip.id
          }
        }
      }
    ]
    managementIpConfiguration: {
      name: 'management'
      properties: {
        subnet: {
          id: firewallMgmtSubnet.id
        }
        publicIPAddress: {
          id: firewallMgmtPip.id
        }
      }
    }
    firewallPolicy: {
      id: fwPolicy.id
    }
    // No forced tunnelling; routes stay in the VNet
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Very small firewall policy with a single DNAT rule that
// forwards inbound :80/443 to the private IP of the App Gateway
// ─────────────────────────────────────────────────────────────────────────────
resource fwPolicy 'Microsoft.Network/firewallPolicies@2023-05-01' = {
  name: '${firewallName}-policy'
  location: location
  properties: {
    sku: {
      tier: 'Basic'
    }
  }
}

resource fwPolicyRg 'Microsoft.Network/firewallPolicies/ruleCollectionGroups@2023-05-01' = {
  name: 'AppGatewayDnatRules'
  parent: fwPolicy
  properties: {
    priority: 100
    ruleCollections: [
      {
        name: 'AGNATCollection'
        ruleCollectionType: 'FirewallPolicyNatRuleCollection'
        priority: 100
        action: {
          type: 'DNAT'
        }
        rules: [
          {
            name: 'HttpHttpsToAPIM'
            ruleType: 'NatRule'
            description: 'Forward public :443 -> internal API Management'
            ipProtocols: [
              'TCP'
            ]
            sourceAddresses: [
              '*'     // restrict as needed
            ]
            destinationAddresses: [
              firewallPip.properties.ipAddress
            ]
            destinationPorts: [
              '443'
            ]
            translatedAddress: targetIpAddress // private IP of the APIM
            translatedPort   : '443'
          }
        ]
      }
    ]
  }
}



// ─────────────────────────────────────────────────────────────────────────────
// Outputs
// ─────────────────────────────────────────────────────────────────────────────
output firewallId      string = azureFirewall.id
output firewallPipId   string = firewallPip.id
output firewallPipIp   string = firewallPip.properties.ipAddress
