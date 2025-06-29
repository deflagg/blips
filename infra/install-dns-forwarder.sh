@DNS_FORWARDER_VM_PRIVATE_KEY = $env:DNS_FORWARDER_VM_PRIVATE_KEY

# I needa  temp file from the string data
Set-Content -Path '.\dnsforwarederprivatekey.pem' -Value $DNS_FORWARDER_VM_PRIVATE_KEY

ssh-keygen -R 10.1.0.36    
ssh -i 'C:\Users\defla\Downloads\dnsforwarederprivatekey.pem' azureuser@10.1.0.36

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

#sudo chattr +i /etc/resolv.conf
#sudo chattr -i /etc/resolv.conf

# enable system to resolve its own hostname


# update dnsmasq config to forward to Azure DNS 168.63.129.16
#sudo systemctl restart dnsmasq


# options edns0 trust-ad

# sudo apt purge resolvconf


# listen-address=127.0.0.1,172.16.201.2