param(
    [string]$ResourceGroupName = "sysdesign",
    [string]$Location          = "eastus2"
)

$TemplateFile   = Join-Path $PSScriptRoot 'main_temp.bicep'
$ParametersFile = Join-Path $PSScriptRoot 'main.parameters.json'
$DnsForwarderScript = Join-Path $PSScriptRoot 'install-dns-forwarder.sh'

#az account set --subscription $env:AZURE_SUBSCRIPTION_ID | Out-Null

Write-Host "`n➤ Creating resource group $ResourceGroupName in $Location ..."
az group create `
    --name     $ResourceGroupName `
    --location $Location `
    --tags 'env=dev' `
           'app=blips' `
           'costcenter=primary' | Out-Null 


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
    --parameters AZURE_AKS_APPGW_CHAIN_PFX_BASE64=$env:AZURE_AKS_APPGW_CHAIN_PFX_BASE64 `
    --parameters AZURE_AKS_APPGW_ROOT_CERT_BASE64=$env:AZURE_AKS_APPGW_ROOT_CERT_BASE64 `
                 @$ParametersFile

if ($LASTEXITCODE) { throw "Stack deployment failed." }


Write-Host "`n➤ Running install-dns-forwarder.sh on $vmName ..."
$scriptPath = Join-Path $PSScriptRoot 'install-dns-forwarder.sh'

# if vm exists
$vmExists = az vm show --resource-group $ResourceGroupName --name 'dnsforwarder' --query "name" -o tsv

if ($vmExists) {
    Write-Host "`n➤ Found DNS forwarder VM"
    Write-Host "`n➤ Running install-dns-forwarder.sh on dnsforwarder VM to configure DNS forwarding..."

    az vm run-command invoke `
    --resource-group  $ResourceGroupName `
    --name            'dnsforwarder' `
    --command-id      RunShellScript `
    --scripts         "@$scriptPath" `
    --output          table
} else {
    Write-Host "`n➤ DNS forwarder VM does not exist."
}
