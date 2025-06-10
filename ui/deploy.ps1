# Log in to Azure
az login

SUBSCRIPTION_ID="400acf99-3ce6-4ee6-8bf7-9b209093ac5f"

# Set your subscription
az account set --subscription $SUBSCRIPTION_ID

# Log in to your Azure Container Registry
az acr login --name acrsysdesign

# Build the Docker image
docker build -t acrsysdesign.azurecr.io/blips-ui:latest .

# Push the image to ACR
docker push acrsysdesign.azurecr.io/blips-ui:latest

# Get the name of your App Service
WEB_APP_NAME=$(az deployment group show --resource-group sysdesign --name webAppModule --query properties.outputs.webAppHostname.value -o tsv | cut -d'.' -f1)


# Configure the App Service to use the container from ACR
az webapp config container set \
    --name $WEB_APP_NAME \
    --resource-group sysdesign \
    --docker-custom-image-name acrsysdesign.azurecr.io/blips-ui:latest \
    --docker-registry-server-url https://acrsysdesign.azurecr.io

# Enable managed identity for the App Service to pull from ACR
az webapp identity assign --resource-group sysdesign --name $WEB_APP_NAME --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/sysdesign/providers/Microsoft.ContainerRegistry/registries/acrsysdesign --role "AcrPull"

# Enable continuous deployment (optional)
# This will automatically redeploy the app when you push a new image
az webapp deployment container config --enable-cd true --name $WEB_APP_NAME --resource-group sysdesign