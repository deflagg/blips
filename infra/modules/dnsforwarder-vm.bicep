// @description('Virtual Network ID to deploy the DNS forwarder VM into')
// param vnetId string

// @description('Location for all resources')
// param location string = resourceGroup().location

// param virtualMachines_dnsforwarder_name string = 'dnsforwarder'
// param networkInterfaces_dnsforwarder482_z1_name string = 'dnsforwarder482_z1'
// param disks_dnsforwarder_OsDisk_1_d896b03008be41c186b15ea259a2a784_name string = 'dnsforwarder_OsDisk_1_d896b03008be41c186b15ea259a2a784'
// param networkSecurityGroups_dnsforwarder_nsg_name string = 'dnsforwarder-nsg'

// resource disks_dnsforwarder_OsDisk_1_d896b03008be41c186b15ea259a2a784_name_resource 'Microsoft.Compute/disks@2024-03-02' = {
//   name: disks_dnsforwarder_OsDisk_1_d896b03008be41c186b15ea259a2a784_name
//   location: location
//   sku: {
//     name: 'Standard_LRS'
//     tier: 'Standard'
//   }
//   zones: [
//     '1'
//   ]
//   properties: {
//     osType: 'Linux'
//     hyperVGeneration: 'V2'
//     supportsHibernation: true
//     supportedCapabilities: {
//       diskControllerTypes: 'SCSI, NVMe'
//       acceleratedNetwork: true
//       architecture: 'x64'
//     }
//     creationData: {
//       createOption: 'FromImage'
//       imageReference: {
//         id: '/Subscriptions/400acf99-3ce6-4ee6-8bf7-9b209093ac5f/Providers/Microsoft.Compute/Locations/eastus2/Publishers/canonical/ArtifactTypes/VMImage/Offers/ubuntu-24_04-lts/Skus/server/Versions/24.04.202506060'
//       }
//     }
//     diskSizeGB: 30
//     diskIOPSReadWrite: 500
//     diskMBpsReadWrite: 60
//     encryption: {
//       type: 'EncryptionAtRestWithPlatformKey'
//     }
//     networkAccessPolicy: 'AllowAll'
//     securityProfile: {
//       securityType: 'TrustedLaunch'
//     }
//     publicNetworkAccess: 'Enabled'
//   }
// }


// resource networkSecurityGroups_dnsforwarder_nsg_name_SSH 'Microsoft.Network/networkSecurityGroups/securityRules@2024-05-01' = {
//   name: 'SSH'
//   parent: networkSecurityGroups_dnsforwarder_nsg_name_resource
//   properties: {
//     protocol: 'TCP'
//     sourcePortRange: '*'
//     destinationPortRange: '22'
//     sourceAddressPrefix: '*'
//     destinationAddressPrefix: '*'
//     access: 'Allow'
//     priority: 300
//     direction: 'Inbound'
//     sourcePortRanges: []
//     destinationPortRanges: []
//     sourceAddressPrefixes: []
//     destinationAddressPrefixes: []
//   }
// }

// resource networkSecurityGroups_dnsforwarder_nsg_name_resource 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
//   name: networkSecurityGroups_dnsforwarder_nsg_name
//   location: location
//   properties: {
//     securityRules: [
//       {
//         name: 'SSH'
//         id: networkSecurityGroups_dnsforwarder_nsg_name_SSH.id
//         type: 'Microsoft.Network/networkSecurityGroups/securityRules'
//         properties: {
//           protocol: 'TCP'
//           sourcePortRange: '*'
//           destinationPortRange: '22'
//           sourceAddressPrefix: '*'
//           destinationAddressPrefix: '*'
//           access: 'Allow'
//           priority: 300
//           direction: 'Inbound'
//           sourcePortRanges: []
//           destinationPortRanges: []
//           sourceAddressPrefixes: []
//           destinationAddressPrefixes: []
//         }
//       }
//     ]
//   }
// }

