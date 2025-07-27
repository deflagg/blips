param keyVaultName string
param certificateName string = 'azure-aks-appgw'  // e.g., without -pfx-base64 suffix
param pfxBase64 string = '<your-base64-encoded-pfx-content>'  // Secure parameter from your current secret
param pfxPassword string = '<pfx-password-if-encrypted>'  // Secure parameter; empty string if none
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

// Assign role to identity (Key Vault Certificate Officer)
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, scriptIdentity.id, 'KeyVaultCertificateOfficer')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a4417e6f-fecd-4de8-b567-7b0420556985')  // Key Vault Certificate Officer role ID
    principalId: scriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Deployment script to import PFX as certificate and output the secret ID
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
    azPowerShellVersion: '10.4.1'  // Latest stable version
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
      $cert = Import-AzKeyVaultCertificate -VaultName $VaultName -Name $CertName -FilePath $pfxPath -Password $PfxPassword

      # Set output: Unversioned secret ID (trim version from SecretId)
      $DeploymentScriptOutputs = @{}
      $unversionedSecretId = $cert.SecretId -replace '/[^/]+$', ''
      $DeploymentScriptOutputs['certSecretId'] = $unversionedSecretId

      # Clean up temp file
      Remove-Item $pfxPath -Force
    '''
    arguments: '-VaultName ${keyVaultName} -CertName ${certificateName} -PfxBase64 "${pfxBase64}" -PfxPassword "${pfxPassword}"'
  }
  dependsOn: [
    roleAssignment
  ]
}

// Output the certificate's unversioned secret ID
output certSecretId string = importCertScript.properties.outputs.certSecretId
