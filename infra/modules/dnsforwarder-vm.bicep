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
