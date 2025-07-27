@description('Project prefix used for naming.')
param projectName string

@description('Name of the Application Gateway.')
param applicationGatewayName string = 'appgateway-${projectName}'

@description('Name of the VNet that already contains **appgateway-subnet**.')
param vnetName string = 'vnet-${projectName}'

@description('Deployment location.')
param location string = resourceGroup().location

@description('Name of the Key Vault.')
param keyVaultName string

@description('ID of the secret for the base64-encoded PFX.')
param pfxSecretUriWithVersion string


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

resource keyVault 'Microsoft.KeyVault/vaults@2024-12-01-preview' existing = {
  name: keyVaultName
}

resource kvAccessPolicy 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, applicationGatewayIdentity.id, 'kv-secret-user')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: applicationGatewayIdentity.properties.principalId 
    principalType: 'ServicePrincipal'
  }
}

// resource waitForRbac 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
//   name: 'wait-for-rbac'
//   kind: 'AzurePowerShell'          // the other option is 'AzureCLI'
//   location: location
//   // make the script run after the role assignment finishes
//   dependsOn: [
//     kvAccessPolicy                // your Key Vault Secrets User role
//   ]

//   properties: {
//     azPowerShellVersion: '14.0.0'   // any version ≥ 3.0 is fine
//     scriptContent: '''
//       Write-Host "Sleeping 1200 seconds to allow RBAC propagation..."
//       Start-Sleep -Seconds 1200
//     '''
//     timeout: 'PT60M'               // ISO‑8601; gives the script 5 min max
//     cleanupPreference: 'OnSuccess'
//     retentionInterval: 'P1D'      // keep logs for 1 day
//   }
// }

// resource waitForRbac 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
//   name: 'wait-for-rbac'
//   kind: 'AzurePowerShell'
//   location: location
//   identity: {
//     type: 'UserAssigned'
//     userAssignedIdentities: {
//       '${applicationGatewayIdentity.id}': {}
//     }
//   }
//   dependsOn: [
//     kvAccessPolicy
//   ]

//   properties: {
//     azPowerShellVersion: '14.0.0'
//     arguments: '-clientId ${applicationGatewayIdentity.properties.clientId} -pfxSecretUriWithVersion "${pfxSecretUriWithVersion}"'
//     scriptContent: '''
//       param(
//         [string]$clientId,
//         [string]$pfxSecretUriWithVersion
//       )

//       Connect-AzAccount -Identity -AccountId $clientId

//       $uri = [Uri]$pfxSecretUriWithVersion
//       $segments = $uri.Segments
//       $secretName = $segments[2].TrimEnd('/')
//       $version = $segments[3].TrimEnd('/')

//       $maxAttempts = 120  # 120 attempts x 20 seconds = 3600 seconds = 1 hour
//       $attempt = 0

//       Start-Sleep -Seconds 60

//       while ($attempt -lt $maxAttempts) {
//         try {
//           $secretValue = Get-AzKeyVaultSecret -VaultName $uri.Host.Split('.')[0] -Name $secretName -Version $version -AsPlainText -ErrorAction Stop
//           Write-Host "Retrieved secret value: $secretValue"
//           Write-Host "Secret access successful. RBAC has propagated."
//           Write-Host "Duration: $($attempt * 20) seconds"
//           break
//         } catch {
//           Write-Host "Attempt $attempt failed: $($_.Exception.Message)"
//           Start-Sleep -Seconds 30
//         }
//         $attempt++
//       }

