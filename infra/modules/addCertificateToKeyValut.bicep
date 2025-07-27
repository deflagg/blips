param keyVaultName string
param certificateName string = ''  // e.g., without -pfx-base64 suffix
param pfxBase64 string = ''  // Secure parameter from your current secret
@secure()
param pfxPassword string = ''  // Optional: Password for the PFX file (leave empty for password-less)
param location string = resourceGroup().location

// Your existing Key Vault resource (abbreviated)
resource keyVault 'Microsoft.KeyVault/vaults@2024-12-01-preview' existing = {
  name: keyVaultName
}

// User-assigned managed identity for the script (needs Key Vault Certificate Officer role on the vault)
resource scriptIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2025-01-31-preview' = {
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
resource importCertScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
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
    azPowerShellVersion: '14.0.0'  // Latest stable version
    retentionInterval: 'P1D'
    cleanupPreference: 'OnSuccess'
    environmentVariables: [
      {
        name: 'PfxPassword'
        secureValue: pfxPassword
      }
    ]
    scriptContent: '''
      param (
        [string]$VaultName,
        [string]$CertName,
        [string]$PfxBase64
      )

      $PfxPassword = $env:PfxPassword

      # Decode base64 to temp PFX file
      $pfxBytes = [Convert]::FromBase64String($PfxBase64)
      $pfxPath = "$env:TEMP\cert.pfx"
      [IO.File]::WriteAllBytes($pfxPath, $pfxBytes)

      # Import to Key Vault as certificate
      if ([string]::IsNullOrEmpty($PfxPassword)) {
        $cert = Import-AzKeyVaultCertificate -VaultName $VaultName -Name $CertName -FilePath $pfxPath
      } else {
        $securePassword = ConvertTo-SecureString -String $PfxPassword -AsPlainText -Force
        $cert = Import-AzKeyVaultCertificate -VaultName $VaultName -Name $CertName -FilePath $pfxPath -Password $securePassword
      }

      # Set output: Unversioned secret ID (trim version from SecretId)
      $DeploymentScriptOutputs = @{}
      $unversionedSecretId = $cert.SecretId -replace '/[^/]+$', ''
      $DeploymentScriptOutputs['certSecretId'] = $unversionedSecretId

      # Clean up temp file
      Remove-Item $pfxPath -Force
    '''
    arguments: '-VaultName ${keyVaultName} -CertName ${certificateName} -PfxBase64 "${pfxBase64}"'
  }
  dependsOn: [
    roleAssignment
  ]
}

// Output the certificate's unversioned secret ID
output certSecretId string = importCertScript.properties.outputs.certSecretId
