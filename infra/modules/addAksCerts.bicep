param keyVaultName string
param certificateName string = ''  // e.g., without -pfx-base64 suffix
param pfxBase64 string = ''  // Secure parameter from your current secret
@secure()
param pfxPassword string = ''  // Optional: Password for the PFX file (leave empty for password-less)
param location string = resourceGroup().location

param azureAksAppgwRootCertBase64Name string 
param rootCertBase64 string = ''  // Base64-encoded root CA certificate, if needed

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
resource kvSecretOfficerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, scriptIdentity.id, 'kv-certificates-officer')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a4417e6f-fecd-4de8-b567-7b0420556985')  // Key Vault Certificate Officer role ID
    principalId: scriptIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource kvUserOfficerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, scriptIdentity.id, 'kv-secrets-officer')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
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
      $DeploymentScriptOutputs = @{}
      $errorMessage = ''

      try {
        # Decode base64 to temp PFX file using cross-platform path
        $pfxBytes = [Convert]::FromBase64String($PfxBase64)
        $tempPath = [System.IO.Path]::GetTempPath()
        $pfxPath = [System.IO.Path]::Combine($tempPath, 'cert.pfx')
        [IO.File]::WriteAllBytes($pfxPath, $pfxBytes)

        # Import to Key Vault as certificate
        if ([string]::IsNullOrEmpty($PfxPassword)) {
          $cert = Import-AzKeyVaultCertificate -VaultName $VaultName -Name $CertName -FilePath $pfxPath
        } else {
          $securePassword = ConvertTo-SecureString -String $PfxPassword -AsPlainText -Force
          $cert = Import-AzKeyVaultCertificate -VaultName $VaultName -Name $CertName -FilePath $pfxPath -Password $securePassword
        }

        # Set output: Unversioned secret ID (trim version from SecretId)
        $unversionedSecretId = $cert.SecretId -replace '/[^/]+$', ''
        $DeploymentScriptOutputs['certSecretId'] = $unversionedSecretId

        # Clean up temp file
        Remove-Item $pfxPath -Force
      } catch {
        $errorMessage = $_.Exception.Message
        $DeploymentScriptOutputs['error'] = $errorMessage
      }
    '''
    arguments: '-VaultName ${keyVaultName} -CertName ${certificateName} -PfxBase64 "${pfxBase64}"'
  }
  dependsOn: [
    kvSecretOfficerRoleAssignment
    kvUserOfficerRoleAssignment
  ]
}

resource pfxSecret 'Microsoft.KeyVault/vaults/secrets@2024-12-01-preview' = if (!empty(certificateName) && !empty(pfxBase64)) {
  parent: keyVault
  name: '${certificateName}-base64'
  properties: {
    value: pfxBase64
    contentType: 'application/x-pkcs12'
    
  }
}

resource rootCertSecret 'Microsoft.KeyVault/vaults/secrets@2024-12-01-preview' = if (!empty(azureAksAppgwRootCertBase64Name) && !empty(rootCertBase64)) {
  parent: keyVault
  name: azureAksAppgwRootCertBase64Name
  properties: {
    value: rootCertBase64
    contentType: 'application/x-pkcs12'
    
  }
}

// Output the certificate's unversioned secret ID (or error if failed)
output certSecretId string = importCertScript.properties.outputs.certSecretId
output importError string = contains(importCertScript.properties.outputs, 'error') ? importCertScript.properties.outputs.error : ''
