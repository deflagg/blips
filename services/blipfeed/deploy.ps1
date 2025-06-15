# --- User-defined variables ---
$acrName = "acrsysdesign"
$imageName = "blipfeed"
$imageTag = "latest"
# ------------------------------

set-location -path "./services/$($imageName)"

# Derived variables
$acrLoginServer = "$($acrName).azurecr.io"
$fullImageName = "$($acrLoginServer)/$($imageName):$($imageTag)"

# 1. Login to Azure Container Registry
write-host "Logging in to ACR: $($acrLoginServer)..."
az acr login --name $acrName
if ($LASTEXITCODE -ne 0) {
    write-error "Failed to login to ACR. Please check your credentials and ACR name."
    exit 1
}
write-host "ACR login successful." -f Green

# 2. Build the Docker image
write-host "Building Docker image: $($imageName):$($imageTag)..."
docker build -t "$($imageName):$($imageTag)" ./
if ($LASTEXITCODE -ne 0) {
    write-error "Docker build failed."
    exit 1
}
write-host "Docker image built successfully." -f Green

# 3. Tag the Docker image for ACR
write-host "Tagging image for ACR: $($fullImageName)..."
docker tag "$($imageName):$($imageTag)" $fullImageName
if ($LASTEXITCODE -ne 0) {
    write-error "Failed to tag Docker image."
    exit 1
}
write-host "Image tagged successfully." -f Green

# 4. Push the image to ACR
write-host "Pushing image to ACR: $($fullImageName)..."
docker push $fullImageName
if ($LASTEXITCODE -ne 0) {
    write-error "Failed to push image to ACR."
    exit 1
}
write-host "Image pushed to ACR successfully: $($fullImageName)" -f Green

az aks install-cli

# add kubectl to PATH 
$env:PATH += ";/usr/local/bin"

az aks get-credentials --resource-group sysdesign --name aks-sysdesign

$release   = "blipfeed"
$namespace = "blipfeed"
$chartPath = "./helm"

helm uninstall $release -n $namespace

#helm lint "$chartPath"          # catches chart errors
# Idempotent deploy: upgrades if present, installs if not
helm upgrade --install $release "$chartPath" `
  --namespace $namespace `
  --create-namespace `
  --atomic

if ($LASTEXITCODE -ne 0) {
    write-error "Helm upgrade/install failed."
    exit 1
}

write-host "Helm release $release deployed (namespace: $namespace)." -f Green

$resourceGroup = "global"
$zoneName = "priv.dns-sysdesign.com"
$recordName = "blipfeed" # e.g., blipfeed.<your-domain.com>

# Get the external IP of the service
#$externalIp = kubectl get svc blips-blipfeed -n blipfeed -o jsonpath="{.status.loadBalancer.ingress[0].ip}"
# $externalIp = kubectl get svc blips-blipfeed -n blipfeed -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"

# application gateway frontend IP 

#get the IP address of the application gateway
$externalIp = "20.57.68.47"



if (-not $externalIp) {
    Write-Host "No external IP found for service blips-blipfeed. Skipping DNS update."
} else {
    # Create the record set if it doesn't exist
    az network dns record-set a create --resource-group $resourceGroup --zone-name $zoneName --name $recordName --ttl 60

    # Remove existing records (optional, ensures only current IP is present)
    az network dns record-set a remove-record --resource-group $resourceGroup --zone-name $zoneName --record-set-name $recordName --ipv4-address "*" --yes

    # Add the new IP
    az network dns record-set a add-record --resource-group $resourceGroup --zone-name $zoneName --record-set-name $recordName --ipv4-address $externalIp

    Write-Host "DNS record updated: $recordName.$zoneName -> $externalIp"
}


