# Set your subscription
az account set --subscription $env:AZ_SUBSCRIPTION_ID

# Log in to your Azure Container Registry
az acr login --name acrsysdesign

#print current directory
Write-Host "`n➤ Building and pushing Docker image to Azure Container Registry ..."


# Build the Docker image
docker build -f ./ui/Dockerfile -t acrsysdesign.azurecr.io/blips-ui:latest --progress=plain ./ui


# List the images to verify the build
docker images

# Push the image to ACR
docker push acrsysdesign.azurecr.io/blips-ui:latest

# Get the name of your App Service
$WEB_APP_NAME = (az deployment group show --resource-group sysdesign --name webAppModule --query "properties.outputs.webAppHostname.value" -o tsv).Split('.')[0]

# Configure the App Service to use the container from ACR
az webapp config container set `
    --name $WEB_APP_NAME `
    --resource-group sysdesign `
    --docker-custom-image-name acrsysdesign.azurecr.io/blips-ui:latest `
    --docker-registry-server-url https://acrsysdesign.azurecr.io

# Enable managed identity for the App Service to pull from ACR
az webapp identity assign --resource-group sysdesign --name $WEB_APP_NAME --scope "/subscriptions/$env:AZ_SUBSCRIPTION_ID/resourceGroups/sysdesign/providers/Microsoft.ContainerRegistry/registries/acrsysdesign" --role "AcrPull"

# Enable continuous deployment (optional)
az webapp deployment container config --enable-cd true --name $WEB_APP_NAME --resource-group sysdesign