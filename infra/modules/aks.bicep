@description('Specifies a project name.')
@minLength(6)
param projectName string = 'sysdesign'

@description('Location for all resources')
param location string = resourceGroup().location

@description('ID of an existing Azure Container Registry to attach to AKS.')
param containerRegistryId string

@description('Resource ID of the subnet where agent nodes live.')
param vnetSubnetId string



@description('Specifies the ID of the Application Gateway Subnet.')
param appGatewaySubnetId string

@description('Specifies the ID of the Application Gateway.')
param appGatewayId string = 'appgateway-sysdesign'

@description('Specifies the ID of the Application Gateway managed identity.')
param appGatewayIdentityId string


@description('Specifies the name of the AKS cluster.')
param aksClusterName string = 'aks-${projectName}'

@description('Specifies the DNS prefix for the AKS cluster.')
param dnsPrefix string = 'aksdns-${projectName}'

resource aksClusterIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: 'aks-sysdesign-identity'
  location: location
}

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
        vnetSubnetID: vnetSubnetId
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
          applicationGatewayId: appGatewayId
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

resource applicationGateway 'Microsoft.Network/applicationGateways@2024-05-01' existing = {
  name: last(split(appGatewayId, '/'))
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

resource applicationGatewayIdentity 'Microsoft.Network/applicationGateways@2024-05-01' existing = {
  name: last(split(appGatewayIdentityId, '/'))
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

// Turn the ID into a typed stub so the compiler knows about it
resource appgatewaysubnet 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: last(split(appGatewaySubnetId, '/'))
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

// Turn the ID into a typed stub so the compiler knows about it
resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-01-01-preview' existing = {
  name: last(split(containerRegistryId, '/'))
}


resource acrName_acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, containerRegistryId, 'acrPull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: aksCluster.properties.identityProfile.kubeletIdentity.objectId
    principalType: 'ServicePrincipal'
  }
}


output containerRegistryId string = containerRegistryId
output aksClusterId string = aksCluster.id
output aksClusterResource object = aksCluster
