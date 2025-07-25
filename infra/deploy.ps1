param(
    [string]$ResourceGroupName = "sysdesign",
    [string]$Location          = "eastus2"
)

$TemplateFile   = Join-Path $PSScriptRoot 'main.bicep'
$ParametersFile = Join-Path $PSScriptRoot 'main.parameters.json'
$DnsForwarderScript = Join-Path $PSScriptRoot 'install-dns-forwarder.sh'

Write-Host "`n➤ Creating resource group $ResourceGroupName in $Location ..."
az group create `
    --name     $ResourceGroupName `
    --location $Location | Out-Null


Write-Host "`n➤ Deploying infrastructure stack via $TemplateFile ..."
#write-Host  "`n PFX Base64: $env:AZURE_AKS_APPGW_PFX_BASE64"
az stack group create `
    --resource-group $ResourceGroupName `
    --name ${ResourceGroupName}-stack `
    --template-file  $TemplateFile `
    --action-on-unmanage detachAll `
    --deny-settings-mode None `
    --description 'Core infrastructure deployment.' `
    --verbose `
    --parameters AZURE_AKS_APPGW_PFX_BASE64=$env:AZURE_AKS_APPGW_PFX_BASE64 `
                 @$ParametersFile


Write-Host "`n➤ Running install-dns-forwarder.sh on $vmName ..."
$scriptPath = Join-Path $PSScriptRoot 'install-dns-forwarder.sh'
az vm run-command invoke `
    --resource-group  $ResourceGroupName `
    --name            'dnsforwarder' `
    --command-id      RunShellScript `
    --scripts         "@$scriptPath" `
    --output          table
