@description('Project prefix used for naming.')
param projectName string

@description('Hub VNet name')
param hubVnetName string = '${projectName}-hub'

@description('Address space for hub VNet')
param hubAddressSpace string = '10.1.0.0/16'

@description('GatewaySubnet prefix')
param gatewaySubnetPrefix string = '10.1.0.0/27'

@description('P2S VPN client address pool')
param vpnClientAddressPool string = '172.16.201.0/24'

@description('Name of your root certificate (public cert) for P2S auth')
param vpnRootCertName string = 'clientRootCert'

// VPN certificates were created with the scripts in the vpncert folder
@description('Base-64 public cert data; export from your root cert')
param vpnRootCertData string = 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tDQpNSUlESFRDQ0FnV2dBd0lCQWdJVWV5NURFRk00SU1FcmRvVVV5QWhnNTl2V0I0SXdEUVlKS29aSWh2Y05BUUVMDQpCUUF3SGpFY01Cb0dBMVVFQXd3VFFteHBjSE5CZW5WeVpWWndibEp2YjNSRFFUQWVGdzB5TlRBMk1qUXlNRFF3DQpNemxhRncwek5UQTJNakl5TURRd016bGFNQjR4SERBYUJnTlZCQU1NRTBKc2FYQnpRWHAxY21WV2NHNVNiMjkwDQpRMEV3Z2dFaU1BMEdDU3FHU0liM0RRRUJBUVVBQTRJQkR3QXdnZ0VLQW9JQkFRQ3lzUHpwMWhuZndwS2NQbTg1DQpXRWpkYmhVK0VrOWRCbjBUSW5Ceng1WmZsUWdIZnNVM3J5S0hPTVhCMkdvRlhFTUhyY1IzVm9LbEs0eTZzU3piDQpXa2VRWTdwNEt0ejFXbkljY3FVYlZwRjd6eVlHbEpLR0pQb2VHVVFvYWZQTm4wM0o0QlJzYU80L0J3Wk0yanpFDQpNMjFxWmFPRVRaVnZsOVNkdlFaakhvTmdhblhSdDY5bHhsM2VEdkhsb2ZwVEpTREluaW5tREwyZXVpMWx2WkRSDQprc0JhQ0ZINWpoK0laMEN3bGpYS0ZvQXVlcndiY2dneTNWOFFyRENHSEUzWjhPV0tVbnpzTmJwTDRXS01DTGhTDQpUWmF6dk5NL2pOS05DNW8wR0JDOU10YVJHVi82Z29ndEtXbFcyN1RvemMvOE1VaWxDKzI4NHFzdnNKeXhIYjhCDQpnL2RYQWdNQkFBR2pVekJSTUIwR0ExVWREZ1FXQkJUbHRYTGlvZEcyZTdWWGQwd2VTelJEOG90NGVUQWZCZ05WDQpIU01FR0RBV2dCVGx0WExpb2RHMmU3VlhkMHdlU3pSRDhvdDRlVEFQQmdOVkhSTUJBZjhFQlRBREFRSC9NQTBHDQpDU3FHU0liM0RRRUJDd1VBQTRJQkFRQStFSnVncjI2dUg4ZDBzTGlEbUkyVmR5UWlySDMvdmd6SkFWMmdQeEhZDQpKVnRHQTVrdkNLYmVOUmNKZ0VwNXBwdk9XWDdaMnc5aHVFdjBySkpMeVM1TDh5ejR0eHBkMUZwUFZWS0hDNkM3DQozTVFXUUdCaW1HVlNpRTNKWkRsaHFIVXA0Wk5VMHFFR3M5dXA3NVh4ZjVQTmc3NGIrVGl3aWRPeStuRnFGRHdnDQpqdndqczRwWU5nZG03anAzQjB6c09tMk5ZaGlFSmZILzRKbWtrMnFqbS9odFFRa0pwQk9xcXQ2bEt5RmNnMkhYDQp0YkdMei9RSE45cXBzR3hDSkxBMHUvcFpoYmlVMEozOUVISHA1WnZpTnN6aDAvRU9tUjhnRHNiSU5odzdyTWV5DQpib0Q5OXRYaDlFTkw1K0FkbVBsdU1VR3ovMlNPQk1UV3dxNVd6WWRpakpuUw0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQ0K'

@description('Your on-premises / home router public IP')
param localGatewayIp string = '100.15.238.25' // Found at https://whatismyipaddress.com/

@description('On-prem address space behind your gateway')
param localAddressPrefixes array = [
  '10.100.0.0/16'
]

@description('Shared key for the IPSec connection')
param connectionSharedKey string = 'secretVPNConnectionKey!'

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
    ]
  }
}

resource vpnPip 'Microsoft.Network/publicIPAddresses@2024-07-01' = {
  name: '${projectName}-vpn-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}


resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-07-01' = {
  name: '${projectName}-vpn-gateway'
  location: location
  properties: {
    gatewayType: 'Vpn'
    sku: {
      name: 'VpnGw1'
      tier: 'VpnGw1'
    }
    vpnType: 'RouteBased'
    enableBgp: false
    ipConfigurations: [
      {
        name: 'vnetGatewayConfig'
        properties: {
          subnet: {
            // point at your new GatewaySubnet
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', hubVnet.name, 'GatewaySubnet')
          }
          publicIPAddress: {
            id: vpnPip.id
          }
        }
      }
    ]
    vpnClientConfiguration: {
      vpnClientAddressPool: {
        addressPrefixes: [
          vpnClientAddressPool
        ]
      }
      vpnClientRootCertificates: [
        {
          name: vpnRootCertName
          properties: {
            publicCertData: vpnRootCertData
          }
        }
      ]
    }
  }
}

resource localNetGateway 'Microsoft.Network/localNetworkGateways@2024-07-01' = {
  name: '${projectName}-onprem'
  location: location
  properties: {
    gatewayIpAddress: localGatewayIp
    localNetworkAddressSpace: {
      addressPrefixes: localAddressPrefixes
    }
  }
}


resource vpnConnection 'Microsoft.Network/connections@2024-07-01' = {
  name: '${projectName}-hub-to-onprem'
  location: location
  properties: {
    connectionType: 'IPsec'
    virtualNetworkGateway1: {
      id: vpnGateway.id
      properties: {}
    }
    localNetworkGateway2: {
      id: localNetGateway.id
      properties: {}
    }
    sharedKey: connectionSharedKey
  }
}


output vnetName string = hubVnet.name
output vnetId   string = hubVnet.id