// resource networkInterfaces_dnsforwarder482_z1_name_resource 'Microsoft.Network/networkInterfaces@2024-05-01' = {
//   name: networkInterfaces_dnsforwarder482_z1_name
//   location: location
//   kind: 'Regular'
//   properties: {
//     ipConfigurations: [
//       {
//         name: 'ipconfig1'
//         id: '${networkInterfaces_dnsforwarder482_z1_name_resource.id}/ipConfigurations/ipconfig1'
//         type: 'Microsoft.Network/networkInterfaces/ipConfigurations'
//         properties: {
//           privateIPAddress: '10.1.0.36'
//           privateIPAllocationMethod: 'Dynamic'
//           subnet: {
//             id: '${vnetId}/subnets/dnsforwarder'
//           }
//           primary: true
//           privateIPAddressVersion: 'IPv4'
//         }
//       }
//     ]
//     dnsSettings: {
//       dnsServers: []
//     }
//     enableAcceleratedNetworking: true
//     enableIPForwarding: false
//     disableTcpStateTracking: false
//     networkSecurityGroup: {
//       id: networkSecurityGroups_dnsforwarder_nsg_name_SSH.id
//     }
//     nicType: 'Standard'
//     auxiliaryMode: 'None'
//     auxiliarySku: 'None'
//   }
// }


// resource virtualMachines_dnsforwarder_name_resource 'Microsoft.Compute/virtualMachines@2024-11-01' = {
//   name: virtualMachines_dnsforwarder_name
//   location: location
//   zones: [
//     '1'
//   ]
//   properties: {
//     hardwareProfile: {
//       vmSize: 'Standard_DS1_v2'
//     }
//     additionalCapabilities: {
//       hibernationEnabled: false
//     }
//     storageProfile: {
//       imageReference: {
//         publisher: 'canonical'
//         offer: 'ubuntu-24_04-lts'
//         sku: 'server'
//         version: 'latest'
//       }
//       osDisk: {
//         osType: 'Linux'
//         name: '${virtualMachines_dnsforwarder_name}_OsDisk_1_d896b03008be41c186b15ea259a2a784'
//         createOption: 'FromImage'
//         caching: 'ReadWrite'
//         managedDisk: {
//           storageAccountType: 'Standard_LRS'
//           id: disks_dnsforwarder_OsDisk_1_d896b03008be41c186b15ea259a2a784_name_resource.id
//         }
//         deleteOption: 'Delete'
//         diskSizeGB: 30
//       }
//       dataDisks: []
//       diskControllerType: 'SCSI'
//     }
//     osProfile: {
//       computerName: virtualMachines_dnsforwarder_name
//       adminUsername: 'azureuser'
//       linuxConfiguration: {
//         disablePasswordAuthentication: true
//         ssh: {
//           publicKeys: [
//             {
//               path: '/home/azureuser/.ssh/authorized_keys'
//               keyData: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCb1si1YErm+scmn/VYcbFA470rn9capj6W6E6+ObjpkSsG0gfp6Tft1UYVAzYGlXjaZT4yUTQdU2cwzq/Hf3PpRMLnPL/m/7iJdsdo+4iB1QIgXYwamkdudDF1GWdU+5HngaWl7Kz+Uu3GZO0kCFY0EYhJpBaSL2AzALCAl2Ecm+/DK8UaDBIyqE+y09azBQUVo7ttq5bZDlFp8/aqsyYpmLTGixmoj6+05ETEALCO/AHpEo5syEa1PSiB29cFyTnVdBYPrIzExlr/EqSDw8nkCFnKddqKoRzjpmkJssihaaZJJ6NH57dqtzfWGLHu6kAyinE1ClcE4541qRv2/upsD5jW7SZKy2hCeiSj1Y8S+SorIMOLz5Dg99ro4TKM5gv1gg+/Ta1umL4xgE8049ZyFpPqwzna4ASg3Lbafh+n8XQObVTU8Bn46Y/gMsR1VpZ02Ox82JWeQjPTL+NdeQbGA/2KvJUK+O7ib4Ipax/QhKTScMC43I51c9x0SlnvbsU= generated-by-azure'
//             }
//           ]
//         }
//         provisionVMAgent: true
//         patchSettings: {
//           patchMode: 'ImageDefault'
//           assessmentMode: 'ImageDefault'
//         }
//       }
//       secrets: []
//       allowExtensionOperations: true
//       requireGuestProvisionSignal: true
//     }
//     securityProfile: {
//       uefiSettings: {
//         secureBootEnabled: true
//         vTpmEnabled: true
//       }
//       securityType: 'TrustedLaunch'
//     }
//     networkProfile: {
//       networkInterfaces: [
//         {
//           id: networkInterfaces_dnsforwarder482_z1_name_resource.id
//           properties: {
//             deleteOption: 'Detach'
//           }
//         }
//       ]
//     }
//     diagnosticsProfile: {
//       bootDiagnostics: {
//         enabled: true
//       }
//     }
//   }
// }









































