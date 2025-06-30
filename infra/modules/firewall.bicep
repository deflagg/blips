@description('Project / prefix for all names.')
param projectName string

@description('Azure region for the firewall.')
param location string = resourceGroup().location

@description('Name of the virtual network that will host Azure Firewall.')
param vnetName string

@description('Address prefix for the AzureFirewallSubnet.')
param firewallSubnetPrefix string = '10.0.3.0/26'

@description('IPv4 address of target.  Used as the DNAT translation target.')
param ipAddress string

var firewallName = 'azfw-${projectName}'
var fwPipName    = '${firewallName}-pip'
var fwSubnetName = 'l4firewall'

// ─────────────────────────────────────────────────────────────────────────────
// Networking - ensure the required subnet exists inside the hub VNet
// ─────────────────────────────────────────────────────────────────────────────
resource vnet 'Microsoft.Network/virtualNetworks@2023-04-01' existing = {
  name: vnetName
}

resource firewallSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-04-01' = {
  parent: vnet
  name: fwSubnetName
  properties: {
    addressPrefix: firewallSubnetPrefix
    delegations: []
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Public IP for the firewall
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

// ─────────────────────────────────────────────────────────────────────────────
// Azure Firewall
// ─────────────────────────────────────────────────────────────────────────────
resource azureFirewall 'Microsoft.Network/azureFirewalls@2023-04-01' = {
  name: firewallName
  location: location
  properties: {
    sku: {
      name: 'AZFW_VNet'
      tier: 'Standard'
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
            description: 'Forward public :80/443 -> internal API Management'
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
              '80'
              '443'
            ]
            translatedAddress: ipAddress // private IP of the APIM
            translatedPort   : '0'  // keep original port (80/443)
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
