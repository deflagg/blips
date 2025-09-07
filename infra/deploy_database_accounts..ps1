param(
    [string]$ResourceGroupName = "sysdesign",
    [string]$Location          = "eastus2"
)

$TemplateFile   = Join-Path $PSScriptRoot 'deploy_database_accounts.bicep'
$ParametersFile = Join-Path $PSScriptRoot 'main.parameters.json'


Write-Host "`n➤ Deploying Database stack via $TemplateFile ..."

az stack group create `
    --resource-group $ResourceGroupName `
    --name ${ResourceGroupName}-stack `
    --template-file  $TemplateFile `
    --action-on-unmanage detachAll `
    --deny-settings-mode None `
    --description 'Database deployment.' `
    --verbose `
    --parameters AZURE_AKS_APPGW_CHAIN_PFX_BASE64=$env:AZURE_AKS_APPGW_CHAIN_PFX_BASE64 `
    --parameters AZURE_AKS_APPGW_ROOT_CERT_BASE64=$env:AZURE_AKS_APPGW_ROOT_CERT_BASE64 `
                 @$ParametersFile

if ($LASTEXITCODE) { throw "Stack deployment failed." }
