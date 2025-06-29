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
param vpnRootCertData string = 'LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tDQpNSUlESFRDQ0FnV2dBd0lCQWdJVUYzWHlDd282YnFBQkE3cnYzV3BzMTZlOTNkVXdEUVlKS29aSWh2Y05BUUVMDQpCUUF3SGpFY01Cb0dBMVVFQXd3VFFteHBjSE5CZW5WeVpWWndibEp2YjNSRFFUQWVGdzB5TlRBMk1qVXdNRFV3DQpORFJhRncwek5UQTJNak13TURVd05EUmFNQjR4SERBYUJnTlZCQU1NRTBKc2FYQnpRWHAxY21WV2NHNVNiMjkwDQpRMEV3Z2dFaU1BMEdDU3FHU0liM0RRRUJBUVVBQTRJQkR3QXdnZ0VLQW9JQkFRQy94RkVuOHYxdm13SjVNOGNXDQpGTmRBdGdHTStzQlBLVE9LNmhZblBNckFJRllWMnp4b1JWTDNQOWJYaktQbU1VSU4rb1ZUbG9lVHcxZEZ2WVJiDQpMSGNNcllBRWIzb21mQ21XYndzUjFhMmFMdUFoSHFFejBQS3ZaNWtiK1d2bUMycUh3NGhOeDdiVVh2anVjQkhQDQp3U3htSEJ4NW9FcytnVzNWV0c4OU16MGdFUHpwMHRZZnFLam1YVkl5RCt0dGZZYWd4R2hETHJNUUY2VGNZNk0yDQpxc3VxN3dTNFBDb2hRS2x3bG9SdC9sOXRjcjZGZXhBNUZpR2VpSUMxVFZ4VU9NS0RpY212NmNtd0IrM3laalN4DQpxWEdiZnhYSFZuVnAvRFF0Q0tEemF1MnB2RUZadnoyK1VOMkRDd3RONXFXUVpRMFdFamNseDdGVVFIa1A5N3JDDQpXR1J6QWdNQkFBR2pVekJSTUIwR0ExVWREZ1FXQkJSYlI0SW81cmc4RGRGT2lmYUFwa2RoYWM2OVZEQWZCZ05WDQpIU01FR0RBV2dCUmJSNElvNXJnOERkRk9pZmFBcGtkaGFjNjlWREFQQmdOVkhSTUJBZjhFQlRBREFRSC9NQTBHDQpDU3FHU0liM0RRRUJDd1VBQTRJQkFRQmozNHN0U2lSc0tlbXZ6b214WDd1UkVXZXlDdlJrKzhhSktRZStSK055DQp0cHJ3VGNod0kxb2ZuUDZlZGFuUUx5TTBneXFzNjF2RFJzNFVBNUg1MDZnRlpZd0JVSmRTblJ5enlWaTIzcjdVDQpML0E1ZU90Rjk5c0dKTktLNXJURVM5NkI3TmJrZ3d3QXpveFJuekFoK3JXKzk1NTdBWlRxUVZuNzIyUWtMRy9iDQpkUWIyRnpJL2R3ajV3WXFSSTR4MVd4K3JxUWdvalk0cXByV3NrUFcycVZseTBhSWlOM2NiV1JaWWhycFFRSDZRDQpXbVc1YTVuTHBwYWxiK2RpMkhJSVVBcUFyOGNWK3paUDE0d0FHUlYwOWZXVDFWdWR4MlJ2NmdPTUlVL0d4N1daDQpkOS9zOW5BZ2E2YkVwRTBMREdReVBNb1ZrSzBsbzRZcmViUHdjZTdqd0dZdA0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQ0K'

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
      {
        name: 'dnsforwarder'         // subnet for the DNS forwarder VM
        properties: {
          addressPrefix: '10.1.0.32/27'
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


// resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-07-01' = {
//   name: '${projectName}-vpn-gateway'
//   location: location
//   properties: {
//     gatewayType: 'Vpn'
//     sku: {
//       name: 'VpnGw1'
//       tier: 'VpnGw1'
//     }
//     vpnType: 'RouteBased'
//     enableBgp: false
//     ipConfigurations: [
//       {
//         name: 'vnetGatewayConfig'
//         properties: {
//           subnet: {
//             // point at your new GatewaySubnet
//             id: resourceId('Microsoft.Network/virtualNetworks/subnets', hubVnet.name, 'GatewaySubnet')
//           }
//           publicIPAddress: {
//             id: vpnPip.id
//           }
//         }
//       }
//     ]
//     vpnClientConfiguration: {
//       vpnClientAddressPool: {
//         addressPrefixes: [
//           vpnClientAddressPool
//         ]
//       }
//       vpnClientRootCertificates: [
//         {
//           name: vpnRootCertName
//           properties: {
//             publicCertData: vpnRootCertData
//           }
//         }
//       ]
//     }
//   }
// }

// resource localNetGateway 'Microsoft.Network/localNetworkGateways@2024-07-01' = {
//   name: '${projectName}-onprem'
//   location: location
//   properties: {
//     gatewayIpAddress: localGatewayIp
//     localNetworkAddressSpace: {
//       addressPrefixes: localAddressPrefixes
//     }
//   }
// }


// resource vpnConnection 'Microsoft.Network/connections@2024-07-01' = {
//   name: '${projectName}-hub-to-onprem'
//   location: location
//   properties: {
//     connectionType: 'IPsec'
//     virtualNetworkGateway1: {
//       id: vpnGateway.id
//       properties: {}
//     }
//     localNetworkGateway2: {
//       id: localNetGateway.id
//       properties: {}
//     }
//     sharedKey: connectionSharedKey
//   }
// }


output vnetName string = hubVnet.name
output vnetId   string = hubVnet.id
