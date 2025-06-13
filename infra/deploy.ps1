param(
    [string]$ResourceGroupName = "sysdesign",
    [string]$Location          = "eastus2"
)

$TemplateFile   = Join-Path $PSScriptRoot 'main.bicep'
$ParametersFile = Join-Path $PSScriptRoot 'main.parameters.json'


Write-Host "`n➤ Creating resource group $ResourceGroupName in $Location ..."
az group create `
    --name     $ResourceGroupName `
    --location $Location | Out-Null

Write-Host "`n➤ Deploying infrastructure stack via $TemplateFile ..."
az stack group create `
    --resource-group $ResourceGroupName `
    --name ${ResourceGroupName}-stack `
    --template-file  $TemplateFile `
    --action-on-unmanage detachAll `
    --deny-settings-mode None `
    --description 'Core infrastructure deployment.' `
    --verbose
#    --parameters     @$ParametersFile

