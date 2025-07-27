param keyVaultName string
param certificateName string
param pfxBase64 string
@secure()
param pfxPassword string
param location string = resourceGroup().location

// Your existing Key Vault resource (abbreviated)
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

// User-assigned managed identity for the script (needs Key Vault Certificate Officer role on the vault)
resource scriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'kv-import-identity'
  location: location
}

// Assign role to identity (Contributor or Key Vault Certificate Officer)
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, scriptIdentity.id, 'KeyVaultCertificateOfficer')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a4417e6f-fecd-4de8-b567-7b0420556985')  // Key Vault Certificate Officer role ID
    principalId: scriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Deployment script to import PFX as certificate
resource importCertScript 'Microsoft.Resources/deploymentScripts@2020-10-01' = {
  name: 'import-kv-certificate'
  location: location
  kind: 'AzurePowerShell'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${scriptIdentity.id}': {}
    }
  }
  properties: {
    azPowerShellVersion: '14.0.0'
    retentionInterval: 'P1D'
    cleanupPreference: 'OnSuccess'
    scriptContent: '''
      param (
        [string]$VaultName,
        [string]$CertName,
        [string]$PfxBase64,
        [securestring]$PfxPassword
      )

      # Decode base64 to temp PFX file
      $pfxBytes = [Convert]::FromBase64String($PfxBase64)
      $pfxPath = "$env:TEMP\cert.pfx"
      [IO.File]::WriteAllBytes($pfxPath, $pfxBytes)

      # Import to Key Vault as certificate
      Import-AzKeyVaultCertificate -VaultName $VaultName -Name $CertName -FilePath $pfxPath 
        # -Password (ConvertTo-SecureString $PfxPassword -AsPlainText -Force)

      # Clean up temp file
      Remove-Item $pfxPath -Force
    '''
    arguments: '-VaultName ${keyVaultName} -CertName ${certificateName} -PfxBase64 "${pfxBase64}" -PfxPassword "${pfxPassword}"'
  }
  dependsOn: [
    roleAssignment
  ]
}
