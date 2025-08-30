# --- User‑defined variables -----------------------------------------------
$acrName     = "acrsysdesign"
$imageName   = "blipwriter"
$imageTag    = "latest"
$aksName     = "aks-sysdesign"         # 👈 keep in sync with your bicep
$aksRG       = "sysdesign"             # 👈 resource group for the AKS cluster
$release     = "blipwriter"
$namespace   = "blipwriter"
$chartPath   = "./helm"
# DNS
$recordRG    = "global"
$zoneName    = "priv.dns-sysdesign.com"
$recordName  = "blipwriter"
$agwIp       = ""           # Application Gateway public IP
# --------------------------------------------------------------------------

$folderName  = "blipWriter"
Set-Location -Path "./services/${folderName}"

# az account set --subscription $env:AZURE_SUBSCRIPTION_ID | Out-Null

# --------------------------------------------------------------------------
# 1. Login to Azure Container Registry
# --------------------------------------------------------------------------
$acrLoginServer = "${acrName}.azurecr.io"
$fullImageName  = "${acrLoginServer}/${imageName}:${imageTag}"

Write-Host "Logging in to ACR: ${acrLoginServer} ..."
az acr login --name $acrName --output none
if ($LASTEXITCODE) { throw "ACR login failed." }
Write-Host "ACR login successful." -ForegroundColor Green

# --------------------------------------------------------------------------
# 2. Build & push image
# --------------------------------------------------------------------------
Write-Host "Building image ${imageName}:${imageTag} ..."
docker build -t "${imageName}:${imageTag}" . || throw "Docker build failed."

Write-Host "Tagging for ACR → ${fullImageName} ..."
docker tag "${imageName}:${imageTag}" $fullImageName || throw "Tagging failed."

Write-Host "Pushing to ACR ..."
docker push $fullImageName || throw "Push failed."
Write-Host "Image pushed: ${fullImageName}" -ForegroundColor Green

# --------------------------------------------------------------------------
# 3. AKS CLI & kube‑config
# --------------------------------------------------------------------------
az aks install-cli --output none
$env:PATH += if ($IsWindows) { ";$Env:USERPROFILE\.azure-kubectl" } else { ":/usr/local/bin" }

az aks get-credentials -g $aksRG -n $aksName --overwrite-existing --output none

# --------------------------------------------------------------------------
# 4. Grab the CSI add‑on’s managed‑identity client‑ID  
# --------------------------------------------------------------------------
$kvClientId = az aks show -g $aksRG -n $aksName `
               --query "addonProfiles.azureKeyvaultSecretsProvider.identity.clientId" -o tsv
if (-not $kvClientId) { throw "Could not retrieve Key Vault add‑on client‑ID." }

Write-Host "CSI add‑on UAMI client‑ID: ${kvClientId}"

# --------------------------------------------------------------------------
# 5. Helm deploy / upgrade 
# --------------------------------------------------------------------------
helm uninstall $release -n $namespace 2>$null

# Escaping dots in annotation key (PowerShell) → use backtick `
#$saAnnotationKeyEsc = "serviceAccount.annotations.azure`\.workload`\.identity\/client-id"
$saAnnotationKeyEsc = "serviceAccount.annotations.azure\.workload\.identity\/client-id"
$uamiClientId = az identity show -g $aksRG -n 'aks-sysdesign-identity' --query clientId -o tsv

if (-not $uamiClientId) {
    throw "Could not retrieve Workload Identity client‑ID."
}
Write-Host "Workload Identity UAMI client‑ID: ${uamiClientId}"

# Fetch OIDC issuer URL from AKS
$issuerUrl = az aks show -g $aksRG -n $aksName --query "oidcIssuerProfile.issuerUrl" -o tsv
if (-not $issuerUrl) { throw "Could not retrieve AKS OIDC issuer URL." }
Write-Host "AKS OIDC Issuer URL: ${issuerUrl}"

# Create or update federated identity credential
$fedCredName = "blipwriter-fed-cred"  # Unique name
az identity federated-credential delete --name $fedCredName --identity-name aks-sysdesign-identity --resource-group $aksRG --yes --output none
az identity federated-credential create `
    --name $fedCredName `
    --identity-name aks-sysdesign-identity `
    --resource-group $aksRG `
    --issuer $issuerUrl `
    --subject system:serviceaccount:blipwriter:blipwriter-sa `
    --audience api://AzureADTokenExchange
if ($LASTEXITCODE) { throw "Failed to create federated identity credential." }
Write-Host "Federated identity credential created: ${fedCredName}" -ForegroundColor Green

# Wait for propagation
Start-Sleep -Seconds 5

# Log environment variables
Write-Host "Environment variables:"
Write-Host "ASPNETCORE_ENVIRONMENT: $env:ASPNETCORE_ENVIRONMENT"


helm upgrade --install $release $chartPath `
    --namespace $namespace --create-namespace --atomic `
    --set "$saAnnotationKeyEsc=$uamiClientId" `
    --set "azureWorkloadIdentity.clientId=$uamiClientId" `
    --set-string "env.ASPNETCORE_ENVIRONMENT=$($env:ASPNETCORE_ENVIRONMENT)" `
    --set-string "env.DOTNET_ENVIRONMENT=$($env:DOTNET_ENVIRONMENT)" `
    --set-string "env.ASPNETCORE_FORWARDEDHEADERS_ENABLED=true"

if ($LASTEXITCODE) { throw "Helm upgrade/install failed." }



Write-Host "Helm release ${release} deployed in namespace ${namespace}." -ForegroundColor Green

# get the AGW public IP
$agwIp = az network public-ip show `
    --resource-group $aksRG `
    --name "appgateway-sysdesign-pip" `
    --query "ipAddress" -o tsv

# --------------------------------------------------------------------------
# 6. DNS record management (AGW IP) – unchanged
# --------------------------------------------------------------------------
if (-not $agwIp) {
    Write-Host "No external IP found. Skipping DNS update."
} else {
    az network dns record-set a create `
        --resource-group $recordRG `
        --zone-name $zoneName `
        --name $recordName `
        --ttl 60 --output none

    # Remove *all* A records first
    $records = az network dns record-set a list `
        --resource-group $recordRG `
        --zone-name $zoneName `
        --query "[?name=='$recordName'].aRecords[].ipv4Address" -o tsv
    foreach ($ip in $records) {
        az network dns record-set a remove-record `
            --resource-group $recordRG --zone-name $zoneName `
            --record-set-name $recordName --ipv4-address $ip --yes --output none
    }

    # Add the current AGW IP
    az network dns record-set a add-record `
        --resource-group $recordRG --zone-name $zoneName `
        --record-set-name $recordName --ipv4-address $agwIp --output none

    Write-Host "DNS updated: ${recordName}.${zoneName} ➜ ${agwIp}"
}
