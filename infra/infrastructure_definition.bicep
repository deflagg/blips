@description('Specifies a project name.')
@minLength(6)
param projectName string = 'sysdesign'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Specifies the name of the Container Registry.')
param containerRegistryName string = 'acr${projectName}'

@description('Specifies the SKU for the Container Registry.')
@allowed([
  'Basic'
  'Standard'
  'Premium'
])
param containerRegistrySku string = 'Basic'

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' = {
  name: containerRegistryName
  location: location
  sku: {
    name: containerRegistrySku
  }
  properties: {
    adminUserEnabled: false
  }
}


@description('Specifies the name of the Virtual Network.')
param vnetName string = 'vnet-${projectName}'

@description('Specifies the SSH RSA public key string for the Linux nodes.')
param sshPublicKey string = 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQD'

resource vnet 'Microsoft.Network/virtualNetworks@2024-03-01' = {
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
        name: 'appgateway-subnet'
        
        properties: {
          
          addressPrefix: '10.0.2.0/24'
        }
      }
      {
        name: 'default-subnet'
        properties: {
          addressPrefix: '10.0.1.0/24'
          delegations: []
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      
    ]
    virtualNetworkPeerings: []
    enableDdosProtection: false
  }
}

// Create a user-assigned managed identity for the Application Gateway
resource applicationGatewayIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: 'appgateway-sysdesign-identity'
  location: location
}

resource aksClusterIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: 'aks-sysdesign-identity'
  location: location
}

// Get subnet for the Application Gateway
resource appgatewaysubnet 'Microsoft.Network/virtualNetworks/subnets@2024-03-01' existing = {
  name: 'appgateway-subnet'
  parent: vnet
}

var publicIPAddressName = 'appgateway-sysdesign-ip'
resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: 'appgateway-sysdesign-ip'
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

@description('Specifies the name of the Application Gateway.')
param applicationGatewayName string = 'appgateway-sysdesign'

resource applicationGateway 'Microsoft.Network/applicationGateways@2024-03-01' = {
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
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'appgateway-subnet')
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appGwPublicFrontendIp'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: resourceId('Microsoft.Network/publicIPAddresses', '${publicIPAddressName}')
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port_80'
        properties: {
          port: 80
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
          port: 80
          protocol: 'Http'
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
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', applicationGatewayName, 'port_80')
          }
          protocol: 'Http'
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


@description('Specifies the name of the AKS cluster.')
param aksClusterName string = 'aks-${projectName}'

@description('Specifies the DNS prefix for the AKS cluster.')
param dnsPrefix string = 'aksdns-${projectName}'

resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-05-01' = {
  name: aksClusterName
  location: location
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aksClusterIdentity.id}': {}
    }
  }
  properties:   {
    dnsPrefix: dnsPrefix
    agentPoolProfiles: [
      {
        name: 'agentpool'
        count: 1
        vmSize: 'Standard_D2s_v3'
        osDiskSizeGB: 128
        osDiskType: 'Managed'
        kubeletDiskType: 'OS'
        vnetSubnetID: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, 'default-subnet')
        maxPods: 110
        type: 'VirtualMachineScaleSets'
        enableAutoScaling: true
        minCount: 1
        maxCount: 2
        mode: 'System'
        osType: 'Linux'
        osSKU: 'Ubuntu'
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'calico'
      loadBalancerSku: 'Standard'
      serviceCidr: '10.1.0.0/16'
      dnsServiceIP: '10.1.0.10'
      podCidr: '10.244.0.0/16'
    }
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    addonProfiles: {
      ingressApplicationGateway: {
        config: {
          applicationGatewayId: applicationGateway.id
        }
        enabled: true
      }
    }
    enableRBAC: true
  }
}

// Assigns the Reader role to the Resource Group
resource resourceGroupReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, resourceGroup().id, 'reader')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7') 
    principalId: aksCluster.properties.addonProfiles.ingressApplicationGateway.identity.objectId
    principalType: 'ServicePrincipal'
    
  }
}

// Assigns the Reader role to the Application Gateway Ingress Controller (AGIC) managed identity for access to the Application Gateway.
resource applicationGatewayAgicReaderRoleAssignment1  'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, applicationGateway.id, 'reader')
  scope: applicationGateway
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7') 
    principalId: aksCluster.properties.addonProfiles.ingressApplicationGateway.identity.objectId
    principalType: 'ServicePrincipal'
    
  }
}

// Assigns the Managed Identity Operator role to the Application Gateway Ingress Controller (AGIC) managed identity for the Application Gateway Identity.
resource applicationGatewayAgicManagedIdentityOperatorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, applicationGatewayIdentity.id, 'managed identity operator')
  scope: applicationGatewayIdentity
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'f1a07417-d97a-45cb-824c-7a7467783830') 
    principalId: aksCluster.properties.addonProfiles.ingressApplicationGateway.identity.objectId
    principalType: 'ServicePrincipal'
    
  }
}

// Assigns the Contributor role to the Application Gateway Ingress Controller (AGIC) managed identity for the Application Gateway.
resource applicationGatewayAgicContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, applicationGateway.id, 'contributor')
  scope: applicationGateway
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') 
    principalId: aksCluster.properties.addonProfiles.ingressApplicationGateway.identity.objectId
    principalType: 'ServicePrincipal'
    
  }
}

// Assigns the Network Contributor role to the Application Gateway Ingress Controller (AGIC) managed identity for the Application Gateway subnet.
resource applicationGatewaySubnetAgicNetworkContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(subscription().id, appgatewaysubnet.id, 'network contributor')
  scope: appgatewaysubnet 
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7') 
    principalId: aksCluster.properties.addonProfiles.ingressApplicationGateway.identity.objectId
    principalType: 'ServicePrincipal'
    
  }
}


resource acrName_acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, containerRegistry.id, 'acrPull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: aksCluster.properties.identityProfile.kubeletIdentity.objectId
    principalType: 'ServicePrincipal'
  }
}


// Output all resources id's
output containerRegistryId string = containerRegistry.id
output vnetId string = vnet.id
output applicationGatewayId string = applicationGateway.id
output aksClusterId string = aksCluster.id
output applicationGatewayIdentityId string = applicationGatewayIdentity.id
output appgatewaysubnetId string = appgatewaysubnet.id
output publicIPAddressId string = publicIPAddress.id
//output applicationGatewayAgicReaderRoleAssignmentId string = applicationGatewayAgicReaderRoleAssignment.id
output applicationGatewayAgicManagedIdentityOperatorRoleAssignmentId string = applicationGatewayAgicManagedIdentityOperatorRoleAssignment.id
output applicationGatewayAgicContributorRoleAssignmentId string = applicationGatewayAgicContributorRoleAssignment.id
//output applicationGatewaySubnetAgicNetworkContributorAssignmentId string = applicationGatewaySubnetAgicNetworkContributorAssignment.id
output aksClusterResource object = aksCluster