@description('project name')
param projectName string

@description('Virtual Network ID to deploy the DNS forwarder VM into')
param vnetId string

@description('Location for all resources')
param location string = resourceGroup().location

param virtualMachines_dnsforwarder_name string = 'dnsforwarder'
param networkInterfaces_dnsforwarder482_z1_name string = 'dnsforwarder482_z1'
param networkSecurityGroups_dnsforwarder_nsg_name string = 'dnsforwarder-nsg'



/* --------------------------------------------------------------------- */
/*  NSG (parent) + SSH rule (child)                                      */
/* --------------------------------------------------------------------- */
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: networkSecurityGroups_dnsforwarder_nsg_name
  location: location
}

resource nsgSshRule 'Microsoft.Network/networkSecurityGroups/securityRules@2024-05-01' = {
  name: 'SSH'
  parent: nsg
  properties: {
    protocol: 'TCP'
    sourcePortRange: '*'
    destinationPortRange: '22'
    sourceAddressPrefix: '*'
    destinationAddressPrefix: '*'
    access: 'Allow'
    priority: 300
    direction: 'Inbound'
  }
}

/* --------------------------------------------------------------------- */
/*  NIC                                                                  */
/* --------------------------------------------------------------------- */
resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: networkInterfaces_dnsforwarder482_z1_name
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${vnetId}/subnets/dnsforwarder'
          }
          primary: true
          privateIPAddressVersion: 'IPv4'
        }
      }
    ]
    enableAcceleratedNetworking: true
    enableIPForwarding: false
    networkSecurityGroup: {
      id: nsg.id
    }
    nicType: 'Standard'
  }
}

/* --------------------------------------------------------------------- */
/*  Virtual machine                                                      */
/* --------------------------------------------------------------------- */
resource vm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: virtualMachines_dnsforwarder_name
  location: location
  zones: [
    '1'
  ]
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_DS1_v2'
    }
    additionalCapabilities: {
      hibernationEnabled: false
    }
    storageProfile: {
      imageReference: {
        publisher: 'canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        osType: 'Linux'
        name: '${virtualMachines_dnsforwarder_name}_OsDisk_1_d896b03008be41c186b15ea259a2a784'
        createOption: 'FromImage'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
        deleteOption: 'Delete'
        diskSizeGB: 30
      }
      diskControllerType: 'SCSI'
    }
    osProfile: {
      computerName: virtualMachines_dnsforwarder_name
      adminUsername: 'azureuser'
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/azureuser/.ssh/authorized_keys'
              keyData: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCb1si1YErm+scmn/VYcbFA470rn9capj6W6E6+ObjpkSsG0gfp6Tft1UYVAzYGlXjaZT4yUTQdU2cwzq/Hf3PpRMLnPL/m/7iJdsdo+4iB1QIgXYwamkdudDF1GWdU+5HngaWl7Kz+Uu3GZO0kCFY0EYhJpBaSL2AzALCAl2Ecm+/DK8UaDBIyqE+y09azBQUVo7ttq5bZDlFp8/aqsyYpmLTGixmoj6+05ETEALCO/AHpEo5syEa1PSiB29cFyTnVdBYPrIzExlr/EqSDw8nkCFnKddqKoRzjpmkJssihaaZJJ6NH57dqtzfWGLHu6kAyinE1ClcE4541qRv2/upsD5jW7SZKy2hCeiSj1Y8S+SorIMOLz5Dg99ro4TKM5gv1gg+/Ta1umL4xgE8049ZyFpPqwzna4ASg3Lbafh+n8XQObVTU8Bn46Y/gMsR1VpZ02Ox82JWeQjPTL+NdeQbGA/2KvJUK+O7ib4Ipax/QhKTScMC43I51c9x0SlnvbsU= generated-by-azure'
            }
          ]
        }
        provisionVMAgent: true
        patchSettings: {
          patchMode: 'ImageDefault'
          assessmentMode: 'ImageDefault'
        }
      }
      allowExtensionOperations: true
      requireGuestProvisionSignal: true
    }
    securityProfile: {
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
      securityType: 'TrustedLaunch'
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: {
            deleteOption: 'Detach'
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}
