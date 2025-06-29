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
az stack group create `
    --resource-group $ResourceGroupName `
    --name ${ResourceGroupName}-stack `
    --template-file  $TemplateFile `
    --action-on-unmanage detachAll `
    --deny-settings-mode None `
    --description 'Core infrastructure deployment.' `
    --verbose
#    --parameters     @$ParametersFile


Write-Host "`n➤ Installing DNS forwarder on new VM ..."
$DNS_FORWARDER_VM_PRIVATE_KEY = $env:DNS_FORWARDER_VM_PRIVATE_KEY
# call dns forwarder script with the private key
Set-Content -Path '.\dnsforwarederprivatekey.pem' -Value $DNS_FORWARDER_VM_PRIVATE_KEY
ssh-keygen -R 10.1.0.36    
ssh -i '.\dnsforwarederprivatekey.pem' azureuser@10.1.0.36

sudo apt update
sudo apt install -y dnsmasq
sudo apt purge resolvconf
sudo -i
echo "no-resolv" | sudo tee -a /etc/dnsmasq.conf
echo "server=168.63.129.16" | sudo tee -a /etc/dnsmasq.conf
echo "interface=eth0" | sudo tee -a /etc/dnsmasq.conf

sudo rm /etc/resolv.conf
echo "nameserver 127.0.0.1" | sudo tee -a /etc/resolv.conf
sudo sed -i 's/127.0.0.1 localhost/127.0.0.1 localhost dnsforwarder/' /etc/hosts

sudo systemctl start dnsmasq
sudo systemctl enable dnsmasq