//       if ($attempt -eq $maxAttempts) {
//         throw "Failed to propagate RBAC after $maxAttempts attempts."
//       }
//     '''
//     timeout: 'PT60M'
//     cleanupPreference: 'OnSuccess'
//     retentionInterval: 'P1D'
//   }
// }


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
  // dependsOn: [
  //   waitForRbac
  // ]

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
    // get from Key Vault
    sslCertificates: [
      {
        name: 'appGwSslCert'
        properties: {
          keyVaultSecretId: pfxSecretUriWithVersion
          
        }
      }
    ]
    httpListeners: [
      {
        name: 'myListener'
        properties: {
          protocol: 'Https'
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', applicationGatewayName, 'appGwPublicFrontendIp')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', applicationGatewayName, 'port_443')
          }
          requireServerNameIndication: false
          sslCertificate: {
            id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', applicationGatewayName,'appGwSslCert')
          }
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
      maxCapacity: 3
    }
  }
  // properties: {
  //   sku: {
  //     name: 'Standard_v2'
  //     tier: 'Standard_v2'
  //   }

  //   gatewayIPConfigurations: [
  //     {
  //       name: 'appGatewayIpConfig'
  //       properties: {
  //         subnet: {
  //           id: appGwSubnetId
  //         }
  //       }
  //     }
  //   ]

  //   frontendIPConfigurations: [
  //     {
  //       name: 'appGwPublicFrontendIp'
  //       properties: {
  //         publicIPAddress: {
  //           id: publicIPAddress.id
  //         }
  //       }
  //     }
  //     // {
  //     //   name: 'appGwPrivateFrontendIp'
  //     //   properties: {
  //     //     subnet: {
  //     //       id: appGwSubnetId
  //     //     }
  //     //     privateIPAllocationMethod: 'Dynamic' // or 'Static' with privateIPAddress
  //     //   }
  //     // }
  //   ]

  //   frontendPorts: [
  //     {
  //       name: 'port_443'
  //       properties: {
  //         port: 443
  //       }
  //     }
  //   ]

  //   backendAddressPools: [
  //     {
  //       name: 'myBackendPool'
  //       properties: {}
  //     }
  //   ]

  //   backendHttpSettingsCollection: [
  //     {
  //       name: 'myHTTPSetting'
  //       properties: {
  //         port: 443
  //         protocol: 'Https'
  //         cookieBasedAffinity: 'Disabled'
  //         pickHostNameFromBackendAddress: false
  //         requestTimeout: 20
  //       }
  //     }
  //   ]
  //   // get from Key Vault
  //   sslCertificates: [
  //     {
  //       name: 'appGwSslCert'
  //       properties: {
  //         keyVaultSecretId: pfxSecretUriWithVersion
          
  //       }
  //     }
  //   ]
  //   httpListeners: [
  //     {
  //       name: 'myListener'
  //       properties: {
  //         protocol: 'Https'
  //         frontendIPConfiguration: {
  //           id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', applicationGatewayName, 'appGwPublicFrontendIp')
  //         }
  //         frontendPort: {
  //           id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', applicationGatewayName, 'port_443')
  //         }
  //         requireServerNameIndication: false
  //         sslCertificate: {
  //           id: resourceId('Microsoft.Network/applicationGateways/sslCertificates', applicationGatewayName,'appGwSslCert')
  //         }
  //       }
  //     }
  //   ]

  //   requestRoutingRules: [
  //     {
  //       name: 'myRoutingRule'
  //       properties: {
  //         ruleType: 'Basic'
  //         priority: 1
  //         httpListener: {
  //           id: resourceId('Microsoft.Network/applicationGateways/httpListeners', applicationGatewayName, 'myListener')
  //         }
  //         backendAddressPool: {
  //           id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', applicationGatewayName, 'myBackendPool')
  //         }
  //         backendHttpSettings: {
  //           id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', applicationGatewayName, 'myHTTPSetting')
  //         }
  //       }
  //     }
  //   ]

  //   enableHttp2: false
  //   autoscaleConfiguration: {
  //     minCapacity: 0
  //     maxCapacity: 3
  //   }
  // }


}




// -----------------------------------------------------------------------------
// Outputs
// -----------------------------------------------------------------------------
output appGatewayId                 string = applicationGateway.id
output appGatewayIdentityId         string = applicationGatewayIdentity.id
output publicIpId                   string = publicIPAddress.id
//output privateIpAddress             string = applicationGateway.properties.frontendIPConfigurations[1].properties.privateIPAddress
